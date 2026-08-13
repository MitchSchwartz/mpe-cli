# shellcheck shell=bash
cmd_logs() {
    mpe_cli_require_config
    local target="${1:-}"
    local lines="$MPE_LOG_LINES_DEFAULT"
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -n)
                shift
                lines="$(mpe_cli_clamp_log_lines "${1:-}")"
                ;;
            -h | --help)
                echo "Usage: $MPE_CLI_NAME logs <surge|touch|looper|watchdog|jackd> [-n N]"
                exit 0
                ;;
            *)
                echo "$MPE_CLI_NAME logs: unknown option: $1" >&2
                exit 1
                ;;
        esac
        shift
    done
    case "$target" in
        surge)
            mpe_cli_remote_bash "tail -n $lines \"\${MPE_SURGE_LOG:-\$HOME/surge-cli.log}\" 2>/dev/null || echo '(no surge log)'"
            ;;
        touch)
            mpe_cli_ssh "journalctl -u touch-patch-browser.service -n $lines --no-pager"
            ;;
        looper)
            mpe_cli_ssh "journalctl -u mpe-looper.service -n $lines --no-pager"
            ;;
        watchdog)
            mpe_cli_ssh "journalctl -u surge-watchdog.service -n $lines --no-pager"
            ;;
        jackd)
            mpe_cli_ssh "journalctl -u mpe-jackd.service -n $lines --no-pager"
            ;;
        "" | -h | --help)
            echo "Usage: $MPE_CLI_NAME logs <surge|touch|looper|watchdog> [-n N]" >&2
            exit 1
            ;;
        *)
            echo "$MPE_CLI_NAME logs: unknown target: $target (use surge, touch, looper, watchdog, or jackd)" >&2
            exit 1
            ;;
    esac
}
