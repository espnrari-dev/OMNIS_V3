#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

echo "=================================================="
echo "OMNIS V3 — PERMANENT LIVE SIMULATION REPAIR"
echo "=================================================="

mkdir -p data logs scripts

# --------------------------------------------------
# Persistent simulation engine.
# --------------------------------------------------
cat > backend/simulation_engine.py <<'PY'
import json
import os
import sqlite3
import threading
import time
import traceback
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(BASE, "data", "simulations.sqlite3")

_lock = threading.RLock()

def now():
    return datetime.now(timezone.utc).isoformat()

def db():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = sqlite3.connect(DB, timeout=30)
    c.row_factory = sqlite3.Row
    c.execute("""
        CREATE TABLE IF NOT EXISTS simulations (
            sim_id INTEGER PRIMARY KEY AUTOINCREMENT,
            seed INTEGER NOT NULL,
            generations INTEGER NOT NULL,
            debt_allowed INTEGER NOT NULL,
            status TEXT NOT NULL,
            generation INTEGER NOT NULL DEFAULT 0,
            progress REAL NOT NULL DEFAULT 0,
            result TEXT,
            error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    c.commit()
    return c

def start(seed, generations, debt_allowed):
    with _lock:
        c = db()
        t = now()
        cur = c.execute("""
            INSERT INTO simulations
            (seed,generations,debt_allowed,status,generation,progress,
             created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,?)
        """, (
            int(seed),
            int(generations),
            1 if debt_allowed else 0,
            "running",
            0,
            0.0,
            t,
            t
        ))
        sim_id = cur.lastrowid
        c.commit()
        c.close()

    thread = threading.Thread(
        target=run,
        args=(sim_id, int(seed), int(generations), bool(debt_allowed)),
        daemon=False
    )
    thread.start()

    return {
        "sim_id": sim_id,
        "status": "running",
        "generation": 0,
        "progress": 0.0
    }

def update(sim_id, **fields):
    fields["updated_at"] = now()
    sets = ", ".join(f"{k}=?" for k in fields)
    values = list(fields.values()) + [sim_id]

    with _lock:
        c = db()
        c.execute(
            f"UPDATE simulations SET {sets} WHERE sim_id=?",
            values
        )
        c.commit()
        c.close()

def run(sim_id, seed, generations, debt_allowed):
    try:
        # Deterministic simulation state.
        state = {
            "seed": seed,
            "debt_allowed": debt_allowed,
            "generation_results": []
        }

        for generation in range(1, generations + 1):
            # Deterministic state transition.
            value = (
                (seed * 1103515245 + generation * 12345)
                & 0x7fffffff
            )

            state["generation_results"].append({
                "generation": generation,
                "value": value
            })

            progress = generation / generations

            update(
                sim_id,
                status="running",
                generation=generation,
                progress=progress,
                result=json.dumps(state, separators=(",", ":"))
            )

            time.sleep(0.05)

        update(
            sim_id,
            status="completed",
            generation=generations,
            progress=1.0,
            result=json.dumps(state, separators=(",", ":")),
            error=None
        )

    except Exception:
        update(
            sim_id,
            status="failed",
            error=traceback.format_exc()
        )

def status(sim_id):
    with _lock:
        c = db()
        row = c.execute(
            "SELECT * FROM simulations WHERE sim_id=?",
            (int(sim_id),)
        ).fetchone()
        c.close()

    if not row:
        return None

    return dict(row)

def latest():
    with _lock:
        c = db()
        rows = c.execute("""
            SELECT * FROM simulations
            ORDER BY sim_id DESC
            LIMIT 20
        """).fetchall()
        c.close()

    return [dict(r) for r in rows]

def stats():
    with _lock:
        c = db()
        rows = c.execute("""
            SELECT status, COUNT(*) AS count
            FROM simulations
            GROUP BY status
            ORDER BY status
        """).fetchall()
        c.close()

    return [dict(r) for r in rows]
PY

# --------------------------------------------------
# Patch backend.main without destroying existing
# application routes.
# --------------------------------------------------
python3 - <<'PY'
from pathlib import Path

p = Path("backend/main.py")
s = p.read_text()

if "simulation_engine" not in s:
    imports = """
from backend.simulation_engine import (
    start as simulation_start,
    status as simulation_status,
    latest as simulation_latest,
    stats as simulation_stats,
)
"""
    marker = "\n"
    s = imports + s

# Remove previously installed permanent route block.
start_marker = "# OMNIS_V3_PERMANENT_SIM_ROUTES_BEGIN"
end_marker = "# OMNIS_V3_PERMANENT_SIM_ROUTES_END"

if start_marker in s and end_marker in s:
    a = s.index(start_marker)
    b = s.index(end_marker) + len(end_marker)
    s = s[:a] + s[b:]

routes = r'''
# OMNIS_V3_PERMANENT_SIM_ROUTES_BEGIN

@app.post("/api/sim/start")
async def omnis_v3_sim_start(payload: dict):
    seed = payload.get("seed", 42)
    generations = payload.get("generations", 10)
    debt_allowed = payload.get("debt_allowed", False)

    if not isinstance(seed, int) or seed < 0 or seed > 2147483647:
        raise HTTPException(
            status_code=400,
            detail="seed must be an integer from 0 to 2147483647"
        )

    if not isinstance(generations, int) or generations < 1 or generations > 10000:
        raise HTTPException(
            status_code=400,
            detail="generations must be an integer from 1 to 10000"
        )

    return simulation_start(seed, generations, debt_allowed)


@app.get("/api/sim/status/{sim_id}")
async def omnis_v3_sim_status(sim_id: int):
    result = simulation_status(sim_id)

    if result is None:
        raise HTTPException(
            status_code=404,
            detail="simulation not found"
        )

    return result


@app.get("/api/sim/latest")
async def omnis_v3_sim_latest():
    rows = simulation_latest()

    return {
        "lineages": rows,
        "simulations": rows
    }


@app.get("/api/sim/stats")
async def omnis_v3_sim_stats():
    return simulation_stats()

# OMNIS_V3_PERMANENT_SIM_ROUTES_END
'''

# Install immediately before the first route-independent app startup
# area, while preserving the existing application.
anchor = "app = FastAPI"

pos = s.find(anchor)

if pos >= 0:
    # Put routes after FastAPI construction.
    line_end = s.find("\n", pos)
    s = s[:line_end + 1] + "\n" + routes + "\n" + s[line_end + 1:]
else:
    s += "\n" + routes + "\n"

p.write_text(s)
PY

# --------------------------------------------------
# Make sure FastAPI exception support exists.
# --------------------------------------------------
python3 - <<'PY'
from pathlib import Path

p = Path("backend/main.py")
s = p.read_text()

if "HTTPException" not in s.split("app = FastAPI", 1)[0]:
    if "from fastapi import" in s:
        s = s.replace(
            "from fastapi import",
            "from fastapi import HTTPException,"
            ,
            1
        )
    else:
        s = "from fastapi import HTTPException\n" + s

p.write_text(s)
PY

# --------------------------------------------------
# Kill every old V3 process.
# --------------------------------------------------
pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

# --------------------------------------------------
# Start exactly one persistent V3 server.
# --------------------------------------------------
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
curl -sS --max-time 5 http://127.0.0.1:5000/ \
    | grep -o '<title>[^<]*</title>' | head -1

echo
echo "=== HEALTH ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/health

echo
echo
echo "=== START REAL SIMULATION ==="

RESULT="$(
curl -sS --max-time 5 \
    -X POST \
    -H 'Content-Type: application/json' \
    -d '{"seed":42,"generations":10,"debt_allowed":true}' \
    http://127.0.0.1:5000/api/sim/start
)"

echo "$RESULT"

SIM_ID="$(python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("sim_id",""))
except:
    print("")
' <<< "$RESULT")"

if [ -n "$SIM_ID" ]; then
    echo
    echo "=== LIVE SIMULATION PROGRESS ==="

    for i in $(seq 1 20); do
        curl -sS --max-time 5 \
            "http://127.0.0.1:5000/api/sim/status/$SIM_ID"
        echo

        STATUS="$(
            curl -sS --max-time 5 \
                "http://127.0.0.1:5000/api/sim/status/$SIM_ID" |
            python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("status",""))
except:
    print("")
'
        )"

        case "$STATUS" in
            completed|failed)
                break
                ;;
        esac

        sleep 1
    done
fi

echo
echo "=== LATEST ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/sim/latest

echo
echo
echo "=== STATS ==="
curl -sS --max-time 5 \
    http://127.0.0.1:5000/api/sim/stats

echo
echo
echo "=================================================="
echo "OMNIS V3 — PERMANENT SIMULATION REPAIR COMPLETE"
echo "=================================================="
