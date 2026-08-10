# Load laptop-side appliance SSH config (no product-repo dependency).

MPE_CLI_CONFIG="${MPE_CLI_CONFIG:-${HOME}/.config/mpe/mpe.env}"
MPE_CLI_NAME="${MPE_CLI_NAME:-mpe}"

mpe_cli_load_config() {
    if [ -f "$MPE_CLI_CONFIG" ]; then
        # shellcheck disable=SC1090
        set -a
        source "$MPE_CLI_CONFIG"
        set +a
    fi
    PI_HOST="${PI_HOST:-raspberrypi.local}"
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/your_pi_key}"
    PI_MPE_MODULE="${PI_MPE_MODULE:-}"
}

mpe_cli_require_config() {
    mpe_cli_load_config
    if [ -z "${PI_USER:-}" ]; then
        echo "$MPE_CLI_NAME: PI_USER not set." >&2
        echo "Copy config/mpe.env.example to $MPE_CLI_CONFIG and set PI_USER, PI_HOST, SSH_KEY." >&2
        exit 1
    fi
}

mpe_cli_remote_repo() {
    if [ -n "${PI_MPE_MODULE:-}" ]; then
        printf '%s' "$PI_MPE_MODULE"
    else
        printf '%s' '~/MPE-Module'
    fi
}

mpe_cli_pi_source_line() {
    local repo
    repo="$(mpe_cli_remote_repo)"
    printf 'source %s/scripts/lib/paths.sh' "$repo"
}
