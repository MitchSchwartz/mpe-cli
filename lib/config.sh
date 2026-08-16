# shellcheck shell=bash
# Load laptop-side appliance SSH config (no product-repo dependency).

MPE_CLI_CONFIG="${MPE_CLI_CONFIG:-${HOME}/.config/mpe/mpe.env}"
MPE_CLI_NAME="${MPE_CLI_NAME:-mpe}"

# PI_MPE_MODULE is interpolated into a shell command that executes on the Pi
# (mpe_cli_pi_source_line -> mpe_cli_remote_bash -> `bash -s`). It is code, not
# data. Three rules keep it that way: it may only come from the config file,
# it must be a plain absolute path, and it is shell-quoted at the point of use.
mpe_cli_validate_pi_mpe_module() {
    local value="${PI_MPE_MODULE:-}"
    [ -n "$value" ] || return 0
    case "$value" in
        /*) ;;
        *)
            echo "$MPE_CLI_NAME: PI_MPE_MODULE must be an absolute path (got: $value)" >&2
            exit 1
            ;;
    esac
    case "$value" in
        *[!A-Za-z0-9_./-]*)
            echo "$MPE_CLI_NAME: PI_MPE_MODULE contains illegal characters: $value" >&2
            exit 1
            ;;
    esac
    case "$value" in
        *..*)
            echo "$MPE_CLI_NAME: PI_MPE_MODULE must not contain '..': $value" >&2
            exit 1
            ;;
    esac
}

mpe_cli_load_config() {
    # Never inherit PI_MPE_MODULE from the caller's environment — it reaches a
    # remote shell, so an exported value would be remote code execution. Only
    # the config file may set it.
    unset PI_MPE_MODULE
    if [ -f "$MPE_CLI_CONFIG" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$MPE_CLI_CONFIG"
        set +a
    fi
    mpe_cli_validate_pi_mpe_module
}

mpe_cli_require_config() {
    # A missing config is a hard error, not a fallthrough. Without this, an
    # absent/renamed/unreadable config leaves PI_USER, PI_HOST and SSH_KEY to be
    # supplied by the caller's environment — which silently retargets every
    # remote command at an arbitrary host with an arbitrary key.
    if [ ! -f "$MPE_CLI_CONFIG" ] || [ ! -r "$MPE_CLI_CONFIG" ]; then
        echo "$MPE_CLI_NAME: config not found or unreadable: $MPE_CLI_CONFIG" >&2
        echo "Copy config/mpe.env.example to $MPE_CLI_CONFIG and set PI_USER, PI_HOST, SSH_KEY." >&2
        exit 1
    fi
    mpe_cli_load_config
    local missing=0
    if [ -z "${PI_USER:-}" ]; then
        echo "$MPE_CLI_NAME: PI_USER not set." >&2
        missing=1
    fi
    if [ -z "${PI_HOST:-}" ]; then
        echo "$MPE_CLI_NAME: PI_HOST not set." >&2
        missing=1
    fi
    if [ -z "${SSH_KEY:-}" ]; then
        echo "$MPE_CLI_NAME: SSH_KEY not set." >&2
        missing=1
    fi
    if [ "$missing" -ne 0 ]; then
        echo "Copy config/mpe.env.example to $MPE_CLI_CONFIG and set PI_USER, PI_HOST, SSH_KEY." >&2
        exit 1
    fi
    if [ ! -f "$SSH_KEY" ]; then
        echo "$MPE_CLI_NAME: SSH_KEY not found: $SSH_KEY" >&2
        exit 1
    fi
}

mpe_cli_remote_repo() {
    if [ -n "${PI_MPE_MODULE:-}" ]; then
        printf '%s' "$PI_MPE_MODULE"
    else
        # Deliberately a literal tilde: this string is not used locally, it is
        # sent to the Pi and expanded by the remote shell. Expanding it here
        # would resolve to the *laptop's* home. See mpe_cli_pi_source_line.
        # shellcheck disable=SC2088
        printf '%s' '~/MPE-Module'
    fi
}

mpe_cli_pi_source_line() {
    local repo
    repo="$(mpe_cli_remote_repo)"
    if [ -n "${PI_MPE_MODULE:-}" ]; then
        # Validated absolute path. %q emits a single shell-safe word, so even a
        # future loosening of the validator cannot inject a second command.
        printf 'source %q/scripts/lib/paths.sh' "$repo"
    else
        # Default is the literal '~/MPE-Module' and must stay unquoted so the
        # remote shell expands the tilde. %q here would emit '\~' and break
        # every remote command.
        printf 'source %s/scripts/lib/paths.sh' "$repo"
    fi
}
