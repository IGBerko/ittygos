# helpers for the hooks (run inside the chroot)
export DEBIAN_FRONTEND=noninteractive
CFG=/tmp/ittygos/config

say() { printf '  -> %s\n' "$*"; }

# names from a list file, comments and empty lines removed
list_names() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1"; }

# One package per line. "a|b" means: the first one that exists (names differ between releases).
# Prints the chosen names, one per line. Exits with a list of everything that was not found.
resolve_list() {
	missing=
	for entry in $(list_names "$1"); do
		found=
		for p in $(echo "$entry" | tr '|' ' '); do
			if apt-cache show "$p" >/dev/null 2>&1; then found=$p; break; fi
		done
		if [ -n "$found" ]; then echo "$found"; else missing="$missing $entry"; fi
	done
	if [ -n "$missing" ]; then
		echo "ERROR: packages not found in the repositories (fix $(basename "$1")):$missing" >&2
		return 1
	fi
}

# install a list; every name is checked first so all typos show up at once
pkg_install() {
	names=$(resolve_list "$1") || exit 1
	# shellcheck disable=SC2086
	apt-get install -y --no-install-recommends $names
}
