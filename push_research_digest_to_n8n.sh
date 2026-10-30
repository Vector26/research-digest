#!/bin/sh
# Push Research News Digest workflow to n8n (create or update + activate).
# Usage: N8N_API_KEY and POSTGRES_PASSWORD required (sourced from n8n .env by install.sh).
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
WF_IMPORT="${WF_IMPORT:-$SCRIPT_DIR/research_digest.import.json}"
N8N_BASE="${N8N_BASE:-http://127.0.0.1:5678}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Research News Digest}"
CRED_NAME="${CRED_NAME:-Research Digest Postgres}"

if [ -z "${N8N_API_KEY:-}" ]; then
  echo "push_research_digest_to_n8n: set N8N_API_KEY" >&2
  exit 3
fi
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
  echo "push_research_digest_to_n8n: set POSTGRES_PASSWORD" >&2
  exit 3
fi
if [ ! -f "$WF_IMPORT" ]; then
  echo "push_research_digest_to_n8n: missing $WF_IMPORT" >&2
  exit 2
fi

export WF_IMPORT N8N_BASE N8N_API_KEY WORKFLOW_NAME CRED_NAME POSTGRES_PASSWORD

python3 << 'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base = os.environ["N8N_BASE"].rstrip("/")
key = os.environ["N8N_API_KEY"]
wf_name = os.environ["WORKFLOW_NAME"]
cred_name = os.environ["CRED_NAME"]
pg_pass = os.environ["POSTGRES_PASSWORD"]
imp_path = os.environ["WF_IMPORT"]


def api(method, path, body=None):
    data = None
    headers = {"X-N8N-API-KEY": key}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.stderr.write(e.read().decode("utf-8", errors="replace")[:4000])
        raise


def find_workflow_id():
    doc = api("GET", "/api/v1/workflows?limit=250")
    rows = doc.get("data") if isinstance(doc, dict) else doc
    if not isinstance(rows, list):
        rows = []
    for w in rows:
        if (w.get("name") or "").strip() == wf_name:
            return (w.get("id") or "").strip()
    return ""


def find_credential_id():
    doc = api("GET", "/api/v1/credentials?limit=250")
    rows = doc.get("data") if isinstance(doc, dict) else doc
    if not isinstance(rows, list):
        rows = []
    for c in rows:
        if (c.get("name") or "").strip() == cred_name:
            return (c.get("id") or "").strip()
    return ""


def ensure_credential():
    cid = find_credential_id()
    payload = {
        "name": cred_name,
        "type": "postgres",
        "data": {
            "host": "postgres",
            "port": 5432,
            "database": "n8n",
            "user": "n8n",
            "password": pg_pass,
            "ssl": "disable",
            "allowUnauthorizedCerts": False,
            "maxConnections": 100,
            "sshTunnel": False,
        },
    }
    if cid:
        api("PATCH", f"/api/v1/credentials/{cid}", payload)
        print("OK updated postgres credential", cid)
        return cid
    out = api("POST", "/api/v1/credentials", payload)
    cid = (out.get("id") or "").strip()
    if not cid:
        raise SystemExit("credential create failed")
    print("OK created postgres credential", cid)
    return cid


def patch_cred_refs(obj, cred_id):
    if isinstance(obj, dict):
        if obj.get("name") == cred_name and "id" in obj:
            obj["id"] = cred_id
        for v in obj.values():
            patch_cred_refs(v, cred_id)
    elif isinstance(obj, list):
        for v in obj:
            patch_cred_refs(v, cred_id)


cred_id = ensure_credential()

with open(imp_path, encoding="utf-8") as f:
    imp = json.load(f)

patch_cred_refs(imp, cred_id)

wf_id = find_workflow_id()
if wf_id:
    live = api("GET", f"/api/v1/workflows/{wf_id}")
    payload = {
        "name": imp.get("name", wf_name),
        "nodes": imp["nodes"],
        "connections": imp["connections"],
        "settings": {**(live.get("settings") or {}), **(imp.get("settings") or {})},
    }
    if live.get("staticData") is not None:
        payload["staticData"] = live.get("staticData")
    out = api("PUT", f"/api/v1/workflows/{wf_id}", payload)
    print("OK updated workflow", wf_id, "updatedAt=", out.get("updatedAt"))
else:
    payload = {
        "name": imp.get("name", wf_name),
        "nodes": imp["nodes"],
        "connections": imp["connections"],
        "settings": imp.get("settings") or {},
    }
    out = api("POST", "/api/v1/workflows", payload)
    wf_id = (out.get("id") or "").strip()
    if not wf_id:
        raise SystemExit("workflow create failed")
    print("OK created workflow", wf_id)

api("POST", f"/api/v1/workflows/{wf_id}/activate")
print("OK activated workflow", wf_id)
PY
