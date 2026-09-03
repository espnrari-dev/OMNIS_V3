#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASHBOARD="frontend/static/index.html"

[ -f "$DASHBOARD" ] || {
    echo "FATAL: V3 dashboard missing"
    exit 1
}

# V2 is forbidden in the authoritative dashboard.
if grep -qE 'OMNIS V2|OMNIS_V2|V2 — System Command|V2 - System Command' "$DASHBOARD"; then
    echo "FATAL: V2 dashboard detected. Refusing to run."
    exit 1
fi

# V3 identity must exist.
grep -q 'OMNIS V3' "$DASHBOARD" || {
    echo "FATAL: Dashboard does not identify as OMNIS V3."
    exit 1
}

echo "V3 dashboard lock: PASS"
