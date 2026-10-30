#!/usr/bin/env bash
# Install Research News Digest: schema, n8n workflow, bashrc shortcut.
set -euo pipefail

RD_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
N8N_ENV="${N8N_ENV:-$HOME/n8n/.env}"
BASHRC="${BASHRC:-$HOME/.bashrc}"
PUSH_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --push-only) PUSH_ONLY=true ;;
  esac
done

if [ "$PUSH_ONLY" = false ]; then
  echo "Applying Postgres schema..."
  docker exec -i n8n_postgres psql -U n8n -d n8n < "$RD_DIR/schema.sql"

  if [ -n "${LLAMA_SERVER_SCRIPT:-}" ] && [ -f "$LLAMA_SERVER_SCRIPT" ]; then
    if grep -q 'HOST="${LLAMA_HOST:-127.0.0.1}"' "$LLAMA_SERVER_SCRIPT" 2>/dev/null; then
      echo "WARNING: llama-server still defaults to 127.0.0.1 — n8n cannot reach it from Docker."
    fi
  fi

  MARK_BEGIN="# >>> research-digest >>>"
  MARK_END="# <<< research-digest <<<"
  if ! grep -qF "$MARK_BEGIN" "$BASHRC" 2>/dev/null; then
    cat >>"$BASHRC" <<EOF

$MARK_BEGIN
alias rdigest='bash "$RD_DIR/research-digest-cli.sh"'
$MARK_END
EOF
    echo "Added rdigest shortcut to $BASHRC"
  fi

  if command -v ufw >/dev/null 2>&1; then
    echo "Note: ufw is available but inactive by default. To restrict llama :8081 to local/docker:"
    echo "  sudo ufw deny 8081 && sudo ufw allow from 172.16.0.0/12 to any port 8081"
  fi
fi

if [ ! -f "$N8N_ENV" ]; then
  echo "Missing $N8N_ENV" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$N8N_ENV"
set +a

export N8N_API_KEY POSTGRES_PASSWORD
chmod +x "$RD_DIR/push_research_digest_to_n8n.sh" "$RD_DIR/research-digest-cli.sh" "$RD_DIR/verify_scopes.sh"
RUNTIME_DIR="${RUNTIME_DIR:-${N8N_FILES_DIR:-$HOME/n8n/n8n_files}/research-digest}"
mkdir -p "$RUNTIME_DIR"
cp -f "$RD_DIR/pipeline_lib.mjs" "$RD_DIR/run_digest.mjs" "$RD_DIR/run_digest.sh" "$RUNTIME_DIR/"
chmod +x "$RUNTIME_DIR/run_digest.sh"
cp -a "$RD_DIR/pi" "$RUNTIME_DIR/"
bash "$RD_DIR/push_research_digest_to_n8n.sh"

echo "Install complete. Run: rdigest (or: bash $RD_DIR/research-digest-cli.sh)"
