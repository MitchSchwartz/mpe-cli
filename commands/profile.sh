# shellcheck shell=bash
# Audio profile switch (standalone | usb-host | usb-host-session).

cmd_profile() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        set)
            cmd_profile_set "$@"
            ;;
        status)
            cmd_profile_status "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME profile status
       $MPE_CLI_NAME profile set standalone|usb-host|usb-host-session

  status   MPE_AUDIO_PROFILE from /etc/mpe/mpe.env + gadget unit state
  set      Run set-audio-profile.sh on the Pi (restarts jackd when engine=jack)
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME profile: unknown subcommand: $sub" >&2
            exit 1
            ;;
    esac
}

cmd_profile_status() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
echo "=== CONFIG ==="
grep -E "^MPE_AUDIO_PROFILE=" /etc/mpe/mpe.env 2>/dev/null | sed "s/^/  /" || echo "  MPE_AUDIO_PROFILE unset (default standalone)"
echo ""
echo "=== UNITS ==="
for unit in usb-audio-gadget.service uac2-stall-watchdog.service mic-to-uac2-bridge.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        printf "  %-28s %s\n" "$unit" "$(systemctl is-active "$unit" 2>/dev/null | head -1)"
    fi
done
'
}

cmd_profile_set() {
    mpe_cli_require_config
    local profile="${1:-}"
    mpe_cli_validate_enum "$profile" "standalone usb-host usb-host-session" "profile"
    mpe_cli_remote_bash "
set -e
repo=\"\${MPE_MODULE_REPO:-\$HOME/MPE-Module}\"
script=\"\$repo/scripts/set-audio-profile.sh\"
[ -x \"\$script\" ] || script=\"\$repo/scripts/set-audio-profile.sh\"
sudo bash \"\$script\" \"$profile\"
"
    echo "$MPE_CLI_NAME: profile set to $profile — watch: $MPE_CLI_NAME engine status"
}
