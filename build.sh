#!/bin/bash
# ittyGOS build script: Debian 13 (trixie) -> chroot -> live ISO (BIOS + UEFI)
#
#   sudo ./build.sh setup       install the build tools on the host (WSL2 Ubuntu / Debian)
#   sudo ./build.sh bootstrap   debootstrap the base system into work/chroot
#   sudo ./build.sh configure   install packages, run hooks, add the overlay (re-runnable)
#   sudo ./build.sh shell       open a shell inside the chroot (to try and change things by hand)
#   sudo ./build.sh iso         pack the chroot into out/ittyGOS-<version>.iso
#   sudo ./build.sh all         bootstrap + configure + iso
#   sudo ./build.sh clean       remove work/ (keeps out/)
#
# Variables: WITH_NVIDIA=1 (proprietary driver, off by default), SQUASH_LEVEL=15 (zstd 1..19),
#            LIVE_LOCALE=en_US.UTF-8, LIVE_LAYOUTS=us,ru, MIRROR=..., WORK=..., OUT=...
#            DRY_RUN=1 only prints what would be done (no root needed)
# Put this directory in the WSL home (ext4), not under /mnt/c: it is much faster and keeps permissions.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"
SUITE=trixie
ARCH=amd64
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"
CHROOT="$WORK/chroot"
ISO_DIR="$WORK/iso"
WITH_NVIDIA="${WITH_NVIDIA:-0}"
SQUASH_LEVEL="${SQUASH_LEVEL:-15}"
LIVE_LOCALE="${LIVE_LOCALE:-en_US.UTF-8}"
LIVE_LAYOUTS="${LIVE_LAYOUTS:-us,ru}"
DRY_RUN="${DRY_RUN:-0}"
ISO_NAME="ittyGOS-$VERSION.iso"

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# run a command, or only print it in a dry run
run() {
	if [ "$DRY_RUN" = 1 ]; then printf '   + %s\n' "$*"; else "$@"; fi
}
# write stdin to a file, or only name the file in a dry run
put() {
	if [ "$DRY_RUN" = 1 ]; then printf '   + write %s\n' "$1"; cat > /dev/null; else cat > "$1"; fi
}

need_root() {
	[ "$DRY_RUN" = 1 ] && return 0
	[ "$(id -u)" = 0 ] || die "root privileges required: sudo ./build.sh $1"
}

# ---------- setup ----------
cmd_setup() {
	need_root setup
	if [ "$DRY_RUN" != 1 ] && ! command -v apt-get >/dev/null 2>&1; then
		die "this host has no apt-get. Build on Debian or Ubuntu (for example WSL2 Ubuntu), not on Alpine/ittyOS"
	fi
	say "installing the build tools"
	run apt-get update
	run apt-get install -y debootstrap debian-archive-keyring squashfs-tools xorriso \
		isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools rsync
	say "ready. Next: sudo ./build.sh all"
}

# ---------- mounts of the chroot ----------
MOUNTED=0
mount_chroot() {
	[ "$MOUNTED" = 1 ] && return 0
	run mount -t proc proc "$CHROOT/proc"
	run mount -t sysfs sysfs "$CHROOT/sys"
	run mount --rbind /dev "$CHROOT/dev"
	run mount --make-rslave "$CHROOT/dev"
	run mount -t tmpfs tmpfs "$CHROOT/run"
	MOUNTED=1
}
umount_chroot() {
	[ "$MOUNTED" = 1 ] || return 0
	[ "$DRY_RUN" = 1 ] && { MOUNTED=0; return 0; }
	for m in run dev sys proc; do
		umount -R "$CHROOT/$m" 2>/dev/null || umount -l "$CHROOT/$m" 2>/dev/null || true
	done
	MOUNTED=0
}
trap 'umount_chroot' EXIT

