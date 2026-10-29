# helpers for the hooks (run inside the chroot)
export DEBIAN_FRONTEND=noninteractive
CFG=/tmp/ittygos/config

say() { printf '  -> %s\n' "$*"; }

# names from a list file, comments and empty lines removed
list_names() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1"; }

# install a list; first check that every name exists so one typo shows up immediately
pkg_install() {
	f=$1
	missing=
	for p in $(list_names "$f"); do
		apt-cache show "$p" >/dev/null 2>&1 || missing="$missing $p"
	done
	if [ -n "$missing" ]; then
		echo "ERROR: packages not found in the repositories (fix $(basename "$f")):$missing" >&2
		exit 1
	fi
	# shellcheck disable=SC2046
	apt-get install -y --no-install-recommends $(list_names "$f")
}
