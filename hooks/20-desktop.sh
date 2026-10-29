#!/bin/bash
# KDE Plasma without the extras
set -euo pipefail
. /tmp/ittygos/hooks/lib.sh

say "KDE Plasma"
pkg_install "$CFG/packages-kde.txt"

say "removing what we do not want"
for p in $(list_names "$CFG/packages-remove.txt"); do
	if dpkg -s "$p" >/dev/null 2>&1; then apt-get purge -y "$p" || true; fi
done
apt-get autoremove -y --purge

say "services"
systemctl enable sddm NetworkManager >/dev/null 2>&1 || true
# a faster boot: nobody waits for the network
systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true
systemctl enable zramswap >/dev/null 2>&1 || true
