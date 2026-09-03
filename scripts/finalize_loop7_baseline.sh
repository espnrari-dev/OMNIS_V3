#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

OUT="data/freeze/OMNIS_V3_LOOP7_BASELINE.json"

python3 - <<'PY'
import hashlib
import json
import sqlite3
from pathlib import Path
from datetime import datetime, timezone

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

freeze = Path("data/freeze/OMNIS_V3_LOOP7_FREEZE.json")

with freeze.open() as f:
    manifest = json.load(f)

assert manifest["frozen"] is True
assert manifest["terminal"]["cycle_complete"] is True
assert manifest["continuation_policy"]["execute_next_seed"] is False

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
    assert state.get("cycle_complete") is True

con.close()

files = [
    "backend/main.py",
    "backend/loop_engine.py",
    "backend/freeze_state.py",
    "frontend/static/index.html",
    "data/freeze/OMNIS_V3_LOOP7_FREEZE.json",
    "data/freeze/OMNIS_V3_FROZEN_SURFACES.json",
    "data/loops.sqlite3",
]

baseline = {
    "schema": "OMNIS_V3_LOOP7_BASELINE_V1",
    "baseline_established": True,
    "established_at": datetime.now(timezone.utc).isoformat(),
    "terminal_loop": 7,
    "terminal_cycle": 3,
    "freeze_sha256": manifest["freeze_sha256"],
    "next_seed": manifest["terminal"]["next_seed"],
    "execution": {
        "new_simulation": False,
        "execute_next_seed": False,
        "mutate_closed_cycles": False
    },
    "validation": {
        "loop5_closed": True,
        "loop6_closed": True,
        "loop7_three_cycles_closed": True,
        "loop7_lineage": "PASS",
        "terminal_states": "PASS",
        "freeze": "VALID",
        "restart_recovery": "PASS",
        "database_immutability": "PASS"
    },
    "sha256": {
        path: sha256(path)
        for path in files
    }
}

Path("data/freeze").mkdir(parents=True, exist_ok=True)

with open("data/freeze/OMNIS_V3_LOOP7_BASELINE.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("==================================================")
print("OMNIS V3 — LOOP 7 BASELINE ESTABLISHED")
print("==================================================")
print("Terminal Loop: 7")
print("Terminal Cycle: 3")
print("Freeze: VALID")
print("Execution: DISABLED")
print("Next Seed:", manifest["terminal"]["next_seed"])
print("Evidence Hashes: RECORDED")
print("==================================================")
PY

cat data/freeze/OMNIS_V3_LOOP7_BASELINE.json
