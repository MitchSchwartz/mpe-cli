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
printf "Throttled:   "; vcgencmd get_throttled 2>/dev/null || echo "(unavailable)"
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
'
}
