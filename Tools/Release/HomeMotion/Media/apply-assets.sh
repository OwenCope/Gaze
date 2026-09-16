#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SITE="${1:-/Users/owencope/Developer/gaze-site}"
[ -f "$SITE/src/app/page.tsx" ] || { echo 'Expected a gaze-site checkout' >&2; exit 1; }
mkdir -p "$SITE/public/previews" "$SITE/public/features"
for style in normal semi-liquid-glass; do
  cp "$HERE/../Studio/assets/gaze-panel-$style.mp4" "$SITE/public/previews/"
  cp "$HERE/../Studio/assets/gaze-panel-$style-poster.png" "$SITE/public/previews/"
done
for name in gaze-panel-native-liquid-glass.mp4 gaze-panel-native-liquid-glass-poster.png; do
  cp "$HERE/../NativeGlassCrop/assets/$name" "$SITE/public/previews/"
done
cp "$HERE/settings-pan.mp4" "$SITE/public/features/settings-pan.mp4"
cp "$HERE/gaze-panel-preview.vtt" "$SITE/public/previews/"
ffmpeg -hide_banner -loglevel error -ss 2.5 -i "$HERE/settings-pan.mp4" -frames:v 1 -y "$SITE/public/previews/settings-poster.png"
echo 'Copied selected preview assets locally. Nothing deployed.'
