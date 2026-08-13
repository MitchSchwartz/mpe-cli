# Realtime scheduling (SCHED_FIFO) on the audio path — read-only.
#
# How RT actually works on this appliance, since the chrt wrapper was removed:
# the JACK server's threads and its clients get real-time priority from jackd
# itself. mpe-jackd.service runs with LimitRTPRIO=95, jackd takes its own
# priority (default 70, MPE_JACK_RT_PRIORITY to override), and each client's
# audio thread is handed a fixed offset below that — Surge lands at
# SCHED_FIFO 65. Neither Surge nor Python self-elevates, and they should not:
# a chrt wrapper around the process would fight jackd and elevate non-audio
# threads too.
#
# The MPE_SURGE_RT_PRIORITY / MPE_LOOPER_RT_PRIORITY env keys and the chrt
# wrapper they fed are removed alongside the ALSA path they existed to serve.
# There is nothing left to set here — this command reports; it does not tune.
#
# See MPE-Module docs/LATENCY-SPIKE.md for the measurement protocol: change one
# variable at a time and re-measure.

cmd_rt() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        status)
            cmd_rt_status "$@"
            ;;
        surge | looper)
            echo "$MPE_CLI_NAME rt $sub: removed — there is no per-service RT knob left." >&2
            echo "Surge and the looper inherit realtime priority from jackd" >&2
            echo "(LimitRTPRIO=95, Surge's audio thread lands at SCHED_FIFO 65)." >&2
            echo "See: $MPE_CLI_NAME rt status · $MPE_CLI_NAME jack status" >&2
            exit 1
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME rt status

  status   Verify the RT chain end to end — the unit's LimitRTPRIO ceiling and
           the live scheduling policy of jackd and each audio client.

There is no set command. RT is assigned by jackd (LimitRTPRIO=95); Surge's
audio thread is SCHED_FIFO 65 by design. The MPE_*_RT_PRIORITY env keys and the
chrt wrapper are retired — setting them changed nothing and reported success.
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME rt: unknown subcommand: $sub (use status)" >&2
            exit 1
            ;;
    esac
}

cmd_rt_status() {
    mpe_cli_require_config
    mpe_cli_ssh "bash -s" <<'EOF'
echo "=== UNIT RT LIMITS ==="
for unit in mpe-jackd.service surge-xt-cli.service; do
    lim="$(systemctl show "$unit" -p LimitRTPRIO 2>/dev/null | cut -d= -f2)"
    if [ -n "$lim" ]; then
        printf "  %-22s LimitRTPRIO=%s\n" "$unit" "$lim"
    fi
done

echo ""
echo "=== LIVE ==="
for _spec in "jackd:jackd" "surge:surge-xt-cli"; do
    _label="${_spec%%:*}"
    _pat="${_spec##*:}"
    _pid="$(pgrep -x "$_pat" 2>/dev/null | head -1)"
    [ -z "$_pid" ] && _pid="$(pgrep -f "$_pat" 2>/dev/null | head -1)"
    if [ -z "$_pid" ]; then
        printf "  %-7s not running\n" "$_label"
        continue
    fi
    # Process-level scheduling, not thread-level: the main thread of a JACK
    # client is SCHED_OTHER by design, and that is the answer most likely to
    # mislead. The audio thread — the one jackd elevated — is the one to read.
    _a=$(chrt -p "$_pid" 2>/dev/null | sed -n 's/.*policy: //p')
    _tid=""
    for _t in /proc/"$_pid"/task/*; do
        _t="${_t##*/}"
        _p="$(chrt -p "$_t" 2>/dev/null | sed -n 's/.*policy: //p')"
        if [ "$_p" = "SCHED_FIFO" ]; then
            _r="$(chrt -p "$_t" 2>/dev/null | sed -n 's/.*priority: //p')"
            _tid="$_t"
            printf "  %-7s pid=%s  main=%s   audio thread %s = SCHED_FIFO %s\n" \
                "$_label" "$_pid" "$_a" "$_t" "$_r"
            break
        fi
    done
    if [ -z "$_tid" ]; then
        printf "  %-7s pid=%s  main=%s   audio thread: none found with SCHED_FIFO\n" \
            "$_label" "$_pid" "$_a"
    fi
done
EOF
}
