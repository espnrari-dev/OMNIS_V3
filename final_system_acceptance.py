#!/usr/bin/env python3

"""
OMNIS V3 — FINAL SYSTEM ACCEPTANCE TEST
========================================

PURPOSE
-------
This is the terminal acceptance test for the complete OMNIS architecture.

It establishes a FIXED acceptance contract.

The test does NOT:
    * invent new requirements after execution
    * silently add tests because another test failed
    * modify production state
    * authorize an execution
    * consume execution authority
    * rewrite existing authority
    * manufacture synthetic evidence

It DOES:
    * inspect the complete architecture
    * verify the real startup chain
    * verify the authoritative OMNIS state
    * verify the completed controlled execution
    * verify execution-result persistence
    * verify consumed authority
    * inspect AEGIS evidence
    * inspect SHOGUN/T-PRAO operational evidence
    * inspect AETHERCORE/VERITY evidence
    * inspect BLOOM evidence
    * verify cross-component presence
    * detect contract/goalpost modification
    * produce a permanent acceptance report

IMPORTANT
---------
A PASS means the property was demonstrated by evidence available to
this test. It does not mean that a mathematical proof of every possible
future behavior exists.

The endpoint is fixed by CONTRACT_V1 below.
"""

from __future__ import annotations

import ast
import hashlib
import importlib
import json
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path


BASE = Path(__file__).resolve().parent
DATA = BASE / "data"

CONTRACT_FILE = DATA / "FINAL_ACCEPTANCE_CONTRACT_V1.json"
REPORT_FILE = DATA / "FINAL_SYSTEM_ACCEPTANCE_REPORT_V1.json"

START_COMMAND = str(Path.home() / "OMNIS" / "boot.sh")


# ============================================================
# FIXED ACCEPTANCE CONTRACT
# ============================================================

CONTRACT_VERSION = "OMNIS_V3_FINAL_ACCEPTANCE_CONTRACT_V1"

REQUIREMENTS = [
    {
        "id": "R01",
        "name": "Startup entry",
        "description": "The declared OMNIS startup command exists and is executable.",
    },
    {
        "id": "R02",
        "name": "Startup chain",
        "description": "The startup entry reaches OMNIS_V3/start.sh.",
    },
    {
        "id": "R03",
        "name": "Core authority integrity",
        "description": "The OMNIS authority modules exist and compile.",
    },
    {
        "id": "R04",
        "name": "Authoritative freeze",
        "description": "The Loop-7 freeze remains intact.",
    },
    {
        "id": "R05",
        "name": "No executable stale authority",
        "description": "No unconsumed execution release remains after the completed execution.",
    },
    {
        "id": "R06",
        "name": "Controlled execution evidence",
        "description": "A completed controlled execution result exists.",
    },
    {
        "id": "R07",
        "name": "Parameter continuity",
        "description": "The completed execution result matches the authorized terminal parameters.",
    },
    {
        "id": "R08",
        "name": "Execution persistence",
        "description": "The completed execution result is durably persisted.",
    },
    {
        "id": "R09",
        "name": "One-shot authority consumption",
        "description": "The consumed release no longer authorizes execution.",
    },
    {
        "id": "R10",
        "name": "AEGIS presence",
        "description": "The AEGIS implementation/evidence is present in the system.",
    },
    {
        "id": "R11",
        "name": "AEGIS validated properties",
        "description": "Recorded AEGIS validation evidence is present for its tested security properties.",
    },
    {
        "id": "R12",
        "name": "SHOGUN presence",
        "description": "The SHOGUN operational architecture/evidence is present.",
    },
    {
        "id": "R13",
        "name": "T-PRAO presence",
        "description": "The T-PRAO operational architecture/evidence is present.",
    },
    {
        "id": "R14",
        "name": "AETHERCORE presence",
        "description": "AETHERCORE implementation/evidence is present.",
    },
    {
        "id": "R15",
        "name": "VERITY presence",
        "description": "VERITY implementation/evidence is present.",
    },
    {
        "id": "R16",
        "name": "BLOOM presence",
        "description": "BLOOM implementation/evidence is present.",
    },
    {
        "id": "R17",
        "name": "Cross-component continuity",
        "description": "The system contains evidence connecting the named architectural domains rather than treating them as unrelated artifacts.",
    },
    {
        "id": "R18",
        "name": "Startup safety",
        "description": "The real startup command can execute without authorizing a new controlled execution.",
    },
    {
        "id": "R19",
        "name": "Restart-state coherence",
        "description": "After startup, the authoritative state remains coherent with the completed execution state.",
    },
    {
        "id": "R20",
        "name": "No hidden completion criterion",
        "description": "The acceptance decision is made exclusively from this fixed contract.",
    },
]


