#!/bin/bash
# Install mpe CLI to ~/.local/bin and seed config if missing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/mpe"
CONFIG_FILE="${CONFIG_DIR}/mpe.env"

mkdir -p "$BIN_DIR" "$CONFIG_DIR"
chmod +x "$REPO_ROOT/bin/mpe"
ln -sf "$REPO_ROOT/bin/mpe" "$BIN_DIR/mpe"

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$REPO_ROOT/config/mpe.env.example" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "Created $CONFIG_FILE — edit PI_USER, PI_HOST, SSH_KEY before use."
else
    echo "Config exists: $CONFIG_FILE"
fi

echo "Installed: $BIN_DIR/mpe -> $REPO_ROOT/bin/mpe"
if command -v mpe >/dev/null 2>&1; then
    echo "Verify: mpe ping"
else
    echo "Add ~/.local/bin to PATH if needed, then: mpe ping"
fi
