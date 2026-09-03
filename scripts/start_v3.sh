#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASH="frontend/static/index.html"

[ -f "$DASH" ] || exit 1

grep -q 'OMNIS V3' "$DASH"
! grep -qE 'OMNIS V2|OMNIS_V2' "$DASH"

grep -q 'id="seed"' "$DASH"
grep -q 'id="generations"' "$DASH"
grep -q 'id="debt_allowed"' "$DASH"
grep -q 'id="systemQuestion"' "$DASH"
grep -q 'id="omnis-v3-runtime"' "$DASH"

pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

PAGE="$(curl -sS --max-time 5 http://127.0.0.1:5000/)"

echo "$PAGE" | grep -q 'OMNIS V3'
! echo "$PAGE" | grep -qE 'OMNIS V2|OMNIS_V2'
echo "$PAGE" | grep -q 'id="seed"'
echo "$PAGE" | grep -q 'id="generations"'
echo "$PAGE" | grep -q 'id="debt_allowed"'
echo "$PAGE" | grep -q 'id="systemQuestion"'

echo "======================================"
echo "OMNIS V3 — LOCKED AND RUNNING"
echo "======================================"
echo
echo "Dashboard:"
echo "http://127.0.0.1:5000/"
echo
echo "Health:"
curl -sS --max-time 5 http://127.0.0.1:5000/api/health
echo
