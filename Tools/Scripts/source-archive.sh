#!/bin/bash
# Builds the source archive published on gazeunlock.com.
#
# Not a zip of the working directory. It is built from what git tracks, which
# means anything ignored cannot end up in it by accident — and two of the
# ignored things are other people's property that must never be redistributed:
# FaceIDKit, and whatever else lands in Frameworks/.
#
# Then two tracked things are dropped as well, because tracking is not the same
# as being ours to licence. See NOTICE below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
OUT="$ROOT/build/Gaze-$VERSION-source.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Excluded from the archive, by path prefix.
#
# The recognition model is the important one. It is InsightFace's ArcFace
# (w600k_r50) by deepinsight, first obtained via Sapphire, which bundles the
# same model; its weights are licensed for non-commercial research use — so it
# is not ours to hand out under MIT. Shipping
# it inside an archive that says MIT on the front would be claiming a grant
# nobody gave.
EXCLUDE=(
	"Resources/FaceEmbedding.mlpackage/"
	"Resources/Liveness.mlmodelc/"
	"Resources/Liveness.mlpackage/"
)

echo "→ Collecting tracked files"
mkdir -p "$STAGE/src"
count=0
while IFS= read -r file; do
	skip=""
	for prefix in "${EXCLUDE[@]}"; do
		case "$file" in "$prefix"*) skip=1 ;; esac
	done
	[ -n "$skip" ] && continue
	mkdir -p "$STAGE/src/$(dirname "$file")"
	cp "$ROOT/$file" "$STAGE/src/$file"
	count=$((count + 1))
done < <(git -C "$ROOT" ls-files)
echo "  ✓ $count files"

# The repository's own NOTICE.md is the source of truth for credits, so the archive
# carries that rather than a second copy that would drift out of step with it.
cp "$ROOT/NOTICE.md" "$STAGE/src/NOTICE.md"

cat >> "$STAGE/src/NOTICE.md" <<'NOTICE'

# What is not in this archive

The following resources are excluded from the archive. The app builds without them.

## The recognition model

`Resources/FaceEmbedding.mlpackage` — the model faces are matched against. It
is InsightFace's ArcFace (w600k_r50) by deepinsight, first obtained via
Sapphire, which bundles the same model, and is not ours to redistribute. Without it
the app falls back to comparing facial landmarks directly, which is much
weaker: it can tell you from a stranger, and not much more.

## FaceIDKit

The animations in setup are Aviorrok's, licensed to this app alone and
explicitly not for redistribution. `SetupMark` substitutes system symbols when
the framework is absent, so setup works and simply looks plainer.

## Legacy texture model

`Resources/Liveness.mlmodelc` and `Resources/Liveness.mlpackage` are excluded.
The current app does not use this model. Photo rejection uses the separate
Spoof detector, and movement challenges do not depend on the legacy weights.

## What that means for building

`./build.sh` builds with the available resources and reports a missing recognition
model. The legacy texture model is excluded from app bundles too.
NOTICE

echo "→ Packing"
mkdir -p "$ROOT/build"
rm -f "$OUT"
(cd "$STAGE/src" && zip -qr "$OUT" .)

# Belt and braces. The exclusion above is a string comparison, and a rename
# upstream would silently defeat it — so the finished archive is inspected for
# the things that must not be in it rather than trusted to be right.
echo "→ Checking"
leaked=""
for pattern in "FaceIDKit" "mlpackage" "Frameworks/" "Resources/Liveness.mlmodelc/"; do
	if unzip -l "$OUT" | grep -qi "$pattern"; then
		echo "  ✗ $pattern is in the archive" >&2
		leaked=1
	fi
done
[ -n "$leaked" ] && exit 1

echo "  ✓ nothing that shouldn't be"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
