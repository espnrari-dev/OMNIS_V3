from pathlib import Path
import ast
import re

ROOT = Path("backend")

print("=" * 100)
print("OMNIS V3 — UNIVERSAL EXECUTION AUTHORITY AUDIT")
print("=" * 100)

files = sorted(ROOT.rglob("*.py"))

print(f"Backend Python files scanned: {len(files)}")
print()

# ---------------------------------------------------------------------
# 1. STATIC EXECUTION PATTERN SCAN
# ---------------------------------------------------------------------

patterns = {
    "simulation_engine.start": r'\bsimulation_engine\.start\s*\(',
    "simulation_start": r'\bsimulation_start\s*\(',
    "_sim_new definition/call": r'\b_sim_new\s*\(',
    "run_simulation definition/call": r'\brun_simulation\s*\(',
    "Thread constructor": r'\b(?:threading|_sim_threading)\.Thread\s*\(',
    "Thread.start": r'\.start\s*\(',
    "subprocess": r'\bsubprocess\.(?:run|Popen|call|check_call|check_output)\s*\(',
    "os.system": r'\bos\.system\s*\(',
    "os.popen": r'\bos\.popen\s*\(',
    "exec": r'\bexec\s*\(',
    "eval": r'\beval\s*\(',
}

compiled = {
    k: re.compile(v)
    for k, v in patterns.items()
}

hits = []

for path in files:
    try:
        lines = path.read_text().splitlines()
    except Exception as e:
        print(f"READ ERROR: {path}: {e}")
        continue

    for lineno, line in enumerate(lines, 1):
        for kind, rx in compiled.items():
            if rx.search(line):
                hits.append((path, lineno, kind, line.strip()))

print("=" * 100)
print("STATIC EXECUTION REFERENCES")
print("=" * 100)

for path, lineno, kind, line in hits:
    print(f"{path}:{lineno}")
    print(f"  TYPE: {kind}")
    print(f"  CODE: {line}")
    print()

print(f"TOTAL EXECUTION REFERENCES: {len(hits)}")

# ---------------------------------------------------------------------
# 2. FREEZE AUTHORITY REFERENCES
# ---------------------------------------------------------------------

print()
print("=" * 100)
print("FREEZE AUTHORITY REFERENCES")
print("=" * 100)

gate_names = [
    "_assert_execution_allowed",
    "_assert_execution_allowed_bloom",
    "_assert_legacy_sim_execution_allowed",
    "execution_allowed",
    "get_freeze_state",
]

for path in files:
    try:
        text = path.read_text()
    except Exception:
        continue

    found = [g for g in gate_names if g in text]

    if found:
        print(path)
        for g in found:
            print(f"  PASS: {g}")

# ---------------------------------------------------------------------
# 3. AST FUNCTION INVENTORY
# ---------------------------------------------------------------------

print()
print("=" * 100)
print("FUNCTIONS CAPABLE OF STARTING OR DISPATCHING EXECUTION")
print("=" * 100)

execution_names = {
    "start",
    "run",
    "run_simulation",
    "_sim_new",
    "execute",
    "worker",
    "loop",
    "cycle",
    "tick",
    "dispatch",
    "launch",
}

for path in files:
    try:
        source = path.read_text()
        tree = ast.parse(source, filename=str(path))
    except Exception as e:
        print(f"AST ERROR: {path}: {e}")
        continue

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            function_text = ast.get_source_segment(source, node) or ""

            execution_calls = []

            for call in ast.walk(node):
                if isinstance(call, ast.Call):
                    if isinstance(call.func, ast.Attribute):
                        name = call.func.attr
                    elif isinstance(call.func, ast.Name):
                        name = call.func.id
                    else:
                        name = ""

                    if (
                        name in execution_names
                        or name in {
                            "Thread",
                            "Popen",
                            "run",
                            "system",
                            "popen",
                        }
                    ):
                        execution_calls.append(name)

            if (
                node.name in execution_names
                or execution_calls
                or "execution_allowed" in function_text
                or "_assert_" in function_text
            ):
                print()
                print(f"{path}:{node.lineno} :: {node.name}()")

                if execution_calls:
                    print(
                        "  execution calls:",
                        ", ".join(sorted(set(execution_calls)))
                    )

                gates = [
                    g for g in gate_names
                    if g in function_text
                ]

                if gates:
                    print(
                        "  gate references:",
                        ", ".join(gates)
                    )
                else:
                    print("  gate references: NONE")

