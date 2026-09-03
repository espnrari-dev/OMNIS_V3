import json
import os
import sqlite3
import threading
import time
import traceback
from datetime import datetime, timezone

from .freeze_state import execution_allowed, get_freeze_state, consume_execution_authority

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(BASE, "data", "simulations.sqlite3")

_lock = threading.RLock()


class ExecutionFrozenError(RuntimeError):
    """Raised when simulation execution is blocked by the OMNIS freeze gate."""
    pass


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


def _assert_execution_allowed():
    """
    AUTHORITATIVE OMNIS V3 EXECUTION GATE.

    This is deliberately located at the simulation-engine entry point
    rather than relying on individual HTTP routes or loop callers.

    Any caller attempting to create a simulation must pass this gate.
    """

    state = get_freeze_state()

    if not execution_allowed():
        raise ExecutionFrozenError(
            "OMNIS V3 execution blocked by freeze policy: "
            f"{json.dumps(state, sort_keys=True)}"
        )


def start(seed, generations, debt_allowed):
    """
    Start one simulation.

    Execution authorization is enforced here, at the engine boundary.
    """

    _assert_execution_allowed()

    # Consume the one-shot authority before creating
    # the execution record or worker thread.
    authorization = consume_execution_authority()

    # Use authoritative terminal parameters when supplied
    # by the release authority.
    seed = int(authorization["seed"])
    generations = int(authorization["generations"])
    debt_allowed = bool(
        authorization.get("debt_allowed", debt_allowed)
    )

    with _lock:
        c = db()
        t = now()

        cur = c.execute("""
            INSERT INTO simulations
            (seed, generations, debt_allowed, status, generation, progress,
             created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
        args=(
            sim_id,
            int(seed),
            int(generations),
            bool(debt_allowed),
        ),
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
        state = {
            "seed": seed,
            "debt_allowed": debt_allowed,
            "generation_results": []
        }

        for generation in range(1, generations + 1):
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
                result=json.dumps(
                    state,
                    separators=(",", ":")
                )
            )

            time.sleep(0.05)

        update(
            sim_id,
            status="completed",
            generation=generations,
            progress=1.0,
            result=json.dumps(
                state,
                separators=(",", ":")
            ),
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
