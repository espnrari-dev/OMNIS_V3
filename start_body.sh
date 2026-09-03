#!/data/data/com.termux/files/usr/bin/bash
set -e

BASE="$HOME/OMNIS_V3"
cd "$BASE"

echo "============================================================"

echo
echo "=== CLEANING PRIOR OMNIS INSTANCES ==="

# Stop prior instances owned by the OMNIS startup chain.
pkill -f "$HOME/deep_recon/SHOGUN_LIVE_OPERATIONAL.sh" 2>/dev/null || true
pkill -f "$HOME/SHOGUN_OS/WATCH.sh" 2>/dev/null || true

# Remove any orphaned copies of the same startup jobs.
sleep 0.2

echo "[0/4] Prior OMNIS/SHOGUN startup instances cleared"

echo
echo "=== SINGLE-INSTANCE RUNTIME CONTROL ==="

# These are the background services owned by the OMNIS startup chain.
SERVICES=(
    "$HOME/deep_recon/SHOGUN_LIVE_OPERATIONAL.sh"
    "$HOME/SHOGUN_OS/WATCH.sh"
)

# Remove stale instances before creating the new controlled instance.
for service in "${SERVICES[@]}"; do
    pkill -f "$service" 2>/dev/null || true
done

sleep 0.5

echo "PASS: stale managed instances cleared"

echo "OMNIS V3 — START"
echo "============================================================"

# Required authority files
test -f "$BASE/backend/freeze_state.py"
test -f "$BASE/backend/operational_release.py"
test -f "$BASE/backend/simulation_engine.py"

echo "[1/4] Authority modules present"

# Python integrity
python3 -m py_compile \
    "$BASE/backend/freeze_state.py" \
    "$BASE/backend/operational_release.py" \
    "$BASE/backend/simulation_engine.py" \
    "$BASE/backend/controlled_launch.py"

echo "[2/4] Python integrity PASS"

# Read current authoritative state.
python3 - <<'PY'
from backend.freeze_state import get_freeze_state, execution_allowed

state = get_freeze_state()
terminal = state.get("terminal") or {}
release = state.get("operational_release")

print()
print("AUTHORITATIVE STATE")
print("  frozen:", state.get("frozen"))
print("  simulation_id:", terminal.get("simulation_id"))
print("  next_seed:", terminal.get("next_seed"))
print("  generations:", terminal.get("generations"))
print("  debt_allowed:", terminal.get("debt_allowed"))
print("  release_present:", isinstance(release, dict))
print(
    "  release_consumed:",
    None if not isinstance(release, dict)
    else release.get("consumed")
)
print("  execution_allowed:", execution_allowed())

if state.get("frozen") is not True:
    raise SystemExit("FATAL: Loop-7 freeze is not intact")

print()
print("[3/4] Authority state PASS")
PY

# ------------------------------------------------------------
# IMPORTANT:
# STARTING OMNIS DOES NOT AUTOMATICALLY EXECUTE A CONSUMED
# ONE-SHOT RELEASE.
# ------------------------------------------------------------

echo "[4/4] OMNIS V3 STARTUP ENTRY ACTIVE"
echo
echo "OMNIS V3 STARTED"
echo "Execution authority remains controlled by freeze_state."
echo "============================================================"


echo
echo "=== SINGLE-INSTANCE VERIFICATION ==="

count_service() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null | wc -l
}

shogun_count="$(count_service "$HOME/deep_recon/SHOGUN_LIVE_OPERATIONAL.sh")"
watch_count="$(count_service "$HOME/SHOGUN_OS/WATCH.sh")"

echo "SHOGUN_LIVE_OPERATIONAL instances: $shogun_count"
echo "SHOGUN WATCH instances:            $watch_count"

if [ "$shogun_count" -gt 1 ]; then
    echo "FATAL: multiple SHOGUN_LIVE_OPERATIONAL instances detected"
    exit 1
fi

if [ "$watch_count" -gt 1 ]; then
    echo "FATAL: multiple SHOGUN WATCH instances detected"
    exit 1
fi

echo "PASS: no duplicate managed service instances detected"
