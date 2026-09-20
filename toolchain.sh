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

	  Gaze targets macOS ${MIN_SDK_MAJOR}, so it needs Xcode ${MIN_SDK_MAJOR} or newer. Command Line
	  Tools on its own is not enough — coremlc, which compiles the recognition
	  model, ships only with the full Xcode.

	  Once it's installed:
	      sudo xcode-select -s /Applications/Xcode.app

	  Or point this build at one directly:
	      DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer $0
	EOF
	exit 1
}

# The oldest macOS SDK on this machine that can still build the project, and its version.
#
# For distribution, not for day-to-day builds. Compiling against the newest SDK installed
# is right when the only Mac that runs the result is this one; hand the build to someone a
# major version behind and it can reference symbols their system does not have, and their
# Mac kills it at launch with no dialog and no crash report.
#
# Command Line Tools is a fine source here even though `find_developer_dir` rejects it —
# that rejection is about `coremlc`, which the model compile still gets from a full Xcode.
# This only needs headers and stubs to link against.
#
# Prints "<path> <version>", or nothing if the only SDK installed is the newest.
oldest_usable_sdk() {
	local dir sdk name version best_path="" best_version=""

	for dir in /Library/Developer/CommandLineTools /Applications/Xcode*.app/Contents/Developer; do
		for sdk in "$dir"/SDKs/MacOSX*.sdk "$dir"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk; do
			# Skip the unversioned aliases; they point at the newest, which is the
			# thing being avoided.
			[ -d "$sdk" ] || continue
			[ -L "$sdk" ] && continue

			version="$(/usr/libexec/PlistBuddy -c "Print :Version" "$sdk/SDKSettings.plist" 2>/dev/null)" || continue
			[ -n "$version" ] || continue
			[ "${version%%.*}" -ge "$MIN_SDK_MAJOR" ] 2>/dev/null || continue

			if [ -z "$best_version" ] || _version_lt "$version" "$best_version"; then
				best_version="$version"
				best_path="$sdk"
			fi
		done
	done

	[ -n "$best_path" ] && printf '%s %s' "$best_path" "$best_version"
}

# True when $1 sorts before $2 as a dotted version.
_version_lt() {
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n | head -1)" = "$1" ]
}

# The architecture of the machine doing the building.
#
# This was pinned to arm64, which fails on an Intel Mac for no reason — nothing in the
# project is Apple silicon-specific.
host_target() {
	printf '%s-apple-macos%s.0' "$(uname -m)" "$MIN_SDK_MAJOR"
}

# Every architecture a release build ships.
#
# Local builds compile only the host because the only Mac running the result is this
# one; a release is downloaded onto whatever Mac, so it carries both slices even
# though that costs a second compile.
release_targets() {
	printf '%s\n' "arm64-apple-macos${MIN_SDK_MAJOR}.0" "x86_64-apple-macos${MIN_SDK_MAJOR}.0"
}
