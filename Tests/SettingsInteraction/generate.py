#!/usr/bin/env python3
"""Extract current Settings members verbatim; only external services are replaced."""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[2]
destination = Path(sys.argv[1])
source = (root / "Sources/App/SettingsView.swift").read_text()
members = [
    "private var behaviourSection:", "private func setLoginItemEnabled(", "private func refreshLoginItemState(",
    "private var behaviourFooter:", "private var updatesSection:",
    "private var releaseRowTitle:", "private var releaseRowDetail:",
    "private var releaseButtonTitle:", "private func releaseAction(", "private func bind(",
]

def member(anchor):
    start = source.index("\t" + anchor)
    end = source.index("\n\t}", start) + len("\n\t}")
    return source[start:end]

state_names = ["settings", "updates", "releases", "loginItemEnabled", "loginItemNeedsApproval", "loginItemError", "loginItemFailedRequest"]
state_lines = []
for name in state_names:
    matches = [line for line in source.splitlines() if line.startswith(f"\t@State private var {name} ") or line.startswith(f"\t@State private var {name}:")]
    assert len(matches) == 1, name
    state_lines.append(matches[0])

assert "refreshLoginItemState()" in member("private func refreshExternalState(")
# aboutSection moved out of SettingsView into the top-level SettingsAboutPane struct (same file).
pane_start = source.index("private struct SettingsAboutPane:")
about = source[pane_start:source.index("\n}\n", pane_start) + len("\n}")]
source_start = about.index("\t\t\tif updates.repositoryURL != nil {")
source_end = about.index("\n\t\t\t}", source_start) + len("\n\t\t\t}")
source_build = about[source_start:source_end]
assert 'title: "Source build"' in source_build

body = """import AppKit
import SwiftUI

struct SettingsFixture: View {
    enum Section { case behaviour, updates, sourceBuild }
    let section: Section
    let driver: FixtureDriver
""" + "\n".join(state_lines) + """
    var body: some View {
        Form {
            switch section {
            case .behaviour: behaviourSection
            case .updates: updatesSection
            case .sourceBuild: sourceBuildSection
            }
        }
        .formStyle(.grouped)
        .environment(\\.nativeSettingsForm, true)
        .frame(width: 668, height: 660)
        .onAppear {
            driver.changeLoginItem = setLoginItemEnabled
            driver.refresh = refreshLoginItemState
        }
        .onDisappear { driver.changeLoginItem = nil; driver.refresh = nil }
    }
""" + "\n\n".join(member(anchor) for anchor in members) + "\n    @ViewBuilder private var sourceBuildSection: some View {\n" + source_build + "\n    }\n}\n"
destination.write_text(body)
destination.with_suffix(".json").write_text(json.dumps({
    "source": "Sources/App/SettingsView.swift",
    "sha256": hashlib.sha256(source.encode()).hexdigest(),
    "members": {anchor: hashlib.sha256(member(anchor).encode()).hexdigest() for anchor in members},
    "sourceBuildSectionHash": hashlib.sha256(source_build.encode()).hexdigest(),
    "limits": "Extracted native panels and handlers with fake services; not the full Settings lifecycle."
}, indent=2) + "\n")

capture = (root / "Sources/Setup/SetupCaptureStep.swift").read_text()
assert capture.count("AVCaptureDevice.") == 4
destination.with_name("CaptureFixture.swift").write_text(capture.replace("AVCaptureDevice.", "FixtureCameraAuthorization."))
destination.with_name("CaptureFixture.json").write_text(json.dumps({
    "source": "Sources/Setup/SetupCaptureStep.swift",
    "sha256": hashlib.sha256(capture.encode()).hexdigest(),
    "replacement": "AVCaptureDevice static permission calls replaced by FixtureCameraAuthorization; view and actions unchanged",
    "camera": "Tests/Onboarding/Stubs.swift"
}, indent=2) + "\n")
