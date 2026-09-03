#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

echo "=================================================="
echo "OMNIS V3 — BUILD LOOPS 5 → 6 → 7"
echo "=================================================="

mkdir -p backend data logs scripts

# --------------------------------------------------
# LOOP ENGINE
# --------------------------------------------------
cat > backend/loop_engine.py <<'PY'
import json
import os
import sqlite3
import threading
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(BASE, "data", "loops.sqlite3")

_lock = threading.RLock()


def now():
    return datetime.now(timezone.utc).isoformat()


def db():
    os.makedirs(os.path.dirname(DB), exist_ok=True)

    c = sqlite3.connect(DB, timeout=30)
    c.row_factory = sqlite3.Row

    c.execute("""
        CREATE TABLE IF NOT EXISTS loop_cycles (
            cycle_id INTEGER PRIMARY KEY AUTOINCREMENT,
            loop INTEGER NOT NULL,
            parent_cycle INTEGER,
            simulation_id INTEGER,
            cycle_number INTEGER NOT NULL,
            input_state TEXT NOT NULL,
            observation TEXT NOT NULL,
            decision TEXT NOT NULL,
            action TEXT NOT NULL,
            observed_result TEXT,
            evaluation TEXT,
            next_state TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)

    c.commit()
    return c


def latest(loop=None):
    with _lock:
        c = db()

        if loop is None:
            rows = c.execute("""
                SELECT *
                FROM loop_cycles
                ORDER BY cycle_id DESC
                LIMIT 50
            """).fetchall()
        else:
            rows = c.execute("""
                SELECT *
                FROM loop_cycles
                WHERE loop=?
                ORDER BY cycle_id DESC
                LIMIT 50
            """, (int(loop),)).fetchall()

        c.close()

    return [dict(r) for r in rows]


def stats():
    with _lock:
        c = db()
        rows = c.execute("""
            SELECT loop, status, COUNT(*) AS count
            FROM loop_cycles
            GROUP BY loop, status
            ORDER BY loop, status
        """).fetchall()
        c.close()

    return [dict(r) for r in rows]


def get_cycle(cycle_id):
    with _lock:
        c = db()
        row = c.execute(
            "SELECT * FROM loop_cycles WHERE cycle_id=?",
            (int(cycle_id),)
        ).fetchone()
        c.close()

    return dict(row) if row else None


def record(
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
    status="closed",
):
    t = now()

    with _lock:
        c = db()

        cur = c.execute("""
            INSERT INTO loop_cycles (
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
            )
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            int(loop),
            parent_cycle,
            simulation_id,
            int(cycle_number),
            json.dumps(input_state, separators=(",", ":")),
            json.dumps(observation, separators=(",", ":")),
            json.dumps(decision, separators=(",", ":")),
            json.dumps(action, separators=(",", ":")),
            json.dumps(observed_result, separators=(",", ":")),
            json.dumps(evaluation, separators=(",", ":")),
            json.dumps(next_state, separators=(",", ":")),
            status,
            t,
            t,
        ))

        c.commit()
        cycle_id = cur.lastrowid
        c.close()

    return get_cycle(cycle_id)


def _simulation_rows():
    sim_db = os.path.join(BASE, "data", "simulations.sqlite3")

    if not os.path.exists(sim_db):
        return []

    c = sqlite3.connect(sim_db, timeout=30)
    c.row_factory = sqlite3.Row

    rows = c.execute("""
        SELECT *
        FROM simulations
        ORDER BY sim_id DESC
        LIMIT 20
    """).fetchall()

    c.close()
    return [dict(r) for r in rows]


def _latest_simulation():
    rows = _simulation_rows()
    return rows[0] if rows else None


def _parse_result(sim):
    try:
        return json.loads(sim.get("result") or "{}")
    except Exception:
        return {}


