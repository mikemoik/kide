#!/usr/bin/env bash
# podman/start.sh [FILE…] — start the kide container (image `kide`,
# podman/Containerfile.kide) on your ~/workspace: fish, from which `kide`
# opens the IDE. With FILE arguments kide opens them right away (still from
# fish, with its hooks' environment); quitting it ends the container.
#
# The host's ~/workspace (created if missing) is mounted on the container's
# WORKDIR /workspace; FILE arguments are relative to it. Run as your normal user (rootless podman, not sudo): your
# host user is mapped to the image's user (KIDE_UID/KIDE_GID from
# podman/base.conf next to this script, default 1001), so files written in
# ~/workspace stay yours. kide's data and state are kept in the volume
# kide-data. TERM and SSH_CONNECTION are passed on when set (PuTTY/SSH); the
# host's proxy variables (http_proxy, https_proxy, … ) are not (--http-proxy=false).
#
# git over SSH: your key ~/.ssh/gitlab is loaded into an ssh-agent for this
# session, which goes in with SELinux confinement off for this container
# (SELinux blocks the agent socket otherwise); ~/.ssh/known_hosts and
# ~/.gitconfig go in read-only.
set -euo pipefail

KIDE_UID=1001
KIDE_GID=1001
conf="$(dirname "$(readlink -f "$0")")/base.conf"
if [ -f "$conf" ]; then
    KIDE_UID=$(sed -n 's/^KIDE_UID=//p' "$conf")
    KIDE_GID=$(sed -n 's/^KIDE_GID=//p' "$conf")
fi

# no agent yet: rerun this script under one (it ends with the session)
[ -n "${SSH_AUTH_SOCK:-}" ] || exec ssh-agent "$0" "$@"
ssh-add "$HOME/.ssh/gitlab"

cmd=()
[ $# -eq 0 ] || cmd=(fish -c 'kide $argv' "$@")

mkdir -p "$HOME/workspace"
exec podman run --rm -it --http-proxy=false -e TERM -e SSH_CONNECTION \
    --userns="keep-id:uid=$KIDE_UID,gid=$KIDE_GID" \
    --security-opt label=disable \
    -v "$SSH_AUTH_SOCK:/run/ssh-agent.sock" -e SSH_AUTH_SOCK=/run/ssh-agent.sock \
    -v "$HOME/.ssh/known_hosts:/etc/ssh/ssh_known_hosts:ro" \
    -v "$HOME/.gitconfig:/run/gitconfig:ro" -e GIT_CONFIG_GLOBAL=/run/gitconfig \
    -v "$HOME/workspace:/workspace:Z" \
    -v kide-data:/var/lib/kide \
    kide "${cmd[@]}"
