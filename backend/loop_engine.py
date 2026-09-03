from .freeze_state import execution_allowed, get_freeze_state
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
def _assert_loop_execution_allowed():
    """
    AUTHORITATIVE OMNIS V3 LOOP DISPATCH GATE.

    Loop execution must not initiate a new simulation while
    the global freeze authority reports execution blocked.
    """
    if not execution_allowed():
        raise RuntimeError(
            "OMNIS V3 loop execution blocked by freeze policy"
        )


def _assert_loop_dispatch_execution_allowed():
    """
    AUTHORITATIVE OMNIS V3 LOOP PRE-DISPATCH EXECUTION GATE.

    The loop engine is itself an execution authority because
    it can request a new simulation from the autonomous loop.
    """
    state = get_freeze_state()

    if not execution_allowed():
        raise RuntimeError(
            "OMNIS V3 loop execution blocked before dispatch: "
            + __import__("json").dumps(
                state,
                sort_keys=True
            )
        )


def close_loop7(cycles=3):
    _assert_loop_dispatch_execution_allowed()

    _assert_loop_execution_allowed()

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
