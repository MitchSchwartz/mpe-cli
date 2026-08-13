# shellcheck shell=bash
# List MIDI ports (read-only). Helps verify controllers (APC mini, RC-5, Roli).

# shellcheck source=../lib/target.sh
source "$MPE_CLI_ROOT/lib/target.sh"

mpe_cli_midi_snapshot() {
    echo "=== USB (Akai/APC/MIDI class) ==="
    lsusb 2>/dev/null | grep -iE 'akai|apc|novation|roli|midi|lumi|boss|loop' || echo "(no matching USB devices)"
    echo ""
    echo "=== aconnect -l ==="
    aconnect -l 2>/dev/null || echo "(aconnect unavailable)"
    echo ""
    if command -v python3 >/dev/null 2>&1; then
        echo "=== python-rtmidi ==="
        python3 <<'PY' 2>&1 || true
try:
    import rtmidi
except ImportError:
    print("(python-rtmidi not installed — pip3 install python-rtmidi)")
    raise SystemExit(0)
ins = rtmidi.MidiIn()
outs = rtmidi.MidiOut()
print("IN:", ins.get_ports() or ["(none)"])
print("OUT:", outs.get_ports() or ["(none)"])
PY
    fi
}

mpe_cli_midi_remote_script() {
    cat <<'EOF'
echo "=== USB (Akai/APC/MIDI class) ==="
lsusb 2>/dev/null | grep -iE "akai|apc|novation|roli|midi|lumi|boss|loop" || echo "(no matching USB devices)"
echo ""
echo "=== aconnect -l ==="
aconnect -l 2>/dev/null || echo "(aconnect unavailable)"
echo ""
if command -v python3 >/dev/null 2>&1; then
  echo "=== python-rtmidi ==="
  python3 <<'PY' 2>&1 || true
try:
    import rtmidi
except ImportError:
    print("(python-rtmidi not installed)")
    raise SystemExit(0)
ins = rtmidi.MidiIn()
outs = rtmidi.MidiOut()
print("IN:", ins.get_ports() or ["(none)"])
print("OUT:", outs.get_ports() or ["(none)"])
PY
fi
EOF
}

cmd_midi_list() {
    local target="${1:-local}"
    case "$target" in
        -h | --help | help)
            cat <<EOF
Usage: $MPE_CLI_NAME midi-list [local|pi]

Read-only snapshot: lsusb MIDI matches, aconnect -l, python-rtmidi port names.

Allowlist: $MPE_CLI_NAME midi-list · $MPE_CLI_NAME midi-list local · $MPE_CLI_NAME midi-list pi
EOF
            return 0
            ;;
    esac

    target="$(mpe_cli_normalize_target "$target")" || exit 1

    case "$target" in
        local)
            echo "=== MIDI ports (laptop) ==="
            mpe_cli_midi_snapshot
            ;;
        pi)
            echo "=== MIDI ports (Pi) ==="
            mpe_cli_run_on_target pi true "$(mpe_cli_midi_remote_script)"
            ;;
    esac
}
