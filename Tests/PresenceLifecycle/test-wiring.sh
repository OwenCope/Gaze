#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
node - "$ROOT" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = process.argv[2];
const app = fs.readFileSync(`${root}/Sources/App/GazeApp.swift`, 'utf8');

const syncStart = app.indexOf('func syncPresenceWatcher()');
assert(syncStart >= 0, 'AppServices exposes syncPresenceWatcher() for the Settings toggle');
const syncEnd = app.indexOf('\n\t}', syncStart);
assert(syncEnd > syncStart, 'syncPresenceWatcher body found');
const sync = app.slice(syncStart, syncEnd);

// Decision: gated on the launch policy AND the opt-in setting, nothing else.
assert.match(sync, /permitsAutomaticLocking && Preferences\.shared\.walkAwayLock/,
	'sync runs the watcher only when the policy permits automatic locking and walkAwayLock is on');
assert(!sync.includes('PasswordReplaySafety'), 'sync is independent of password replay');
assert(!sync.includes('unlockBackend'), 'sync is independent of the unlock backend');

// No duplicate starts: an existing watcher is left alone.
assert.match(sync, /guard presenceWatcher == nil else \{ return \}/,
	'sync never starts a second watcher when one is already running');
assert(sync.indexOf('PresenceWatcher(store:') >= 0, 'sync creates a watcher when enabled');
assert.strictEqual(sync.indexOf('PresenceWatcher(store:'), sync.lastIndexOf('PresenceWatcher(store:'),
	'exactly one watcher creation site remains');

// Disable / prohibited policy: stop and clear, so a mode switch cannot leave it running.
assert(sync.includes('presenceWatcher?.stop()'), 'sync stops the watcher when it should not run');
assert.match(sync, /presenceWatcher = nil/, 'sync clears the watcher when it should not run');

// Toggle-safe: sync touches only the presence watcher, never an unlock attempt.
for (const name of ['lockWatcher', 'unlockService', 'browserApprovals', 'LockWatcher(', 'UnlockService(', 'GazeBrowserApproval(']) {
	assert(!sync.includes(name), `sync leaves ${name} alone so the toggle never restarts unlock work`);
}

// Startup ordering: startUnlockTrigger syncs before any scan-only / UI-review /
// replay / backend early return, so backend none with replay disabled still
// arms the watcher, and prohibited policies still disarm a leftover one.
const triggerStart = app.indexOf('func startUnlockTrigger()');
assert(triggerStart > syncEnd, 'startUnlockTrigger exists after sync');
const trigger = app.slice(triggerStart);
const syncCall = trigger.indexOf('syncPresenceWatcher()');
assert(syncCall >= 0, 'startUnlockTrigger calls syncPresenceWatcher');
for (const [name, marker] of [
	['scan-only early return', 'if Self.executionPolicy == .scanOnly'],
	['UI-review early return', 'guard !Self.isUIReview else'],
	['replay gate', 'guard PasswordReplaySafety.isEnabled else'],
	['backend switch', 'switch Preferences.shared.unlockBackend'],
]) {
	const at = trigger.indexOf(marker);
	assert(at >= 0, `${marker} still present`);
	assert(syncCall < at, `sync runs before the ${name}`);
}

// Old backend-specific creation is gone: nothing outside sync creates the watcher.
const rest = app.slice(0, syncStart) + app.slice(syncEnd);
assert(!rest.includes('PresenceWatcher(store:'), 'no backend-branch watcher creation remains');

// Startup path reaches it: launch calls startUnlockTrigger, whose first act is sync.
assert(app.includes('AppServices.shared.startUnlockTrigger()'), 'launch still enters startUnlockTrigger');

console.log('Presence lifecycle wiring checks passed: idempotent sync, stop/clear on disable, startup ordering before every early return.');
NODE
