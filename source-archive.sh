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

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
OUT="$ROOT/build/Gaze-$VERSION-source.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Excluded from the archive, by path prefix.
#
# The recognition model is the important one. It is cshariq's, from Sapphire,
# and its licence is unknown — so it is not ours to hand out under MIT. Shipping
# it inside an archive that says MIT on the front would be claiming a grant
# nobody gave.
EXCLUDE=(
	"Resources/FaceEmbedding.mlpackage/"
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

cat > "$STAGE/src/NOTICE.md" <<'NOTICE'
# What is not in here

This archive is the source of Gaze, under the MIT licence in `LICENSE`. Two
things are deliberately missing, and the app will build without them.

## The recognition model

`Resources/FaceEmbedding.mlpackage` — the model faces are matched against. It
comes from Sapphire, by cshariq, and is not ours to redistribute. Without it
the app falls back to comparing facial landmarks directly, which is much
weaker: it can tell you from a stranger, and not much more.

## FaceIDKit

The animations in setup are Aviorrok's, licensed to this app alone and
explicitly not for redistribution. `SetupMark` substitutes system symbols when
the framework is absent, so setup works and simply looks plainer.

## What that means for building

`./build.sh` states which of these it found and carries on without either. The
app you get is the app minus those two things, not a broken one.
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
for pattern in "FaceIDKit" "mlpackage" "Frameworks/"; do
	if unzip -l "$OUT" | grep -qi "$pattern"; then
		echo "  ✗ $pattern is in the archive" >&2
		leaked=1
	fi
done
[ -n "$leaked" ] && exit 1

echo "  ✓ nothing that shouldn't be"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
