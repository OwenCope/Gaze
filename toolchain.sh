# Locates a toolchain that can build this project. Sourced, not run.
#
# There was a hardcoded `DEVELOPER_DIR=/Applications/Xcode-beta.app/...` here, which is
# only true on the machine it was written on — everyone else got
#
#     xcrun: error: missing DEVELOPER_DIR path: /Applications/Xcode-beta.app/Contents/Developer
#
# before a single file compiled. Nothing about this project needs the beta specifically; it
# needs *some* install that meets two requirements, so look for one rather than assuming.
#
#   1. The macOS 26 SDK. The app targets macOS 26 and uses APIs from it (`glassEffect`,
#      `.symbolEffect(.replace.magic)`), so an older SDK cannot compile it.
#   2. A full Xcode. Command Line Tools ships an SDK but no `coremlc`, and the recognition
#      model has to be compiled — without it the app silently falls back to landmark
#      geometry, which is much weaker.

MIN_SDK_MAJOR=26

# Major version of the macOS SDK a given developer directory provides, or nothing.
_sdk_major() {
	local version
	version="$(DEVELOPER_DIR="$1" xcrun --show-sdk-version --sdk macosx 2>/dev/null)" || return 1
	printf '%s' "${version%%.*}"
}

# Prints the first developer directory that satisfies both requirements.
#
# Order is deliberate: an explicit `DEVELOPER_DIR` wins, then whatever `xcode-select` points
# at, then anything installed. That way setting the variable is always an override rather
# than a suggestion, and the common case — one Xcode, selected — needs no configuration.
find_developer_dir() {
	local candidates=() dir app major

	[ -n "${DEVELOPER_DIR:-}" ] && candidates+=("$DEVELOPER_DIR")

	dir="$(xcode-select -p 2>/dev/null)" || dir=""
	[ -n "$dir" ] && candidates+=("$dir")

	# Any Xcode, release or beta, under whatever name it was installed as.
	for app in /Applications/Xcode*.app; do
		[ -d "$app/Contents/Developer" ] && candidates+=("$app/Contents/Developer")
	done

	# `${a[@]+...}` because macOS still ships bash 3.2, where expanding an empty array
	# under `set -u` is an error rather than nothing.
	for dir in ${candidates[@]+"${candidates[@]}"}; do
		[ -d "$dir" ] || continue

		major="$(_sdk_major "$dir")" || continue
		[ -n "$major" ] || continue
		[ "$major" -ge "$MIN_SDK_MAJOR" ] || continue

		# Rejects Command Line Tools, which satisfies the SDK check but has no coremlc.
		DEVELOPER_DIR="$dir" xcrun -f coremlc >/dev/null 2>&1 || continue

		printf '%s' "$dir"
		return 0
	done

	return 1
}

# Sets and exports DEVELOPER_DIR, or explains what to install and stops.
require_toolchain() {
	local found
	if found="$(find_developer_dir)"; then
		export DEVELOPER_DIR="$found"
		return 0
	fi

	cat >&2 <<-EOF
	✗ No Xcode with the macOS ${MIN_SDK_MAJOR} SDK was found.

	  Face ID targets macOS ${MIN_SDK_MAJOR}, so it needs Xcode ${MIN_SDK_MAJOR} or newer. Command Line
	  Tools on its own is not enough — coremlc, which compiles the recognition
	  model, ships only with the full Xcode.

	  Once it's installed:
	      sudo xcode-select -s /Applications/Xcode.app

	  Or point this build at one directly:
	      DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer $0
	EOF
	exit 1
}

# The architecture of the machine doing the building.
#
# This was pinned to arm64, which fails on an Intel Mac for no reason — nothing in the
# project is Apple silicon-specific.
host_target() {
	printf '%s-apple-macos%s.0' "$(uname -m)" "$MIN_SDK_MAJOR"
}
