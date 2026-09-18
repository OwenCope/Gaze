# Live acceptance

`ObserveSession.swift` records lock/unlock and sleep/wake notifications alongside
the current console session flags. It does not lock, unlock, enter credentials,
change preferences, capture screens, or access the camera. Keep outputs under
`build/`; they are local test evidence.

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library Tools/Release/LiveAcceptance/ObserveSession.swift -o build/ObserveSession
    build/ObserveSession build/session-events.jsonl 1200

Correlate these observations with Gaze's LockWatcher logs and the owner's result
for each case. A notification alone is not proof that Gaze caused an unlock; a
password-submission log alone is not proof that macOS unlocked.

Record the executable hash, macOS build, camera, movement count, and timestamps.
Run normal recognition, an immediate relock, display sleep/wake, a covered camera,
an omitted movement, manual-input interruption, and disabled-unlock fallback.
The owner performs movements and enters any manual password privately. Never
record the password field, alter the stored password, or count fixture tests as
live outcomes. Close each case as pass, fail, or not run with its evidence.
