#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."

PORT="${OMNIS_PORT:-5050}"
URL="http://127.0.0.1:${PORT}/static/index.html"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

is_healthy() {
    curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null | grep -q '^200$'
}

open_dashboard() {
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "$URL"
    else
        echo "Open this in your browser: $URL"
    fi
}

# --- Already running and healthy? Just open it, like waking a console. ---
if is_healthy; then
    echo "OMNIS V3 is already running."
    open_dashboard
    exit 0
fi

echo "Booting OMNIS V3..."

# --- Force-kill any stale/duplicate process, verified before continuing. ---
for i in 1 2 3 4 5; do
    PIDS=$(pgrep -f "uvicorn backend.main" 2>/dev/null || true)
    if [ -z "$PIDS" ]; then
        break
    fi
    kill -9 $PIDS 2>/dev/null
    sleep 1
done
rm -f logs/omnis_v3.pid
mkdir -p data logs

# --- Keep the process alive if the screen locks (Termux:API required). ---
command -v termux-wake-lock &>/dev/null && termux-wake-lock >/dev/null 2>&1 || true

# --- Ensure dependencies exist. ---
if ! command -v uvicorn &>/dev/null; then
    echo "Installing Python dependencies..."
    pip install -r requirements.txt
fi

# --- Launch fully detached: setsid + disown so closing the terminal or
#     Termux session does not kill it (nohup alone does not guarantee this
#     inside Termux's process model). ---
setsid nohup python3 -m uvicorn backend.main:app --host 0.0.0.0 --port "$PORT" \
    >> logs/uvicorn_stdout.log 2>&1 < /dev/null &
echo $! > logs/omnis_v3.pid
disown

# --- Wait for real health, not a guessed sleep duration. ---
for i in $(seq 1 20); do
    if is_healthy; then
        echo "OMNIS V3 is up."
        open_dashboard
        exit 0
    fi
    sleep 1
done

echo "OMNIS V3 did not come up within 20s. Recent log output:"
tail -n 30 logs/uvicorn_stdout.log 2>/dev/null
tail -n 30 logs/omnis_v3.log 2>/dev/null
exit 1