# --------------------------------------------------
# LOOP 5
#
# Observe current V3 simulation.
# Interpret the result.
# Make an explicit decision.
# Record action/evaluation.
# Produce next state.
# --------------------------------------------------
def close_loop5():
    sim = _latest_simulation()

    if not sim:
        raise RuntimeError("Loop 5 requires at least one simulation.")

    result = _parse_result(sim)

    observation = {
        "source": "OMNIS_V3_SIMULATION",
        "simulation_id": sim["sim_id"],
        "status": sim["status"],
        "generation": sim["generation"],
        "progress": sim["progress"],
        "result_available": bool(result),
    }

    decision = {
        "type": "simulation_state_evaluation",
        "decision": (
            "ACCEPT_COMPLETED_STATE"
            if sim["status"] == "completed"
            and float(sim["progress"]) >= 1.0
            else "REQUIRE_CONTINUATION"
        ),
    }

    action = {
        "type": "record_state_transition",
        "action": "PERSIST_LOOP5_TRANSITION",
    }

    evaluation = {
        "closed": (
            sim["status"] == "completed"
            and float(sim["progress"]) >= 1.0
        ),
        "simulation_terminal": sim["status"] in (
            "completed",
            "failed",
        ),
    }

    next_state = {
        "source_simulation_id": sim["sim_id"],
        "last_status": sim["status"],
        "last_generation": sim["generation"],
        "last_progress": sim["progress"],
        "last_result": result,
        "loop5_closed": evaluation["closed"],
    }

    return record(
        loop=5,
        parent_cycle=None,
        simulation_id=sim["sim_id"],
        cycle_number=1,
        input_state={
            "simulation": sim,
        },
        observation=observation,
        decision=decision,
        action=action,
        observed_result=result,
        evaluation=evaluation,
        next_state=next_state,
        status="closed" if evaluation["closed"] else "open",
    )


# --------------------------------------------------
# LOOP 6
#
# Consume Loop 5 state.
# Adapt the next simulation parameters.
# The adaptation is deterministic and traceable.
# --------------------------------------------------
def close_loop6():
    l5 = latest(5)

    if not l5:
        raise RuntimeError("Loop 6 requires a completed Loop 5 record.")

    parent = l5[0]
    parent_state = json.loads(parent["next_state"])

    if not parent_state.get("loop5_closed"):
        raise RuntimeError(
            "Loop 6 blocked: Loop 5 is not closed."
        )

    sim = _latest_simulation()

    previous_seed = int(sim["seed"])
    previous_generations = int(sim["generations"])

    result = parent_state.get("last_result") or {}
    generation_results = result.get("generation_results") or []

    last_value = 0

    if generation_results:
        last_value = int(
            generation_results[-1].get("value", 0)
        )

    # Deterministic adaptive transition.
    next_seed = (
        (previous_seed ^ last_value)
        & 0x7fffffff
    )

    next_generations = max(
        1,
        min(
            10000,
            previous_generations + (
                1 if last_value % 2 == 0 else 0
            ),
        ),
    )

    observation = {
        "source_loop": 5,
        "parent_cycle": parent["cycle_id"],
        "previous_seed": previous_seed,
        "previous_generations": previous_generations,
        "last_value": last_value,
    }

    decision = {
        "type": "adaptive_parameter_selection",
        "rule": "next_seed = previous_seed XOR last_value",
        "decision": "ADAPT_NEXT_SIMULATION",
    }

    action = {
        "type": "prepare_next_simulation",
        "seed": next_seed,
        "generations": next_generations,
        "debt_allowed": bool(sim["debt_allowed"]),
    }

    evaluation = {
        "adaptation_valid": (
            0 <= next_seed <= 2147483647
            and 1 <= next_generations <= 10000
        ),
        "source_state_consumed": True,
    }

    next_state = {
        "loop5_cycle": parent["cycle_id"],
        "next_seed": next_seed,
        "next_generations": next_generations,
        "debt_allowed": bool(sim["debt_allowed"]),
        "adaptation_rule": "xor_last_observed_value",
        "loop6_closed": evaluation["adaptation_valid"],
    }

    return record(
        loop=6,
        parent_cycle=parent["cycle_id"],
        simulation_id=sim["sim_id"],
        cycle_number=1,
        input_state=parent_state,
        observation=observation,
        decision=decision,
        action=action,
        observed_result={
            "last_value": last_value,
        },
        evaluation=evaluation,
        next_state=next_state,
        status="closed" if evaluation["adaptation_valid"] else "open",
    )


