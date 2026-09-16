#!/bin/sh
set -eu
cd "$(dirname "$0")"
SITE=${GAZE_SITE_DIR:-/Users/owencope/Developer/gaze-site}
export NODE_PATH="$SITE/node_modules"
npx --yes esbuild@0.28.2 entry.jsx --bundle --outfile=app.js --format=iife --platform=browser --jsx=automatic --log-level=warning --alias:@="$SITE/src" --alias:next/navigation=./navigation.js
