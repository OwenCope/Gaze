# Gaze status notifications

Gaze can tell other apps on the Mac what it is doing, so an app like DynamicLake can show matching UI in its own island.

## Turning it on

The feed is off by default. The person using Gaze turns it on in Settings, General, This Mac: **Share status with other apps**. While it is off, Gaze posts nothing, not even `hello`.

## Notifications

Every notification is posted on `DistributedNotificationCenter.default()` with `object` set to nil. The name is `com.gazeunlock.Gaze.status.` followed by the event.

| Event | When | Extra keys |
| --- | --- | --- |
| `hello` | Gaze starts, or the feed is turned on | `appVersion` |
| `state` | Reply to `request` | `phase`, plus the extras of the current phase |
| `screenLocked` | The screen locks | |
| `screenUnlocked` | The screen unlocks | `by`: `gaze` or `other` (absent if unknown) |
| `scanStarted` | Gaze starts looking for a face | |
| `scanStopped` | Gaze stops looking | |
| `challenge` | Gaze asks for a movement | `movement`: `nod`, `turnLeft`, `turnRight`, `blink`, `openMouth`, `followLight` |
| `recognised` | The face matched, before the Mac unlocks | |
| `notRecognised` | No match | |
| `spoofRejected` | A photo, screen or mask was rejected | |
| `unavailable` | Gaze can't check faces right now | `reason`: `paused`, `lockedOut`, `passwordChanged`, `cameraNotResponding`, `recognitionUnavailable`, `passwordEntryFailed`, `other` |
| `appLockShown` | App Lock covers an app | `bundleID` of that app |
| `appLockUnlocked` | App Lock lets the person in | `bundleID` of that app |

Every `userInfo` also has `version` (Int, currently 1) and `timestamp` (Double, seconds since 1970). All values are strings or numbers.

`phase` in `state` is one of `idle`, `locked`, `scanning`, `challenge`, `recognised`, `notRecognised`, `spoofRejected`, `unavailable`, `appLocked`.

## Syncing when your app starts

Post `com.gazeunlock.Gaze.status.request` with no `userInfo`. If the feed is on, Gaze answers with `state`.

## Example

```swift
let center = DistributedNotificationCenter.default()
let prefix = "com.gazeunlock.Gaze.status."
for event in ["state", "screenLocked", "screenUnlocked", "scanStarted", "scanStopped",
              "challenge", "recognised", "notRecognised", "spoofRejected", "unavailable"] {
    center.addObserver(forName: .init(prefix + event), object: nil, queue: .main) { note in
        let info = note.userInfo ?? [:]
        print(event, info["phase"] ?? "", info["movement"] ?? "", info["reason"] ?? "")
    }
}
center.postNotificationName(.init(prefix + "request"), object: nil, userInfo: nil, deliverImmediately: true)
```

## Versions

`version` changes only when a key is removed, renamed or changes meaning. New events, new keys and new values can arrive within a version, so ignore what you don't know.

## Privacy

Any process on the Mac can read distributed notifications, so the feed only says what someone looking at the screen could see. It never includes names, faces, photos, passwords, match scores, face data, file paths, the account name, or anything about who tried to unlock.