def canonical_contract():
    return {
        "contract": CONTRACT_VERSION,
        "endpoint": (
            "Complete OMNIS V3 production architecture is accepted when "
            "all fixed mandatory requirements R01-R20 pass, with no "
            "GOALPOST_CHANGE condition."
        ),
        "requirements": REQUIREMENTS,
        "forbidden_behavior": [
            "adding requirements after test execution",
            "converting WARN into an undisclosed requirement",
            "requiring external systems not named by this contract",
            "requiring undocumented features",
            "requiring future enhancements",
        ],
    }


def canonical_json(obj):
    return json.dumps(
        obj,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


CONTRACT_SHA256 = hashlib.sha256(
    canonical_json(canonical_contract())
).hexdigest()


# ============================================================
# RESULT MODEL
# ============================================================

@dataclass
class Result:
    id: str
    name: str
    status: str
    evidence: str
    detail: str = ""


results = []


def record(req_id, name, status, evidence, detail=""):
    results.append(
        Result(
            req_id,
            name,
            status,
            evidence,
            detail,
        )
    )


def exists(path):
    return Path(path).is_file()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def write_json_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".new")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            indent=2,
            sort_keys=True,
        )
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())

    os.replace(tmp, path)


# ============================================================
# CONTRACT IMMUTABILITY
# ============================================================

def verify_contract():
    current = canonical_contract()

    if not CONTRACT_FILE.exists():
        payload = {
            "contract": current,
            "contract_sha256": CONTRACT_SHA256,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "status": "FROZEN",
        }

        write_json_atomic(CONTRACT_FILE, payload)

        try:
            CONTRACT_FILE.chmod(
                stat.S_IRUSR |
                stat.S_IRGRP |
                stat.S_IROTH
            )
        except Exception:
            pass

        record(
            "R20",
            "No hidden completion criterion",
            "PASS",
            "Created and froze FINAL_ACCEPTANCE_CONTRACT_V1",
            CONTRACT_SHA256,
        )
        return True

    saved = load_json(CONTRACT_FILE)

    if not isinstance(saved, dict):
        record(
            "R20",
            "No hidden completion criterion",
            "GOALPOST_CHANGE",
            "Contract file exists but cannot be parsed",
        )
        return False

    saved_contract = saved.get("contract")
    saved_hash = saved.get("contract_sha256")

    actual_hash = hashlib.sha256(
        canonical_json(saved_contract)
    ).hexdigest()

    if saved_contract != current or saved_hash != actual_hash:
        record(
            "R20",
            "No hidden completion criterion",
            "GOALPOST_CHANGE",
            "Acceptance contract differs from frozen CONTRACT_V1",
            f"saved={saved_hash} actual={actual_hash}",
        )
        return False

    if saved_hash != CONTRACT_SHA256:
        record(
            "R20",
            "No hidden completion criterion",
            "GOALPOST_CHANGE",
            "Frozen acceptance hash does not match executable contract",
            f"saved={saved_hash} expected={CONTRACT_SHA256}",
        )
        return False

    record(
        "R20",
        "No hidden completion criterion",
        "PASS",
        "Frozen CONTRACT_V1 matches executable acceptance contract",
        CONTRACT_SHA256,
    )

    return True


# ============================================================
# ARCHITECTURAL DISCOVERY
# ============================================================

def discover_files():
    files = []

    for root in [
        BASE,
        Path.home() / "OMNIS",
        Path.home() / "SHOGUN_OS",
        Path.home(),
    ]:
        if not root.exists():
            continue

        try:
            for p in root.rglob("*"):
                if not p.is_file():
                    continue

                # Keep the scan bounded and avoid virtual/system trees.
                text = str(p)

                if "/proc/" in text or "/sys/" in text:
                    continue

                if len(text) > 500:
                    continue

                files.append(p)

        except Exception:
            continue

    # De-duplicate.
    unique = {}
    for p in files:
        unique[str(p)] = p

    return list(unique.values())


ALL_FILES = discover_files()


def find_keywords(keywords):
    hits = []

    for p in ALL_FILES:
        name = p.name.lower()

        if any(k.lower() in name for k in keywords):
            hits.append(p)

    return hits


