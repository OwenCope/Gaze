#!/bin/bash
# Build the secret-free fixture bundle. Uses the ACTUAL staged component
# (../readme-editor.tsx) via esbuild aliases — no copy, no real notes.
# Run from Tools/Release/NotesVersioning/fixture/.
set -euo pipefail
cd "$(dirname "$0")"
# Resolve react/react-dom from the real site install (read-only); the fixture
# itself vendors nothing and stores no notes.
export NODE_PATH="${GAZE_SITE_NODE_MODULES:-/Users/owencope/Developer/gaze-site/node_modules}"
npx --yes esbuild@0.28.2 entry.tsx --bundle \
  --outfile=app.js \
  --format=iife \
  --platform=browser \
  --jsx=automatic \
  --log-level=warning \
  --alias:next/navigation=./stubs/next-navigation.js \
  --alias:@/components/ui/liquid-glass-button=./stubs/liquid-button.jsx
echo "built $(ls -l app.js | awk '{print $9, $5}')"
