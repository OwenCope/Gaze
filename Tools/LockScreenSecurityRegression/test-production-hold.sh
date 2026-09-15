#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
node - "$ROOT" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = process.argv[2];
const backend = fs.readFileSync(`${root}/Sources/Security/UnlockBackend.swift`, 'utf8');
const submission = backend.slice(backend.indexOf('func submitPassword('));
assert(submission.indexOf('try PasswordReplaySafety.requireEnabled()') < submission.indexOf('readPassword: PasswordVault.password'));
assert(submission.indexOf('try PasswordReplaySafety.requireEnabled()') >= 0);
const watcher = fs.readFileSync(`${root}/Sources/Security/LockWatcher.swift`, 'utf8');
const lockAttempt = watcher.slice(watcher.indexOf('private func attemptUnlock('));
const modelReady = lockAttempt.indexOf('if let antiSpoof, !antiSpoof.isActive');
const cameraStart = lockAttempt.indexOf('await camera.start(pinnedDeviceID: pinnedCamera)');
assert(modelReady >= 0 && cameraStart > modelReady, 'required PAD is loaded and validated before opening the camera');
assert.match(lockAttempt.slice(modelReady, cameraStart), /guard requestIsCurrent\(\) else/, 'revalidate the attempt after synchronous model loading');
const recognitionTest = fs.readFileSync(`${root}/Sources/Enrollment/RecognitionTestView.swift`, 'utf8');
const recognitionStatus = recognitionTest.slice(recognitionTest.indexOf('private var statusText: String'));
assert(recognitionStatus.indexOf('camera.lastFrameCapturedAt == nil') >= 0 && recognitionStatus.indexOf('camera.lastFrameCapturedAt == nil') < recognitionStatus.indexOf('camera.faceMissing'), 'waiting for first capture must not be reported as no face');
assert(recognitionTest.includes('camera.analyzedFrames') && recognitionTest.includes('camera.expiredFrames'), 'recognition details distinguish analyzed and expired frames');
const camera = fs.readFileSync(`${root}/Sources/Camera/CameraController.swift`, 'utf8');
assert(camera.includes('init(accessScope: CameraSessionGate.Scope = .foreground)'));
assert(camera.indexOf('guard sessionGate.begin(') < camera.indexOf('await requestAccess()'));
assert.match(camera, /self\.lease\.generation == generation,\s*self\.sessionGate\.isValid else/);
assert.match(camera, /func stop\(\) \{\s*sessionGate.end\(\)/);
assert(lockAttempt.includes('CameraController(accessScope: .lockScreen)'));
assert(!lockAttempt.includes('presentSince') && !lockAttempt.includes('faceSince'), 'successful-match time must not count as continuous mismatch');
assert(lockAttempt.includes('rejectionHold.consume(capturedAt: sampleCapturedAt, required: .seconds(Self.rejectAfter))'));
assert.match(lockAttempt, /rejectionHold.reset\(\)\s*if let decision = result.spoofDecision/, 'a matching identity clears the rejection timer before PAD processing');
assert(lockAttempt.includes('RecognitionScanPacing.delay(since: previousPoll, now: .now)'), 'recognition work counts toward polling interval');
assert(!lockAttempt.includes('Task.sleep(for: .milliseconds(60))'), 'slow evaluation must not be followed by an unconditional 60ms sleep');
assert.match(lockAttempt, /guard result.matched, let face = result.face else \{\s*matchingHold.reset\(\)[\s\S]*?resetMovementGuidance\(reason: "identity mismatch"\)/, 'low identity scores still invalidate all unlock proof');
assert.match(lockAttempt, /let consumption = challenge.consume\(sample\)\s*if consumption.poseSourceInvalidated \{\s*matchingHold.reset\(\)\s*rejectionHold.reset\(\)\s*resetMovementGuidance\(reason: "pose source changed"\)\s*continue/, 'pose source changes clear identity hold and all movement proof before completion');
const presence = fs.readFileSync(`${root}/Sources/Security/PresenceWatcher.swift`, 'utf8');
assert.match(presence, /while ContinuousClock.now < deadline \{\s*guard camera.state == .running else \{ return false \}/);
assert(presence.includes('camera.absence == .noFace') && presence.includes('capturedAt.duration(to: now) <= CameraFrameLease.maximumAge'));
assert(!watcher.includes('scanOnlyAttemptStarted'), 'scan-only remains available after the first lock/wake cycle');
assert.match(watcher, /guard UnlockExecutionPolicy.current.permitsPasswordSubmission else/);
assert.match(watcher, /private func beginAttempt[^\{]*\{\s*guard UnlockExecutionPolicy.current.permitsScanning\(passwordReplayEnabled: PasswordReplaySafety.isEnabled/);
assert.match(watcher, /func contextIsCurrent\(\)[\s\S]*?UnlockExecutionPolicy.current.permitsScanning\(passwordReplayEnabled: PasswordReplaySafety.isEnabled/);
assert.match(watcher, /guard attempt == nil else \{ return \}/, 'duplicate wake cannot restart an active scan');
assert.match(watcher, /if self.attemptID == identifier \{\s*self.attempt = nil\s*self.attemptID = nil/, 'old cancelled attempt cannot clear a newer task');
assert.match(watcher, /challenge\?\.prepareBaseline\(sample\)/);
assert.match(watcher, /if !challengeGate.isPresented \{\s*guard challenge.isBaselineReady else \{ continue \}/);
assert.match(watcher, /func resetMovementGuidance\(reason: String\) \{\s*challenge\?\.reset\(\)\s*guard challengeGate.reset\(\) else \{ return \}\s*report\(.scanning\)\s*capsule.update\(phase: .challenge\(prompt: "Face the camera to retry", symbol: "viewfinder",\s*hintX: 0, hintY: 0, pulses: false\)\)\s*StateBroadcast.post\(.detecting\)/);
for (const reason of ['frame gap', 'face unavailable', 'frame quality', 'camera continuity', 'stale inference', 'identity mismatch', 'identity changed']) {
  assert(watcher.includes(`resetMovementGuidance(reason: "${reason}")`), `${reason} withdraws stale movement guidance`);
}
const app = fs.readFileSync(`${root}/Sources/App/GazeApp.swift`, 'utf8');
assert(app.indexOf('Self.executionPolicy.permitsBrowserApproval') < app.indexOf('if Self.executionPolicy == .scanOnly'), 'browser listener starts before scan-only returns');
const approval = fs.readFileSync(`${root}/Sources/Browser/GazeBrowserApproval.swift`, 'utf8');
assert.match(approval, /guard session.isValid else/);
assert.match(approval, /session.isValid && requestLease.permits\(request\)/);
assert.match(approval, /session.onInvalidation = \{ camera.stop\(\); panel.close\(\) \}/);
assert.match(approval, /if consumption.poseSourceInvalidated \{\s*hold.reset\(\); challenge.reset\(\); gate.reset\(\); panel.motion = .scanning\s*continue/, 'browser approval also discards wider proof on a pose source change');
assert.match(approval, /if !gate.isPresented \{\s*guard challenge.isBaselineReady else \{ continue \}/);
assert.match(app, /case .keystroke:\s*guard PasswordReplaySafety.isEnabled else \{ return \}/);
const browser = fs.readFileSync(`${root}/Tools/GazePasswords/Live/PasswordBrowserService.swift`, 'utf8');
for (const name of ['handleSave', 'handleRequest']) {
  const start = browser.indexOf(`private func ${name}(`);
  assert(start >= 0, `${name} exists`);
  const next = browser.indexOf('\n\tprivate func ', start + 1);
  const handler = browser.slice(start, next < 0 ? undefined : next);
  const gate = handler.indexOf('guard consoleSession.isValid');
  const activate = handler.indexOf('activateVault()');
  assert(gate >= 0 && activate >= 0 && gate < activate, `${name} checks the console before activating the vault`);
}
assert.match(browser, /guard !cancelled, consoleSession.isValid, !store.isLocked/);
const native = fs.readFileSync(`${root}/Tools/GazePasswords/NativeHost/NativeBridgeExchange.swift`, 'utf8');
assert(native.indexOf('try check()') < native.indexOf('try await launch()'), 'native bridge checks unlocked session before launch');
assert.match(native, /session.onInvalidation = \{ cancellation.cancel\(\) \}/);
const main = fs.readFileSync(`${root}/Tools/GazePasswords/NativeHost/BrowserBridgeMain.swift`, 'utf8');
assert(main.indexOf('guard session.isValid') < main.indexOf('try NativeMessageChannel.write(response'), 'native bridge rechecks session before output');
console.log('Production-wiring checks passed: frame diagnostics, PAD startup ordering, prepared guidance, duplicate-wake protection, explicit opt-in, scanning/browser coexistence and session gates present.');
NODE
