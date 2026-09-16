#!/bin/sh
set -eu
INPUT=${1:?Pass the original reference screenshot}
OUTPUT=${2:-Tools/Release/HomeMotion/Studio/assets/preview-wallpaper.png}
EXPECTED="6e33ecaf36aed47606207d28d1b826b864efa75bcacd8f1c5d95b19c71761173"
ACTUAL=$(shasum -a 256 "$INPUT" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'This cleanup recipe is only for the measured reference screenshot.' >&2; exit 1; }
ffmpeg -v error -i "$INPUT" -vf 'delogo=x=1170:y=145:w=600:h=340:show=0,delogo=x=1280:y=1480:w=480:h=350:show=0,delogo=x=2630:y=4:w=304:h=65:show=0,scale=1470:956' -map_metadata -1 -frames:v 1 -y "$OUTPUT"
