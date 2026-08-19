# shellcheck shell=bash
# JACK graph-server bring-up — manual experiment, never the boot path.
#
# Surge already has JUCE's JACK backend compiled in (it dlopens libjack.so.0),
# so no rebuild is needed: installing a package that provides that library is
# what turns the backend on. See MPE-Module docs/AUDIO-ENGINE-FOUNDATION.md
# Part 7.
#
# Everything here runs Surge OUTSIDE systemd so the appliance boot path is
# untouched and rollback is a single command:
#
#     mpe jack stop      # kill the experiment, hand Surge back to systemd
#
# surge-watchdog.service is BindsTo=surge-xt-cli.service, so stopping the unit
# stops the watchdog too — it will not fight us for the process.

MPE_JACK_BUFFERS="64 128 256 512 1024"
MPE_JACK_PERIODS="2 3 4"
MPE_JACK_RT_PRIO=70
MPE_JACK_RATE=48000
MPE_JACK_LOGDIR='$HOME/.cache/mpe-jack'

cmd_jack() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        install) cmd_jack_install "$@" ;;
        devices) cmd_jack_devices "$@" ;;
        start) cmd_jack_start "$@" ;;
        buffer) cmd_jack_buffer "$@" ;;
        surge) cmd_jack_surge "$@" ;;
        caps) cmd_jack_caps "$@" ;;
        ports) cmd_jack_ports "$@" ;;
        status) cmd_jack_status "$@" ;;
        stop) cmd_jack_stop "$@" ;;
        logs) cmd_jack_logs "$@" ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME jack <subcommand>

  install              Install jackd2 + jack-example-tools (preseeds RT limits)
  devices              surge-xt-cli --list-devices (does a JACK device appear?)
  start [buf] [per]    Stop surge-xt-cli.service, run jackd on the DAC
                       buf: $MPE_JACK_BUFFERS (default 512)
                       per: $MPE_JACK_PERIODS (default 3)
  buffer <frames>      Change period size LIVE — no restart, keep playing.
                       QUICK FEEL-TEST ONLY: renegotiation drops the ALSA
                       format to 16-bit. Use 'start <buf>' for real A/B.
                       frames: $MPE_JACK_BUFFERS
  surge [index]        Launch surge-xt-cli as a JACK client (auto-detects index)
  caps                 Output device hardware limits (formats, rates, USB depth)
  ports                jack_lsp -c — ports and their connections
  status               jackd / surge state, xruns, DSP load
  logs [-n N]          Tail the jackd + surge experiment logs
  stop                 ROLLBACK: kill the experiment, restart surge-xt-cli.service

This never touches systemd units or boot. 'stop' restores the appliance.
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME jack: unknown subcommand: $sub" >&2
            exit 1
            ;;
    esac
}

# Pick the real output DAC: skip the SoC headphones, HDMI, the USB gadget and
# the ALSA loopback. Those are all present on this board and none is the DAC.
mpe_jack_detect_snippet() {
    cat <<'EOF'
_jack_pick_dac() {
    aplay -l 2>/dev/null \
        | sed -n 's/^card \([0-9]\+\): \([^ ]*\) .*/\1 \2/p' \
        | grep -viE ' (Headphones|vc4hdmi[0-9]*|UAC2Gadget|Loopback)$' \
        | head -1 \
        | awk '{print "hw:"$1}'
}
EOF
}

