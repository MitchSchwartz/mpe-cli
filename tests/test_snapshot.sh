#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=../lib/snapshot.sh
source "$ROOT/lib/snapshot.sh"

assert_include() {
    local probes="$1" expected="$2"
    local got
    got="$(python3 - <<PY
include = $(mpe_cli_snapshot_py_include "$probes")
print(repr(include))
PY
)"
    [ "$got" = "$expected" ] || {
        echo "probes=$probes: expected $expected got $got" >&2
        exit 1
    }
}

assert_include "" "False"
assert_include "0" "False"
assert_include "1" "True"

bash -n "$ROOT/lib/snapshot.sh"
bash -n "$ROOT/commands/status.sh"
bash -n "$ROOT/commands/diagnose.sh"
bash -n "$ROOT/commands/engine.sh"
bash -n "$ROOT/commands/jack.sh"

echo "test_snapshot.sh: ok"
