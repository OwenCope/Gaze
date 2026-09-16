#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SITE_DIR="${GAZE_SITE_DIR:-/Users/owencope/Developer/gaze-site}"
export NODE_PATH="$SITE_DIR/node_modules"
npx --yes esbuild@0.28.2 entry.tsx --bundle --outfile=app.js --format=iife --platform=browser --jsx=automatic --log-level=warning --alias:@fixture/release-composer="$SITE_DIR/src/components/release-composer.tsx" --alias:next/navigation=./router.js --alias:@vercel/blob/client=./upload.js --alias:@/components/ui/liquid-glass-button=./button.jsx
