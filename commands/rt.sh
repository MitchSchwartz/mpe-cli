# Realtime scheduling (SCHED_FIFO) for the audio path — fixed env keys only.
#
# Both services permit RT via LimitRTPRIO in their units, but neither forces it:
# JUCE is supposed to elevate its own audio thread and does not on this build,
# and Python never self-elevates at all. These env keys are what actually turn
# SCHED_FIFO on, via the chrt wrapper in start-surge-cli.sh / mpe-looper-service.sh.
#
# See MPE-Module docs/LATENCY-SPIKE.md (Arm A/2) for the measurement protocol:
# change one target at a time and re-measure.

# LimitRTPRIO in both units. Above the warn line a runaway FIFO process can
# starve the touch UI and network stack, which is why Surge ships RT off.
MPE_RT_MAX=95
MPE_RT_WARN_ABOVE=40

cmd_rt() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        status)
            cmd_rt_status "$@"
            ;;
        surge | looper)
            cmd_rt_set "$sub" "$@"
            ;;
        -h | --help | help | "")
            cat <<EOF
Usage: $MPE_CLI_NAME rt status
       $MPE_CLI_NAME rt surge <1-$MPE_RT_MAX|off>
       $MPE_CLI_NAME rt looper <1-$MPE_RT_MAX|off>

  status   Show configured priority and the live scheduling policy of each process
  surge    Set MPE_SURGE_RT_PRIORITY in /etc/mpe/mpe.env and restart surge-xt-cli
  looper   Set MPE_LOOPER_RT_PRIORITY in /etc/mpe/mpe.env and restart mpe-looper

Keep the looper below Surge so the synth wins when both are runnable.
Priorities above $MPE_RT_WARN_ABOVE warn: a runaway FIFO process can starve the touch UI.
EOF
            ;;
        *)
            echo "$MPE_CLI_NAME rt: unknown subcommand: $sub (use status|surge|looper)" >&2
            exit 1
            ;;
    esac
}

# Echoes "env_key unit process_pattern" for a target.
mpe_cli_rt_target() {
    case "$1" in
        surge) printf 'MPE_SURGE_RT_PRIORITY surge-xt-cli.service surge-xt-cli' ;;
        looper) printf 'MPE_LOOPER_RT_PRIORITY mpe-looper.service mpe-looper.py' ;;
    esac
}

cmd_rt_status() {
    mpe_cli_require_config
    mpe_cli_ssh "bash -s" <<'EOF'
echo "=== CONFIGURED (/etc/mpe/mpe.env) ==="
grep -E "^MPE_(SURGE|LOOPER)_RT_PRIORITY=" /etc/mpe/mpe.env 2>/dev/null \
    || echo "(neither set — both processes stay SCHED_OTHER)"

echo ""
echo "=== LIVE ==="
for _spec in "surge:surge-xt-cli" "looper:mpe-looper.py"; do
    _label="${_spec%%:*}"
    _pat="${_spec##*:}"
    _pid=$(pgrep -f "$_pat" | head -1)
    if [ -z "$_pid" ]; then
        printf "%-7s not running\n" "$_label"
        continue
    fi
    _pol=$(chrt -p "$_pid" 2>/dev/null | tr "\n" " ")
    printf "%-7s pid=%s %s\n" "$_label" "$_pid" "$_pol"
    printf "%-7s rtprio limit: %s\n" "" \
        "$(grep -E 'realtime priority' /proc/$_pid/limits 2>/dev/null | tr -s ' ')"
done
EOF
}

cmd_rt_set() {
    mpe_cli_require_config
    local target="$1"
    local prio="${2:-}"
    read -r env_key unit pattern <<<"$(mpe_cli_rt_target "$target")"

    case "$prio" in
        off | 0)
            prio=0
            ;;
        "" | -h | --help)
            echo "Usage: $MPE_CLI_NAME rt $target <1-$MPE_RT_MAX|off>" >&2
            exit 1
            ;;
        *[!0-9]*)
            echo "$MPE_CLI_NAME rt $target: priority must be a number or 'off' (got: $prio)" >&2
            exit 1
            ;;
        *)
            if [ "$prio" -lt 1 ] || [ "$prio" -gt "$MPE_RT_MAX" ]; then
                echo "$MPE_CLI_NAME rt $target: priority out of range 1-$MPE_RT_MAX (got: $prio)" >&2
                exit 1
            fi
            if [ "$prio" -gt "$MPE_RT_WARN_ABOVE" ]; then
                echo "$MPE_CLI_NAME: WARNING: priority $prio is high — a busy FIFO process" >&2
                echo "  at this level can starve the touch UI and SSH. Recommended: 10-20." >&2
            fi
            ;;
    esac

    mpe_cli_ssh "sudo bash -c 'if grep -q \"^${env_key}=\" /etc/mpe/mpe.env 2>/dev/null; then sed -i \"s/^${env_key}=.*/${env_key}=${prio}/\" /etc/mpe/mpe.env; else echo ${env_key}=${prio} >> /etc/mpe/mpe.env; fi'"
    mpe_cli_ssh "sudo systemctl restart ${unit}"
    echo "$MPE_CLI_NAME: ${env_key}=${prio} — restarted ${unit}"

    # Verify rather than trust: the env var only takes effect if the unit also
    # permits RT (LimitRTPRIO). A unit installed before that was added will
    # silently stay SCHED_OTHER.
    #
    # Tolerate failure here — the restart above can drop the next SSH connection,
    # and reporting a landed change as failed is worse than skipping the check.
    sleep 4
    mpe_cli_ssh "bash -s" <<EOF || echo "VERIFY: skipped (ssh unavailable right after restart) — run: $MPE_CLI_NAME rt status"
_pid=\$(pgrep -f "${pattern}" | head -1)
if [ -z "\$_pid" ]; then
    echo "VERIFY: ${target} not running after restart — check: mpe logs ${target} -n 30"
    exit 0
fi
_pol=\$(chrt -p "\$_pid" 2>/dev/null | tr "\n" " ")
echo "VERIFY: \$_pol"
case "\$_pol" in
    *SCHED_FIFO*)
        [ "${prio}" = "0" ] && echo "  unexpected: still SCHED_FIFO after setting off"
        ;;
    *)
        if [ "${prio}" != "0" ]; then
            echo "  WARNING: still SCHED_OTHER — chrt could not elevate."
            echo "  Check LimitRTPRIO on ${unit} (reinstall units:"
            echo "  ./scripts/configure-pi-paths.sh --local --force) then retry."
        fi
        ;;
esac
EOF
}
