cmd_restart() {
    mpe_cli_require_config
    local target="${1:-}"
    case "$target" in
        surge)
            mpe_cli_ssh "sudo systemctl restart surge-xt-cli.service && sudo systemctl start surge-watchdog.service"
            echo "$MPE_CLI_NAME: restarted surge-xt-cli.service (+ watchdog start)"
            ;;
        touch)
            mpe_cli_ssh "sudo systemctl restart touch-patch-browser.service"
            echo "$MPE_CLI_NAME: restarted touch-patch-browser.service"
            ;;
        looper)
            mpe_cli_ssh "sudo systemctl restart mpe-looper.service"
            echo "$MPE_CLI_NAME: restarted mpe-looper.service"
            ;;
        jackd)
            mpe_cli_ssh "sudo systemctl restart mpe-jackd.service"
            echo "$MPE_CLI_NAME: restarted mpe-jackd.service"
            ;;
        watchdog)
            mpe_cli_ssh "sudo systemctl restart surge-watchdog.service"
            echo "$MPE_CLI_NAME: restarted surge-watchdog.service"
            ;;
        all)
            mpe_cli_remote_bash '
# shellcheck source=lib/mpe-services.sh
source "$MPE_MODULE_REPO/scripts/lib/mpe-services.sh"
mpe_restart_core_services
echo "  restarted surge + patch browser (+ boot animation when applicable)"
'
            echo "$MPE_CLI_NAME: restarted core services"
            ;;
        -h | --help | "")
            echo "Usage: $MPE_CLI_NAME restart <surge|touch|looper|jackd|all>" >&2
            exit 1
            ;;
        *)
            echo "$MPE_CLI_NAME restart: unknown target: $target (use surge, touch, looper, jackd, or all)" >&2
            exit 1
            ;;
    esac
}
