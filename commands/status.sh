# shellcheck shell=bash
cmd_status() {
    mpe_cli_require_config
    # shellcheck source=../lib/snapshot.sh
    source "$MPE_CLI_ROOT/lib/snapshot.sh"
    mpe_cli_snapshot_fetch || exit 1
    mpe_cli_render_services_block
    mpe_cli_render_mpe_env_snippet
}
