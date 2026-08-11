# Product repo paths (laptop clone + remote appliance clone).

mpe_cli_local_repo() {
    mpe_cli_load_config
    if [ -n "${LOCAL_MPE_MODULE:-}" ]; then
        printf '%s' "$LOCAL_MPE_MODULE"
    else
        printf '%s' "$HOME/Documents/GitHub/MPE-Module"
    fi
}

mpe_cli_require_local_repo() {
    local repo
    repo="$(mpe_cli_local_repo)"
    if [ ! -d "$repo" ]; then
        echo "$MPE_CLI_NAME: local repo not found: $repo" >&2
        echo "Set LOCAL_MPE_MODULE in $MPE_CLI_CONFIG" >&2
        exit 1
    fi
    printf '%s' "$repo"
}

mpe_cli_require_tests_dir() {
    local repo="$1"
    if [ ! -d "$repo/tests" ]; then
        echo "$MPE_CLI_NAME: no tests/ in $repo" >&2
        exit 1
    fi
}

# Remote bash lines: assign appliance repo path and cd (tilde expands when quoted).
mpe_cli_remote_repo_cd() {
    cat <<EOF
repo="$(mpe_cli_remote_repo)"
repo="\${repo/#\\~/\$HOME}"
cd "\$repo" || exit 1
EOF
}
