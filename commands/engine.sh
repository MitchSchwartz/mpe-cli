# shellcheck shell=bash
# Audio engine — status and Gate B soak injections.
#
# JACK is the only engine (MPE-Module spec amended 2026-08-13); there is no
# `alsa` value left and MPE_AUDIO_ENGINE is retired. `engine set` is gone
# rather than kept as a no-op: a soak runner needs a hard failure, not a
# success message for a change that cannot happen.
#
# Production graph server is mpe-jackd.service + surge-watchdog reconciliation.
# Do NOT use `mpe jack stop` for soak — that is the manual experiment rollback path.

cmd_engine() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        status)
            cmd_engine_status "$@"
            ;;
        set)
            echo "$MPE_CLI_NAME engine set: removed — JACK is the only audio engine." >&2
            echo "There is no 'alsa' value and MPE_AUDIO_ENGINE is read by nothing." >&2
            echo "A jackd that will not start is a hard failure (state=failed), not a" >&2
            echo "route to an alternate engine. Rollback of the whole change is the spec." >&2
            exit 1
            ;;
        mask-jackd)
            cmd_engine_mask_jackd "$@"
            ;;
        unmask-jackd)
            cmd_engine_unmask_jackd "$@"
            ;;
        start-jackd)
            cmd_engine_start_jackd "$@"
            ;;
        sync-units)
            cmd_engine_sync_units "$@"
            ;;
        calibrate-smoke)
            cmd_engine_calibrate_smoke "$@"
            ;;
        kill-jackd)
            cmd_engine_kill_jackd "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME engine status
       $MPE_CLI_NAME engine mask-jackd|unmask-jackd|start-jackd|sync-units
       $MPE_CLI_NAME engine kill-jackd [--kill]

  status       Published /run/mpe/engine.state + jackd/surge unit state
  mask-jackd   systemctl mask mpe-jackd.service (soak 2a — reboot after)
  unmask-jackd systemctl unmask mpe-jackd.service (soak 2d prep)
  start-jackd  systemctl start mpe-jackd.service
  sync-units   configure-pi-paths.sh --local --force on the Pi (restore units after mask)
  calibrate-smoke  One-patch cal with jackd up (criterion 14 smoke)
  kill-jackd   pkill jackd on the production graph (soak 2b); --kill for SIGKILL
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME engine: unknown subcommand: $sub" >&2
            exit 1
            ;;
    esac
}

cmd_engine_status() {
    mpe_cli_require_config
    # shellcheck source=../lib/snapshot.sh
    source "$MPE_CLI_ROOT/lib/snapshot.sh"
    mpe_cli_snapshot_fetch 1 || exit 1

    echo "=== ENGINE STATE ==="
    mpe_cli_render_engine_state_kv
    echo ""
    echo "=== UNITS ==="
    for unit in mpe-jackd surge-xt-cli surge-watchdog; do
        stale="$(mpe_cli_snapshot_stale --arg u "$unit" '.services[$u].stale')"
        active="$(mpe_cli_snapshot_field --arg u "$unit" '.services[$u].active // "unknown"')"
        enabled="$(mpe_cli_snapshot_field --arg u "$unit" '.services[$u].enabled // "unknown"')"
        if [ "$stale" = "true" ]; then
            active=unknown
            enabled=unknown
        fi
        printf "  %-24s active=%-12s enabled=%s\n" "${unit}.service" "$active" "$enabled"
    done
    if [ "$(mpe_cli_snapshot_field --arg u mpe-jackd '.services[$u].enabled // empty')" = "masked" ]; then
        echo "  mpe-jackd.service is MASKED"
    fi
    echo ""
    echo "=== PROCESSES ==="
    jack_pid="$(mpe_cli_snapshot_field '.processes.jackd_pid // empty')"
    surge_pid="$(mpe_cli_snapshot_field '.processes.surge_pid // empty')"
    printf "  jackd: "; [ -n "$jack_pid" ] && echo "$jack_pid" || echo "not running"
    printf "  surge: "; [ -n "$surge_pid" ] && echo "$surge_pid" || echo "not running"
    graph_stale="$(mpe_cli_snapshot_stale '.graph.stale')"
    on_graph="$(mpe_cli_snapshot_field '.graph.surge_on_graph')"
    if [ "$graph_stale" != "true" ] && [ -n "$jack_pid" ]; then
        echo ""
        echo "=== JACK GRAPH ==="
        if [ "$on_graph" = "true" ]; then
            echo "  Surge on graph: yes"
        else
            echo "  Surge on graph: no"
        fi
    fi
}

