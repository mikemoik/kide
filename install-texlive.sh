#!/usr/bin/env bash
# install-texlive.sh [SOURCE] — install the current TeX Live into the
# workspace: /workspace/opt/texlive (host: ~/workspace/opt/texlive). Run it
# once in the kide container, after the image is built; TeX Live is not part
# of the image, and RHEL9's texlive packages (2020) are too old.
#
# No internet needed: SOURCE is the TeX Live ISO, which you download on a
# connected machine and put into the workspace yourself (~7 GB):
#   https://mirror.ctan.org/systems/texlive/Images/texlive.iso
#   (checksum next to it: texlive<YEAR>.iso.sha512)
# Default SOURCE: the newest /workspace/dist/texlive*.iso (host:
# ~/workspace/dist/). SOURCE may also be a directory holding the ISO's content
# (unpacked or mounted) or a mirror of CTAN's systems/texlive/tlnet.
#
# An ISO is unpacked with bsdtar (no mount, no root) next to the install
# directory and removed afterwards: have ~7 GB free for that on top of the
# install (full scheme without docs: ~5 GB).
#
# Environment:
#   TEXLIVE_PREFIX  install directory (default /workspace/opt/texlive)
#   TEXLIVE_SCHEME  full (default), medium, small, basic, minimal, …
#   TEXLIVE_DOCS=1  also install the packages' documentation (~+4 GB)
#
# The install is "portable": everything (also the per-user trees and the font
# caches) is inside TEXLIVE_PREFIX, with no absolute paths, so the same tree
# works in the container and on the host. kide's fish hook (20-kide.fish) puts
# /workspace/opt/texlive/bin/x86_64-linux on PATH in every new shell.
# Needs perl; bsdtar for an ISO (both in the kide image).
set -euo pipefail

prefix=${TEXLIVE_PREFIX:-/workspace/opt/texlive}
scheme=${TEXLIVE_SCHEME:-full}
docs=${TEXLIVE_DOCS:-0}
dist=/workspace/dist

die() { echo "install-texlive.sh: $*" >&2; exit 1; }

src=${1:-}
if [ -z "$src" ]; then
    # shellcheck disable=SC2012  # plain names, newest first
    src=$(ls -t "$dist"/texlive*.iso 2>/dev/null | head -n 1 || true)
    [ -n "$src" ] || die "no $dist/texlive*.iso (host: ~/workspace/dist/).
Download https://mirror.ctan.org/systems/texlive/Images/texlive.iso on a
connected machine, put it there, or pass the ISO or directory as argument."
fi
[ -e "$src" ] || die "$src: not found"
command -v perl >/dev/null || die "perl not found (dnf install perl)"
if [ -e "$prefix" ] && [ -n "$(ls -A "$prefix")" ]; then
    die "$prefix exists and is not empty; remove it first to reinstall"
fi
mkdir -p "$(dirname "$prefix")"

tmp=
cleanup() {
    [ -n "$tmp" ] || return 0
    # the ISO's directories are read-only
    chmod -R u+w "$tmp" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ -d "$src" ]; then
    inst=$(readlink -f "$src")
else
    command -v bsdtar >/dev/null || die "bsdtar not found (dnf install bsdtar); or unpack the ISO yourself and pass the directory"
    tmp=$(mktemp -d "$(dirname "$prefix")/.texlive-iso.XXXXXX")
    echo "unpacking $src to $tmp …"
    bsdtar -xf "$src" -C "$tmp"
    inst=$tmp
fi
[ -f "$inst/install-tl" ] && [ -f "$inst/tlpkg/texlive.tlpdb" ] ||
    die "$src: no TeX Live installer (install-tl, tlpkg/texlive.tlpdb)"

profile=$(mktemp)
trap 'rm -f "$profile"; cleanup' EXIT
cat >"$profile" <<EOF
selected_scheme scheme-$scheme
TEXDIR $prefix
TEXMFLOCAL $prefix/texmf-local
TEXMFSYSVAR $prefix/texmf-var
TEXMFSYSCONFIG $prefix/texmf-config
instopt_portable 1
instopt_adjustpath 0
instopt_adjustrepo 0
tlpdbopt_autobackup 0
tlpdbopt_install_docfiles $docs
tlpdbopt_install_srcfiles 0
EOF

echo "installing TeX Live (scheme-$scheme) from $inst into $prefix …"
# (no warning about our own TEXLIVE_* variables)
TEXLIVE_INSTALL_ENV_NOCHECK=1 perl "$inst/install-tl" -profile "$profile" -repository "$inst"

bin=$(echo "$prefix"/bin/*-linux)
"$bin/tex" --version | head -n 1
echo "TeX Live is in $prefix; binaries: $bin"
echo "(on PATH in every new fish shell in the kide container)"
