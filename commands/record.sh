cmd_record() {
    mpe_cli_require_config
    local remote_out=""
    local fps=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                echo "Usage: $MPE_CLI_NAME record [remote-file.mkv] [fps]"
                exit 0
                ;;
            *)
                if [ -z "$remote_out" ]; then
                    remote_out="$1"
                elif [ -z "$fps" ]; then
                    fps="$1"
                else
                    echo "$MPE_CLI_NAME record: too many arguments" >&2
                    exit 1
                fi
                ;;
        esac
        shift
    done

    local repo remote_cmd
    repo="$(mpe_cli_remote_repo)"
    remote_cmd="cd $repo && ./scripts/record-screen.sh"
    if [ -n "$remote_out" ]; then
        remote_cmd+=" $(printf '%q' "$remote_out")"
    fi
    if [ -n "$fps" ]; then
        remote_cmd+=" $(printf '%q' "$fps")"
    fi

    echo "$MPE_CLI_NAME: recording on $PI_USER@$PI_HOST (Ctrl+C to stop)…" >&2
    mpe_cli_ssh_tty "bash -lc $(printf '%q' "$remote_cmd")"
}
