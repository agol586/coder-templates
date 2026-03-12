#!/bin/bash
# Starts code-server (VS Code Web) bound to localhost:13337.
# This script is invoked from the Coder agent startup script.
set -euo pipefail

CODE_SERVER_PORT="${CODE_SERVER_PORT:-13337}"

code-server \
  --auth none \
  --port "${CODE_SERVER_PORT}" \
  --disable-telemetry \
  --disable-update-check \
  "$@" \
  </dev/null >/tmp/code-server.log 2>&1 &

echo "code-server started on port ${CODE_SERVER_PORT}"
