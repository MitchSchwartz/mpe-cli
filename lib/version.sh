# shellcheck shell=bash
# Version comparison for `mpe version --check`.
#
# MPE_CLI_VERSION itself is declared in bin/mpe alongside MPE_CLI_ROOT and
# MPE_CLI_NAME, so the entrypoint stays the single place a reader looks for
# "what is this". Only the comparison logic lives here.
#
# Consumers pin a floor rather than an exact version: the product repo asserts
# the CLI is new enough to have the subcommands and suites it depends on.

# 0 if the string is a dotted numeric version (1, 1.2, 1.2.3).
mpe_cli_version_is_valid() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

# 0 if $1 >= $2. Missing trailing components count as 0, so 1.2 == 1.2.0.
mpe_cli_version_ge() {
    local have="$1" want="$2"
    local -a h w
    IFS=. read -r -a h <<<"$have"
    IFS=. read -r -a w <<<"$want"

    local i len=${#h[@]}
    [ "${#w[@]}" -gt "$len" ] && len=${#w[@]}

    for ((i = 0; i < len; i++)); do
        local hi="${h[i]:-0}" wi="${w[i]:-0}"
        # Strip leading zeros so 10 > 09 compares numerically, not as strings.
        hi=$((10#$hi))
        wi=$((10#$wi))
        if [ "$hi" -gt "$wi" ]; then return 0; fi
        if [ "$hi" -lt "$wi" ]; then return 1; fi
    done
    return 0
}