# --------------------------------------------------
# LOOP 7
#
# Consume Loop 6 state and execute a bounded number
# of autonomous feedback cycles.
#
# No infinite daemon.
# Explicitly bounded for safety and observability.
# --------------------------------------------------
def close_loop7(cycles=3):
    cycles = int(cycles)

    if cycles < 1 or cycles > 100:
        raise ValueError("Loop 7 cycles must be between 1 and 100.")

    l6 = latest(6)

    if not l6:
        raise RuntimeError("Loop 7 requires a completed Loop 6 record.")

    parent = l6[0]
    parent_state = json.loads(parent["next_state"])

    if not parent_state.get("loop6_closed"):
        raise RuntimeError(
            "Loop 7 blocked: Loop 6 is not closed."
        )

    seed = int(parent_state["next_seed"])
    generations = int(parent_state["next_generations"])
    debt_allowed = bool(parent_state["debt_allowed"])

    produced = []
    parent_cycle = parent["cycle_id"]

    # Import the already-existing V3 simulation engine.
    from backend import simulation_engine

    for n in range(1, cycles + 1):
        sim_start = simulation_engine.start(
            seed,
            generations,
            debt_allowed,
        )

        sim_id = sim_start["sim_id"]

        # Wait for this bounded simulation to terminate.
        # The existing engine is authoritative for execution.
        for _ in range(400):
            sim = simulation_engine.status(sim_id)

            if not sim:
                raise RuntimeError(
                    f"Loop 7 lost simulation {sim_id}."
                )

            if sim["status"] in ("completed", "failed"):
                break

            import time
            time.sleep(0.025)

        sim = simulation_engine.status(sim_id)

        if not sim:
            raise RuntimeError(
                f"Loop 7 could not recover simulation {sim_id}."
            )

        result = _parse_result(sim)

        observation = {
            "cycle": n,
            "simulation_id": sim_id,
            "status": sim["status"],
            "generation": sim["generation"],
            "progress": sim["progress"],
        }

        decision = {
            "type": "closed_loop_continuation",
            "decision": (
                "CONTINUE"
                if sim["status"] == "completed"
                else "STOP_ON_FAILURE"
            ),
        }

        action = {
            "type": "execute_adapted_simulation",
            "seed": seed,
            "generations": generations,
            "debt_allowed": debt_allowed,
        }

        evaluation = {
            "success": sim["status"] == "completed",
            "terminal": sim["status"] in (
                "completed",
                "failed",
            ),
        }

        next_seed = seed

        generation_results = result.get(
            "generation_results",
            []
        )

        if generation_results:
            last_value = int(
                generation_results[-1].get("value", 0)
            )

            next_seed = (
                (seed ^ last_value)
                & 0x7fffffff
            )

        next_state = {
            "previous_simulation_id": sim_id,
            "next_seed": next_seed,
            "generations": generations,
            "debt_allowed": debt_allowed,
            "cycle_complete": evaluation["success"],
        }

        cycle = record(
            loop=7,
            parent_cycle=parent_cycle,
            simulation_id=sim_id,
            cycle_number=n,
            input_state={
                "seed": seed,
                "generations": generations,
                "debt_allowed": debt_allowed,
            },
            observation=observation,
            decision=decision,
            action=action,
            observed_result=result,
            evaluation=evaluation,
            next_state=next_state,
            status="closed" if evaluation["success"] else "failed",
        )

        produced.append(cycle)

        parent_cycle = cycle["cycle_id"]
        seed = next_seed

        if not evaluation["success"]:
            break

    return produced


def snapshot():
    return {
        "loop5": latest(5)[:1],
        "loop6": latest(6)[:1],
        "loop7": latest(7)[:10],
        "stats": stats(),
    }
PY

# --------------------------------------------------
# PATCH MAIN — preserve all existing routes.
# --------------------------------------------------
python3 - <<'PY'
from pathlib import Path

p = Path("backend/main.py")
s = p.read_text()

imports = """
from backend.loop_engine import (
    close_loop5,
    close_loop6,
    close_loop7,
    latest as loop_latest,
    stats as loop_stats,
    snapshot as loop_snapshot,
)
"""

if "from backend.loop_engine import" not in s:
    s = imports + "\n" + s

begin = "# OMNIS_V3_LOOP_5_7_ROUTES_BEGIN"
end = "# OMNIS_V3_LOOP_5_7_ROUTES_END"