# ---------------------------------------------------------------------
# 4. TARGETED FUNCTION REVIEW
# ---------------------------------------------------------------------

print()
print("=" * 100)
print("TARGETED EXECUTION AUTHORITIES")
print("=" * 100)

targets = [
    ("backend/simulation_engine.py", "start"),
    ("backend/simulation_engine.py", "run"),
    ("backend/bloom_engine.py", "run_simulation"),
    ("backend/main.py", "_sim_new"),
]

for filename, target in targets:
    path = Path(filename)

    print()
    print(f"--- {filename}::{target} ---")

    if not path.exists():
        print("STATUS: MISSING")
        continue

    try:
        source = path.read_text()
        tree = ast.parse(source, filename=filename)
    except Exception as e:
        print("STATUS: AST ERROR:", e)
        continue

    found = None

    for node in tree.body:
        if (
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == target
        ):
            found = node
            break

    if found is None:
        print("STATUS: FUNCTION NOT FOUND")
        continue

    segment = ast.get_source_segment(source, found) or ""

    print(f"definition line: {found.lineno}")

    gates = [
        g for g in gate_names
        if g in segment
    ]

    if gates:
        for g in gates:
            print(f"  GATE PRESENT: {g}")
    else:
        print("  GATE PRESENT: NONE")

    print("  DIRECT EXECUTION OPERATIONS:")

    direct = []

    for call in ast.walk(found):
        if isinstance(call, ast.Call):
            if isinstance(call.func, ast.Attribute):
                full = call.func.attr
                if call.func.attr in {
                    "start",
                    "run",
                    "Popen",
                    "call",
                    "check_call",
                    "check_output",
                    "system",
                    "popen",
                }:
                    direct.append(full)

            elif isinstance(call.func, ast.Name):
                if call.func.id in {
                    "Thread",
                    "Popen",
                    "exec",
                    "eval",
                }:
                    direct.append(call.func.id)

    if direct:
        for item in sorted(set(direct)):
            print(f"    {item}")
    else:
        print("    NONE")

# ---------------------------------------------------------------------
# 5. LIVE FREEZE STATE
# ---------------------------------------------------------------------

print()
print("=" * 100)
print("LIVE FREEZE STATE")
print("=" * 100)

try:
    from backend.freeze_state import (
        get_freeze_state,
        execution_allowed,
    )

    state = get_freeze_state()

    print("frozen:", state.get("frozen"))
    print(
        "continuation_policy:",
        state.get("continuation_policy")
    )
    print("execution_allowed:", execution_allowed())

    if execution_allowed():
        print("VERDICT: EXECUTION CURRENTLY ALLOWED")
    else:
        print("VERDICT: EXECUTION CURRENTLY BLOCKED")

except Exception as e:
    print("FREEZE STATE ERROR:", repr(e))

# ---------------------------------------------------------------------
# 6. SYNTAX VALIDATION
# ---------------------------------------------------------------------

print()
print("=" * 100)
print("SYNTAX VALIDATION")
print("=" * 100)

failed = []

for path in files:
    try:
        ast.parse(
            path.read_text(),
            filename=str(path)
        )
    except Exception as e:
        failed.append((path, e))

if failed:
    print("FAIL: syntax errors detected")
    for path, error in failed:
        print(f"  {path}: {error}")
else:
    print("PASS: all backend Python files parse successfully")

print()
print("=" * 100)
print("AUDIT COMPLETE")
print("=" * 100)
