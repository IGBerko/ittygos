# helpers for the hooks (run inside the chroot)
export DEBIAN_FRONTEND=noninteractive
CFG=/tmp/ittygos/config

say() { printf '  -> %s\n' "$*"; }

# names from a list file, comments and empty lines removed
list_names() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1"; }

# can apt really install it? (a known name may still have "Candidate: (none)")
has_candidate() {
	c=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
	[ -n "$c" ] && [ "$c" != "(none)" ]
}

# One package per line. "a|b" means: the first one that exists (names differ between releases).
# Prints the chosen names, one per line. Exits with a list of everything that was not found.
resolve_list() {
	missing=
	for entry in $(list_names "$1"); do
		found=
		for p in $(echo "$entry" | tr '|' ' '); do
			if has_candidate "$p"; then found=$p; break; fi
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

# optional packages: installed one by one when available, skipped (with a note) otherwise
pkg_install_optional() {
	for p in $(list_names "$1"); do
		if has_candidate "$p"; then
			apt-get install -y --no-install-recommends "$p" || echo "note: could not install the optional package $p" >&2
		else
			echo "note: optional package $p is not available in this release: skipped"
		fi
	done
}
