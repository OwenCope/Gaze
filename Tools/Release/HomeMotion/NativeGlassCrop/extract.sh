#!/bin/sh
set -eu
SOURCE=${1:-/Users/owencope/Developer/gaze-site/public/clips/liquidGlass.mp4}
OUTPUT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/assets
mkdir -p "$OUTPUT"
# Reconstruct a clean studio backdrop from fixed empty wallpaper samples.
python3 "$(dirname "$0")/make_backdrop.py" "$SOURCE" "$OUTPUT/backdrop.png"
# Blend only the wallpaper below the native panel, leaving the material intact.
ffmpeg -v error -framerate 30 -loop 1 -i "$OUTPUT/backdrop.png" -i "$SOURCE" \
  -filter_complex "[1:v]fps=30,trim=duration=4.5,setpts=PTS-STARTPTS,crop=240:128:520:0,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lt(Y,100),255,max(0,(128-Y)*255/28))',scale=400:214[panel];[0:v][panel]overlay=280:0:shortest=1,fps=30,format=yuv420p[out]" \
  -map '[out]' -frames:v 135 -c:v libx264 -crf 18 -preset medium -movflags +faststart -an -y "$OUTPUT/gaze-panel-native-liquid-glass.mp4"
ffmpeg -v error -ss 1 -i "$OUTPUT/gaze-panel-native-liquid-glass.mp4" -frames:v 1 -y "$OUTPUT/gaze-panel-native-liquid-glass-poster.png"
ffmpeg -v error -i "$OUTPUT/gaze-panel-native-liquid-glass.mp4" -f null -
