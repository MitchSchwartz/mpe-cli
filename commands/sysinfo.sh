cmd_sysinfo() {
    mpe_cli_require_config
    mpe_cli_remote_bash '
echo "=== BOARD + OS ==="
printf "Model:       "; tr -d "\0" < /proc/device-tree/model 2>/dev/null; echo
printf "Revision:    "; grep -m1 "^Revision" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d " "
printf "Arch:        "; uname -m
printf "OS:          "; grep -m1 "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d "\""
printf "Debian:      "; cat /etc/debian_version 2>/dev/null || echo "(unknown)"

echo ""
echo "=== KERNEL + PREEMPTION ==="
printf "Release:     "; uname -r
printf "Build:       "; uname -v
printf "Preempt:     "; grep -o "PREEMPT[A-Z_]*" /proc/version 2>/dev/null | sort -u | tr "\n" " "; echo
printf "RT kernel:   "
if uname -v | grep -q "PREEMPT_RT"; then
    echo "yes (PREEMPT_RT in build string)"
elif [ -e /sys/kernel/realtime ]; then
    echo "realtime flag = $(cat /sys/kernel/realtime)"
else
    echo "no"
fi

echo ""
echo "=== BOOT / FIRMWARE ==="
printf "EEPROM:      "; vcgencmd bootloader_version 2>/dev/null | tr "\n" " " || echo "(vcgencmd unavailable)"; echo
printf "Firmware:    "; vcgencmd version 2>/dev/null | tr "\n" " "; echo
printf "Booted via tryboot: "
if [ -e /proc/device-tree/chosen/bootloader/tryboot ]; then
    tr -d "\0" < /proc/device-tree/chosen/bootloader/tryboot; echo
else
    echo "no (or not reported)"
fi
printf "config.txt kernel:  "
grep -E "^ *(kernel|os_prefix)=" /boot/firmware/config.txt 2>/dev/null | tr "\n" " " || echo "(none - firmware default)"
echo
printf "tryboot.txt: "; [ -f /boot/firmware/tryboot.txt ] && echo "present" || echo "absent"

echo ""
echo "=== POWER + CLOCK ==="
_thr=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
if [ -n "$_thr" ]; then
    _t=$((_thr))
    _now=""
    _past=""
    if [ $((_t & 0x1)) -ne 0 ]; then _now="$_now under-voltage"; fi
    if [ $((_t & 0x2)) -ne 0 ]; then _now="$_now arm-freq-capped"; fi
    if [ $((_t & 0x4)) -ne 0 ]; then _now="$_now THROTTLED"; fi
    if [ $((_t & 0x8)) -ne 0 ]; then _now="$_now soft-temp-limit"; fi
    if [ $((_t & 0x10000)) -ne 0 ]; then _past="$_past under-voltage"; fi
    if [ $((_t & 0x20000)) -ne 0 ]; then _past="$_past arm-freq-capped"; fi
    if [ $((_t & 0x40000)) -ne 0 ]; then _past="$_past throttled"; fi
    if [ $((_t & 0x80000)) -ne 0 ]; then _past="$_past soft-temp-limit"; fi
    printf "Throttled:   %s\n" "$_thr"
    printf "  right now: %s\n" "${_now:-none}"
    printf "  since boot:%s\n" " ${_past:-none}"
else
    echo "Throttled:   (vcgencmd unavailable)"
fi
printf "ARM clock:   "
_ac=$(vcgencmd measure_clock arm 2>/dev/null | cut -d= -f2)
_amax=$(vcgencmd get_config arm_freq 2>/dev/null | cut -d= -f2)
if [ -n "$_ac" ] && [ "$_ac" -gt 0 ] 2>/dev/null; then
    printf "%s MHz now" "$((_ac / 1000000))"
    if [ -n "$_amax" ]; then printf " / %s MHz configured" "$_amax"; fi
    echo ""
else
    echo "(unavailable)"
fi
printf "cpufreq:     "
_cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
_max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
if [ -n "$_cur" ] && [ -n "$_max" ]; then
    printf "%s MHz cur / %s MHz max\n" "$((_cur / 1000))" "$((_max / 1000))"
else
    echo "(unavailable)"
fi
printf "Core volts:  "; vcgencmd measure_volts core 2>/dev/null | cut -d= -f2 || echo "(unavailable)"
printf "SoC temp:    "; vcgencmd measure_temp 2>/dev/null | cut -d= -f2 || echo "(unavailable)"

echo ""
echo "=== AUDIO SCHEDULING ==="
printf "Governor:    "; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "(unavailable)"
printf "limits.d:    "; ls /etc/security/limits.d/ 2>/dev/null | tr "\n" " "; echo
_pid=$(pgrep -f surge-xt-cli | head -1)
if [ -n "$_pid" ]; then
    printf "Surge pid:   %s\n" "$_pid"
    printf "Scheduling:  "; chrt -p "$_pid" 2>/dev/null | tr "\n" " "; echo
    printf "RT limits:   "; grep -E "realtime priority|locked memory" /proc/$_pid/limits 2>/dev/null | tr -s " " | tr "\n" "| "; echo
else
    echo "Surge pid:   not running"
fi

echo ""
echo "=== SURGE AUDIO CONFIG ==="
grep -E "^MPE_(SURGE_BUFFER_SIZE|SURGE_SAMPLE_RATE|AUDIO_PROFILE)=" /etc/mpe/mpe.env 2>/dev/null || echo "(no /etc/mpe/mpe.env)"
_buf=$(grep -m1 -E "^MPE_SURGE_BUFFER_SIZE=" /etc/mpe/mpe.env 2>/dev/null | cut -d= -f2)
_rate=$(grep -m1 -E "^MPE_SURGE_SAMPLE_RATE=" /etc/mpe/mpe.env 2>/dev/null | cut -d= -f2)
printf "Block latency: "
if [ -n "$_buf" ] && [ -n "$_rate" ] && [ "$_rate" -gt 0 ] 2>/dev/null; then
    python3 -c "print(round(1000 * $_buf / $_rate, 2), \"ms\")" 2>/dev/null || echo "(python3 unavailable)"
else
    echo "(buffer/rate not set)"
fi

echo ""
echo "=== AUDIO BACKENDS (graph-server feasibility) ==="
_sbin=""
if [ -n "$_pid" ]; then
    _sbin=$(readlink -f /proc/$_pid/exe 2>/dev/null)
fi
printf "Surge binary:  %s\n" "${_sbin:-(not running)}"
printf "Surge JACK:    "
if [ -n "$_sbin" ] && [ -r "$_sbin" ]; then
    _lj=$(ldd "$_sbin" 2>/dev/null | grep -ci jack)
    _sj=$(strings -a "$_sbin" 2>/dev/null | grep -c "^JACK_DEFAULT_SERVER\|jack_client_open")
    if [ "${_lj:-0}" -gt 0 ]; then
        echo "linked against libjack (ldd match)"
    elif [ "${_sj:-0}" -gt 0 ]; then
        echo "jack symbols present, not dynamically linked — likely dlopen at runtime"
    else
        echo "NO jack references found — cannot be a JACK/PipeWire client"
    fi
else
    echo "(binary unreadable)"
fi
printf "libjack:       "; ldconfig -p 2>/dev/null | grep -m1 -o "libjack\.so[^ ]*" || echo "not installed"
printf "PipeWire:      "
if command -v pipewire >/dev/null 2>&1; then
    pipewire --version 2>&1 | head -1
else
    echo "not installed"
fi
printf "pipewire-jack: "; ldconfig -p 2>/dev/null | grep -c "pipewire-0.3/jack" 2>/dev/null || echo 0
printf "jackd:         "; command -v jackd >/dev/null 2>&1 && jackd --version 2>&1 | head -1 || echo "not installed"
'
}
