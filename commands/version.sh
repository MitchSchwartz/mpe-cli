# shellcheck shell=bash
# shellcheck source=../lib/version.sh
source "$MPE_CLI_ROOT/lib/version.sh"

# Report the installed CLI version, or assert a minimum for consuming repos.
#
# Exit codes are the contract — a consumer script pins a floor with
# `mpe version --check X.Y.Z` and branches on the status:
#   0  installed version satisfies the floor
#   1  installed version is older than the floor
#   2  usage error (missing or malformed version argument)

cmd_version() {
    local arg1="${1:-}"

    case "$arg1" in
        "")
            echo "$MPE_CLI_NAME $MPE_CLI_VERSION"
            return 0
            ;;
        -h | --help | help)
            mpe_cli_version_usage
            return 0
            ;;
        --check | --min)
            local want="${2:-}"
            if [ -z "$want" ]; then
                echo "$MPE_CLI_NAME version: $arg1 requires a version (e.g. $arg1 1.1.0)" >&2
                exit 2
            fi
            if ! mpe_cli_version_is_valid "$want"; then
                echo "$MPE_CLI_NAME version: not a dotted numeric version: $want" >&2
                exit 2
            fi
            if mpe_cli_version_ge "$MPE_CLI_VERSION" "$want"; then
                return 0
            fi
            echo "$MPE_CLI_NAME $MPE_CLI_VERSION is older than required $want" >&2
            echo "Update the CLI: cd <mpe-cli clone> && git pull && ./install.sh" >&2
            exit 1
            ;;
        *)
            echo "$MPE_CLI_NAME version: unknown option: $arg1" >&2
            mpe_cli_version_usage >&2
            exit 2
            ;;
    esac
}

mpe_cli_version_usage() {
    cat <<EOF
Usage: $MPE_CLI_NAME version [--check <x.y.z>]

  version                 Print "$MPE_CLI_NAME <version>"
  version --check 1.1.0   Exit 0 if installed >= 1.1.0, 1 if older, 2 on bad input

Consuming repos pin a floor in a test/CI preflight:

  mpe version --check 1.1.0 || exit 1

Allowlist examples:
  $MPE_CLI_NAME version · $MPE_CLI_NAME version --check 1.1.0
EOF
}
