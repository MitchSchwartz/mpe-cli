#!/usr/bin/env bash
# Regression tests for remote command injection via PI_MPE_MODULE, and for the
# missing-config fallthrough that let the environment retarget the appliance.
#
# No framework: run directly, exits non-zero on first failure.
#   bash tests/test_config_injection.sh
#
# Background: PI_MPE_MODULE is interpolated into a shell command executed on the
# Pi via `bash -s`. Before 1.3.0 it was taken from the caller's environment and
# emitted unquoted, so `PI_MPE_MODULE='/tmp/x; id #'` ran arbitrary commands on
# the appliance as the SSH user — through every "read-only, agent-safe"
# subcommand, because the injection is in the preamble prepended to all of them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n     %s\n' "$1" "$2" >&2; FAILED=1; }

# Emit the remote source line under a given env/config, printing nothing else.
source_line() {
    bash -c '
        set -euo pipefail
        source "$1/lib/config.sh"
        mpe_cli_load_config
        mpe_cli_pi_source_line
    ' _ "$REPO_ROOT" 2>&1
}

echo "== PI_MPE_MODULE injection =="

# 1. The original exploit. The payload must not appear in the emitted line.
out="$(PI_MPE_MODULE='/tmp/pwn; id #' MPE_CLI_CONFIG=/dev/null source_line)"
case "$out" in
    *';'*|*'id'*|*'#'*) fail "env payload rejected" "leaked into: $out" ;;
    'source ~/MPE-Module/scripts/lib/paths.sh') pass "env payload rejected" ;;
    *) fail "env payload rejected" "unexpected output: $out" ;;
esac

# 2. Even a benign environment value must be ignored — the variable is
#    config-file-only, so no future caller can reintroduce the vector.
out="$(PI_MPE_MODULE='/opt/elsewhere' MPE_CLI_CONFIG=/dev/null source_line)"
if [ "$out" = 'source ~/MPE-Module/scripts/lib/paths.sh' ]; then
    pass "benign env value ignored"
else
    fail "benign env value ignored" "got: $out"
fi

# 3. A legitimate config value still works (no over-correction).
printf 'PI_MPE_MODULE=/home/pi/MPE-Module\n' >"$TMP/ok.env"
out="$(MPE_CLI_CONFIG="$TMP/ok.env" source_line)"
if [ "$out" = 'source /home/pi/MPE-Module/scripts/lib/paths.sh' ]; then
    pass "valid config value accepted"
else
    fail "valid config value accepted" "got: $out"
fi

# NOTE: the rejection cases below capture output rather than piping into grep.
# The validator exits 1 by design, and with `set -o pipefail` a pipeline
# inherits that failure even when grep matches — which would report a working
# validator as broken.

# 4. A malicious config value is rejected outright.
printf 'PI_MPE_MODULE="/tmp/pwn; id #"\n' >"$TMP/bad.env"
out="$(MPE_CLI_CONFIG="$TMP/bad.env" source_line)"
case "$out" in
    *"illegal characters"*) pass "malicious config value rejected" ;;
    *) fail "malicious config value rejected" "got: $out" ;;
esac

# 5. Path traversal is rejected.
printf 'PI_MPE_MODULE=/home/../../etc\n' >"$TMP/trav.env"
out="$(MPE_CLI_CONFIG="$TMP/trav.env" source_line)"
case "$out" in
    *"must not contain"*) pass "traversal rejected" ;;
    *) fail "traversal rejected" "got: $out" ;;
esac

# 6. Relative paths are rejected.
printf 'PI_MPE_MODULE=MPE-Module\n' >"$TMP/rel.env"
out="$(MPE_CLI_CONFIG="$TMP/rel.env" source_line)"
case "$out" in
    *"absolute path"*) pass "relative path rejected" ;;
    *) fail "relative path rejected" "got: $out" ;;
esac

# 7. The default must keep a LITERAL tilde. It is expanded by the remote shell;
#    quoting it (%q -> \~) or expanding it locally would point at the laptop's
#    home directory and break every remote command.
printf 'PI_USER=x\n' >"$TMP/def.env"
out="$(MPE_CLI_CONFIG="$TMP/def.env" source_line)"
if [ "$out" = 'source ~/MPE-Module/scripts/lib/paths.sh' ]; then
    pass "default keeps literal tilde"
else
    fail "default keeps literal tilde" "got: $out"
fi

echo "== missing config must not fall through to the environment =="

# 8. An absent config previously left PI_USER/PI_HOST/SSH_KEY to the caller's
#    environment, silently retargeting the appliance at an arbitrary host.
out="$(MPE_CLI_CONFIG=/nonexistent PI_USER=evil PI_HOST=evil.host SSH_KEY=/etc/hostname \
    bash -c '
        set -euo pipefail
        source "$1/lib/config.sh"
        mpe_cli_require_config
        echo "REACHED-WIRE:$PI_USER@$PI_HOST"
    ' _ "$REPO_ROOT" 2>&1)"
case "$out" in
    *REACHED-WIRE*) fail "missing config is fatal" "env supplied the target: $out" ;;
    *"config not found or unreadable"*) pass "missing config is fatal" ;;
    *) fail "missing config is fatal" "unexpected output: $out" ;;
esac

# 9. Local-only commands must still work without any appliance config, since
#    lib/repo.sh calls load_config purely to resolve LOCAL_MPE_MODULE.
if MPE_CLI_CONFIG=/nonexistent "$REPO_ROOT/bin/mpe" version >/dev/null 2>&1; then
    pass "local-only commands work without config"
else
    fail "local-only commands work without config" "mpe version exited non-zero"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "All config injection tests passed."
else
    echo "FAILURES present." >&2
fi
exit "$FAILED"
