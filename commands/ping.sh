# shellcheck shell=bash
cmd_ping() {
    mpe_cli_require_config
    if mpe_cli_ssh "echo ok" >/dev/null; then
        echo "$MPE_CLI_NAME: $PI_USER@$PI_HOST reachable"
    else
        echo "$MPE_CLI_NAME: cannot reach $PI_USER@$PI_HOST" >&2
        exit 1
    fi
}
