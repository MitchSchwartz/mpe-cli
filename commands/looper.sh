# shellcheck shell=bash
# Looper yolo deploy + systemd restart (fixed SSH surface for agents).

# shellcheck source=../lib/repo.sh
source "$MPE_CLI_ROOT/lib/repo.sh"
# shellcheck source=../lib/target.sh
source "$MPE_CLI_ROOT/lib/target.sh"

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
        debug)
            cmd_looper_debug "$@"
            ;;
        buffer)
            cmd_looper_buffer "$@"
            ;;
        enable)
            cmd_looper_enable "$@"
            ;;
        disable)
            cmd_looper_disable "$@"
            ;;
        sl-clips)
            cmd_looper_sl_clips "$@"
            ;;
        sl-smoke)
            cmd_looper_sl_smoke "$@"
            ;;
        sl-diagnose)
            cmd_looper_sl_diagnose "$@"
            ;;
        sl-rewire)
            cmd_looper_sl_rewire "$@"
            ;;
        sl-stop)
            cmd_looper_sl_stop "$@"
            ;;
        sl-reset)
            cmd_looper_sl_reset "$@"
            ;;
        sl-restart)
            cmd_looper_sl_restart "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME looper deploy [branch]
       $MPE_CLI_NAME looper restart
       $MPE_CLI_NAME looper debug on|off
       $MPE_CLI_NAME looper buffer 512|1024
       $MPE_CLI_NAME looper enable|disable
       $MPE_CLI_NAME looper sl-clips [local|pi]
       $MPE_CLI_NAME looper sl-smoke [local|pi]
       $MPE_CLI_NAME looper sl-diagnose [local|pi]
       $MPE_CLI_NAME looper sl-rewire [local|pi]
       $MPE_CLI_NAME looper sl-restart [local|pi]

  deploy    git pull on Pi + restart mpe-looper.service (default branch: $(mpe_cli_default_looper_branch))
  restart   systemctl restart mpe-looper.service only
  debug     Toggle MPE_LOOPER_DEBUG in /etc/mpe/mpe.env and restart looper
  buffer    Set MPE_SURGE_BUFFER_SIZE (Surge + looper period) and restart both services
  enable    Set MPE_LOOPER_ENABLED=1 in /etc/mpe/mpe.env (D5 guard test — reboot after)
  disable   Remove MPE_LOOPER_ENABLED from /etc/mpe/mpe.env
  sl-clips  Generate 16 SooperLooper fixture WAVs (default target: pi)
  sl-smoke  Restart SooperLooper -l 16, load clips, trigger all, sample load (default: pi)
  sl-diagnose 45s soak: xrun delta, fan-in count, peak dBFS (default: pi)
  sl-rewire   Fix graph: common_out -> playback, dry=0 all loops (default: pi)
  sl-stop     Pause all SooperLooper loops immediately (default: pi)
  sl-reset    Pause + undo_all every loop — silence + clear (default: pi)
  sl-restart  Restart SooperLooper on JACK + wire record path (after jackd restart)
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME looper: unknown subcommand: $sub (use deploy|restart|debug|buffer|sl-clips|sl-smoke)" >&2
            exit 1
            ;;
    esac
}

# SooperLooper eval scripts live in the product repo; default target is the appliance.
mpe_cli_looper_sl_target() {
    local raw="${1:-pi}"
    if mpe_cli_target_is_known "$raw"; then
        mpe_cli_normalize_target "$raw"
    else
        echo "$MPE_CLI_NAME looper: unknown target: $raw (use local or pi)" >&2
        exit 1
    fi
}

mpe_cli_looper_run_sl_script() {
    local script_rel="$1"
    local target="$2"
    local label="$3"

    case "$target" in
        local)
            local repo script
            repo="$(mpe_cli_require_local_repo)"
            script="${repo}/${script_rel}"
            if [ ! -f "$script" ]; then
                echo "$MPE_CLI_NAME looper: missing script: $script" >&2
                echo "Checkout docs/sooperlooper-eval (or newer) in $repo" >&2
                exit 1
            fi
            echo "=== $label (local) ==="
            echo "Repo: $repo"
            (
                cd "$repo" || exit 1
                bash "$script"
            )
            ;;
        pi)
            mpe_cli_require_config
            echo "=== $label (Pi) ==="
            echo "Host: $PI_USER@$PI_HOST"
            mpe_cli_remote_bash "
