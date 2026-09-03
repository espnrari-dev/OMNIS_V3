#!/data/data/com.termux/files/usr/bin/bash
set -e

BASE="$HOME/OMNIS_V3"
RUNTIME="$BASE/data/runtime"
PIDFILE="$RUNTIME/omnis_runtime.pid"
LOCKDIR="$RUNTIME/omnis_runtime.lock"
BODY="$BASE/start_body.sh"

mkdir -p "$RUNTIME"

echo "========================================================"
echo "OMNIS V3 — CONTROLLED SINGLE-INSTANCE START"
echo "========================================================"

# ----------------------------------------------------------
# Clear previous registered supervisor.
# ----------------------------------------------------------

if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"

    if [[ "$OLD_PID" =~ ^[0-9]+$ ]] &&
       [ -d "/proc/$OLD_PID" ]; then

        OLD_CMD="$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null || true)"

        if [[ "$OLD_CMD" == *"$BASE/start.sh"* ]]; then
            echo "Terminating previous OMNIS supervisor: PID $OLD_PID"

            kill "$OLD_PID" 2>/dev/null || true

            for _ in $(seq 1 30); do
                [ ! -d "/proc/$OLD_PID" ] && break
                sleep 0.1
            done

            if [ -d "/proc/$OLD_PID" ]; then
                kill -9 "$OLD_PID" 2>/dev/null || true
            fi

            echo "PASS: previous OMNIS supervisor terminated"
        fi
    fi

    rm -f "$PIDFILE"
fi

rm -rf "$LOCKDIR"

# ----------------------------------------------------------
# Acquire singleton ownership.
# ----------------------------------------------------------

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "FATAL: OMNIS singleton lock already exists"
    exit 1
fi

# ----------------------------------------------------------
# Register this supervisor.
# ----------------------------------------------------------

echo "$$" > "$PIDFILE"

cleanup() {
    CURRENT_PID="$(cat "$PIDFILE" 2>/dev/null || true)"

    if [ "$CURRENT_PID" = "$$" ]; then
        rm -f "$PIDFILE"
        rmdir "$LOCKDIR" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM HUP

if [ "$(cat "$PIDFILE" 2>/dev/null)" != "$$" ]; then
    echo "FATAL: OMNIS PID registration failed"
    exit 1
fi

echo
echo "=== SINGLE-INSTANCE RUNTIME CONTROL ==="
echo "OMNIS supervisor PID: $$"
echo "PASS: supervisor registered"

# ----------------------------------------------------------
# Execute authoritative OMNIS startup.
# ----------------------------------------------------------

echo
echo "=== EXECUTING OMNIS V3 STARTUP ==="

test -x "$BODY" || chmod 700 "$BODY"

"$BODY"

echo
echo "PASS: OMNIS V3 startup completed"

# ----------------------------------------------------------
# Verify ownership.
# ----------------------------------------------------------

echo
echo "=== SINGLE-INSTANCE VERIFICATION ==="

REGISTERED_PID="$(cat "$PIDFILE" 2>/dev/null || true)"

if [ "$REGISTERED_PID" != "$$" ]; then
    echo "FATAL: registered PID changed"
    exit 1
fi

if [ ! -d "/proc/$$" ]; then
    echo "FATAL: supervisor process is not alive"
    exit 1
fi

if [ ! -d "$LOCKDIR" ]; then
    echo "FATAL: singleton lock disappeared"
    exit 1
fi

echo "PASS: registered PID = $$"
echo "PASS: supervisor process alive"
echo "PASS: singleton lock active"
echo "PASS: exactly one managed OMNIS supervisor"

echo
echo "========================================================"
echo "OMNIS V3 — RUNTIME SUPERVISOR ACTIVE"
echo "========================================================"
echo "PID: $$"
echo "Singleton: ENFORCED"
echo "Runtime state: $RUNTIME"
echo "Execution authority remains controlled by freeze_state."
echo "========================================================"

# ----------------------------------------------------------
# Remain alive as the actual managed instance.
# ----------------------------------------------------------

while true; do

    if [ ! -f "$PIDFILE" ]; then
        echo "FATAL: OMNIS PID registration disappeared"
        exit 1
    fi

    CURRENT_PID="$(cat "$PIDFILE" 2>/dev/null || true)"

    if [ "$CURRENT_PID" != "$$" ]; then
        echo "FATAL: OMNIS PID ownership changed"
        exit 1
    fi

    if [ ! -d "$LOCKDIR" ]; then
        echo "FATAL: OMNIS singleton lock disappeared"
        exit 1
    fi

    sleep 5
done
