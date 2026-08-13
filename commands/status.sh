cmd_status() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
services=(
  mpe-jackd.service
  surge-xt-cli.service
  surge-watchdog.service
  touch-patch-browser.service
  patch-browser.service
  usb-audio-gadget.service
  uac2-stall-watchdog.service
  mpe-pressure-remap.service
)
for unit in "${services[@]}"; do
  if ! systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    continue
  fi
  state="$(systemctl is-active "$unit" 2>/dev/null | head -1 | tr -d "\r")"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null | head -1 | tr -d "\r")"
  [ -n "$state" ] || state=unknown
  [ -n "$enabled" ] || enabled=unknown
  printf "  %-32s active=%-10s enabled=%s\n" "$unit" "$state" "$enabled"
done
if [ -f /etc/mpe/mpe.env ]; then
  echo ""
  echo "  /etc/mpe/mpe.env:"
  # MPE_AUDIO_ENGINE is retired (JACK is the only engine); it is deliberately
  # not shown — a stale value from a pre-amendment appliance has no effect.
  grep -E "^(MPE_UI_MODE|MPE_AUDIO_PROFILE)=" /etc/mpe/mpe.env 2>/dev/null | sed "s/^/    /" || true
fi
'
}
