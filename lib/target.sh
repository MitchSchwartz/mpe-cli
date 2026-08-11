# Shared local|pi target parsing and dispatch (read-only ops).

mpe_cli_target_is_known() {
    case "$1" in
        local | l | pi | remote) return 0 ;;
        *) return 1 ;;
    esac
}

mpe_cli_normalize_target() {
    case "$1" in
        pi | remote) printf '%s' pi ;;
        local | l | "") printf '%s' local ;;
        *)
            echo "$MPE_CLI_NAME: unknown target: $1 (use local or pi)" >&2
            return 1
            ;;
    esac
}

# Echo normalized target (local|pi). First arg may be target or empty for default local.
mpe_cli_parse_target() {
    local raw="${1:-local}"
    if mpe_cli_target_is_known "$raw"; then
        mpe_cli_normalize_target "$raw"
        return 0
    fi
    mpe_cli_normalize_target local
}

# Run a fixed local shell command or the same command on the appliance via SSH.
# Usage: mpe_cli_run_on_target <local|pi> <local_cmd> <remote_heredoc_body>
mpe_cli_run_on_target() {
    local target="$1"
    local local_cmd="$2"
    local remote_script="$3"

    case "$target" in
        local)
            bash -c "$local_cmd"
            ;;
        pi)
            mpe_cli_require_config
            echo "Host: $PI_USER@$PI_HOST"
            mpe_cli_remote_bash "$remote_script"
            ;;
        *)
            echo "$MPE_CLI_NAME: internal target error: $target" >&2
            exit 1
            ;;
    esac
}
