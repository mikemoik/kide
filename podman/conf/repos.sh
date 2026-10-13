#!/bin/sh
# Repo setup for podman/Containerfile.kide, run as root before any
# dnf install (copied from $CONF_DIR, see podman/base.conf). Replace it for
# another base: whatever the
# base image needs so that dnf finds every package the Containerfile installs
# (e.g. copy in .repo files), or nothing if its repos are already set up.
#
# Rocky Linux 9 (base.conf's default): CRB and EPEL, standing in for the RHEL9
# target's own repos.
set -eu
dnf -y install dnf-plugins-core epel-release
dnf config-manager --set-enabled crb