cmd_jack_install() {
    mpe_cli_require_config
    echo "$MPE_CLI_NAME: installing jackd2 + jack-example-tools on the appliance..."
    mpe_cli_ssh "bash -s" <<'EOF'
set -e
# jackd2 asks about raising RT limits for @audio. We run jackd from an SSH
# session, where PAM limits DO apply, so this must be answered yes and
# answered non-interactively or apt hangs waiting on a tty.
echo "jackd2 jackd/tweak_rt_limits boolean true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    jackd2 jack-example-tools
echo ""
echo "=== RESULT ==="
printf "jackd:     "; command -v jackd >/dev/null && jackd --version 2>&1 | head -1 || echo "MISSING"
printf "libjack:   "; ldconfig -p 2>/dev/null | grep -m1 libjack.so.0 || echo "MISSING"
printf "jack_lsp:  "; command -v jack_lsp || echo "MISSING"
printf "audio grp: "; id -nG | tr ' ' '\n' | grep -qx audio && echo "mitch is in audio" || echo "NOT in audio group"
printf "rt limits: "; grep -hE 'rtprio|memlock' /etc/security/limits.d/*.conf 2>/dev/null | tr -s ' ' | tr '\n' '|' || echo "none"
echo ""
EOF
}

cmd_jack_devices() {
    mpe_cli_require_config
    mpe_cli_ssh "bash -s" <<'EOF'
source /etc/mpe/mpe.env 2>/dev/null || true
SURGE_CLI="${MPE_SURGE_CLI:-$HOME/surge/build/surge_xt_products/surge-xt-cli}"

# Surge dlopens libjack.so.0 by soname, so what matters is that the dynamic
# loader can find it — not that any particular package is installed.
echo "=== libjack resolution (what Surge's dlopen will hit) ==="
printf "ldconfig:  "; ldconfig -p 2>/dev/null | grep libjack || echo "(no cache entry)"
printf "on disk:   "; find /usr/lib -name 'libjack.so*' 2>/dev/null | tr '\n' ' '; echo
printf "provider:  "; dpkg -S "$(find /usr/lib -name 'libjack.so.0' 2>/dev/null | head -1)" 2>/dev/null || echo "(none)"
echo ""
echo "=== surge-xt-cli --list-devices ==="
timeout 30 "$SURGE_CLI" --list-devices 2>&1 || echo "(exit $?)"
EOF
}

cmd_jack_start() {
    mpe_cli_require_config
    local buf="${1:-512}" per="${2:-3}"

    mpe_cli_validate_enum "$buf" "$MPE_JACK_BUFFERS" "jack start: buffer"
    mpe_cli_validate_enum "$per" "$MPE_JACK_PERIODS" "jack start: periods"

    echo "$MPE_CLI_NAME: stopping surge-xt-cli.service (watchdog follows via BindsTo)..."
    mpe_cli_ssh "bash -s" <<EOF
set -e
$(mpe_jack_detect_snippet)
mkdir -p $MPE_JACK_LOGDIR
# Record what we tore down so 'jack stop' restores the same appliance it found.
# The looper captures from snd-aloop, which has no meaning once Surge is a JACK
# client, so it has to come down for the duration of the experiment.
systemctl is-active --quiet mpe-looper.service \
    && echo looper=active > $MPE_JACK_LOGDIR/prior-state \
    || echo looper=inactive > $MPE_JACK_LOGDIR/prior-state

sudo systemctl stop surge-xt-cli.service 2>/dev/null || true
sudo systemctl stop mpe-looper.service 2>/dev/null || true
sleep 1
pkill -TERM -f surge-xt-cli 2>/dev/null || true
pkill -TERM -f jackd 2>/dev/null || true
sleep 1

DAC=\$(_jack_pick_dac)
if [ -z "\$DAC" ]; then
    echo "ERROR: no DAC found in aplay -l (only gadget/loopback/HDMI present)" >&2
    exit 1
fi

LOG=$MPE_JACK_LOGDIR/jackd.log
: > "\$LOG"

echo "Starting jackd on \$DAC — ${buf} frames x ${per} periods @ ${MPE_JACK_RATE} Hz"
# -s softmode: an xrun must not tear the graph down mid-experiment.
setsid nohup jackd -R -P$MPE_JACK_RT_PRIO -s \
    -d alsa -d "\$DAC" -r $MPE_JACK_RATE -p ${buf} -n ${per} \
    >> "\$LOG" 2>&1 < /dev/null &
sleep 3

if pgrep -x jackd >/dev/null; then
    _pid=\$(pgrep -x jackd | head -1)
    echo "jackd running (pid \$_pid) — \$(chrt -p \$_pid 2>/dev/null | tr '\n' ' ')"
    echo ""
    echo "Theoretical output latency: \$(awk "BEGIN{printf \"%.2f\", ${buf}*${per}/$MPE_JACK_RATE*1000}") ms"
else
    echo "jackd FAILED to start — log follows:" >&2
fi
echo ""
echo "=== jackd log ==="
tail -n 25 "\$LOG"
EOF
}

# JACK renegotiates period size across the whole graph at runtime and calls each
# client's buffer-size callback, so this is an A/B you can run mid-performance.
# A marker goes into the log so status can report xruns for THIS setting only,
# instead of a cumulative count that makes every step look worse than the last.
#
# MEASURED 2026-08-12: the renegotiation also re-picks the ALSA sample format
# and lands on 16-bit, where a fresh 'jack start' at the same period gets 24-bit.
# So a live resize changes TWO variables at once and is only good for a quick
# "does this feel tighter" pass. Any comparison you intend to act on must use
# 'jack start <buf>', which re-probes the device cleanly.
cmd_jack_buffer() {
    mpe_cli_require_config
    local buf="${1:-}"
    mpe_cli_validate_enum "$buf" "$MPE_JACK_BUFFERS" "jack buffer: frames"

    mpe_cli_ssh "bash -s" <<EOF
if ! pgrep -x jackd >/dev/null; then
    echo "ERROR: jackd is not running — run '$MPE_CLI_NAME jack start' first" >&2
    exit 1
fi
_periods=\$(sed -n 's/.*buffer = \([0-9]\+\) periods.*/\1/p' $MPE_JACK_LOGDIR/jackd.log | tail -1)
_periods="\${_periods:-3}"

echo "=== BUFFER ${buf} ===" >> $MPE_JACK_LOGDIR/jackd.log
jack_bufsize ${buf} 2>&1 | tail -2

sleep 2
echo ""
printf "now:       "; jack_bufsize 2>&1 | tail -1
printf "latency:   "; awk "BEGIN{printf \"%.2f ms (%s frames x %s periods)\n\", ${buf}*\$_periods/$MPE_JACK_RATE*1000, ${buf}, \$_periods}"
printf "surge:     "; pgrep -f surge-xt-cli >/dev/null && echo "still running" || echo "DIED — restart with '$MPE_CLI_NAME jack surge'"
printf "format:    "; sed -n 's/.*final selected sample format for playback: //p' $MPE_JACK_LOGDIR/jackd.log | tail -1
EOF
    echo ""
    echo "$MPE_CLI_NAME: NOTE live resize can drop the format to 16-bit — confirm any"
    echo "  keeper setting with '$MPE_CLI_NAME jack start $buf' before believing it."
    echo "$MPE_CLI_NAME: play for ~30s, then: $MPE_CLI_NAME jack status"
}