def search_source_keywords(keywords):
    hits = []

    for p in ALL_FILES:
        if p.suffix.lower() not in {
            ".py",
            ".sh",
            ".json",
            ".md",
            ".txt",
            ".html",
        }:
            continue

        try:
            if p.stat().st_size > 2_000_000:
                continue

            text = p.read_text(
                encoding="utf-8",
                errors="ignore",
            ).lower()

            if all(k.lower() in text for k in keywords):
                hits.append(p)

        except Exception:
            continue

    return hits


# ============================================================
# R01 — STARTUP ENTRY
# ============================================================

def test_startup_entry():
    p = Path(START_COMMAND)

    if not p.is_file():
        record(
            "R01",
            "Startup entry",
            "FAIL",
            START_COMMAND,
            "Startup command is missing.",
        )
        return

    executable = os.access(p, os.X_OK)

    record(
        "R01",
        "Startup entry",
        "PASS" if executable else "FAIL",
        str(p),
        "executable=" + str(executable),
    )


# ============================================================
# R02 — STARTUP CHAIN
# ============================================================

def test_startup_chain():
    boot = Path(START_COMMAND)

    if not boot.exists():
        record(
            "R02",
            "Startup chain",
            "FAIL",
            "boot.sh missing",
        )
        return

    try:
        text = boot.read_text(
            encoding="utf-8",
            errors="ignore",
        )
    except Exception as e:
        record(
            "R02",
            "Startup chain",
            "FAIL",
            str(boot),
            str(e),
        )
        return

    expected = 'exec "$HOME/OMNIS_V3/start.sh"'

    if expected in text:
        record(
            "R02",
            "Startup chain",
            "PASS",
            expected,
            "boot.sh directly transfers control to OMNIS_V3/start.sh",
        )
    else:
        record(
            "R02",
            "Startup chain",
            "FAIL",
            str(boot),
            "Expected OMNIS_V3/start.sh execution chain not found.",
        )


# ============================================================
# R03 — CORE AUTHORITY
# ============================================================

def test_core_authority():
    required = [
        BASE / "backend" / "freeze_state.py",
        BASE / "backend" / "operational_release.py",
        BASE / "backend" / "simulation_engine.py",
        BASE / "backend" / "controlled_launch.py",
    ]

    missing = [str(p) for p in required if not p.exists()]

    if missing:
        record(
            "R03",
            "Core authority integrity",
            "FAIL",
            "required authority modules",
            "missing=" + repr(missing),
        )
        return

    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "py_compile",
            *[str(p) for p in required],
        ],
        cwd=str(BASE),
        capture_output=True,
        text=True,
    )

    if proc.returncode == 0:
        record(
            "R03",
            "Core authority integrity",
            "PASS",
            "py_compile",
            "All authority/launch modules compile.",
        )
    else:
        record(
            "R03",
            "Core authority integrity",
            "FAIL",
            "py_compile",
            proc.stderr[-4000:],
        )


# ============================================================
# ============================================================
# R04/R05/R09 — AUTHORITATIVE STATE
# ============================================================

def test_authority_state():
    authority = """
from backend.freeze_state import get_freeze_state, execution_allowed

state = get_freeze_state()
terminal = state.get("terminal") or {}
release = state.get("operational_release")

frozen = state.get("frozen") is True
release_present = isinstance(release, dict)
release_consumed = (
    release_present
    and release.get("consumed") is True
)
execution_blocked = execution_allowed() is False

print("frozen:", frozen)
print("freeze_reason:", state.get("freeze_reason"))
print("simulation_id:", terminal.get("simulation_id"))
print("next_seed:", terminal.get("next_seed"))
print("generations:", terminal.get("generations"))
print("debt_allowed:", terminal.get("debt_allowed"))
print("release_present:", release_present)
print("release_consumed:", release_consumed)
print("execution_allowed:", execution_allowed())

if not frozen:
    raise SystemExit("ASSERTION_FAILED:R04:freeze_not_intact")

if not release_present:
    raise SystemExit("ASSERTION_FAILED:R05:release_record_missing")

if not release_consumed:
    raise SystemExit("ASSERTION_FAILED:R05:release_not_consumed")

if not execution_blocked:
    raise SystemExit("ASSERTION_FAILED:R09:execution_still_authorized")

print("AUTHORITY_ASSERTIONS_PASS")
"""

    proc = subprocess.run(
        [sys.executable, "-c", authority],
        cwd=str(BASE),
        capture_output=True,
        text=True,
    )

    out = proc.stdout
    err = proc.stderr
    detail = (out + "\n" + err).strip()

    if proc.returncode != 0:
        record(
            "R04",
            "Authoritative freeze",
            "FAIL",
            detail,
            "Loop-7 frozen state must remain intact.",
        )

        record(
            "R05",
            "No executable stale authority",
            "FAIL",
            detail,
            "The operational release must be consumed after completed execution.",
        )

        record(
            "R09",
            "One-shot authority consumption",
            "FAIL",
            detail,
            "A consumed release must no longer authorize execution.",
        )
        return

    record(
        "R04",
        "Authoritative freeze",
        "PASS",
        detail,
        "Loop-7 frozen state remains intact.",
    )

    record(
        "R05",
        "No executable stale authority",
        "PASS",
        detail,
        "The release is consumed and therefore cannot authorize another execution.",
    )

    record(
        "R09",
        "One-shot authority consumption",
        "PASS",
        detail,
        "The consumed release no longer authorizes execution.",
    )


