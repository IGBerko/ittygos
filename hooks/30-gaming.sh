#!/bin/bash
# Steam, Wine, game tools (and optionally the NVIDIA driver)
set -euo pipefail
. /tmp/ittygos/hooks/lib.sh

say "accepting the Steam licence question non-interactively"
echo "steam steam/question select I AGREE" | debconf-set-selections
echo "steam steam/license note" | debconf-set-selections

say "gaming packages"
pkg_install "$CFG/packages-gaming.txt"
say "optional packages"
pkg_install_optional "$CFG/packages-optional.txt"

if [ "${WITH_NVIDIA:-0}" = 1 ]; then
	say "NVIDIA proprietary driver (DKMS)"
	pkg_install "$CFG/packages-nvidia.txt"
	# in a chroot dkms would build for the host kernel: build for the installed ones
	for k in $(ls /lib/modules); do dkms autoinstall -k "$k" || true; done
fi

say "default groups for the live user"
mkdir -p /etc/live/config.conf.d
echo 'LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev powerdev scanner bluetooth sudo render input"' \
	> /etc/live/config.conf.d/ittygos.conf
