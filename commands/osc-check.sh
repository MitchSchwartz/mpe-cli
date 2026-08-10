cmd_osc_check() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
echo "OSC UDP listeners (53270 out, 53280 in):"
ss -ulnp 2>/dev/null | grep -E "53270|53280" || echo "  (none — Surge may not be running)"
echo ""
echo "surge-xt-cli process:"
pgrep -af surge-xt-cli || echo "  (not running)"
'
}
