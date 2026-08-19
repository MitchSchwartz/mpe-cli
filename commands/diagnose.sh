# shellcheck shell=bash
cmd_diagnose() {
    mpe_cli_require_config
    local repo
    repo="$(mpe_cli_remote_repo)"
    mpe_cli_ssh "bash -lc 'cd $repo && ./scripts/diagnose-pi-state.sh'"
}
