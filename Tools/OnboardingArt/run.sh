#!/bin/bash
# Tools/OnboardingArt/run.sh — deterministic build + run of the onboarding artwork generator.
#
# Compiles the generator together with the REAL companion renderer sources
# (verbatim, no copies) and renders the 11 tour PNGs into Resources/Art,
# plus a contact sheet and manifest. No app launch, no camera, no screenshots.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Resources/Art"
WORK="$ROOT/build/vera-7"
BIN="$WORK/OnboardingArtGenerate"

mkdir -p "$WORK"

# The Command Line Tools toolchain compiles this; if a beta toolchain is ever
# needed (see AGENTS.md), prefix with DEVELOPER_DIR=... — the variable passes
# through to the toolchain lookup below.
if [ -n "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR
fi

swiftc -O -o "$BIN" \
  "$ROOT/Tools/OnboardingArt/Generate.swift" \
  "$ROOT/Sources/Companion/GazeCompanionShader.swift" \
  "$ROOT/Sources/Companion/GazeCompanionMotion.swift" \
  "$ROOT/Sources/Companion/GazeCompanionRenderer.swift" \
  "$ROOT/Sources/Companion/GazeCompanionView.swift" \
  "$ROOT/Sources/Companion/GazeRenderDiagnostics.swift" \
  "$ROOT/Sources/LockScreen/GazeFaceMark.swift"

"$BIN" "$OUT" "$WORK"
