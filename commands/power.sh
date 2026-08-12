# Sample ARM clock / throttle / voltage over a window (read-only).
#
# A single sysinfo reading cannot distinguish "governor idling at the 600 MHz
# floor" from "firmware capping the clock because of under-voltage" — both look
# identical at rest. Sample across a window while the synth is under load and
# the difference is obvious: a healthy board climbs toward arm_freq, a
# throttled one stays pinned.
#
# Note: /sys scaling_cur_freq reports what the governor requested, not what the
# silicon is doing. vcgencmd measure_clock arm is the real number.

MPE_POWER_DEFAULT_SECONDS=15
MPE_POWER_MAX_SECONDS=120

cmd_power() {
    mpe_cli_require_config
    local secs="${1:-$MPE_POWER_DEFAULT_SECONDS}"
    case "$secs" in
        -h | --help)
            cat <<EOF
Usage: $MPE_CLI_NAME power [seconds]

Samples ARM clock, throttle flags, core voltage and SoC temperature once a
second (default $MPE_POWER_DEFAULT_SECONDS, max $MPE_POWER_MAX_SECONDS).

Play the patch you are testing during the window — an idle board always reads
600 MHz and tells you nothing.
EOF
            return 0
            ;;
        *[!0-9]* | "")
            echo "$MPE_CLI_NAME power: seconds must be a number (got: $secs)" >&2
            exit 1
            ;;
    esac
    if [ "$secs" -lt 1 ] || [ "$secs" -gt "$MPE_POWER_MAX_SECONDS" ]; then
        echo "$MPE_CLI_NAME power: seconds out of range 1-$MPE_POWER_MAX_SECONDS (got: $secs)" >&2
        exit 1
    fi

    echo "$MPE_CLI_NAME: sampling ${secs}s — play the patch now."
    mpe_cli_ssh "bash -s -- $secs" <<'EOF'
_secs="$1"
_max_mhz=$(vcgencmd get_config arm_freq 2>/dev/null | cut -d= -f2)
_min_seen=999999
_max_seen=0
_uv=0
_thr=0
printf "%-9s %-10s %-9s %-7s %s\n" "elapsed" "arm_clock" "volts" "temp" "flags"
_i=0
while [ "$_i" -lt "$_secs" ]; do
    _hz=$(vcgencmd measure_clock arm 2>/dev/null | cut -d= -f2)
    _mhz=$(( ${_hz:-0} / 1000000 ))
    _v=$(vcgencmd measure_volts core 2>/dev/null | cut -d= -f2)
    _tc=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2)
    _t=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    _tn=$(( ${_t:-0} ))
    _flags=""
    if [ $((_tn & 0x1)) -ne 0 ]; then _flags="$_flags under-volt"; _uv=1; fi
    if [ $((_tn & 0x2)) -ne 0 ]; then _flags="$_flags freq-cap"; fi
    if [ $((_tn & 0x4)) -ne 0 ]; then _flags="$_flags THROTTLED"; _thr=1; fi
    if [ $((_tn & 0x8)) -ne 0 ]; then _flags="$_flags soft-temp"; fi
    if [ "$_mhz" -lt "$_min_seen" ]; then _min_seen="$_mhz"; fi
    if [ "$_mhz" -gt "$_max_seen" ]; then _max_seen="$_mhz"; fi
    printf "%-9s %-10s %-9s %-7s %s\n" "${_i}s" "${_mhz} MHz" "$_v" "$_tc" "${_flags:--}"
    _i=$((_i + 1))
    sleep 1
done
echo ""
echo "--- SUMMARY ---"
printf "ARM clock range: %s - %s MHz (configured max %s MHz)\n" \
    "$_min_seen" "$_max_seen" "${_max_mhz:-unknown}"
if [ -n "$_max_mhz" ] && [ "$_max_seen" -lt "$_max_mhz" ]; then
    _pct=$(( _max_seen * 100 / _max_mhz ))
    printf "Peak reached %s%% of configured clock.\n" "$_pct"
    if [ "$_pct" -lt 90 ]; then
        echo "VERDICT: clock never approached its ceiling."
        echo "  If you were playing hard during this window, the board is being held down."
    fi
else
    echo "VERDICT: clock reached its configured ceiling — not frequency-limited."
fi
if [ "$_uv" -eq 1 ] || [ "$_thr" -eq 1 ]; then
    echo "Under-voltage/throttle asserted DURING the window (live, not since-boot)."
    echo "  Pi 4 needs a 5V/3A USB-C supply; check the PSU and cable before tuning audio."
fi
EOF
}
