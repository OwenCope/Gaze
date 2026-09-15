#!/bin/bash

gaze_signing_identity() {
	local mode="$1" requested="$2" identities="$3" selected
	selected="$(printf '%s\n' "$identities" | awk -v mode="$mode" -v requested="$requested" '
		$1 ~ /^[0-9]+\)$/ && length($2) == 40 && $2 !~ /[^[:xdigit:]]/ {
			name = $0
			sub(/^[^"]*"/, "", name)
			sub(/".*$/, "", name)
			eligible = name ~ /^Developer ID Application: / || (mode != "1" && name ~ /^Apple Development: /)
			if (eligible && (requested == "" || requested == $2 || requested == name)) {
				print $2
				exit
			}
		}')"
	if [ -z "$selected" ]; then
		if [ "$mode" = "1" ]; then
			echo "Release signing requires a valid Developer ID Application identity. Ad-hoc and Apple Development signatures are not accepted." >&2
			echo "Local builds can continue with an Apple Development identity. For public release, use Apple Developer Program membership to create a Developer ID Application certificate (Xcode > Settings > Accounts > Manage Certificates, or developer.apple.com), install it in the login keychain, then rerun with DIST=1 GAZE_SIGNING_IDENTITY=\"Developer ID Application: <Name> (<Team ID>)\". List installed identities with: security find-identity -v -p codesigning. Notarization and stapling are still required before Tools/Release/verify.sh passes." >&2
		else
			echo "Local builds require a valid stable Apple Development or Developer ID Application identity; the existing app was not replaced." >&2
		fi
		return 1
	fi
	printf '%s\n' "$selected"
}
