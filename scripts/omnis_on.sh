#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"
FREEZE="$HOME/OMNIS_V3_FREEZE_V3"

[ -d "$FREEZE" ] || {
    echo "FATAL: V3 freeze missing"
    exit 1
}

echo "=== OMNIS V3 — ONE-SWITCH START ==="

cp "$FREEZE/frontend/static/index.html" frontend/static/index.html
cp "$FREEZE/backend/main.py" backend/main.py
cp "$FREEZE/backend/simulation_engine.py" backend/simulation_engine.py
cp "$FREEZE/scripts/start_v3.sh" scripts/start_v3.sh

if [ -f "$FREEZE/data/simulations.sqlite3" ]; then
    mkdir -p data
    cp "$FREEZE/data/simulations.sqlite3" data/simulations.sqlite3
fi

chmod +x scripts/start_v3.sh

grep -q '<title>OMNIS V3 — System Command</title>' \
    frontend/static/index.html || {
    echo "FATAL: V3 dashboard identity failed"
    exit 1
}

if grep -qE 'OMNIS V2|OMNIS_V2' frontend/static/index.html; then
    echo "FATAL: V2 detected — refusing startup"
    exit 1
fi

pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

PAGE="$(curl -sS --max-time 5 http://127.0.0.1:5000/)"

echo "$PAGE" |
    grep -q '<title>OMNIS V3 — System Command</title>' || {
    echo "FATAL: server did not serve V3"
    exit 1
}

if echo "$PAGE" | grep -qE 'OMNIS V2|OMNIS_V2'; then
    echo "FATAL: server served V2"
    exit 1
fi

echo
echo "=================================================="
echo "OMNIS V3 — ONLINE"
echo "=================================================="
echo
echo "Dashboard:"
echo "http://127.0.0.1:5000/"
echo
echo "Health:"
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/health
echo
echo
echo "Latest:"
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/sim/latest
echo
echo
echo "V3 FREEZE: ACTIVE"
echo "V2 REJECTION: ACTIVE"
echo "SERVER VERIFICATION: PASS"
echo "=================================================="