in_chroot() { run chroot "$CHROOT" /usr/bin/env -i HOME=/root TERM="${TERM:-linux}" \
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"; }

# ---------- bootstrap ----------
cmd_bootstrap() {
	need_root bootstrap
	[ "$DRY_RUN" = 1 ] || command -v debootstrap >/dev/null 2>&1 || die "debootstrap is missing: sudo ./build.sh setup"
	if [ -e "$CHROOT/etc/debian_version" ]; then
		warn "$CHROOT already exists: skipping (./build.sh clean to start from scratch)"
		return 0
	fi
	say "debootstrap $SUITE from $MIRROR (several minutes)"
	run mkdir -p "$WORK"
	run debootstrap --arch="$ARCH" --variant=minbase \
		--keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
		--include=ca-certificates,locales,gnupg \
		"$SUITE" "$CHROOT" "$MIRROR"
}

# ---------- configure ----------
cmd_configure() {
	need_root configure
	[ "$DRY_RUN" = 1 ] || [ -e "$CHROOT/etc/debian_version" ] || die "no chroot yet: ./build.sh bootstrap"

	say "apt sources (main contrib non-free non-free-firmware) and i386 for Steam"
	put "$CHROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main contrib non-free non-free-firmware
deb $MIRROR $SUITE-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $SUITE-security main contrib non-free non-free-firmware
EOF
	# no services may start inside the chroot while packages are installed
	put "$CHROOT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
	run chmod +x "$CHROOT/usr/sbin/policy-rc.d"
	run cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

	say "copying config, hooks and the overlay into the chroot"
	run rm -rf "$CHROOT/tmp/ittygos"
	run mkdir -p "$CHROOT/tmp/ittygos"
	run cp -a "$HERE/config" "$HERE/hooks" "$CHROOT/tmp/ittygos/"
	run cp -a "$HERE/overlay" "$CHROOT/tmp/ittygos/overlay"
	printf '%s\n' "$VERSION" | put "$CHROOT/tmp/ittygos/VERSION"

	mount_chroot
	for h in "$HERE"/hooks/[0-9][0-9]-*.sh; do
		say "hook $(basename "$h")"
		in_chroot env WITH_NVIDIA="$WITH_NVIDIA" LIVE_LOCALE="$LIVE_LOCALE" \
			/bin/bash "/tmp/ittygos/hooks/$(basename "$h")"
	done
	umount_chroot

	run rm -f "$CHROOT/usr/sbin/policy-rc.d"
	run rm -rf "$CHROOT/tmp/ittygos"
	say "configure done. Try it: sudo ./build.sh shell   Pack it: sudo ./build.sh iso"
}

cmd_shell() {
	need_root shell
	[ "$DRY_RUN" = 1 ] || [ -e "$CHROOT/etc/debian_version" ] || die "no chroot yet: ./build.sh bootstrap"
	run cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"
	mount_chroot
	say "inside the chroot (exit to leave)"
	in_chroot /bin/bash -l || true
	umount_chroot
}

# ---------- iso ----------
cmd_iso() {
	need_root iso
	[ "$DRY_RUN" = 1 ] || [ -e "$CHROOT/etc/debian_version" ] || die "no chroot yet: ./build.sh bootstrap && ./build.sh configure"
	for t in mksquashfs xorriso grub-mkstandalone mkfs.vfat mcopy; do
		[ "$DRY_RUN" = 1 ] || command -v "$t" >/dev/null 2>&1 || die "$t is missing: sudo ./build.sh setup"
	done

	say "preparing the ISO tree"
	run rm -rf "$ISO_DIR"
	run mkdir -p "$ISO_DIR/live" "$ISO_DIR/isolinux" "$ISO_DIR/boot/grub" "$OUT"

	local kernel initrd
	if [ "$DRY_RUN" = 1 ]; then kernel=vmlinuz-X; initrd=initrd.img-X; else
		kernel=$(ls "$CHROOT"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1) || true
		initrd=$(ls "$CHROOT"/boot/initrd.img-* 2>/dev/null | sort -V | tail -n1) || true
		[ -n "$kernel" ] && [ -n "$initrd" ] || die "no kernel or initrd in the chroot (the configure step failed?)"
	fi
	run cp "$kernel" "$ISO_DIR/live/vmlinuz"
	run cp "$initrd" "$ISO_DIR/live/initrd.img"

	say "squashfs (zstd level $SQUASH_LEVEL): the slow step"
	run mksquashfs "$CHROOT" "$ISO_DIR/live/filesystem.squashfs" -noappend \
		-comp zstd -Xcompression-level "$SQUASH_LEVEL" -b 1M \
		-e proc sys dev run tmp

	local append="boot=live components username=gamer hostname=ittygos locales=$LIVE_LOCALE keyboard-layouts=$LIVE_LAYOUTS"

	say "BIOS boot (isolinux)"
	run cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/isolinux/"
	for m in ldlinux.c32 libcom32.c32 libutil.c32 vesamenu.c32; do
		run cp "/usr/lib/syslinux/modules/bios/$m" "$ISO_DIR/isolinux/"
	done
	put "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
UI vesamenu.c32
DEFAULT live
TIMEOUT 50
MENU TITLE ittyGOS $VERSION

LABEL live
  MENU LABEL ittyGOS live
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img $append

LABEL safe
  MENU LABEL ittyGOS live (safe graphics)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img $append nomodeset

LABEL text
  MENU LABEL ittyGOS live (text mode, no desktop: for debugging)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img $append systemd.unit=multi-user.target
EOF

	say "UEFI boot (grub)"
	put "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
insmod all_video

menuentry "ittyGOS live" {
    linux /live/vmlinuz $append
    initrd /live/initrd.img
}
menuentry "ittyGOS live (safe graphics)" {
    linux /live/vmlinuz $append nomodeset
    initrd /live/initrd.img
}
menuentry "ittyGOS live (text mode, no desktop: for debugging)" {
    linux /live/vmlinuz $append systemd.unit=multi-user.target
    initrd /live/initrd.img
}
EOF
	put "$WORK/grub-embed.cfg" <<'EOF'
search --file --set=root /live/vmlinuz
set prefix=($root)/boot/grub
configfile /boot/grub/grub.cfg
EOF
	run grub-mkstandalone -O x86_64-efi --modules="part_gpt part_msdos fat iso9660" \
		--locales="" --themes="" --fonts="" \
		"boot/grub/grub.cfg=$WORK/grub-embed.cfg" -o "$WORK/bootx64.efi"
	run dd if=/dev/zero of="$ISO_DIR/boot/grub/efi.img" bs=1M count=16 status=none
	run mkfs.vfat -n ITTYGOS_EFI "$ISO_DIR/boot/grub/efi.img"
	run mmd -i "$ISO_DIR/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
	run mcopy -i "$ISO_DIR/boot/grub/efi.img" "$WORK/bootx64.efi" ::/EFI/BOOT/BOOTX64.EFI

	say "building the hybrid ISO"
	run xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "ITTYGOS" \
		-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
		-eltorito-boot isolinux/isolinux.bin -eltorito-catalog isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
		-output "$OUT/$ISO_NAME" "$ISO_DIR"
	if [ "$DRY_RUN" != 1 ]; then
		( cd "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
		say "ready: $OUT/$ISO_NAME ($(du -h "$OUT/$ISO_NAME" | cut -f1))"
		[ -d /mnt/c ] && say "copy to Windows:  cp $OUT/$ISO_NAME /mnt/c/WSL/"
	fi
}

cmd_clean() {
	need_root clean
	umount_chroot
	run rm -rf "$WORK"
}

case "${1:-}" in
	setup) cmd_setup ;;
	bootstrap) cmd_bootstrap ;;
	configure) cmd_configure ;;
	shell) cmd_shell ;;
	iso) cmd_iso ;;
	all) cmd_bootstrap; cmd_configure; cmd_iso ;;
	clean) cmd_clean ;;
	*) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