cmd_jack_surge() {
    mpe_cli_require_config
    # JUCE addresses devices as <type>.<device> (e.g. 0.4 = ALSA Sound Blaster),
    # matching DEVICE_ID in MPE-Module scripts/detect-audio-device.sh.
    local idx="${1:-}"
    if [ -n "$idx" ] && ! [[ "$idx" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "$MPE_CLI_NAME jack surge: device id must be <type>.<device>, e.g. 1.0 (got: $idx)" >&2
        exit 1
    fi

    mpe_cli_ssh "bash -s" <<EOF
set -e
source /etc/mpe/mpe.env 2>/dev/null || true
SURGE_CLI="\${MPE_SURGE_CLI:-\$HOME/surge/build/surge_xt_products/surge-xt-cli}"

if ! pgrep -x jackd >/dev/null; then
    echo "ERROR: jackd is not running — run '$MPE_CLI_NAME jack start' first" >&2
    exit 1
fi

LIST=\$(timeout 30 "\$SURGE_CLI" --list-devices 2>&1)

IDX="${idx}"
if [ -z "\$IDX" ]; then
    # Match the JACK *device* line only. libjack's own diagnostics mention
    # "Jack" too, so anchor on the device-listing prefix.
    IDX=\$(printf '%s\n' "\$LIST" \
        | grep "Output Audio Device" \
        | grep -i "JACK" \
        | sed -n 's/.*\[\([0-9][0-9]*\.[0-9][0-9]*\)\].*/\1/p' \
        | head -1)
fi
if [ -z "\$IDX" ]; then
    echo "ERROR: no JACK output device in the list. Output devices seen:" >&2
    printf '%s\n' "\$LIST" | grep "Output Audio Device" >&2
    exit 1
fi
echo "Using audio interface \$IDX — \$(printf '%s\n' "\$LIST" | grep -m1 "\\[\$IDX\\]" | sed 's/.*\] : //')"

MIDI=\$(printf '%s\n' "\$LIST" \
    | grep -i "Midi Through Port-0" \
    | sed -n 's/.*\[\([0-9][0-9]*\)\].*/\1/p' | head -1)
if [ -n "\$MIDI" ]; then
    MIDI_ARGS=(--midi-input="\$MIDI")
else
    MIDI_ARGS=(--all-midi-inputs)
fi

mkdir -p $MPE_JACK_LOGDIR
LOG=$MPE_JACK_LOGDIR/surge.log
: > "\$LOG"

# No chrt here: as a JACK client, Surge's audio thread priority is assigned by
# the server. Wrapping it in chrt would fight jackd's own scheduling.
setsid nohup "\$SURGE_CLI" \
    "\${MIDI_ARGS[@]}" \
    --mpe-enable \
    --mpe-pitch-bend-range=48 \
    --audio-interface="\$IDX" \
    --sample-rate=$MPE_JACK_RATE \
    --osc-in-port=53280 \
    --osc-out-port=53270 \
    --no-stdin \
    >> "\$LOG" 2>&1 < /dev/null &
sleep 5

if pgrep -f surge-xt-cli >/dev/null; then
    _pid=\$(pgrep -f surge-xt-cli | head -1)
    echo "surge-xt-cli running (pid \$_pid) — \$(chrt -p \$_pid 2>/dev/null | tr '\n' ' ')"
else
    echo "surge-xt-cli FAILED to start" >&2
fi
echo ""
echo "=== surge log ==="
tail -n 30 "\$LOG"
echo ""
echo "=== jack ports ==="
jack_lsp -c 2>&1 | head -40 || true
EOF
}

# What the output hardware can actually do. Read from /proc so it works while
# jackd holds the device exclusively — 'aplay --dump-hw-params' would need the
# card free and is therefore useless mid-experiment.
cmd_jack_caps() {
    mpe_cli_require_config
    mpe_cli_ssh "bash -s" <<EOF
$(mpe_jack_detect_snippet)
DAC=\$(_jack_pick_dac)
CARD="\${DAC#hw:}"
echo "=== OUTPUT DEVICE: \$DAC ==="
cat /proc/asound/card\$CARD/id 2>/dev/null
echo ""
if [ -r /proc/asound/card\$CARD/stream0 ]; then
    echo "=== USB AUDIO STREAM DESCRIPTOR (hardware ceiling) ==="
    cat /proc/asound/card\$CARD/stream0
else
    echo "(no stream0 — not a USB audio device; likely I2S/HAT)"
    echo "Formats via hw_params require the card to be free of jackd."
fi
echo ""
echo "=== CURRENTLY NEGOTIATED ==="
for _hw in /proc/asound/card\$CARD/pcm0p/sub0/hw_params; do
    [ -r "\$_hw" ] && cat "\$_hw" || echo "(device not open)"
done
EOF
}

cmd_jack_ports() {
    mpe_cli_require_config
    mpe_cli_ssh "jack_lsp -c 2>&1 | head -60"
}

cmd_jack_status() {
    mpe_cli_require_config
    # shellcheck source=../lib/snapshot.sh
    source "$MPE_CLI_ROOT/lib/snapshot.sh"
    mpe_cli_snapshot_fetch || exit 1

    echo "=== SYSTEMD (from snapshot — production units) ==="
    for unit in surge-xt-cli surge-watchdog; do
        stale="$(mpe_cli_snapshot_stale --arg u "$unit" '.services[$u].stale')"
        active="$(mpe_cli_snapshot_field --arg u "$unit" '.services[$u].active // "unknown"')"
        if [ "$stale" = "true" ]; then active=unknown; fi
        printf "  %-24s %s\n" "${unit}.service" "$active"
    done
    echo ""

    mpe_cli_ssh "bash -s" <<EOF
# Process-level chrt lies here: jackd and a JACK client both keep a
# SCHED_OTHER main thread and elevate only the audio thread. Report threads.
echo "=== PROCESSES (thread-level — the audio thread is what matters) ==="
for _spec in "jackd:jackd" "surge:surge-xt-cli"; do
    _label="\${_spec%%:*}"; _pat="\${_spec##*:}"
    _pid=\$(pgrep -f "\$_pat" | head -1)
    if [ -z "\$_pid" ]; then printf "%-7s not running\n" "\$_label"; continue; fi
    _nthreads=\$(ls /proc/\$_pid/task 2>/dev/null | wc -l)
    printf "%-7s pid=%s threads=%s\n" "\$_label" "\$_pid" "\$_nthreads"
    for _t in /proc/\$_pid/task/*; do
        _tid="\${_t##*/}"
        _pol=\$(chrt -p "\$_tid" 2>/dev/null | sed -n 's/.*policy: //p')
        case "\$_pol" in
            SCHED_FIFO | SCHED_RR)
                printf "        tid=%-7s %s prio %s (%s)\n" "\$_tid" "\$_pol" \
                    "\$(chrt -p "\$_tid" 2>/dev/null | sed -n 's/.*priority: //p')" \
                    "\$(cat "\$_t/comm" 2>/dev/null)"
                ;;
        esac
    done
done

echo ""
echo "=== GRAPH ==="
if pgrep -x jackd >/dev/null; then
    printf "buffer:     "; jack_bufsize 2>&1 | tail -1
    printf "samplerate: "; jack_samplerate 2>&1 | tail -1
    # Count xruns since the last buffer change, not since jackd started —
    # a cumulative count would blame each new setting for the previous one.
    printf "xruns:      "
    awk '/^=== BUFFER/{c=0; b=\$3; next} /[Xx]run/{c++} END{
        printf "%d", c+0
        if (b != "") printf " (since buffer -> %s)", b
        printf "\n"
    }' $MPE_JACK_LOGDIR/jackd.log 2>/dev/null || echo "n/a"
    echo ""
    jack_lsp -c 2>&1 | head -30
