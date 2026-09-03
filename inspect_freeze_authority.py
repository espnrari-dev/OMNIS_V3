from pathlib import Path

p = Path("backend/freeze_state.py")

print("=" * 80)
print("OMNIS V3 — FREEZE AUTHORITY INSPECTION")
print("=" * 80)

if not p.exists():
    raise SystemExit("FATAL: backend/freeze_state.py does not exist")

s = p.read_text()

print(s)

print("=" * 80)
print("CHECKS")
print("=" * 80)

if "def get_freeze_state" not in s:
    raise SystemExit("FATAL: get_freeze_state() not found")

if "def execution_allowed" not in s:
    raise SystemExit("FATAL: execution_allowed() not found")

print("PASS: get_freeze_state() located")
print("PASS: execution_allowed() located")
print("PASS: freeze authority structure located")
