#!/bin/bash

collect_gaze_main_sources() {
	local root="$1"
	local source
	GAZE_MAIN_SOURCES=()
	for source in "$root"/Sources/*/*.swift; do
		case "$source" in
			"$root"/Sources/Autofill/*|"$root"/Sources/App/AutofillSettings.swift|"$root"/Sources/Security/FaceCheck.swift) continue ;;
		esac
		GAZE_MAIN_SOURCES+=("$source")
	done
	# Vendored TourKit onboarding source (see ThirdParty/TourKit/SOURCE.json).
	# Compiled into the Gaze module directly; there is no separate TourKit module.
	GAZE_MAIN_SOURCES+=("$root/ThirdParty/TourKit/TourKit.swift")
}
