#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

python3 - <<'PY'
import json
import sqlite3
from pathlib import Path

out = Path("data/freeze/OMNIS_V3_LOOP7_EVIDENCE.json")

con = sqlite3.connect("data/loops.sqlite3")
con.row_factory = sqlite3.Row

rows = con.execute("""
    SELECT cycle_id, loop, parent_cycle, simulation_id,
           cycle_number, status, input_state, observation,
           decision, action, observed_result, evaluation,
           next_state
    FROM loop_cycles
    WHERE loop IN (5,6,7)
    ORDER BY cycle_id
""").fetchall()

evidence = {
    "schema": "OMNIS_V3_LOOP7_EVIDENCE_V1",
    "records": []
}

for r in rows:
    evidence["records"].append({
        "cycle_id": r["cycle_id"],
        "loop": r["loop"],
        "parent_cycle": r["parent_cycle"],
        "simulation_id": r["simulation_id"],
        "cycle_number": r["cycle_number"],
        "status": r["status"],
        "input_state": json.loads(r["input_state"]),
        "observation": json.loads(r["observation"]),
        "decision": json.loads(r["decision"]),
        "action": json.loads(r["action"]),
        "observed_result": json.loads(r["observed_result"]),
        "evaluation": json.loads(r["evaluation"]),
        "next_state": json.loads(r["next_state"])
    })

evidence["summary"] = {
    "total_persisted_records": len(rows),
    "loop5_cycles": sum(r["loop"] == 5 for r in rows),
    "loop6_cycles": sum(r["loop"] == 6 for r in rows),
    "loop7_cycles": sum(r["loop"] == 7 for r in rows),
    "all_closed": all(r["status"] == "closed" for r in rows),
    "loop7_lineage": all(
        rows[i]["parent_cycle"] == rows[i-1]["cycle_id"]
        for i in range(1, len(rows))
        if rows[i]["loop"] == 7
    )
}

with out.open("w") as f:
    json.dump(evidence, f, indent=2)

con.close()

print("==================================================")
print("OMNIS V3 — LOOP 7 EVIDENCE EXTRACTED")
print("==================================================")
print("Persisted records:", len(rows))
print("Loop 5:", evidence["summary"]["loop5_cycles"], "cycle")
print("Loop 6:", evidence["summary"]["loop6_cycles"], "cycle")
print("Loop 7:", evidence["summary"]["loop7_cycles"], "cycles")
print("All closed:", evidence["summary"]["all_closed"])
print("Loop 7 lineage:", evidence["summary"]["loop7_lineage"])
print("Evidence file:", out)
print("==================================================")
PY
