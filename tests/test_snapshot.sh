#!/usr/bin/env bash
# shellcheck disable=SC1091
# Exercises the real helpers in lib/snapshot.sh — not copies of their logic.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MPE_CLI_NAME="mpe"
source "$ROOT/lib/snapshot.sh"

fail=0
check() {
    local label="$1" expected="$2" got="$3"
    if [ "$got" = "$expected" ]; then
        return
    fi
    echo "FAIL $label: expected '$expected' got '$got'" >&2
    fail=1
}

# --- probes argument -> Python literal -------------------------------------
check "py_bool empty" "False" "$(mpe_cli_snapshot_py_include "")"
check "py_bool 0"     "False" "$(mpe_cli_snapshot_py_include 0)"
check "py_bool 1"     "True"  "$(mpe_cli_snapshot_py_include 1)"
check "py_bool true"  "False" "$(mpe_cli_snapshot_py_include true)"

# The literal must be valid Python that round-trips to the right bool.
for probes in "" 0 1; do
    lit="$(mpe_cli_snapshot_py_include "$probes")"
    got="$(python3 -c "include = $lit
print(repr(include))")"
    case "$probes" in
        1) check "python probes=1" "True" "$got" ;;
        *) check "python probes='$probes'" "False" "$got" ;;
    esac
done

# --- stale polarity ---------------------------------------------------------
# Regression: `.stale // true` in jq returns true for a HEALTHY unit, because
# jq's `//` treats false as absent. Three active+enabled units rendered as
# active=unknown on the appliance 2026-08-19.
export MPE_SNAPSHOT_JSON='{
  "services": {
    "mpe-jackd": {"active": "active", "enabled": "enabled", "stale": false},
    "sl-watchdog": {"active": "unknown", "enabled": "unknown", "stale": true}
  },
  "graph": {"surge_on_graph": false, "stale": false}
}'

check "healthy unit not stale" "false" \
    "$(mpe_cli_snapshot_stale --arg u mpe-jackd '.services[$u].stale')"
check "stale unit is stale" "true" \
    "$(mpe_cli_snapshot_stale --arg u sl-watchdog '.services[$u].stale')"
check "absent unit is stale" "true" \
    "$(mpe_cli_snapshot_stale --arg u nope '.services[$u].stale')"
check "graph not stale" "false" "$(mpe_cli_snapshot_stale '.graph.stale')"
check "missing path is stale" "true" "$(mpe_cli_snapshot_stale '.nothing.here')"

# surge_on_graph=false must survive as "false", not collapse to empty.
check "surge off graph reads false" "false" \
    "$(mpe_cli_snapshot_field '.graph.surge_on_graph')"

# --- syntax -----------------------------------------------------------------
bash -n "$ROOT/lib/snapshot.sh"
bash -n "$ROOT/commands/status.sh"
bash -n "$ROOT/commands/diagnose.sh"
bash -n "$ROOT/commands/engine.sh"
bash -n "$ROOT/commands/jack.sh"

# No caller may reintroduce `.stale // true` — the bug this file exists for.
if grep -rn 'stale // true' "$ROOT/commands" "$ROOT/lib" | grep -v '^[^:]*:[0-9]*:#'; then
    echo "FAIL: '.stale // true' inverts polarity — use mpe_cli_snapshot_stale" >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "test_snapshot.sh: ok"
