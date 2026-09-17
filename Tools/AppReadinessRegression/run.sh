#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/toolchain.sh"
require_toolchain
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gaze-readiness.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/Sources/GazeReadiness" "$FIXTURE/Tests/GazeReadinessTests"
cp "$ROOT/Sources/App/ReleaseUpdateChecker.swift" "$ROOT/Sources/App/ReleaseURLPolicy.swift" \
   "$ROOT/Sources/App/DesktopWallpaper.swift" "$FIXTURE/Sources/GazeReadiness/"
cp "$ROOT/Tools/AppReadinessRegression/ThemeStub.swift" "$FIXTURE/Sources/GazeReadiness/"
cp "$ROOT/Tools/AppReadinessRegression/Tests.swift" "$FIXTURE/Tests/GazeReadinessTests/"
cat > "$FIXTURE/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GazeReadiness", platforms: [.macOS("26.0")], targets: [
    .target(name: "GazeReadiness"),
    .testTarget(name: "GazeReadinessTests", dependencies: ["GazeReadiness"])
])
SWIFT
# Actual production files, Swift 6 strict concurrency, isolated preferences and fake HTTP.
# Never constructs DesktopWallpaper.shared or starts Gaze, camera, or authentication.
xcrun swift test --package-path "$FIXTURE" --scratch-path "$ROOT/build/app-readiness-regression" --jobs 2