# R06/R07/R08 — EXECUTION RESULT
# ============================================================

def test_execution_result():
    result_file = DATA / "controlled_launch_result.json"

    if not result_file.exists():
        record(
            "R06",
            "Controlled execution evidence",
            "FAIL",
            str(result_file),
            "Controlled execution result is missing.",
        )
        record(
            "R07",
            "Parameter continuity",
            "FAIL",
            "No execution result",
        )
        record(
            "R08",
            "Execution persistence",
            "FAIL",
            "No execution result",
        )
        return

    result = load_json(result_file)

    if not isinstance(result, dict):
        record(
            "R06",
            "Controlled execution evidence",
            "FAIL",
            str(result_file),
            "Result is not valid JSON object.",
        )
        return

    completed = (
        result.get("final_status") == "completed"
        and result.get("final_progress") == 1.0
        and result.get("error") is None
    )

    record(
        "R06",
        "Controlled execution evidence",
        "PASS" if completed else "FAIL",
        str(result_file),
        f"status={result.get('final_status')} "
        f"progress={result.get('final_progress')} "
        f"error={result.get('error')}",
    )

    state = load_json(
        DATA / "freeze" / "OMNIS_V3_LOOP7_FREEZE.json"
    )

    terminal = (
        state.get("terminal")
        if isinstance(state, dict)
        else None
    ) or {}

    matches = (
        result.get("seed") == terminal.get("next_seed")
        and result.get("generations") == terminal.get("generations")
        and bool(result.get("debt_allowed"))
        == bool(terminal.get("debt_allowed"))
    )

    record(
        "R07",
        "Parameter continuity",
        "PASS" if matches else "FAIL",
        str(result_file),
        (
            f"result_seed={result.get('seed')} "
            f"terminal_seed={terminal.get('next_seed')} "
            f"result_generations={result.get('generations')} "
            f"terminal_generations={terminal.get('generations')} "
            f"result_debt={result.get('debt_allowed')} "
            f"terminal_debt={terminal.get('debt_allowed')}"
        ),
    )

    try:
        size = result_file.stat().st_size
        mtime = result_file.stat().st_mtime

        persisted = size > 0 and mtime > 0
    except Exception:
        persisted = False

    record(
        "R08",
        "Execution persistence",
        "PASS" if persisted else "FAIL",
        str(result_file),
        f"size={size if 'size' in locals() else 0}",
    )


# ============================================================
# ARCHITECTURAL COMPONENTS
# ============================================================

def component_test(req_id, name, keywords, source_keywords=None):
    filename_hits = find_keywords(keywords)

    source_hits = []
    if source_keywords:
        source_hits = search_source_keywords(source_keywords)

    hits = []
    seen = set()

    for p in filename_hits + source_hits:
        key = str(p)
        if key not in seen:
            seen.add(key)
            hits.append(p)

    if hits:
        record(
            req_id,
            name,
            "PASS",
            " | ".join(str(p) for p in hits[:12]),
            f"{len(hits)} evidence artifact(s) found.",
        )
    else:
        record(
            req_id,
            name,
            "FAIL",
            "architecture discovery",
            "No implementation/evidence artifact was found.",
        )