if begin in s and end in s:
    a = s.index(begin)
    b = s.index(end) + len(end)
    s = s[:a] + s[b:]

routes = r'''
# OMNIS_V3_LOOP_5_7_ROUTES_BEGIN

@app.post("/api/loops/5/close")
async def omnis_v3_close_loop5():
    return close_loop5()


@app.post("/api/loops/6/close")
async def omnis_v3_close_loop6():
    return close_loop6()


@app.post("/api/loops/7/close")
async def omnis_v3_close_loop7(payload: dict = None):
    payload = payload or {}
    cycles = payload.get("cycles", 3)
    return {
        "loop": 7,
        "cycles": close_loop7(cycles)
    }


@app.get("/api/loops/latest")
async def omnis_v3_loop_latest():
    return {
        "loops": loop_snapshot()
    }


@app.get("/api/loops/stats")
async def omnis_v3_loop_stats():
    return loop_stats()


@app.get("/api/loops/{loop_number}")
async def omnis_v3_loop_history(loop_number: int):
    if loop_number not in (5, 6, 7):
        raise HTTPException(
            status_code=400,
            detail="Supported loops: 5, 6, 7"
        )

    return {
        "loop": loop_number,
        "cycles": loop_latest(loop_number)
    }

# OMNIS_V3_LOOP_5_7_ROUTES_END
'''

if "app = FastAPI" in s:
    marker = "app = FastAPI"
    pos = s.find(marker)
    line_end = s.find("\n", pos)

    s = (
        s[:line_end + 1]
        + "\n"
        + routes
        + "\n"
        + s[line_end + 1:]
    )
else:
    s += "\n" + routes + "\n"

# Ensure HTTPException exists.
before_app = s.split("app = FastAPI", 1)[0]

if "HTTPException" not in before_app:
    if "from fastapi import" in s:
        s = s.replace(
            "from fastapi import",
            "from fastapi import HTTPException,",
            1
        )
    else:
        s = "from fastapi import HTTPException\n" + s

p.write_text(s)
PY

# --------------------------------------------------
# V3 DASHBOARD — add loop controls without replacing
# the existing dashboard.
# --------------------------------------------------
python3 - <<'PY'
from pathlib import Path
import re

p = Path("frontend/static/index.html")
s = p.read_text()

# Never allow V2 identity.
s = re.sub(
    r'<title>.*?</title>',
    '<title>OMNIS V3 — System Command</title>',
    s,
    count=1,
    flags=re.S,
)

s = s.replace("OMNIS V2", "OMNIS V3")
s = s.replace("OMNIS_V2", "OMNIS_V3")

if 'id="loop57Panel"' not in s:
    panel = r'''
<div class="panel" id="loop57Panel">
<div class="title">CLOSED LOOP CONTROL</div>
<div class="body">

<div class="actions">
<button class="primary" onclick="closeLoop5()">CLOSE LOOP 5</button>
<button class="primary" onclick="closeLoop6()">CLOSE LOOP 6</button>
<button class="primary" onclick="closeLoop7()">RUN LOOP 7</button>
</div>

<div class="reason" id="loop57Status">
Loop 5 → Loop 6 → Loop 7 ready.
</div>

<pre id="loop57Telemetry">Awaiting loop execution.</pre>

</div>
</div>
'''

    if "</main>" in s:
        s = s.replace("</main>", panel + "\n</main>", 1)
    else:
        s += panel

