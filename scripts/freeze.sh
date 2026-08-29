#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FROZEN_DIR="$HOME/OMNIS_V3_FROZEN_${TIMESTAMP}"

echo "Freezing OMNIS V3 to $FROZEN_DIR"

if command -v rsync &>/dev/null; then
    rsync -a --exclude='data' --exclude='logs' --exclude='models' \
        --exclude='.git' --exclude='*.db' --exclude='__pycache__' ./ "$FROZEN_DIR/"
else
    echo "rsync not found; falling back to tar-based copy."
    mkdir -p "$FROZEN_DIR"
    tar -cf - \
        --exclude='./data' --exclude='./logs' --exclude='./models' \
        --exclude='./.git' --exclude='*.db' --exclude='__pycache__' . \
        | tar -xf - -C "$FROZEN_DIR"
fi

cd "$FROZEN_DIR"
tar -czf "$HOME/OMNIS_V3_FROZEN_${TIMESTAMP}.tar.gz" .
echo "Freeze complete: $HOME/OMNIS_V3_FROZEN_${TIMESTAMP}.tar.gz"
echo "To restore: mkdir -p ~/OMNIS_V3 && tar -xzf $HOME/OMNIS_V3_FROZEN_${TIMESTAMP}.tar.gz -C ~/OMNIS_V3 && cd ~/OMNIS_V3 && ./scripts/start.sh"