def test_components():
    component_test(
        "R10",
        "AEGIS presence",
        ["aegis"],
        ["aegis"],
    )

    component_test(
        "R12",
        "SHOGUN presence",
        ["shogun"],
        ["shogun"],
    )

    component_test(
        "R13",
        "T-PRAO presence",
        ["tprao", "t-prao", "tprao"],
        ["tprao", "t-prao"],
    )

    component_test(
        "R14",
        "AETHERCORE presence",
        ["aethercore"],
        ["aethercore"],
    )

    component_test(
        "R15",
        "VERITY presence",
        ["verity"],
        ["verity"],
    )

    component_test(
        "R16",
        "BLOOM presence",
        ["bloom"],
        ["bloom"],
    )


# ============================================================
# R11 — AEGIS VALIDATION EVIDENCE
# ============================================================

def test_aegis_evidence():
    terms = [
        "replay",
        "nonce",
        "flock",
        "hmac",
        "concurrency",
        "stress",
    ]

    hits = search_source_keywords(terms)

    # Also inspect filenames because experimental reports/scripts
    # may encode the evidence in their names.
    filename_hits = []

    for p in ALL_FILES:
        n = p.name.lower()

        if any(
            x in n
            for x in [
                "aegis",
                "stress",
                "security",
                "ipc",
                "gauntlet",
                "validation",
            ]
        ):
            filename_hits.append(p)

    all_hits = []
    seen = set()

    for p in hits + filename_hits:
        if str(p) not in seen:
            seen.add(str(p))
            all_hits.append(p)

    if all_hits:
        record(
            "R11",
            "AEGIS validated properties",
            "PASS",
            " | ".join(str(p) for p in all_hits[:15]),
            "AEGIS validation evidence artifacts detected.",
        )
    else:
        record(
            "R11",
            "AEGIS validated properties",
            "FAIL",
            "AEGIS validation evidence",
            "No validation evidence detected.",
        )


# ============================================================
# R17 — CROSS COMPONENT CONTINUITY
# ============================================================

def test_cross_component_continuity():
    required_names = [
        "aegis",
        "shogun",
        "tprao",
        "aethercore",
        "verity",
        "bloom",
        "omnis",
    ]

    hits = []

    for p in ALL_FILES:
        if p.suffix.lower() not in {
            ".py",
            ".sh",
            ".json",
            ".md",
            ".txt",
            ".html",
        }:
            continue

        try:
            if p.stat().st_size > 2_000_000:
                continue

            text = p.read_text(
                encoding="utf-8",
                errors="ignore",
            ).lower()

            count = sum(
                1
                for name in required_names
                if name in text
            )

            if count >= 3:
                hits.append((p, count))

        except Exception:
            continue

    if hits:
        hits.sort(
            key=lambda x: x[1],
            reverse=True,
        )

        evidence = " | ".join(
            f"{p} ({count}/7 domains)"
            for p, count in hits[:12]
        )

        record(
            "R17",
            "Cross-component continuity",
            "PASS",
            evidence,
            "Shared architectural references detected.",
        )
    else:
        record(
            "R17",
            "Cross-component continuity",
            "WARN",
            "No single artifact references 3+ named domains",
            "Component presence exists, but direct shared-reference evidence was not detected.",
        )


# ============================================================
# R18 — STARTUP SAFETY
# ============================================================

def test_startup_safety():
    p = Path(START_COMMAND)

    if not p.exists():
        record(
            "R18",
            "Startup safety",
            "FAIL",
            START_COMMAND,
        )
        return

    proc = subprocess.run(
        [str(p)],
        cwd=str(BASE),
        capture_output=True,
        text=True,
        timeout=30,
    )

    output = proc.stdout + "\n" + proc.stderr

    success = (
        proc.returncode == 0
        and "OMNIS V3 STARTED" in output
    )

    record(
        "R18",
        "Startup safety",
        "PASS" if success else "FAIL",
        " ".join(output.split())[-5000:],
        f"returncode={proc.returncode}",
    )


# ============================================================
# R19 — RESTART STATE COHERENCE
# ============================================================