cmd_engine_mask_jackd() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
set -e
unit=mpe-jackd.service
path="/etc/systemd/system/$unit"
backup="/etc/mpe/soak-backups/mpe-jackd.service"
sudo mkdir -p /etc/mpe/soak-backups
sudo systemctl stop "$unit" 2>/dev/null || true
if [ -f "$path" ] && [ ! -L "$path" ]; then
    sudo cp -a "$path" "$backup"
    sudo rm -f "$path"
fi
if ! sudo systemctl mask "$unit" 2>/dev/null; then
    sudo ln -sf /dev/null "$path"
    sudo systemctl daemon-reload
fi
systemctl is-enabled "$unit" 2>/dev/null || true
'
    echo "$MPE_CLI_NAME: mpe-jackd.service masked — reboot for soak 2a (jackd absent at boot)"
}

cmd_engine_unmask_jackd() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
set -e
unit=mpe-jackd.service
path="/etc/systemd/system/$unit"
backup="/etc/mpe/soak-backups/mpe-jackd.service"
sudo systemctl unmask "$unit" 2>/dev/null || true
if [ -L "$path" ] && [ "$(readlink -f "$path")" = "/dev/null" ]; then
    sudo rm -f "$path"
fi
if [ -f "$backup" ] && [ ! -f "$path" ]; then
    sudo cp -a "$backup" "$path"
fi
sudo systemctl daemon-reload
sudo systemctl enable "$unit" 2>/dev/null || true
sudo systemctl reset-failed "$unit" 2>/dev/null || true
systemctl is-enabled "$unit" 2>/dev/null || true
'
    echo "$MPE_CLI_NAME: mpe-jackd.service unmasked"
}

cmd_engine_start_jackd() {
    mpe_cli_require_config
    mpe_cli_ssh "sudo systemctl start mpe-jackd.service"
    echo "$MPE_CLI_NAME: started mpe-jackd.service — watch: $MPE_CLI_NAME engine status"
}

cmd_engine_sync_units() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
set -e
repo="${MPE_MODULE_REPO:-$HOME/MPE-Module}"
if [ ! -x "$repo/scripts/configure-pi-paths.sh" ]; then
    echo "ERROR: $repo/scripts/configure-pi-paths.sh not found" >&2
    exit 1
fi
cd "$repo"
./scripts/configure-pi-paths.sh --local --force
'
    echo "$MPE_CLI_NAME: Pi systemd units refreshed (configure-pi-paths --local --force)"
}

cmd_engine_calibrate_smoke() {
    mpe_cli_require_config
    echo "$MPE_CLI_NAME: criterion 14 smoke — 1 favorite patch, jackd stays up until cal stops Surge"
    mpe_cli_remote_bash '
set -e
repo="${MPE_MODULE_REPO:-$HOME/MPE-Module}"
cd "$repo"
echo "=== PRE (jackd should be running) ==="
pgrep -x jackd >/dev/null && echo "jackd: running ($(pgrep -x jackd | head -1))" || echo "jackd: not running"
systemctl is-active mpe-jackd.service surge-xt-cli.service 2>/dev/null || true
python3 scripts/calibrate-patch-normalization.py --favorites-only --limit 1 --no-touch-cal --force
echo "=== POST ==="
pgrep -x jackd >/dev/null && echo "jackd: running ($(pgrep -x jackd | head -1))" || echo "jackd: not running"
systemctl is-active mpe-jackd.service surge-xt-cli.service touch-patch-browser.service 2>/dev/null || true
'
    echo "$MPE_CLI_NAME: calibrate-smoke finished — check: $MPE_CLI_NAME engine status"
}

cmd_engine_kill_jackd() {
    mpe_cli_require_config
    local mode="term"
    if [ "${1:-}" = "--kill" ]; then
        mode="kill"
    elif [ -n "${1:-}" ]; then
        echo "$MPE_CLI_NAME engine kill-jackd: use --kill for SIGKILL or no flag for SIGTERM" >&2
        exit 1
    fi
    mpe_cli_remote_bash "
echo \"=== BEFORE ===\"
cat /run/mpe/engine.state 2>/dev/null || true
if [ \"$mode\" = kill ]; then
    pkill -KILL -x jackd 2>/dev/null && echo \"pkill -KILL -x jackd sent\" || echo \"jackd not running\"
else
    pkill -TERM -x jackd 2>/dev/null && echo \"pkill -TERM -x jackd sent\" || echo \"jackd not running\"
fi
"
    echo "$MPE_CLI_NAME: jackd kill sent ($mode) — watch recovery: $MPE_CLI_NAME engine status"
}
