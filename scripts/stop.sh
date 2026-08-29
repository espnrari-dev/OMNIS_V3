#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PID_FILE="logs/omnis_v3.pid"
if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found; is OMNIS V3 running?"
    exit 1
fi
PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "Stopped OMNIS V3 (PID $PID)."
else
    echo "Process $PID not running."
fi
rm -f "$PID_FILE"