set -euo pipefail
$(mpe_cli_remote_repo_cd)
script=\"${script_rel}\"
if [ ! -f \"\$script\" ]; then
  echo 'missing script: '\$script >&2
  echo 'git pull docs/sooperlooper-eval on the Pi' >&2
  exit 1
fi
bash \"\$script\"
"
            ;;
        *)
            echo "$MPE_CLI_NAME looper: internal target error: $target" >&2
            exit 1
            ;;
    esac
}

cmd_looper_sl_clips() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/generate-test-clips.sh" "$target" "SooperLooper test clips"
}

cmd_looper_sl_smoke() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/smoke-16-loops.sh" "$target" "SooperLooper 16-loop smoke"
}

cmd_looper_sl_diagnose() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    if [ "$target" = pi ]; then
        mpe_cli_require_config
        echo "=== SooperLooper 16-loop crackle diagnostic (Pi) ==="
        echo "Host: $PI_USER@$PI_HOST"
        mpe_cli_remote_bash "
set -euo pipefail
$(mpe_cli_remote_repo_cd)
git fetch origin docs/sooperlooper-eval 2>/dev/null || true
git pull --ff-only origin docs/sooperlooper-eval 2>/dev/null || true
script=\"scripts/sooperlooper/diagnose-16loop-crackle.sh\"
if [ ! -f \"\$script\" ]; then
  echo 'missing script: '\$script >&2
  exit 1
fi
export MPE_SL_DIAG_SEC=\"\${MPE_SL_DIAG_SEC:-45}\"
bash \"\$script\"
"
        return
    fi
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/diagnose-16loop-crackle.sh" "$target" "SooperLooper 16-loop crackle diagnostic"
}

cmd_looper_sl_rewire() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    if [ "$target" = pi ]; then
        mpe_cli_require_config
        echo "=== SooperLooper JACK rewire (Pi) ==="
        echo "Host: $PI_USER@$PI_HOST"
        mpe_cli_remote_bash "
set -euo pipefail
$(mpe_cli_remote_repo_cd)
git fetch origin docs/sooperlooper-eval 2>/dev/null || true
git pull --ff-only origin docs/sooperlooper-eval 2>/dev/null || true
bash scripts/sooperlooper/stop-all-loops.sh 2>/dev/null || true
bash scripts/sooperlooper/wire-jack-graph.sh rewire
echo ''
echo '=== playback fan-in ==='
jack_lsp -c 2>/dev/null | awk '/^system:playback/ { inblock=1; next } inblock && /^[[:space:]]/ { print; next } inblock { inblock=0 }' | head -20
"
        return
    fi
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/wire-jack-graph.sh" "$target" "SooperLooper JACK rewire"
}

mpe_cli_looper_sl_pi_pull() {
    cat <<EOF
set -euo pipefail
$(mpe_cli_remote_repo_cd)
git fetch origin docs/sooperlooper-eval 2>/dev/null || true
git pull --ff-only origin docs/sooperlooper-eval 2>/dev/null || true
EOF
}

cmd_looper_sl_stop() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    if [ "$target" = pi ]; then
        mpe_cli_require_config
        echo "=== SooperLooper stop all loops (Pi) ==="
        mpe_cli_remote_bash "$(mpe_cli_looper_sl_pi_pull)
bash scripts/sooperlooper/stop-all-loops.sh"
        return
    fi
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/stop-all-loops.sh" "$target" "SooperLooper stop all loops"
}

cmd_looper_sl_reset() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    if [ "$target" = pi ]; then
        mpe_cli_require_config
        echo "=== SooperLooper reset all loops (Pi) ==="
        mpe_cli_remote_bash "$(mpe_cli_looper_sl_pi_pull)
bash scripts/sooperlooper/reset-all-loops.sh"
        return
    fi
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/reset-all-loops.sh" "$target" "SooperLooper reset all loops"
}