else
    echo "jackd not running"
fi
EOF
}

cmd_jack_logs() {
    mpe_cli_require_config
    local n="$MPE_LOG_LINES_DEFAULT"
    if [ "${1:-}" = "-n" ]; then
        n="${2:-}"
    fi
    n="$(mpe_cli_clamp_log_lines "$n")"
    mpe_cli_ssh "bash -s" <<EOF
for f in jackd surge; do
    echo "=== \$f ==="
    tail -n $n $MPE_JACK_LOGDIR/\$f.log 2>/dev/null || echo "(no log)"
    echo ""
done
EOF
}

cmd_jack_stop() {
    mpe_cli_require_config
    echo "$MPE_CLI_NAME: rolling back to the systemd-managed appliance..."
    mpe_cli_ssh "bash -s" <<EOF
pkill -TERM -f surge-xt-cli 2>/dev/null || true
sleep 1
pkill -TERM -f jackd 2>/dev/null || true
sleep 1
pkill -KILL -f jackd 2>/dev/null || true

sudo systemctl start surge-xt-cli.service
if grep -qx 'looper=active' $MPE_JACK_LOGDIR/prior-state 2>/dev/null; then
    sudo systemctl start mpe-looper.service
    echo "(restarted mpe-looper.service — it was running before the experiment)"
fi
sleep 4

echo "=== RESTORED ==="
systemctl is-active surge-xt-cli.service surge-watchdog.service mpe-looper.service 2>&1 | tr '\n' ' '; echo
_pid=\$(pgrep -f surge-xt-cli | head -1)
if [ -n "\$_pid" ]; then
    chrt -p "\$_pid" 2>/dev/null | tr '\n' ' '; echo
else
    echo "WARNING: surge-xt-cli did not come back — check: $MPE_CLI_NAME logs surge -n 40" >&2
fi
pgrep -x jackd >/dev/null && echo "WARNING: jackd still running" >&2 || echo "jackd stopped"
EOF
}
