#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FREEZE_DIR="data/freeze"
FREEZE_FILE="$FREEZE_DIR/OMNIS_V3_LOOP7_FREEZE.json"

mkdir -p "$FREEZE_DIR"

echo "=================================================="
echo "OMNIS V3 — LOOP 7 FREEZE PREPARATION"
echo "=================================================="

python3 - <<'PY'
import sqlite3
import json
import os
import hashlib
from datetime import datetime, timezone

DB = "data/loops.sqlite3"
OUT = "data/freeze/OMNIS_V3_LOOP7_FREEZE.json"

if not os.path.isfile(DB):
    raise SystemExit("FAIL: data/loops.sqlite3 missing")

con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row

rows = con.execute("""
    SELECT
        cycle_id,
        loop,
        parent_cycle,
        simulation_id,
        cycle_number,
        input_state,
        observation,
        decision,
        action,
        observed_result,
        evaluation,
        next_state,
        status,
        created_at,
        updated_at
    FROM loop_cycles
    WHERE loop IN (5,6,7)
    ORDER BY cycle_id
""").fetchall()

if not rows:
    raise SystemExit("FAIL: no Loop 5/6/7 records")

records = [dict(r) for r in rows]

l5 = [r for r in records if r["loop"] == 5]
l6 = [r for r in records if r["loop"] == 6]
l7 = [r for r in records if r["loop"] == 7]

if len(l5) != 1:
    raise SystemExit(f"FAIL: expected exactly 1 Loop 5 record, found {len(l5)}")

if len(l6) != 1:
    raise SystemExit(f"FAIL: expected exactly 1 Loop 6 record, found {len(l6)}")

if len(l7) < 3:
    raise SystemExit(
        f"FAIL: expected at least 3 Loop 7 cycles, found {len(l7)}"
    )

for r in records:
    if r["status"] != "closed":
        raise SystemExit(
            f"FAIL: cycle {r['cycle_id']} is not closed"
        )

previous = None
for r in l7:
    if previous is not None:
        if r["parent_cycle"] != previous["cycle_id"]:
            raise SystemExit(
                "FAIL: Loop 7 lineage is not contiguous"
            )
    previous = r

for r in l7:
    state = json.loads(r["next_state"])
    if state.get("cycle_complete") is not True:
        raise SystemExit(
            f"FAIL: Loop 7 cycle {r['cycle_id']} "
            "does not have cycle_complete=true"
        )

terminal = l7[-1]
terminal_state = json.loads(terminal["next_state"])

payload = {
    "schema": "OMNIS_V3_FREEZE_V1",
    "frozen": True,
    "freeze_reason": "Loop 7 fully closed and independently validated",
    "frozen_at": datetime.now(timezone.utc).isoformat(),
    "loop_state": {
        "loop5": {
            "status": "closed",
            "cycles": len(l5)
        },
        "loop6": {
            "status": "closed",
            "cycles": len(l6)
        },
        "loop7": {
            "status": "closed",
            "cycles": len(l7),
            "lineage": "pass",
            "terminal_states": "pass"
        }
    },
    "terminal": {
        "cycle_id": terminal["cycle_id"],
        "simulation_id": terminal["simulation_id"],
        "cycle_number": terminal["cycle_number"],
        "next_seed": terminal_state.get("next_seed"),
        "generations": terminal_state.get("generations"),
        "debt_allowed": terminal_state.get("debt_allowed"),
        "cycle_complete": terminal_state.get("cycle_complete")
    },
    "continuation_policy": {
        "execute_next_seed": False,
        "create_new_simulation": False,
        "mutate_closed_cycles": False,
        "frozen_at_terminal_state": True
    },
    "cycles": [
        {
            "cycle_id": r["cycle_id"],
            "loop": r["loop"],
            "parent_cycle": r["parent_cycle"],
            "simulation_id": r["simulation_id"],
            "cycle_number": r["cycle_number"],
            "status": r["status"],
            "created_at": r["created_at"],
            "updated_at": r["updated_at"],
            "next_state": json.loads(r["next_state"])
        }
        for r in records
    ]
}

canonical = json.dumps(
    payload,
    sort_keys=True,
    separators=(",", ":")
).encode()

payload["freeze_sha256"] = hashlib.sha256(canonical).hexdigest()

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
    f.write("\n")

print("Freeze manifest created:")
print(OUT)
print()
print("Loop 5: CLOSED")
print("Loop 6: CLOSED")
print(f"Loop 7: {len(l7)} CLOSED CYCLES")
print("Lineage: PASS")
print("Terminal states: PASS")
print()
print("Terminal cycle:", terminal["cycle_id"])
print("Terminal simulation:", terminal["simulation_id"])
print("Continuation seed preserved:", terminal_state.get("next_seed"))
print("Continuation execution: DISABLED")
print()
print("Freeze SHA256:", payload["freeze_sha256"])

con.close()
PY

echo
echo "=== FREEZE MANIFEST ==="
cat "$FREEZE_FILE"

echo
echo "=== DASHBOARD / SYSTEM SURFACE DISCOVERY ==="

find . \
    -type f \
    ! -path './.git/*' \
    ! -path './__pycache__/*' \
    \( \
        -name '*.html' \
        -o -name '*.js' \
        -o -name '*.jsx' \
        -o -name '*.tsx' \
        -o -name '*.py' \
        -o -name '*.json' \
    \) \
    -print0 |
while IFS= read -r -d '' f; do
    if grep -qE \
        'loop5|loop6|loop7|api/loops|loops/latest|Loop 7|Loop 6|Loop 5' \
        "$f" 2>/dev/null; then
        echo "$f"
    fi
done

echo
echo "=================================================="
echo "FREEZE MANIFEST READY"
echo "=================================================="
echo
echo "No simulation was executed."
echo "No loop record was modified."
echo "No next_seed was consumed."
echo
echo "The manifest records the exact validated terminal state."
echo