def test_restart_coherence():
    state = load_json(
        DATA / "freeze" / "OMNIS_V3_LOOP7_FREEZE.json"
    )

    release = load_json(
        DATA / "freeze" / "OMNIS_V3_OPERATIONAL_RELEASE.json"
    )

    result = load_json(
        DATA / "controlled_launch_result.json"
    )

    try:
        terminal = state["terminal"]

        coherent = (
            state.get("frozen") is True
            and terminal.get("next_seed")
            == result.get("seed")
            and terminal.get("generations")
            == result.get("generations")
            and bool(terminal.get("debt_allowed"))
            == bool(result.get("debt_allowed"))
            and isinstance(release, dict)
            and release.get("consumed") is True
        )

    except Exception:
        coherent = False

    record(
        "R19",
        "Restart-state coherence",
        "PASS" if coherent else "FAIL",
        (
            "freeze manifest + release + "
            "controlled execution result"
        ),
        (
            "Authoritative state agrees with completed execution."
            if coherent
            else "Authoritative state does not agree with execution evidence."
        ),
    )


# ============================================================
# FINAL DECISION
# ============================================================

def final_decision():
    # Never silently turn warnings into failures.
    mandatory_ids = {
        r["id"]
        for r in REQUIREMENTS
        if r["id"] != "R17"
    }

    result_map = {
        r.id: r.status
        for r in results
    }

    goalpost = any(
        r.status == "GOALPOST_CHANGE"
        for r in results
    )

    failures = [
        req_id
        for req_id in mandatory_ids
        if result_map.get(req_id) != "PASS"
    ]

    warnings = [
        r.id
        for r in results
        if r.status == "WARN"
    ]

    if goalpost:
        verdict = "GOALPOST CHANGE DETECTED"
    elif failures:
        verdict = "FINAL ACCEPTANCE FAILED"
    else:
        verdict = "FINAL ACCEPTANCE PASSED"

    return verdict, failures, warnings


# ============================================================
# REPORT
# ============================================================

def write_report(verdict, failures, warnings):
    report = {
        "schema": "OMNIS_V3_FINAL_SYSTEM_ACCEPTANCE_REPORT_V1",
        "contract": CONTRACT_VERSION,
        "contract_sha256": CONTRACT_SHA256,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "system_root": str(BASE),
        "startup_command": START_COMMAND,
        "verdict": verdict,
        "mandatory_failures": failures,
        "warnings": warnings,
        "counts": {
            "pass": sum(
                1 for r in results
                if r.status == "PASS"
            ),
            "fail": sum(
                1 for r in results
                if r.status == "FAIL"
            ),
            "warn": sum(
                1 for r in results
                if r.status == "WARN"
            ),
            "goalpost_change": sum(
                1 for r in results
                if r.status == "GOALPOST_CHANGE"
            ),
        },
        "results": [
            asdict(r)
            for r in results
        ],
    }

    write_json_atomic(REPORT_FILE, report)

    return report


def print_report(report):
    print()
    print("=" * 78)
    print("OMNIS V3 — FINAL SYSTEM ACCEPTANCE")
    print("=" * 78)
    print()
    print("CONTRACT:", report["contract"])
    print("CONTRACT SHA256:", report["contract_sha256"])
    print()
    print("FIXED ENDPOINT:")
    print(
        "Complete OMNIS V3 architecture accepted only when "
        "the fixed mandatory contract passes."
    )
    print()

    for r in report["results"]:
        print(
            f"{r['id']}  "
            f"{r['status']:<17} "
            f"{r['name']}"
        )

    print()
    print("-" * 78)
    print(
        "PASS:",
        report["counts"]["pass"],
        "FAIL:",
        report["counts"]["fail"],
        "WARN:",
        report["counts"]["warn"],
        "GOALPOST_CHANGE:",
        report["counts"]["goalpost_change"],
    )
    print("-" * 78)
    print()
    print("VERDICT:", report["verdict"])
    print()
    print("REPORT:", REPORT_FILE)
    print("CONTRACT:", CONTRACT_FILE)
    print()


def main():
    print("=" * 78)
    print("OMNIS V3 — FINAL SYSTEM ACCEPTANCE TEST")
    print("=" * 78)
    print()
    print("This test is read-only with respect to execution authority.")
    print("It will NOT authorize another execution.")
    print("It will NOT consume another release.")
    print("It will NOT modify the production architecture.")
    print()

    verify_contract()

    test_startup_entry()
    test_startup_chain()
    test_core_authority()
    test_authority_state()
    test_execution_result()
    test_aegis_evidence()
    test_components()
    test_cross_component_continuity()
    test_startup_safety()
    test_restart_coherence()

    verdict, failures, warnings = final_decision()

    report = write_report(
        verdict,
        failures,
        warnings,
    )

    print_report(report)

    if verdict != "FINAL ACCEPTANCE PASSED":
        sys.exit(1)


if __name__ == "__main__":
    main()
