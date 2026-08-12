# Audio engine (jack | alsa) — status, config, and Gate B soak injections.
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
            cmd_engine_set "$@"
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
        kill-jackd)
            cmd_engine_kill_jackd "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME engine status
       $MPE_CLI_NAME engine set jack|alsa
       $MPE_CLI_NAME engine mask-jackd|unmask-jackd|start-jackd|sync-units
       $MPE_CLI_NAME engine kill-jackd [--kill]

  status       Published /run/mpe/engine.state + jackd/surge unit state
  set          Write MPE_AUDIO_ENGINE to /etc/mpe/mpe.env (reboot to apply)
  mask-jackd   systemctl mask mpe-jackd.service (soak 2a — reboot after)
  unmask-jackd systemctl unmask mpe-jackd.service (soak 2d prep)
  start-jackd  systemctl start mpe-jackd.service
  sync-units   configure-pi-paths.sh --local --force on the Pi (restore units after mask)
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
    mpe_cli_remote_bash '
state_file="/run/mpe/engine.state"
echo "=== ENGINE STATE ==="
if [ -r "$state_file" ]; then
    cat "$state_file"
else
    echo "(missing $state_file)"
fi
echo ""
echo "=== UNITS ==="
for unit in mpe-jackd.service surge-xt-cli.service surge-watchdog.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        printf "  %-24s active=%-12s enabled=%s\n" "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null | head -1)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null | head -1)"
    fi
done
if systemctl is-enabled mpe-jackd.service 2>/dev/null | grep -q masked; then
    echo "  mpe-jackd.service is MASKED"
fi
echo ""
echo "=== PROCESSES ==="
printf "  jackd: "; pgrep -x jackd >/dev/null && pgrep -x jackd | head -1 || echo "not running"
printf "  surge: "; pgrep -f surge-xt-cli >/dev/null && pgrep -f surge-xt-cli | head -1 || echo "not running"
if command -v jack_lsp >/dev/null 2>&1 && pgrep -x jackd >/dev/null; then
    echo ""
    echo "=== JACK GRAPH ==="
    if jack_lsp 2>/dev/null | grep -qi surge; then
        echo "  Surge on graph: yes"
    else
        echo "  Surge on graph: no"
    fi
fi
if [ -f /etc/mpe/mpe.env ]; then
    echo ""
    echo "=== CONFIG ==="
    grep -E "^MPE_AUDIO_ENGINE=" /etc/mpe/mpe.env 2>/dev/null | sed "s/^/  /" || echo "  MPE_AUDIO_ENGINE unset (default jack)"
fi
'
}

cmd_engine_set() {
    mpe_cli_require_config
    local engine="${1:-}"
    mpe_cli_validate_enum "$engine" "jack alsa" "engine"
    mpe_cli_ssh "sudo bash -c 'if grep -q \"^MPE_AUDIO_ENGINE=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^MPE_AUDIO_ENGINE=.*/MPE_AUDIO_ENGINE=${engine}/\" /etc/mpe/mpe.env; else echo MPE_AUDIO_ENGINE=${engine} >> /etc/mpe/mpe.env; fi'"
    echo "$MPE_CLI_NAME: MPE_AUDIO_ENGINE=${engine} — reboot the Pi to apply"
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
