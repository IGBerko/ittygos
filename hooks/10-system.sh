#!/bin/bash
# base system: architectures, locales, packages, ittyGOS identity
set -euo pipefail
. /tmp/ittygos/hooks/lib.sh
VERSION=$(cat /tmp/ittygos/VERSION)

say "i386 architecture (Steam, Wine, Proton need 32-bit libraries)"
dpkg --add-architecture i386
apt-get update
apt-get -y full-upgrade

say "locales"
printf 'en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8\n' > /etc/locale.gen
locale-gen
update-locale LANG="${LIVE_LOCALE:-en_US.UTF-8}"
echo ittygos > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 ittygos\n' > /etc/hosts

say "base packages"
pkg_install "$CFG/packages-base.txt"

say "ittyGOS files (tuning, scripts, defaults)"
cp -a /tmp/ittygos/overlay/. /
chmod 755 /usr/local/bin/ittygos-* 2>/dev/null || true

say "identity: os-release, issue, motd"
# keep the package file out of the way without moving the essential file (re-runnable)
if ! dpkg-divert --list /usr/lib/os-release | grep -q .; then
	dpkg-divert --local --no-rename --divert /usr/lib/os-release.distrib --add /usr/lib/os-release >/dev/null
fi
cat > /usr/lib/os-release <<OSR
PRETTY_NAME="ittyGOS $VERSION (based on Debian 13 trixie)"
NAME="ittyGOS"
VERSION_ID="$VERSION"
VERSION="$VERSION"
ID=ittygos
ID_LIKE=debian
HOME_URL="https://github.com/IGBerko/ittygos"
BUG_REPORT_URL="https://github.com/IGBerko/ittygos/issues"
OSR
printf 'ittyGOS %s \\n \\l\n\n' "$VERSION" > /etc/issue
printf '\n  ittyGOS %s - Debian 13 with KDE for games\n  Steam, Proton, Wine, Java 25/21, Python 3\n  Help: ittygos-help\n\n' "$VERSION" > /etc/motd
