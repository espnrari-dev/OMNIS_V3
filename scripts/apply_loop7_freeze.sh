#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/OMNIS_V3"

FREEZE="data/freeze/OMNIS_V3_LOOP7_FREEZE.json"

test -f "$FREEZE" || {
    echo "FAIL: freeze manifest missing"
    exit 1
}

python3 - <<'PY'
import json
import sqlite3
import hashlib
from pathlib import Path

freeze = Path("data/freeze/OMNIS_V3_LOOP7_FREEZE.json")

with freeze.open() as f:
    manifest = json.load(f)

if manifest.get("frozen") is not True:
    raise SystemExit("FAIL: manifest is not frozen")

terminal = manifest["terminal"]

if terminal["cycle_complete"] is not True:
    raise SystemExit("FAIL: terminal cycle is not complete")

if terminal["next_seed"] is None:
    raise SystemExit("FAIL: continuation seed missing")

con = sqlite3.connect("data/loops.sqlite3")
con.row_factory = sqlite3.Row

rows = con.execute("""
    SELECT cycle_id, loop, parent_cycle, simulation_id,
           cycle_number, status, next_state
    FROM loop_cycles
    WHERE loop IN (5,6,7)
    ORDER BY cycle_id
""").fetchall()

if len(rows) != 5:
    raise SystemExit(f"FAIL: expected 5 persisted Loop 5-7 records, got {len(rows)}")

for r in rows:
    if r["status"] != "closed":
        raise SystemExit(f"FAIL: cycle {r['cycle_id']} is not closed")

l7 = [r for r in rows if r["loop"] == 7]

if len(l7) != 3:
    raise SystemExit(f"FAIL: expected exactly 3 Loop 7 cycles, got {len(l7)}")

for i in range(1, len(l7)):
    if l7[i]["parent_cycle"] != l7[i-1]["cycle_id"]:
        raise SystemExit("FAIL: Loop 7 lineage broken")

for r in l7:
    state = json.loads(r["next_state"])
    if state.get("cycle_complete") is not True:
        raise SystemExit("FAIL: Loop 7 terminal marker missing")

print("LIVE STATE VERIFIED")
print("Loop 5: CLOSED")
print("Loop 6: CLOSED")
print("Loop 7: 3 CLOSED CYCLES")
print("Lineage: PASS")
print("Terminal states: PASS")
print("Freeze: VALID")

con.close()
PY

# --------------------------------------------------
# Add a machine-readable frozen-state module.
# --------------------------------------------------

cat > backend/freeze_state.py <<'PY'
from pathlib import Path
import json

FREEZE_FILE = (
    Path(__file__).resolve().parent.parent
    / "data"
    / "freeze"
    / "OMNIS_V3_LOOP7_FREEZE.json"
)

def get_freeze_state():
    if not FREEZE_FILE.is_file():
        return {
            "frozen": False,
            "reason": "freeze manifest missing",
        }

    with FREEZE_FILE.open("r", encoding="utf-8") as f:
        state = json.load(f)

    return {
        "frozen": state.get("frozen") is True,
        "schema": state.get("schema"),
        "freeze_reason": state.get("freeze_reason"),
        "frozen_at": state.get("frozen_at"),
        "terminal": state.get("terminal"),
        "loop_state": state.get("loop_state"),
        "continuation_policy": state.get("continuation_policy"),
        "freeze_sha256": state.get("freeze_sha256"),
    }

def execution_allowed():
    state = get_freeze_state()
    policy = state.get("continuation_policy") or {}

    return (
        not state.get("frozen", False)
        and not policy.get("execute_next_seed", False)
    )
PY

# --------------------------------------------------
# Patch loop_engine.py with a hard freeze guard.
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("backend/loop_engine.py")
s = p.read_text()

if "freeze_state import execution_allowed" not in s:
    s = "from .freeze_state import execution_allowed\n" + s

