#!/usr/bin/env python3

from pathlib import Path
import json
import hashlib
import inspect
import os
import subprocess
import sys
from datetime import datetime, timezone

BASE = Path(__file__).resolve().parent

FREEZE = BASE / "data/freeze/OMNIS_V3_LOOP7_FREEZE.json"
RELEASE = BASE / "data/freeze/OMNIS_V3_OPERATIONAL_RELEASE.json"
RESULT = BASE / "data/controlled_launch_result.json"

FILES = {
    "freeze_state.py": BASE / "backend/freeze_state.py",
    "operational_release.py": BASE / "backend/operational_release.py",
    "simulation_engine.py": BASE / "backend/simulation_engine.py",
    "controlled_launch.py": BASE / "backend/controlled_launch.py",
}

PASS = 0
FAIL = 0
WARN = 0


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"[PASS] {name}")
        if detail:
            print(f"       {detail}")
    else:
        FAIL += 1
        print(f"[FAIL] {name}")
        if detail:
            print(f"       {detail}")


def warn(name, detail=""):
    global WARN
    WARN += 1
    print(f"[WARN] {name}")
    if detail:
        print(f"       {detail}")


def read_json(path):
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        return {"__read_error__": str(e)}


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


print("=" * 76)
print("OMNIS V3 — POST-EXECUTION CONSOLIDATED AUDIT")
print("=" * 76)
print("timestamp:", datetime.now(timezone.utc).isoformat())
print("base:", BASE)
print()

# ------------------------------------------------------------
# 1. REQUIRED FILES
# ------------------------------------------------------------

print("=== 1. REQUIRED AUTHORITY / LAUNCH FILES ===")

for name, path in FILES.items():
    check(
        f"{name} exists",
        path.is_file(),
        str(path),
    )

print()

# ------------------------------------------------------------
# 2. PYTHON COMPILE
# ------------------------------------------------------------

print("=== 2. PYTHON SYNTAX / COMPILE ===")

compile_targets = [
    str(path)
    for path in FILES.values()
    if path.is_file()
]

proc = subprocess.run(
    [sys.executable, "-m", "py_compile", *compile_targets],
    capture_output=True,
    text=True,
)

check(
    "authority and launch modules compile",
    proc.returncode == 0,
    proc.stderr.strip(),
)

print()

# ------------------------------------------------------------
# 3. FREEZE MANIFEST
# ------------------------------------------------------------

print("=== 3. LOOP-7 FREEZE STATE ===")

freeze = read_json(FREEZE)
release = read_json(RELEASE)
result = read_json(RESULT)

check(
    "freeze manifest exists",
    isinstance(freeze, dict),
)

if isinstance(freeze, dict):
    check(
        "Loop-7 remains frozen",
        freeze.get("frozen") is True,
        f"frozen={freeze.get('frozen')}",
    )

    check(
        "freeze is terminal",
        isinstance(freeze.get("terminal"), dict),
    )

    terminal = freeze.get("terminal") or {}

    print("  simulation_id:", terminal.get("simulation_id"))
    print("  next_seed:", terminal.get("next_seed"))
    print("  generations:", terminal.get("generations"))
    print("  debt_allowed:", terminal.get("debt_allowed"))
    print("  cycle_complete:", terminal.get("cycle_complete"))

else:
    terminal = {}

print()

# ------------------------------------------------------------
# 4. RELEASE STATE
# ------------------------------------------------------------

print("=== 4. OPERATIONAL AUTHORITY STATE ===")

check(
    "operational release exists",
    isinstance(release, dict),
)

