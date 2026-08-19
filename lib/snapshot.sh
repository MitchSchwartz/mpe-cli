# shellcheck shell=bash
# Session snapshot — one fresh build per command (criterion 6).

mpe_cli_snapshot_py_include() {
    # Map shell probes flag to a Python literal for build_snapshot().
    local probes="${1:-0}"
    if [ "$probes" = "1" ]; then
        printf '%s' "True"
    else
        printf '%s' "False"
    fi
}

mpe_cli_snapshot_fetch() {
    # Arg: 1 = include runtime probes (processes/graph), 0 or empty = omit.
    local repo probes="${1:-0}" py_include
    py_include="$(mpe_cli_snapshot_py_include "$probes")"
    repo="$(mpe_cli_remote_repo)"
    MPE_SNAPSHOT_JSON="$(
        mpe_cli_ssh "bash -lc $(printf '%q' "cd $repo && python3 - <<PY
import json
import sys
from patch_browser.session_snapshot import build_snapshot
include = ${py_include}
try:
    snap = build_snapshot(include_runtime_probes=include)
except ValueError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(2)
print(json.dumps(snap))
PY")"
    )" || return 1
    export MPE_SNAPSHOT_JSON
}

mpe_cli_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "$MPE_CLI_NAME: jq is required for snapshot rendering (apt install jq)" >&2
        exit 1
    fi
}

mpe_cli_snapshot_field() {
    mpe_cli_require_jq
    printf '%s' "$MPE_SNAPSHOT_JSON" | jq -r "$@"
}

mpe_cli_render_engine_state_kv() {
    local stale
    stale="$(mpe_cli_snapshot_field '.engine.stale')"
    if [ "$stale" = "true" ]; then
        echo "(engine state stale or absent — unknown)"
        return
    fi
    mpe_cli_snapshot_field '.engine.value // {} | to_entries[] | "\(.key)=\(.value)"'
}

mpe_cli_render_services_block() {
    mpe_cli_snapshot_field -r '
        .services // {} | to_entries[]
        | select(.key as $u | ($u == "mpe-jackd" or $u == "surge-xt-cli" or $u == "surge-watchdog" or $u == "touch-patch-browser" or $u == "patch-browser" or $u == "usb-audio-gadget" or $u == "uac2-stall-watchdog" or $u == "mpe-pressure-remap"))
        | if .value.stale then
            "  \(.key).service active=unknown    enabled=unknown"
          else
            "  \(.key).service active=\(.value.active) enabled=\(.value.enabled)"
          end
    '
}

mpe_cli_render_mpe_env_snippet() {
    if [ "$(mpe_cli_snapshot_field '.config.mpe_env | length')" = "0" ]; then
        return
    fi
    echo ""
    echo "  /etc/mpe/mpe.env:"
    mpe_cli_snapshot_field -r '.config.mpe_env | to_entries[] | "    \(.key)=\(.value)"'
}
