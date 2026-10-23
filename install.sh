#!/usr/bin/env bash
# install.sh [--no-build] [PREFIX] — the whole install in one call:
#
#   curl -fsSL <REPO>/install.sh | KIDE_TARBALL=<REPO tarball URL> bash
#   curl -fsSL …/install.sh | KIDE_TARBALL=… bash -s -- --no-build   # config only, see build-ide.sh
#   ./install.sh [--no-build] [PREFIX]          # from a checkout (no download, no KIDE_TARBALL)
#
# The script holds no repo URL: piped from curl it needs KIDE_TARBALL (the
# tarball of the branch to install, from wherever the repo is hosted).
#
#   1. installs the missing RHEL packages (dnf; asks for the sudo password)
#   2. piped from curl: downloads the repo tarball $KIDE_TARBALL to a temp dir
#   3. builds kreatos-ide offline into PREFIX (build-ide.sh, default ~/.local/kreatos-ide);
#      with --no-build only refreshes plugins, config, launcher and bashrc
#   4. starts a new shell in which `kide` is on PATH
set -euo pipefail

# build toolchain, tar (download), git (gitsigns, lazygit), file (yazi), the
# C/C++ tools kide uses from RHEL, tmux, and fd-find + ripgrep + bat (fd: snacks
# file pickers; rg: grepprg, snacks grep pickers; bat: yazi preview highlighting;
# all three from EPEL, so EPEL must be enabled).
# The libraries C/C++ projects build against are not kide's: they are the
# ibn-dev build environment (separate repo, a container).
# All come from the box's configured dnf repos; install.sh adds no repos.
PKGS=(gcc make cmake python3 rust-toolset golang findutils diffutils tar
      git-core gcc-c++ clang-tools-extra gdb lldb file tmux fd-find ripgrep bat)

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# everything runs inside main, so bash has read the whole script before any
# command (sudo, dnf) can read from stdin when it is piped from curl
main() {
  local missing=() p src tmp=

  # piped from curl (no checkout next to the script): the tarball URL must be
  # given; checked before dnf so nothing is installed for nothing
  src=$(dirname "${BASH_SOURCE[0]:-}")
  if [ ! -f "$src/build-ide.sh" ] && [ -z "${KIDE_TARBALL:-}" ]; then
    echo "install.sh: set KIDE_TARBALL to the repo tarball URL, e.g." >&2
    echo "  curl -fsSL <REPO>/install.sh | KIDE_TARBALL=<REPO>/…/main.tar.gz bash" >&2
    exit 1
  fi

  for p in "${PKGS[@]}"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    log "installing RHEL packages: ${missing[*]}"
    if ((EUID == 0)); then dnf -y install "${missing[@]}"
    else sudo dnf -y install "${missing[@]}" </dev/tty
    fi
  fi

  if [ ! -f "$src/build-ide.sh" ]; then
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" EXIT
    log "downloading $KIDE_TARBALL"
    curl -fL "$KIDE_TARBALL" | tar -xz -C "$tmp" --strip-components=1
    src=$tmp
  fi

  "$src/build-ide.sh" "$@"

  # a script cannot change its caller's PATH: replace it with a new shell that
  # reads ~/.bashrc (interactive terminals only)
  if [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
    [ -n "$tmp" ] && rm -rf "$tmp"
    log "new shell: run kide (exit returns to the previous shell)"
    exec bash -i </dev/tty
  fi
}

main "$@"
