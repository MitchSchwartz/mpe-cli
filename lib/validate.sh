MPE_LOG_LINES_DEFAULT=50
MPE_LOG_LINES_MAX=200

mpe_cli_clamp_log_lines() {
    local raw="${1:-$MPE_LOG_LINES_DEFAULT}"
    if ! [[ "$raw" =~ ^[0-9]+$ ]]; then
        echo "$MPE_CLI_NAME: -n requires a positive integer" >&2
        exit 1
    fi
    if [ "$raw" -gt "$MPE_LOG_LINES_MAX" ]; then
        echo "$MPE_CLI_NAME: -n capped at $MPE_LOG_LINES_MAX" >&2
        raw="$MPE_LOG_LINES_MAX"
    fi
    if [ "$raw" -lt 1 ]; then
        raw=1
    fi
    printf '%s' "$raw"
}
