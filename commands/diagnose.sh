# shellcheck shell=bash
cmd_diagnose() {
    mpe_cli_require_config
    # shellcheck source=../lib/snapshot.sh
    source "$MPE_CLI_ROOT/lib/snapshot.sh"
    mpe_cli_snapshot_fetch || exit 1

    echo "=== SESSION SNAPSHOT ==="
    echo "schema: $(mpe_cli_snapshot_field '.schema')"
    echo "mode:   $(mpe_cli_snapshot_field '.mode')"
    echo "seq:    $(mpe_cli_snapshot_field '.seq // "—"')"
    echo ""
    echo "=== ENGINE (from snapshot) ==="
    mpe_cli_render_engine_state_kv
    echo ""
    echo "=== SERVICES (from snapshot) ==="
    mpe_cli_render_services_block
    echo ""

    local repo
    repo="$(mpe_cli_remote_repo)"
    mpe_cli_ssh "bash -lc 'cd $repo && ./scripts/diagnose-pi-state.sh'"
}
