# Looper yolo deploy + systemd restart (fixed SSH surface for agents).

# shellcheck source=../lib/repo.sh
source "$MPE_CLI_ROOT/lib/repo.sh"

mpe_cli_default_looper_branch() {
    printf '%s' "${MPE_LOOPER_DEPLOY_BRANCH:-yolo/looper-phase0}"
}

cmd_looper() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        deploy)
            cmd_looper_deploy "$@"
            ;;
        restart)
            cmd_looper_restart "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME looper deploy [branch]
       $MPE_CLI_NAME looper restart

  deploy   git pull on Pi + restart mpe-looper.service (default branch: $(mpe_cli_default_looper_branch))
  restart  systemctl restart mpe-looper.service only
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME looper: unknown subcommand: $sub (use deploy|restart)" >&2
            exit 1
            ;;
    esac
}

cmd_looper_deploy() {
    mpe_cli_require_config
    local branch="${1:-$(mpe_cli_default_looper_branch)}"
    mpe_cli_validate_git_branch "$branch"
    echo "$MPE_CLI_NAME looper deploy → $PI_USER@$PI_HOST ($branch)"
    mpe_cli_remote_bash "$(mpe_cli_remote_repo_cd)
branch=$(printf '%q' "$branch")
git stash push -q -m mpe-looper-deploy -- scripts/mpe-looper.py 2>/dev/null || true
git fetch origin \"\$branch\"
git checkout \"\$branch\"
git pull origin \"\$branch\"
./scripts/looper-deploy.sh \"\$branch\""
}

cmd_looper_restart() {
    mpe_cli_require_config
    mpe_cli_ssh "sudo systemctl restart mpe-looper.service"
    echo "$MPE_CLI_NAME: restarted mpe-looper.service"
}
