#!/bin/sh
# Run research digest with Pi CLI (inside n8n container or on host).
set -eu

RD_ROOT="${RD_ROOT:-/files/research-digest}"
if [ ! -d "$RD_ROOT" ]; then
  RD_ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
fi

RD_PI_HOME="${RD_PI_HOME:-$RD_ROOT/pi-runtime}"
mkdir -p "$RD_PI_HOME/.pi/agent"

if [ -f "$RD_ROOT/pi/agent/models.host.json" ] && [ ! -f /host-node/bin/pi ]; then
  cp -f "$RD_ROOT/pi/agent/models.host.json" "$RD_PI_HOME/.pi/agent/models.json"
else
  cp -f "$RD_ROOT/pi/agent/models.json" "$RD_PI_HOME/.pi/agent/models.json"
fi
cp -f "$RD_ROOT/pi/agent/settings.json" "$RD_PI_HOME/.pi/agent/settings.json"
cp -f "$RD_ROOT/pi/agent/curator_system.md" "$RD_PI_HOME/.pi/agent/curator_system.md"

export HOME="$RD_PI_HOME"
export PI_AGENT_DIR="$RD_PI_HOME/.pi/agent"

if [ -x /usr/local/bin/node ]; then
  NODE_BIN=/usr/local/bin/node
elif command -v node >/dev/null 2>&1; then
  NODE_BIN=$(command -v node)
else
  echo "node not found" >&2
  exit 1
fi

exec "$NODE_BIN" "$RD_ROOT/run_digest.mjs"
