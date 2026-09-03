#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

echo "=================================================="
echo "OMNIS V3 — LOOP 7 FINAL BASELINE VERIFICATION"
echo "=================================================="

FILES=(
  "data/freeze/OMNIS_V3_FROZEN_SURFACES.json"
  "data/freeze/OMNIS_V3_LOOP7_BASELINE.json"
  "data/freeze/OMNIS_V3_LOOP7_EVIDENCE.json"
  "data/freeze/OMNIS_V3_LOOP7_FREEZE.json"
  "data/loops.sqlite3"
)

for f in "${FILES[@]}"; do
    test -f "$f" || {
        echo "FAIL: missing $f"
        exit 1
    }
done

echo "ARTIFACT PRESENCE: PASS"

python3 - <<'PY'
import json
import sqlite3
import hashlib
from pathlib import Path

root = Path(".")

freeze = json.loads(
    (root/"data/freeze/OMNIS_V3_LOOP7_FREEZE.json").read_text()
)

baseline = json.loads(
    (root/"data/freeze/OMNIS_V3_LOOP7_BASELINE.json").read_text()
)

evidence = json.loads(
    (root/"data/freeze/OMNIS_V3_LOOP7_EVIDENCE.json").read_text()
)

surfaces = json.loads(
    (root/"data/freeze/OMNIS_V3_FROZEN_SURFACES.json").read_text()
)

assert freeze["frozen"] is True
assert baseline["baseline_established"] is True
assert surfaces["frozen"] is True

summary = evidence["summary"]

assert summary["total_persisted_records"] == 5
assert summary["loop5_cycles"] == 1
assert summary["loop6_cycles"] == 1
assert summary["loop7_cycles"] == 3
assert summary["all_closed"] is True
assert summary["loop7_lineage"] is True

con = sqlite3.connect("data/loops.sqlite3")
con.row_factory = sqlite3.Row

rows = con.execute("""
SELECT cycle_id, loop, parent_cycle, simulation_id,
       cycle_number, status, next_state
FROM loop_cycles
WHERE loop IN (5,6,7)
ORDER BY cycle_id
""").fetchall()

assert len(rows) == 5
assert all(r["status"] == "closed" for r in rows)

l7 = [r for r in rows if r["loop"] == 7]

assert len(l7) == 3

for i in range(1, len(l7)):
    assert l7[i]["parent_cycle"] == l7[i-1]["cycle_id"]

for r in l7:
    state = json.loads(r["next_state"])
    assert state["cycle_complete"] is True

con.close()

policy = freeze["continuation_policy"]

assert policy["create_new_simulation"] is False
assert policy["execute_next_seed"] is False
assert policy["mutate_closed_cycles"] is False
assert policy["frozen_at_terminal_state"] is True

assert baseline["terminal_loop"] == 7
assert baseline["terminal_cycle"] == 3
assert baseline["next_seed"] == freeze["terminal"]["next_seed"]

print("FREEZE MANIFEST: PASS")
print("BASELINE MANIFEST: PASS")
print("EVIDENCE SUMMARY: PASS")
print("DATABASE RECORDS: PASS")
print("LOOP 7 LINEAGE: PASS")
print("TERMINAL STATES: PASS")
print("CONTINUATION POLICY: PASS")
print("NEXT SEED PRESERVED: PASS")

print()
print("SHA256")
for f in [
    "data/freeze/OMNIS_V3_FROZEN_SURFACES.json",
    "data/freeze/OMNIS_V3_LOOP7_BASELINE.json",
    "data/freeze/OMNIS_V3_LOOP7_EVIDENCE.json",
    "data/freeze/OMNIS_V3_LOOP7_FREEZE.json",
    "data/loops.sqlite3",
]:
    h = hashlib.sha256((root/f).read_bytes()).hexdigest()
    print(f"{h}  {f}")

print()
print("==================================================")
print("OMNIS V3 — LOOP 7 FINAL BASELINE: VERIFIED")
print("==================================================")
PY
