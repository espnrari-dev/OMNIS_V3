#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

FREEZE="$HOME/OMNIS_V3_FREEZE_V3"
rm -rf "$FREEZE"
mkdir -p "$FREEZE/frontend/static" "$FREEZE/backend" "$FREEZE/scripts"

cp frontend/static/index.html "$FREEZE/frontend/static/index.html"
cp backend/main.py "$FREEZE/backend/main.py"
cp backend/simulation_engine.py "$FREEZE/backend/simulation_engine.py"
cp scripts/start_v3.sh "$FREEZE/scripts/start_v3.sh"

# Preserve the working simulation database/state.
if [ -f data/simulations.sqlite3 ]; then
    mkdir -p "$FREEZE/data"
    cp data/simulations.sqlite3 "$FREEZE/data/simulations.sqlite3"
fi

# Record exact cryptographic identity of the freeze.
(
    cd "$FREEZE"
    find . -type f -print0 |
        sort -z |
        xargs -0 sha256sum > FREEZE_SHA256
)

cat > "$FREEZE/FREEZE_INFO" <<'INFO'
OMNIS V3 CANONICAL FREEZE
Created: 2026-08-29

Dashboard:
OMNIS V3 — System Command

Canonical operating state:
- V3 dashboard
- Port 5000
- Editable seed
- Editable generations
- Editable debt_allowed
- Persistent SQLite simulation engine
- Live simulation status/progress
- Latest simulation lineage
- Live telemetry polling
- V3 startup lock
- No V2 dashboard fallback

Known-good validation:
- Simulation ID: 1
- Seed: 42
- Generations: 10
- Debt allowed: true
- Status: completed
- Generation: 10
- Progress: 1.0
- Bloom: available
- Health: ok

This directory is the authoritative V3 recovery source.
Do NOT restore OMNIS V2 from any OMNIS.bak.* directory.
INFO

chmod -R a-w "$FREEZE"

echo
echo "=================================================="
echo "OMNIS V3 — CANONICAL FREEZE CREATED"
echo "=================================================="
echo
echo "AUTHORITATIVE:"
echo "$FREEZE"
echo
echo "HASH:"
sha256sum "$FREEZE/FREEZE_SHA256"
echo
echo "V3 DASHBOARD:"
grep -o '<title>[^<]*</title>' "$FREEZE/frontend/static/index.html" | head -1
echo
echo "FREEZE LOCK: PASS"