cmd_looper_sl_restart() {
    local target
    target="$(mpe_cli_looper_sl_target "${1:-pi}")"
    if [ "$target" = pi ]; then
        mpe_cli_require_config
        echo "=== SooperLooper restart + JACK graph (Pi) ==="
        echo "Host: $PI_USER@$PI_HOST"
        mpe_cli_remote_bash "$(mpe_cli_looper_sl_pi_pull)
bash scripts/sooperlooper/restart-sooperlooper.sh"
        return
    fi
    mpe_cli_looper_run_sl_script "scripts/sooperlooper/restart-sooperlooper.sh" "$target" "SooperLooper restart + JACK graph"
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
if [ -x ./scripts/looper-deploy.sh ]; then
    ./scripts/looper-deploy.sh \"\$branch\"
else
    echo \"mpe looper deploy: scripts/looper-deploy.sh not found — git sync only (no looper restart)\"
fi"
}

cmd_looper_restart() {
    mpe_cli_require_config
    mpe_cli_ssh "sudo systemctl restart mpe-looper.service"
    echo "$MPE_CLI_NAME: restarted mpe-looper.service"
}

cmd_looper_debug() {
    mpe_cli_require_config
    local mode="${1:-}"
    case "$mode" in
        on | 1 | true)
            mpe_cli_ssh "sudo bash -c 'if grep -q \"^MPE_LOOPER_DEBUG=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^MPE_LOOPER_DEBUG=.*/MPE_LOOPER_DEBUG=1/\" /etc/mpe/mpe.env; else echo MPE_LOOPER_DEBUG=1 >> /etc/mpe/mpe.env; fi'"
            ;;
        off | 0 | false)
            mpe_cli_ssh "sudo bash -c 'if grep -q \"^MPE_LOOPER_DEBUG=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^MPE_LOOPER_DEBUG=.*/MPE_LOOPER_DEBUG=0/\" /etc/mpe/mpe.env; else echo MPE_LOOPER_DEBUG=0 >> /etc/mpe/mpe.env; fi'"
            ;;
        -h | --help | "")
            echo "Usage: $MPE_CLI_NAME looper debug on|off" >&2
            exit 1
            ;;
        *)
            echo "$MPE_CLI_NAME looper debug: use on or off" >&2
            exit 1
            ;;
    esac
    cmd_looper_restart
    echo "$MPE_CLI_NAME: MPE_LOOPER_DEBUG=$mode — reproduce stutter, then: mpe logs looper -n 30"
}

cmd_looper_buffer() {
    mpe_cli_require_config
    local size="${1:-}"
    case "$size" in
        512 | 1024) ;;
        -h | --help | "")
            echo "Usage: $MPE_CLI_NAME looper buffer 512|1024" >&2
            exit 1
            ;;
        *)
            echo "$MPE_CLI_NAME looper buffer: use 512 or 1024 (got: $size)" >&2
            exit 1
            ;;
    esac
    mpe_cli_ssh "sudo bash -c 'if grep -q \"^MPE_SURGE_BUFFER_SIZE=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^MPE_SURGE_BUFFER_SIZE=.*/MPE_SURGE_BUFFER_SIZE=${size}/\" /etc/mpe/mpe.env; else echo MPE_SURGE_BUFFER_SIZE=${size} >> /etc/mpe/mpe.env; fi'"
    mpe_cli_ssh "sudo systemctl restart surge-xt-cli.service"
    mpe_cli_ssh "sudo systemctl restart mpe-looper.service"
    echo "$MPE_CLI_NAME: MPE_SURGE_BUFFER_SIZE=${size} — restarted surge + looper"
    echo "  Verify: mpe sysinfo && mpe logs looper -n 8"
    echo "  Note: looper-audio-route.sh on forces 512 — skip during 1024 A/B"
}

cmd_looper_enable() {
    mpe_cli_require_config
    mpe_cli_ssh "sudo bash -c 'if grep -q \"^MPE_LOOPER_ENABLED=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^MPE_LOOPER_ENABLED=.*/MPE_LOOPER_ENABLED=1/\" /etc/mpe/mpe.env; else echo MPE_LOOPER_ENABLED=1 >> /etc/mpe/mpe.env; fi'"
    echo "$MPE_CLI_NAME: MPE_LOOPER_ENABLED=1 — reboot for D5 guard test"
}

cmd_looper_disable() {
    mpe_cli_require_config
    mpe_cli_ssh "sudo bash -c 'sed -i \"/^MPE_LOOPER_ENABLED=/d\" /etc/mpe/mpe.env'"
    echo "$MPE_CLI_NAME: MPE_LOOPER_ENABLED removed"
}
