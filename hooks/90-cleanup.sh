#!/bin/bash
# initramfs, caches, identity files that must not be copied into the image
set -euo pipefail
. /tmp/ittygos/hooks/lib.sh

say "initramfs"
update-initramfs -u -k all

say "plymouth theme"
plymouth-set-default-theme -R spinner 2>/dev/null || true

say "cleaning"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/log/*.log /var/log/apt/* /root/.cache /tmp/*.deb
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_* /root/.bash_history
