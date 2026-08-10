# SSH/SCP wrappers — fixed host from config only (no --host passthrough).

mpe_cli_ssh() {
    ssh -i "$SSH_KEY" -o BatchMode=yes "$PI_USER@$PI_HOST" "$@"
}

mpe_cli_ssh_tty() {
    ssh -i "$SSH_KEY" -t "$PI_USER@$PI_HOST" "$@"
}

mpe_cli_scp_from() {
    local remote_path="$1"
    local dest="$2"
    scp -i "$SSH_KEY" "${PI_USER}@${PI_HOST}:${remote_path}" "$dest"
}

mpe_cli_remote_bash() {
    local script="$1"
    mpe_cli_ssh "bash -s" <<EOF
$(mpe_cli_pi_source_line)
$script
EOF
}
