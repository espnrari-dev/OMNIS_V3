#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

echo "=================================================="
echo "OMNIS V3 — LOOP 7 FREEZE ENFORCEMENT VERIFICATION"
echo "=================================================="

echo
echo "=== 1. PYTHON COMPILE ==="
python3 -m py_compile \
  backend/freeze_state.py \
  backend/loop_engine.py \
  backend/main.py

echo "PYTHON COMPILE: PASS"

echo
echo "=== 2. FREEZE MODULE ==="
python3 - <<'PY'
from backend.freeze_state import get_freeze_state, execution_allowed

s = get_freeze_state()

assert s["frozen"] is True, "freeze state is not frozen"
assert execution_allowed() is False, "execution is incorrectly allowed"

print("FROZEN: PASS")
print("EXECUTION_ALLOWED: FALSE")
print("FREEZE HASH:", s["freeze_sha256"])
PY

echo
echo "=== 3. API FREEZE ==="
FREEZE_JSON="$(curl -fsS http://127.0.0.1:5000/api/freeze)"

python3 - "$FREEZE_JSON" <<'PY'
import json
import sys

x = json.loads(sys.argv[1])

assert x["frozen"] is True
assert x["continuation_policy"]["create_new_simulation"] is False
assert x["continuation_policy"]["execute_next_seed"] is False
assert x["continuation_policy"]["mutate_closed_cycles"] is False

print("API FREEZE: PASS")
print("NEW SIMULATION: DISABLED")
print("NEXT SEED: NOT CONSUMED")
print("CLOSED CYCLE MUTATION: DISABLED")
PY

echo
echo "=== 4. DATABASE IMMUTABILITY SNAPSHOT ==="
DB_HASH_BEFORE="$(sha256sum data/loops.sqlite3 | awk '{print $1}')"
ROW_COUNT_BEFORE="$(
  python3 - <<'PY'
import sqlite3
con = sqlite3.connect("data/loops.sqlite3")
print(con.execute("SELECT COUNT(*) FROM loop_cycles").fetchone()[0])
con.close()
PY
)"

echo "DB HASH BEFORE: $DB_HASH_BEFORE"
echo "ROW COUNT BEFORE: $ROW_COUNT_BEFORE"

echo
echo "=== 5. ENGINE IMPORT ==="
python3 - <<'PY'
import backend.loop_engine
print("LOOP ENGINE IMPORT: PASS")
PY

echo
echo "=== 6. RESTART SERVER ==="
pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
  --host 0.0.0.0 \
  --port 5000 \
  > logs/uvicorn.log 2>&1 &

sleep 4

curl -fsS http://127.0.0.1:5000/api/health >/dev/null
echo "SERVER RESTART: PASS"

echo
echo "=== 7. FREEZE SURVIVES RESTART ==="
curl -fsS http://127.0.0.1:5000/api/freeze

python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen(
    "http://127.0.0.1:5000/api/freeze"
) as r:
    x = json.load(r)

assert x["frozen"] is True
assert x["continuation_policy"]["execute_next_seed"] is False

print("RESTART PERSISTENCE: PASS")
PY

echo
echo "=== 8. DATABASE UNCHANGED ==="
DB_HASH_AFTER="$(sha256sum data/loops.sqlite3 | awk '{print $1}')"
ROW_COUNT_AFTER="$(
  python3 - <<'PY'
import sqlite3
con = sqlite3.connect("data/loops.sqlite3")
print(con.execute("SELECT COUNT(*) FROM loop_cycles").fetchone()[0])
con.close()
PY
)"

echo "DB HASH AFTER:  $DB_HASH_AFTER"
echo "ROW COUNT AFTER: $ROW_COUNT_AFTER"

test "$DB_HASH_BEFORE" = "$DB_HASH_AFTER"
test "$ROW_COUNT_BEFORE" = "$ROW_COUNT_AFTER"

echo "DATABASE IMMUTABILITY: PASS"

echo
echo "=== 9. FINAL STATE ==="
curl -fsS http://127.0.0.1:5000/api/loops/latest >/dev/null

echo
echo "=================================================="
echo "LOOP 7 FREEZE ENFORCEMENT: VERIFIED"
echo "=================================================="
echo "Terminal State: FROZEN"
echo "Execution: DISABLED"
echo "Next Seed: PRESERVED"
echo "Database: UNCHANGED"
echo "Restart Recovery: PASS"
echo "=================================================="
