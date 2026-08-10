cmd_pull_videos() {
    mpe_cli_require_config
    local dest="./recordings"
    local delete_source=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                echo "Usage: $MPE_CLI_NAME pull-videos [-o DIR] [--delete-source]"
                exit 0
                ;;
            -o | --output)
                shift
                dest="${1:?missing value for --output}"
                ;;
            --delete-source)
                delete_source=1
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "$MPE_CLI_NAME pull-videos: unknown option: $1" >&2
                exit 1
                ;;
            *)
                dest="$1"
                ;;
        esac
        shift
    done

    mkdir -p "$dest"
    dest="$(cd "$dest" && pwd)"

    mapfile -t remote_files < <(
        mpe_cli_ssh "shopt -s nullglob; for f in \"\$HOME\"/mpe-demo-*.mkv; do printf '%s\n' \"\$f\"; done" 2>/dev/null || true
    )

    if [ "${#remote_files[@]}" -eq 0 ]; then
        echo "$MPE_CLI_NAME: no ~/mpe-demo-*.mkv on $PI_USER@$PI_HOST" >&2
        exit 0
    fi

    echo "$MPE_CLI_NAME: pulling ${#remote_files[@]} file(s) → $dest" >&2
    for remote in "${remote_files[@]}"; do
        mpe_cli_scp_from "$remote" "$dest/"
        echo "  ✓ $(basename "$remote")" >&2
    done

    if [ "$delete_source" -eq 1 ]; then
        mpe_cli_ssh "rm -f $(printf '%q ' "${remote_files[@]}")"
        echo "$MPE_CLI_NAME: deleted ${#remote_files[@]} file(s) from Pi" >&2
    fi

    echo "$MPE_CLI_NAME: done — $dest" >&2
}
