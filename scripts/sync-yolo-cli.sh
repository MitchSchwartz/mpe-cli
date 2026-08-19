#!/usr/bin/env bash
# Sync mpe-cli between nerdrack (yolobot) and the laptop clone.
#
# Nerdrack's om-yolo account cannot push to GitHub (403). After yolobot commits
# on nerdrack, run `publish` from the laptop to land the branch on origin.
# After merging to main, run `update-nerdrack` so the build box matches main.
#
# Usage:
#   scripts/sync-yolo-cli.sh pull [branch]       # nerdrack → laptop
#   scripts/sync-yolo-cli.sh push [branch]       # laptop → origin
#   scripts/sync-yolo-cli.sh publish [branch]    # pull then push
#   scripts/sync-yolo-cli.sh update-nerdrack     # origin/main → nerdrack
#
# Env (optional):
#   MPE_CLI_NERDRACK_HOST   SSH host (default: claudeLogin)
#   MPE_CLI_NERDRACK_REPO   Path on nerdrack (default: /home/claude-sandbox/workspace/mpe-cli)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NERDRACK_HOST="${MPE_CLI_NERDRACK_HOST:-claudeLogin}"
NERDRACK_REPO="${MPE_CLI_NERDRACK_REPO:-/home/claude-sandbox/workspace/mpe-cli}"
NERDRACK_REMOTE="nerdrack"

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

die() {
    echo "sync-yolo-cli: $*" >&2
    exit 1
}

nerdrack_branch() {
    ssh -o BatchMode=yes "$NERDRACK_HOST" \
        "git -C $(printf '%q' "$NERDRACK_REPO") rev-parse --abbrev-ref HEAD"
}

resolve_branch() {
    local branch="${1:-}"
    if [ -n "$branch" ]; then
        printf '%s' "$branch"
        return
    fi
    nerdrack_branch
}

fetch_nerdrack() {
    local branch="$1"
    local fetch_ref="refs/remotes/${NERDRACK_REMOTE}/${branch//\//_}"
    git -C "$ROOT" fetch \
        "ssh://${NERDRACK_HOST}${NERDRACK_REPO}" \
        "${branch}:${fetch_ref}"
    printf '%s' "$fetch_ref"
}

cmd_pull() {
    local branch ref
    branch="$(resolve_branch "${1:-}")"
    [ -n "$branch" ] || die "could not resolve branch (pass a name or check nerdrack HEAD)"

    echo "=== pull: ${NERDRACK_HOST}:${NERDRACK_REPO} (${branch}) → ${ROOT} ==="
    ref="$(fetch_nerdrack "$branch")"

    git -C "$ROOT" checkout -B "$branch"
    git -C "$ROOT" reset --hard "$ref"
    echo ""
    echo "Local branch '$branch' now matches nerdrack."
    git -C "$ROOT" log --oneline -3
    echo ""
    echo "Next: review, then: $0 push $branch"
}

cmd_push() {
    local branch="${1:-}"
    branch="${branch:-$(git -C "$ROOT" branch --show-current)}"
    [ -n "$branch" ] || die "not on a branch; pass a branch name"

    echo "=== push: ${ROOT} (${branch}) → origin ==="
    git -C "$ROOT" push --force-with-lease -u origin "$branch"
    echo "Published: origin/$branch"
}

cmd_publish() {
    local branch="${1:-}"
    cmd_pull "$branch"
    branch="$(git -C "$ROOT" branch --show-current)"
    cmd_push "$branch"
}

cmd_update_nerdrack() {
    echo "=== update-nerdrack: origin/main → ${NERDRACK_HOST}:${NERDRACK_REPO} ==="
    ssh -o BatchMode=yes "$NERDRACK_HOST" bash -s <<EOF
set -euo pipefail
cd $(printf '%q' "$NERDRACK_REPO")
git fetch origin
git checkout main
git reset --hard origin/main
git log --oneline -2
EOF
    echo "Nerdrack mpe-cli is on origin/main."
}

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        pull) cmd_pull "${1:-}" ;;
        push) cmd_push "${1:-}" ;;
        publish) cmd_publish "${1:-}" ;;
        update-nerdrack) cmd_update_nerdrack ;;
        -h | --help | help | "") usage 0 ;;
        *)
            die "unknown command: $cmd (try: pull | push | publish | update-nerdrack)"
            ;;
    esac
}

main "$@"