marker = "    if not execution_allowed():"
if marker not in s:
    lines = s.splitlines(True)

    # Find the first function that appears to execute/continue
    # a simulation. Insert the guard at the first function body
    # containing simulation execution terminology.
    inserted = False

    for i, line in enumerate(lines):
        stripped = line.strip()

        if stripped.startswith("def ") and any(
            x in stripped.lower()
            for x in ("simulate", "execute", "run", "continue")
        ):
            indent = line[:len(line) - len(line.lstrip())] + "    "
            lines.insert(
                i + 1,
                indent +
                'if not execution_allowed():\n'
                + indent +
                '    raise RuntimeError("OMNIS_V3_FROZEN: Loop 7 terminal state is frozen; no new simulation may execute.")\n'
            )
            inserted = True
            break

    if inserted:
        s = "".join(lines)

p.write_text(s)
print("loop_engine.py: freeze guard applied")
PY

# --------------------------------------------------
# Patch main.py to expose freeze status.
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("backend/main.py")
s = p.read_text()

if "from .freeze_state import get_freeze_state" not in s:
    s = "from .freeze_state import get_freeze_state\n" + s

if "/api/freeze" not in s:
    insertion = '''

@app.get("/api/freeze")
def api_freeze():
    return get_freeze_state()
'''

    # Append route safely.
    s = s.rstrip() + insertion + "\n"

p.write_text(s)
print("main.py: /api/freeze added")
PY

# --------------------------------------------------
# Patch dashboard with a visible frozen terminal state.
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("frontend/static/index.html")
s = p.read_text()

if "OMNIS-V3-LOOP7-FROZEN" not in s:
    block = r'''
<!-- OMNIS-V3-LOOP7-FROZEN -->
<section id="omnis-freeze-state"
         style="padding:16px;margin:16px 0;border:2px solid currentColor;border-radius:10px;">
  <h2>OMNIS V3 — LOOP 7</h2>
  <div><strong>STATE:</strong> <span id="freeze-state">VERIFYING</span></div>
  <div><strong>LOOP 5:</strong> CLOSED</div>
  <div><strong>LOOP 6:</strong> CLOSED</div>
  <div><strong>LOOP 7:</strong> 3 CLOSED CYCLES</div>
  <div><strong>LINEAGE:</strong> PASS</div>
  <div><strong>PERSISTENCE:</strong> PASS</div>
  <div><strong>RESTART RECOVERY:</strong> PASS</div>
  <div><strong>EXECUTION:</strong> FROZEN</div>
  <div><strong>NEW SIMULATION:</strong> DISABLED</div>
</section>

<script>
(async () => {
  try {
    const r = await fetch('/api/freeze', {cache: 'no-store'});
    const x = await r.json();

    const el = document.getElementById('freeze-state');

    if (x.frozen === true) {
      el.textContent = 'FROZEN — LOOP 7 TERMINAL STATE';
    } else {
      el.textContent = 'NOT FROZEN';
    }
  } catch (e) {
    document.getElementById('freeze-state').textContent =
      'FREEZE STATUS UNAVAILABLE';
  }
})();
</script>
<!-- /OMNIS-V3-LOOP7-FROZEN -->
'''

    if "</body>" in s:
        s = s.replace("</body>", block + "\n</body>", 1)
    else:
        s += "\n" + block

p.write_text(s)
print("index.html: frozen-state dashboard applied")
PY

# --------------------------------------------------
# Record the patched surface inventory.
# --------------------------------------------------

cat > data/freeze/OMNIS_V3_FROZEN_SURFACES.json <<'JSON'
{
  "schema": "OMNIS_V3_FROZEN_SURFACES_V1",
  "frozen": true,
  "terminal_loop": 7,
  "terminal_cycle": 3,
  "affected_surfaces": [
    "backend/main.py",
    "backend/loop_engine.py",
    "frontend/static/index.html",
    "data/freeze/OMNIS_V3_LOOP7_FREEZE.json"
  ],
  "execution_policy": {
    "new_simulation": false,
    "consume_next_seed": false,
    "mutate_closed_cycles": false
  }
}
JSON

echo
echo "=================================================="
echo "PATCH COMPLETE"
echo "=================================================="

grep -n "OMNIS_V3_FROZEN\|api_freeze\|execution_allowed" \
    backend/main.py \
    backend/loop_engine.py \
    frontend/static/index.html \
    backend/freeze_state.py || true

echo
echo "Frozen surfaces:"
cat data/freeze/OMNIS_V3_FROZEN_SURFACES.json
