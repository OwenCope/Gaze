#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
OUT="$ROOT/build/multiface-check"
APP="$OUT/MultiFaceCheck.app"
mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK_FLAGS=()
SDK="$(oldest_usable_sdk | awk '{print $1}')"
[ -n "$SDK" ] && SDK_FLAGS=(-sdk "$SDK")

fetch_face() {
	curl -sL -A 'Mozilla/5.0' "https://thispersondoesnotexist.com/random-person.jpeg?t=$RANDOM" -o "$1"
}
[ -s "$OUT/A.jpg" ] || fetch_face "$OUT/A.jpg"
[ -s "$OUT/B.jpg" ] || { sleep 2; fetch_face "$OUT/B.jpg"; }
tries=0
while cmp -s "$OUT/A.jpg" "$OUT/B.jpg" && [ "$tries" -lt 3 ]; do
	sleep 2
	fetch_face "$OUT/B.jpg"
	tries=$((tries + 1))
done

xcrun swiftc -warnings-as-errors ${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} -target "$(host_target)" \
	"$ROOT/Sources/Recognition/FaceEmbedder.swift" \
	"$ROOT/Sources/Recognition/FaceAligner.swift" \
	"$ROOT/Tests/MultiFace/main.swift" \
	-o "$APP/Contents/MacOS/MultiFaceCheck"

# Bundle.main lookup needs the model beside the binary, so stage it into the
# tool bundle: prefer the app build, fall back to a prebuilt compiled model.
if [ -d "$ROOT/build/Gaze.app/Contents/Resources/FaceEmbedding.mlmodelc" ]; then
	rm -rf "$APP/Contents/Resources/FaceEmbedding.mlmodelc"
	cp -R "$ROOT/build/Gaze.app/Contents/Resources/FaceEmbedding.mlmodelc" "$APP/Contents/Resources/"
elif [ -d "$ROOT/Resources/FaceEmbedding.mlmodelc" ]; then
	rm -rf "$APP/Contents/Resources/FaceEmbedding.mlmodelc"
	cp -R "$ROOT/Resources/FaceEmbedding.mlmodelc" "$APP/Contents/Resources/"
else
	echo "  ! no FaceEmbedding.mlmodelc staged — check runs on the landmark fallback" >&2
fi

"$APP/Contents/MacOS/MultiFaceCheck" "$OUT"