logic = r'''
<script id="omnis-v3-loop-logic">
(function(){

async function loopAPI(path, options){
    const response = await fetch(
        path,
        options || {}
    );

    const text = await response.text();

    let data;

    try {
        data = JSON.parse(text);
    } catch {
        throw new Error(
            "Invalid JSON response from " + path
        );
    }

    if (!response.ok){
        throw new Error(
            data.detail ||
            data.error ||
            ("HTTP " + response.status)
        );
    }

    return data;
}

function loopStatus(text){
    const el =
        document.getElementById("loop57Status");

    if (el)
        el.textContent = text;
}

function loopTelemetry(data){
    const el =
        document.getElementById("loop57Telemetry");

    if (el)
        el.textContent =
            JSON.stringify(data, null, 2);
}

window.closeLoop5 = async function(){
    loopStatus("Closing Loop 5...");

    try {
        const result =
            await loopAPI("/api/loops/5/close", {
                method: "POST"
            });

        loopStatus(
            "Loop 5: " +
            (result.status || "closed")
        );

        loopTelemetry(result);
    } catch(error){
        loopStatus(
            "Loop 5 failed: " + error.message
        );
    }
};

window.closeLoop6 = async function(){
    loopStatus("Closing Loop 6...");

    try {
        const result =
            await loopAPI("/api/loops/6/close", {
                method: "POST"
            });

        loopStatus(
            "Loop 6: " +
            (result.status || "closed")
        );

        loopTelemetry(result);
    } catch(error){
        loopStatus(
            "Loop 6 failed: " + error.message
        );
    }
};

window.closeLoop7 = async function(){
    loopStatus("Running bounded Loop 7...");

    try {
        const result =
            await loopAPI(
                "/api/loops/7/close",
                {
                    method: "POST",
                    headers: {
                        "Content-Type":
                            "application/json"
                    },
                    body: JSON.stringify({
                        cycles: 3
                    })
                }
            );

        loopStatus("Loop 7: execution complete.");
        loopTelemetry(result);
    } catch(error){
        loopStatus(
            "Loop 7 failed: " + error.message
        );
    }
};

async function refreshLoopTelemetry(){
    try {
        const result =
            await loopAPI("/api/loops/latest");

        const el =
            document.getElementById("loop57Telemetry");

        if (el)
            el.textContent =
                JSON.stringify(
                    result,
                    null,
                    2
                );
    } catch {}
}

refreshLoopTelemetry();

setInterval(
    refreshLoopTelemetry,
    3000
);

})();
</script>
'''

s = re.sub(
    r'<script id="omnis-v3-loop-logic">.*?</script>',
    '',
    s,
    flags=re.S
)

s = s.replace(
    "</body>",
    logic + "\n</body>"
)

p.write_text(s)
PY

# --------------------------------------------------
# COMPILE CHECK BEFORE SERVER RESTART.
# --------------------------------------------------
python3 -m py_compile \
    backend/main.py \
    backend/loop_engine.py

echo
echo "=== PYTHON COMPILE: PASS ==="

# --------------------------------------------------
# Restart exactly one V3 server.
# --------------------------------------------------
pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

echo
echo "=== PROCESS ==="
ps -ef | grep -E '[u]vicorn backend\.main:app' || true

echo
echo "=== DASHBOARD ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/ \
    | grep -o '<title>[^<]*</title>' \
    | head -1

echo
echo "=== HEALTH ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/health

echo
echo
echo "=== LOOP ROUTES ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/openapi.json |
python3 -c '
import json,sys
p=json.load(sys.stdin).get("paths",{})
for x in sorted(p):
    if "/api/loops/" in x:
        print(x)
'

echo
echo "=== EXISTING SIMULATION ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/sim/latest

echo
echo
echo "=== CLOSE LOOP 5 ==="
L5="$(
curl -sS --max-time 10 \
    -X POST \
    http://127.0.0.1:5000/api/loops/5/close
)"
echo "$L5"

echo
echo "=== CLOSE LOOP 6 ==="
L6="$(
curl -sS --max-time 10 \
    -X POST \
    http://127.0.0.1:5000/api/loops/6/close
)"
echo "$L6"

echo
echo "=== RUN LOOP 7 — 3 BOUNDED CYCLES ==="
L7="$(
curl -sS --max-time 30 \
    -X POST \
    -H 'Content-Type: application/json' \
    -d '{"cycles":3}' \
    http://127.0.0.1:5000/api/loops/7/close
)"
echo "$L7"

echo
echo "=== LOOP STATS ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/loops/stats

echo
echo
echo "=== LOOP SNAPSHOT ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/loops/latest

echo
echo
echo "=================================================="
echo "OMNIS V3 — LOOPS 5 → 6 → 7 BUILT"
echo "=================================================="
echo "Loop 5: CLOSED FEEDBACK"
echo "Loop 6: ADAPTIVE TRANSITION"
echo "Loop 7: BOUNDED PERSISTENT FEEDBACK"
echo "=================================================="
