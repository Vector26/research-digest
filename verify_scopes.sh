#!/usr/bin/env bash
# Verification scopes for research-digest pipeline. Exit 0 = all pass.
set -euo pipefail

RUNTIME_DIR="${RUNTIME_DIR:-${N8N_FILES_DIR:-$HOME/n8n/n8n_files}/research-digest}"
RD_DIR="${RD_DIR:-$(CDPATH= cd -- "$(dirname "$0")" && pwd)}"
OUT_DIR="${RD_OUT_DIR:-$RUNTIME_DIR}"
N8N_BASE="${N8N_BASE:-http://127.0.0.1:5678}"
WF_ID="${RD_WORKFLOW_ID:-kFC1Ow112M8FgTr4}"
MODE="${1:-news}"
FAIL=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAIL=1; }

echo "=== Research Digest Scope Checks (mode=$MODE) ==="

# S1: Postgres config loads
echo "[S1] Config in Postgres"
if docker exec -i n8n_postgres psql -U n8n -d n8n -Atqc \
  "SELECT count(*) FROM rd_config;" 2>/dev/null | grep -qE '^[1-9]'; then
  pass "rd_config has rows"
else
  fail "rd_config empty or unreachable"
fi
if docker exec -i n8n_postgres psql -U n8n -d n8n -Atqc \
  "SELECT count(*) FROM rd_topics WHERE active;" 2>/dev/null | grep -qE '^[1-9]'; then
  pass "active topics exist"
else
  fail "no active topics"
fi

# S2: Feed fetch (host-side quick probe)
echo "[S2] Feed fetch + parse"
PROBE=$(node --input-type=module -e "
import { fetchItems } from 'file://$RD_DIR/pipeline_lib.mjs';
const feeds = [
  {url:'https://feeds.feedburner.com/TheHackersNews', kind:'news', category:'cybersecurity'},
];
const { collected, feedStats } = await fetchItems('news', feeds, 3);
if (!feedStats[0]?.ok) process.exit(2);
if (collected.length < 1) process.exit(3);
if (!collected[0].title || !collected[0].url) process.exit(4);
console.log(collected[0].title.slice(0,60));
" 2>/dev/null) && pass "RSS parse OK: $PROBE" || fail "RSS fetch/parse failed"

# S3: Pi CLI + HauhauCS backend available
echo "[S3] Pi CLI backend"
if command -v pi >/dev/null 2>&1 && curl -sf --max-time 5 http://127.0.0.1:8081/v1/models | grep -q hauhaucs; then
  pass "pi CLI present + llama-hauhaucs reachable"
else
  fail "pi or llama-hauhaucs unavailable"
fi

# S4: Trigger n8n workflow
echo "[S4] n8n workflow execution"
set -a && . "${N8N_ENV:-$HOME/n8n/.env}" 2>/dev/null && set +a
BEFORE=$(docker exec -i n8n_postgres psql -U n8n -d n8n -Atqc "SELECT count(*) FROM rd_seen;" 2>/dev/null || echo 0)
curl -sfS -X POST "${N8N_BASE}/webhook/research-digest-run?mode=${MODE}" \
  -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 \
  && pass "webhook accepted" || fail "webhook failed"

sleep 3
EXEC_ID=$(curl -sfS -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "${N8N_BASE}/api/v1/executions?workflowId=${WF_ID}&limit=1" 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "")
EXEC_STATUS=""
if [ -n "$EXEC_ID" ]; then
  for _ in $(seq 1 90); do
    EXEC_STATUS=$(curl -sfS -H "X-N8N-API-KEY: $N8N_API_KEY" \
      "${N8N_BASE}/api/v1/executions/${EXEC_ID}" 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    [ "$EXEC_STATUS" = "success" ] && break
    [ "$EXEC_STATUS" = "error" ] && break
    sleep 5
  done
fi
[ "$EXEC_STATUS" = "success" ] && pass "execution $EXEC_ID success" || fail "execution ${EXEC_ID:-?} status=$EXEC_STATUS"

# S5: Output artifact
echo "[S5] Pipeline output file"
if [ -f "$OUT_DIR/latest.json" ]; then
  pass "latest.json exists"
else
  fail "missing $OUT_DIR/latest.json"
fi

# S6: AI scoring quality
echo "[S6] AI scoring + summaries"
node -e "
const fs=require('fs');
const p='$OUT_DIR/latest.json';
if(!fs.existsSync(p)) process.exit(2);
const d=JSON.parse(fs.readFileSync(p,'utf8'));
if(!d.ok) { console.error(d.error||'not ok'); process.exit(3); }
if(!d.model?.ai_ok) { console.error('ai not ok'); process.exit(4); }
if(!Array.isArray(d.items) || d.items.length<1) { console.error('no items'); process.exit(5); }
const bad=d.items.filter(i=>!i.title||!i.url||!i.ai_summary||i.score<1);
if(bad.length) { console.error('bad items', bad.length); process.exit(6); }
console.log(d.items.length+' items, top score='+d.items[0].score);
" 2>/dev/null && pass "$(node -e "const d=JSON.parse(require('fs').readFileSync('$OUT_DIR/latest.json')); console.log(d.items.length+' items scored')")" \
  || fail "AI output invalid — check latest.json"

# S7: Digest text structure
echo "[S7] Digest message format"
node -e "
const fs=require('fs');
const t=fs.readFileSync('$OUT_DIR/latest.txt','utf8');
if(!/Daily Research News|Weekly Research Papers/.test(t)) process.exit(2);
if(!/https?:\\/\\//.test(t)) process.exit(3);
if(t.length<80) process.exit(4);
console.log(t.split('\\n')[0]);
" 2>/dev/null && pass "digest header OK" || fail "digest text malformed"

# S8: Dedupe + rd_seen
echo "[S8] rd_seen persistence + dedupe"
AFTER=$(docker exec -i n8n_postgres psql -U n8n -d n8n -Atqc "SELECT count(*) FROM rd_seen;" 2>/dev/null || echo 0)
if [ "${AFTER:-0}" -gt "${BEFORE:-0}" ]; then
  pass "rd_seen grew ($BEFORE -> $AFTER)"
else
  fail "rd_seen did not grow ($BEFORE -> $AFTER)"
fi

# Re-run quick dedupe check on same URLs in latest.json
DEDUPE_OK=$(node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('$OUT_DIR/latest.json'));
const urls=(d.items||[]).map(i=>i.url);
console.log(new Set(urls).size===urls.length?'yes':'no');
" 2>/dev/null || echo no)
[ "$DEDUPE_OK" = "yes" ] && pass "no duplicate URLs in output" || fail "duplicate URLs in ranked items"

echo "=== Result: $([ $FAIL -eq 0 ] && echo ALL PASS || echo SOME FAILED) ==="
exit $FAIL