if isinstance(release, dict):
    check(
        "release schema is correct",
        release.get("schema")
        == "OMNIS_V3_OPERATIONAL_RELEASE_V1",
        release.get("schema"),
    )

    check(
        "release authorized",
        release.get("authorized") is True,
        str(release.get("authorized")),
    )

    check(
        "release consumed after execution",
        release.get("consumed") is True,
        f"consumed={release.get('consumed')}",
    )

    if release.get("consumed") is True:
        print("  consumed_at:", release.get("consumed_at"))

    check(
        "release seed matches frozen terminal",
        release.get("seed") == terminal.get("next_seed"),
        f"release={release.get('seed')} terminal={terminal.get('next_seed')}",
    )

    check(
        "release generations match frozen terminal",
        release.get("generations") == terminal.get("generations"),
        f"release={release.get('generations')} terminal={terminal.get('generations')}",
    )

    check(
        "release debt policy matches frozen terminal",
        bool(release.get("debt_allowed"))
        == bool(terminal.get("debt_allowed")),
        f"release={release.get('debt_allowed')} terminal={terminal.get('debt_allowed')}",
    )

    check(
        "release simulation ID matches frozen terminal",
        release.get("source_simulation_id")
        == terminal.get("simulation_id"),
        f"release={release.get('source_simulation_id')} terminal={terminal.get('simulation_id')}",
    )

    freeze_hash = freeze.get("freeze_sha256") if isinstance(freeze, dict) else None

    check(
        "release points to frozen manifest hash",
        release.get("source_freeze_sha256") == freeze_hash,
        f"release={release.get('source_freeze_sha256')} freeze={freeze_hash}",
    )

print()

# ------------------------------------------------------------
# 5. AUTHORITATIVE DECISION AFTER CONSUMPTION
# ------------------------------------------------------------

print("=== 5. EXECUTION AUTHORITY AFTER COMPLETION ===")

try:
    from backend.freeze_state import (
        execution_allowed,
        get_freeze_state,
    )

    state = get_freeze_state()
    allowed = execution_allowed()

    print("execution_allowed:", allowed)

    check(
        "consumed release no longer authorizes execution",
        allowed is False,
        f"execution_allowed={allowed}",
    )

except Exception as e:
    check(
        "freeze authority can be imported",
        False,
        repr(e),
    )

print()

# ------------------------------------------------------------
# 6. CONTROLLED RESULT
# ------------------------------------------------------------

print("=== 6. CONTROLLED EXECUTION RESULT ===")

check(
    "controlled result exists",
    isinstance(result, dict),
)

if isinstance(result, dict):
    check(
        "result schema is correct",
        result.get("schema")
        == "OMNIS_V3_CONTROLLED_LAUNCH_RESULT_V1",
        result.get("schema"),
    )

    check(
        "result has no error",
        result.get("error") is None,
        f"error={result.get('error')}",
    )

    check(
        "simulation completed",
        result.get("final_status") == "completed",
        result.get("final_status"),
    )

    check(
        "final generation reached authorized generation count",
        result.get("final_generation")
        == result.get("generations")
        == terminal.get("generations"),
        (
            f"final={result.get('final_generation')} "
            f"result_generations={result.get('generations')} "
            f"authorized={terminal.get('generations')}"
        ),
    )

    check(
        "final progress is 1.0",
        result.get("final_progress") == 1.0,
        str(result.get("final_progress")),
    )

    check(
        "result seed matches authorization",
        result.get("seed") == release.get("seed"),
        f"result={result.get('seed')} release={release.get('seed')}",
    )

    check(
        "result debt policy matches authorization",
        bool(result.get("debt_allowed"))
        == bool(release.get("debt_allowed")),
        f"result={result.get('debt_allowed')} release={release.get('debt_allowed')}",
    )

    history = result.get("history")

    check(
        "execution history exists",
        isinstance(history, list) and len(history) > 0,
        f"history_entries={len(history) if isinstance(history, list) else 0}",
    )

    if isinstance(history, list) and history:
        last = history[-1]

        check(
            "history terminates in completed state",
            last.get("status") == "completed",
            str(last),
        )

        check(
            "history terminates at final generation",
            last.get("generation")
            == result.get("final_generation"),
            f"history={last.get('generation')} final={result.get('final_generation')}",
        )

print()

# ------------------------------------------------------------
# 7. FILE HASHES
# ------------------------------------------------------------

print("=== 7. CURRENT AUTHORITY FILE INTEGRITY ===")

for name, path in FILES.items():
    if path.is_file():
        try:
            print(f"{name}:")
            print(f"  sha256={sha256(path)}")
            print(f"  bytes={path.stat().st_size}")
        except Exception as e:
            warn(
                f"could not hash {name}",
                repr(e),
            )

