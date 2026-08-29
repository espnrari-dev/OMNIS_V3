#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p data logs

PID_FILE="logs/omnis_v3.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "OMNIS V3 is already running (PID $(cat "$PID_FILE"))."
    exit 1
fi

if ! command -v uvicorn &>/dev/null; then
    echo "Installing Python dependencies..."
    pip install -r requirements.txt
fi

HOST_PORT=$(python3 -c "from backend.config import HOST, PORT; print(HOST, PORT)")
HOST=$(echo "$HOST_PORT" | cut -d' ' -f1)
PORT=$(echo "$HOST_PORT" | cut -d' ' -f2)

echo "Starting OMNIS V3 on $HOST:$PORT ..."
nohup python3 -m uvicorn backend.main:app --host "$HOST" --port "$PORT" >> logs/uvicorn_stdout.log 2>&1 &
echo $! > "$PID_FILE"
sleep 1

# Print every URL actually reachable, since 0.0.0.0 binds all interfaces
# but a browser needs a concrete address.
echo "OMNIS V3 running. Try these in your browser:"
echo "  http://127.0.0.1:$PORT/static/index.html   (same machine)"
LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
if [ -z "$LAN_IP" ] && command -v ip &>/dev/null; then
    LAN_IP=$(ip addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127\.' | head -1)
fi
if [ -n "${LAN_IP:-}" ]; then
    echo "  http://$LAN_IP:$PORT/static/index.html   (from another device on same network)"
fi
echo ""
echo "API key (needed for /api/sim/start and /api/advisor/advise): $(cat data/.api_key 2>/dev/null || echo 'see data/.api_key')"
echo "VERITY model in use: $(python3 -c 'from backend.config import VERITY_MODEL_PATH; print(VERITY_MODEL_PATH or "NONE FOUND — set VERITY_MODEL_PATH")')"
echo "PID $(cat "$PID_FILE") written to $PID_FILE"
