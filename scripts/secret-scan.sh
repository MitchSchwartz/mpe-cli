#!/usr/bin/env bash
# Run gitleaks against this repo (full history). Used locally and by .githooks/pre-commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks not found. Install one of:" >&2
  echo "  curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.24.2/gitleaks_8.24.2_linux_x64.tar.gz | tar xz -C ~/.local/bin gitleaks" >&2
  echo "  brew install gitleaks" >&2
  exit 1
fi

CONFIG="${GITLEAKS_CONFIG:-$ROOT/.gitleaks.toml}"
echo "gitleaks detect --source $ROOT --config $CONFIG"
gitleaks detect --source "$ROOT" --config "$CONFIG" --verbose "$@"