print()

# ------------------------------------------------------------
# 8. SINGLE-AUTHORITY STRUCTURAL CHECK
# ------------------------------------------------------------

print("=== 8. AUTHORITY STRUCTURE ===")

freeze_text = FILES["freeze_state.py"].read_text(
    encoding="utf-8"
)

release_text = FILES["operational_release.py"].read_text(
    encoding="utf-8"
)

simulation_text = FILES["simulation_engine.py"].read_text(
    encoding="utf-8"
)

launch_text = FILES["controlled_launch.py"].read_text(
    encoding="utf-8"
)

check(
    "freeze_state contains authorize_one_shot",
    "def authorize_one_shot(" in freeze_text,
)

check(
    "freeze_state contains consume_execution_authority",
    "def consume_execution_authority(" in freeze_text,
)

check(
    "operational_release delegates authorization",
    "authorize_one_shot" in release_text,
)

check(
    "operational_release contains compatibility release_one",
    "def release_one(" in release_text,
)

check(
    "simulation engine imports authoritative gate",
    "assert_execution_allowed" in simulation_text,
)

check(
    "simulation engine consumes execution authority",
    "consume_execution_authority" in simulation_text,
)

check(
    "controlled launch uses release_one",
    "release_one(" in launch_text,
)

# Detect obvious alternate release implementations.
release_defs = [
    line.strip()
    for line in (
        freeze_text
        + "\n"
        + release_text
        + "\n"
        + simulation_text
        + "\n"
        + launch_text
    ).splitlines()
    if line.strip().startswith("def ")
    and (
        "authorize" in line.lower()
        or "release" in line.lower()
        or "execution_allowed" in line.lower()
    )
]

print("  authorization/release definitions detected:")
for line in release_defs:
    print("   ", line)

print()

# ------------------------------------------------------------
# 9. RUNNING OMNIS / SHOGUN PROCESSES
# ------------------------------------------------------------

print("=== 9. CURRENT RUNNING PROCESS INVENTORY ===")

try:
    proc = subprocess.run(
        ["ps", "-A", "-o", "pid=,args="],
        capture_output=True,
        text=True,
    )

    lines = proc.stdout.splitlines()

    matches = []

    for line in lines:
        low = line.lower()

        if (
            "omnis" in low
            or "shogun" in low
            or "deep_recon" in low
        ):
            matches.append(line.strip())

    if matches:
        for line in matches:
            print(" ", line)
    else:
        print("  No OMNIS/SHOGUN/deep_recon processes detected.")

except Exception as e:
    warn(
        "process inventory unavailable",
        repr(e),
    )

print()

# ------------------------------------------------------------
# 10. STARTUP SCRIPT REFERENCES
# ------------------------------------------------------------

print("=== 10. STARTUP / BOOT REFERENCE CHECK ===")

home = Path.home()

boot_candidates = [
    home / "OMNIS" / "boot.sh",
    home / "OMNIS_V3" / "boot.sh",
]

for path in boot_candidates:
    if path.exists():
        print("[FOUND]", path)
    else:
        print("[MISSING]", path)

warn(
    "Termux previously reported missing ~/OMNIS/boot.sh",
    "This audit records the condition; it does not recreate or execute a boot script.",
)

print()

# ------------------------------------------------------------
# 11. FINAL VERDICT
# ------------------------------------------------------------

print("=" * 76)
print("FINAL AUDIT")
print("=" * 76)

print(f"PASS: {PASS}")
print(f"FAIL: {FAIL}")
print(f"WARN: {WARN}")
print()

if FAIL == 0:
    print("VERDICT: POST-EXECUTION CONSOLIDATION PASSED")
    print()
    print("The controlled execution completed successfully.")
    print("The Loop-7 freeze remains intact.")
    print("The terminal release was consumed.")
    print("The consumed release no longer authorizes another execution.")
    print("The execution result matches the authorized terminal parameters.")
else:
    print("VERDICT: CONSOLIDATION INCOMPLETE")
    print()
    print("One or more integrity conditions failed.")
    print("No corrective execution was attempted by this audit.")

print("=" * 76)
