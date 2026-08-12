# Integrating with Face ID

Face ID publishes what it is doing so other apps — notch apps especially — can show it in
their own interface. Two apps drawing a panel over the same strip of screen is worse for the
user than one, and the one that already owns that strip should win.

## The notification

Name: `app.faceid.FaceID.state`, on `DistributedNotificationCenter`.

```swift
DistributedNotificationCenter.default().addObserver(
    forName: .init("app.faceid.FaceID.state"), object: nil, queue: .main
) { note in
    guard let state = note.object as? String else { return }
    let score = note.userInfo?["score"] as? Double
    // state: "idle" | "locked" | "detecting" | "succeeded" | "failed" | "lockedOut"
}
```

The state is in `object`, not only in `userInfo`. That is on purpose: `userInfo` is the part
of a distributed notification that gets dropped first, and it is discarded outright for
sandboxed observers on some paths. Read `object` and you always get the state; read
`userInfo` for the extras when they survive.

## States

| State | Meaning |
| --- | --- |
| `idle` | Nothing happening. The Mac is unlocked, or Face ID is off. |
| `locked` | Screen locked, Face ID armed, no face seen yet. |
| `detecting` | A face is in frame and being matched. |
| `succeeded` | Recognised. The unlock, if configured, is happening now. |
| `failed` | Not recognised within the search window, or rejected by the liveness check. |
| `lockedOut` | Too many failures. Disabled until an account password is entered. |

`userInfo["score"]` carries the cosine similarity on `succeeded`, as a `Double`. Absent
otherwise.

Transitions are deduplicated — `detecting` is posted once when a face appears, not on every
frame. `locked` always precedes `detecting` for a given attempt.

## What it deliberately does not do

It is one-way. Nothing on this channel can start an unlock, read a faceprint, or reach the
stored password. A subscriber learns only what someone standing behind the Mac could see by
looking at the screen.

That is a security decision rather than a missing feature: an integration point that could
*cause* an unlock would be a way to attack this app from another process, and the whole point
of the app is that unlocking is hard to trigger by accident.

## Checking it works

Save as `listen.swift` and run `swift listen.swift`, then lock the screen.

```swift
import Foundation

DistributedNotificationCenter.default().addObserver(
    forName: .init("app.faceid.FaceID.state"), object: nil, queue: .main
) { note in
    let score = (note.userInfo?["score"] as? Double).map { String(format: " %.3f", $0) } ?? ""
    print("\(Date().formatted(date: .omitted, time: .standard))  \(note.object ?? "?")\(score)")
}

RunLoop.main.run()
```

Expect `locked` when the screen locks, `detecting` when you appear, then `succeeded` or
`failed`, and `idle` once the Mac is unlocked again.

## Drawing over the same strip

The panel this app puts under the notch lives in its own SkyLight space at the lock screen
level. While it is resting it is sized to sit *inside* a typical notch app's bar rather than
overlap it, but the panel that drops out while scanning will draw over whatever is there.

If you would rather draw the state yourself, subscribe to the notification and turn this
app's panel off — that switch does not exist yet. Ask, and it will.
