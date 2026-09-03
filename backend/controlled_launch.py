"""
OMNIS V3 — CONTROLLED NOMINAL LAUNCH

Launches exactly one simulation through the existing
authoritative simulation_engine.start() boundary.

Safety properties:
    - Requires operational_release preflight.
    - Uses the terminal next_seed.
    - Starts exactly one simulation.
    - Polls its authoritative database state.
    - Records the outcome.
    - Never modifies freeze_state.py.
    - Never bypasses simulation_engine.start().
"""

import json
import os
import time
from datetime import datetime, timezone

from .operational_release import release_one
from . import simulation_engine


BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULT_FILE = os.path.join(
    BASE,
    "data",
    "controlled_launch_result.json"
)


def now():
    return datetime.now(timezone.utc).isoformat()


def write_result(data):
    os.makedirs(os.path.dirname(RESULT_FILE), exist_ok=True)

    tmp = RESULT_FILE + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())

    os.replace(tmp, RESULT_FILE)


def launch():
    print("=" * 80)
    print("OMNIS V3 — CONTROLLED NOMINAL LAUNCH")
    print("=" * 80)

    release = release_one()

    seed = release["seed"]
    generations = release["generations"]
    debt_allowed = release["debt_allowed"]

    print()
    print("AUTHORIZED EXECUTION:")
    print("  seed:", seed)
    print("  generations:", generations)
    print("  debt_allowed:", debt_allowed)
    print()

    print("Launching through simulation_engine.start()...")

    started = now()

    launch_result = simulation_engine.start(
        seed,
        generations,
        debt_allowed
    )

    sim_id = launch_result["sim_id"]

    print()
    print("SIMULATION STARTED")
    print("  sim_id:", sim_id)
    print("  status:", launch_result["status"])

    history = []

    while True:
        state = simulation_engine.status(sim_id)

        if state is None:
            raise RuntimeError(
                f"Simulation {sim_id} disappeared from authoritative DB."
            )

        snapshot = {
            "timestamp": now(),
            "status": state["status"],
            "generation": state["generation"],
            "progress": state["progress"],
        }

        history.append(snapshot)

        print(
            "  status={status} generation={generation}/{total} "
            "progress={progress:.3f}".format(
                status=state["status"],
                generation=state["generation"],
                total=generations,
                progress=float(state["progress"]),
            )
        )

        if state["status"] in ("completed", "failed"):
            finished = now()

            result = {
                "schema": "OMNIS_V3_CONTROLLED_LAUNCH_RESULT_V1",
                "started_at": started,
                "finished_at": finished,
                "sim_id": sim_id,
                "seed": seed,
                "generations": generations,
                "debt_allowed": debt_allowed,
                "final_status": state["status"],
                "final_generation": state["generation"],
                "final_progress": state["progress"],
                "error": state["error"],
                "history": history,
            }

            write_result(result)

            print()
            print("=" * 80)
            print("CONTROLLED EXECUTION COMPLETE")
            print("=" * 80)
            print("sim_id:", sim_id)
            print("final_status:", state["status"])
            print("generation:", state["generation"])
            print("progress:", state["progress"])
            print("result_file:", RESULT_FILE)

            if state["status"] == "failed":
                print()
                print("EXECUTION FAILED")
                print(state["error"])
                raise RuntimeError(
                    "Controlled simulation failed."
                )

            print()
            print("PASS: controlled simulation completed")
            return result

        time.sleep(0.10)


if __name__ == "__main__":
    launch()
