#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

echo "=================================================="
echo "OMNIS V3 — FINAL LOOP 7 CLOSURE"
echo "=================================================="

# --------------------------------------------------
# 1. Confirm the V3 server is alive.
# --------------------------------------------------
echo
echo "=== SERVER ==="
curl -fsS --max-time 5 \
    http://127.0.0.1:5000/api/health

# --------------------------------------------------
# 2. Read the persisted Loop 5→7 state.
# --------------------------------------------------
echo
echo
echo "=== PERSISTED LOOP STATE ==="
SNAPSHOT="$(
    curl -fsS --max-time 5 \
        http://127.0.0.1:5000/api/loops/latest
)"
echo "$SNAPSHOT"

# --------------------------------------------------
# 3. Independent database verification.
# --------------------------------------------------
echo
echo
echo "=== DATABASE VERIFICATION ==="

python3 - <<'PY'
import sqlite3
import json
import os
import sys

db = "data/loops.sqlite3"

if not os.path.isfile(db):
    raise SystemExit("FAIL: loops.sqlite3 does not exist")

c = sqlite3.connect(db)
c.row_factory = sqlite3.Row

rows = c.execute("""
    SELECT cycle_id, loop, parent_cycle, simulation_id,
           cycle_number, status, next_state
    FROM loop_cycles
    WHERE loop IN (5,6,7)
    ORDER BY cycle_id
""").fetchall()

print("Persisted cycles:", len(rows))

for r in rows:
    print(
        f"cycle_id={r['cycle_id']} "
        f"loop={r['loop']} "
        f"parent={r['parent_cycle']} "
        f"simulation={r['simulation_id']} "
        f"number={r['cycle_number']} "
        f"status={r['status']}"
    )

# Required Loop 5.
l5 = [r for r in rows if r["loop"] == 5]
if not l5:
    raise SystemExit("FAIL: Loop 5 record missing")

if l5[-1]["status"] != "closed":
    raise SystemExit("FAIL: Loop 5 is not closed")

# Required Loop 6.
l6 = [r for r in rows if r["loop"] == 6]
if not l6:
    raise SystemExit("FAIL: Loop 6 record missing")

if l6[-1]["status"] != "closed":
    raise SystemExit("FAIL: Loop 6 is not closed")

# Required Loop 7.
l7 = [r for r in rows if r["loop"] == 7]
if len(l7) < 3:
    raise SystemExit(
        f"FAIL: expected at least 3 Loop 7 cycles, found {len(l7)}"
    )

for r in l7:
    if r["status"] != "closed":
        raise SystemExit(
            f"FAIL: Loop 7 cycle {r['cycle_id']} is not closed"
        )

# Verify Loop 7 lineage.
previous = None

for r in l7:
    if previous is not None:
        if r["parent_cycle"] != previous["cycle_id"]:
            raise SystemExit(
                "FAIL: Loop 7 parent/child lineage is broken"
            )
    previous = r

# Verify each terminal state says cycle_complete=true.
for r in l7:
    state = json.loads(r["next_state"])
    if state.get("cycle_complete") is not True:
        raise SystemExit(
            f"FAIL: Loop 7 cycle {r['cycle_id']} "
            "does not contain cycle_complete=true"
        )

print("Loop 5: CLOSED")
print("Loop 6: CLOSED")
print(f"Loop 7: {len(l7)} CLOSED CYCLES")
print("Loop 7 lineage: PASS")
print("Loop 7 terminal states: PASS")

c.close()
PY

# --------------------------------------------------
# 4. Verify API-visible Loop 7 history independently.
# --------------------------------------------------
echo
echo
echo "=== LOOP 7 HISTORY ==="
curl -fsS --max-time 5 \
    http://127.0.0.1:5000/api/loops/7

# --------------------------------------------------
# 5. Verify restart recovery WITHOUT creating a new
#    Loop 7 simulation.
# --------------------------------------------------
echo
echo
echo "=== RESTART RECOVERY TEST ==="

pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

curl -fsS --max-time 5 \
    http://127.0.0.1:5000/api/health

echo
echo
echo "=== POST-RESTART LOOP STATE ==="

AFTER_RESTART="$(
    curl -fsS --max-time 5 \
        http://127.0.0.1:5000/api/loops/latest
)"

echo "$AFTER_RESTART"

# --------------------------------------------------
# 6. Final machine verification.
# --------------------------------------------------
echo
echo
echo "=== FINAL VERIFICATION ==="

python3 - <<'PY'
import json
import urllib.request

data = json.load(
    urllib.request.urlopen(
        "http://127.0.0.1:5000/api/loops/latest",
        timeout=5
    )
)

loops = data["loops"]

l5 = loops.get("loop5", [])
l6 = loops.get("loop6", [])
l7 = loops.get("loop7", [])

assert l5, "Loop 5 missing after restart"
assert l6, "Loop 6 missing after restart"
assert l7, "Loop 7 missing after restart"

assert json.loads(l5[0]["next_state"])["loop5_closed"] is True
assert json.loads(l6[0]["next_state"])["loop6_closed"] is True

for row in l7:
    state = json.loads(row["next_state"])
    assert row["status"] == "closed"
    assert state["cycle_complete"] is True

print("Loop 5 persistence: PASS")
print("Loop 6 persistence: PASS")
print("Loop 7 persistence: PASS")
print("Restart recovery: PASS")
PY

echo
echo
echo "=================================================="
echo "OMNIS V3 — LOOP 7 FULLY CLOSED"
echo "=================================================="
echo "Loop 5: CLOSED"
echo "Loop 6: CLOSED"
echo "Loop 7: CLOSED"
echo "Persistence: PASS"
echo "Lineage: PASS"
echo "Restart recovery: PASS"
echo "=================================================="
echo
echo "NO NEW SIMULATION WAS CREATED BY THIS CLOSURE TEST."
echo "=================================================="
