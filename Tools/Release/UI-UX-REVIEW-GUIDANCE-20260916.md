# UI/UX review: lock-screen guidance and accessibility — 2026-09-16

Fresh product review of lock-screen guidance, requested by the owner after the
unlock improvements. Read-only sources; no thresholds, gates, broadcast,
authentication, lock, camera, password, enrollment or preference changes made.

## Scope and method

Reviewed `Sources/LockScreen/NotchCapsule.swift`,
`Sources/LockScreen/NotchCapsuleController.swift`,
`Sources/LockScreen/GazeFaceMark.swift`, `Sources/Security/LockWatcher.swift`,
`Sources/Security/LockScanDiagnostics.swift`,
`Sources/Recognition/LivenessChallenge.swift`,
`Sources/Enrollment/RecognitionTestView.swift` (+ `RecognitionTestPanel.swift`),
and `Tools/GazePreview/Tests/GuidanceCaptionTests.swift` as the render-evidence
harness. No live lock, camera, or unlock was triggered; no choppiness or
real-world reliability is inferred — static reads and offscreen renders cannot
establish either.

## Design constraint honoured throughout

Normal animated return captions are intentionally hidden
(`NotchCapsule.swift:457-459` `hidesReturnCaption`, applied at `:477-478` and
`:441` for the ear layout), and onboarding teaches returning to the starting
pose. None of the findings below recommends restoring the rejected caption.
The compensating cues are verified present and must be kept:

- Reduce Motion keeps the written return cue
  (`hidesReturnCaption` is false under Reduce Motion; asserted in
  `GuidanceCaptionTests.swift:52-57`).
- VoiceOver keeps the return instruction even when the visual caption hides:
  `GazeFaceMark.swift:114-116` labels the mark with the live `prompt`, and the
  mark is not hidden when the caption is (`NotchCapsule.swift:478` hides only
  the caption text). Do not "fix" the hidden caption by removing that label.
- Layout space is retained while hidden (opacity-0, still in hierarchy), so no
  companion resize — asserted per-layout in `GuidanceCaptionTests.swift:46-50`.

## Findings (prioritized, at most five)

### 1. Two-movement mode shows no progress — a fresh prompt reads as a reset

Evidence: `LockWatcher.swift:644` logs `requiring fresh response
\(challengeGate.completedActions + 1) of \(challengeGate.requiredActions)`,
but the capsule receives only the bare `challenge.guidancePrompt`
(`:639-643`), and `LivenessChallenge.guidancePrompt` (`LivenessChallenge.swift:95-102`)
carries no count. After movement 1 of 2 completes, the loop calls
`challenge.next()` and presents the next bare prompt (`LockWatcher.swift:665-669`)
with no intermediate "first one done" beat. The diagnostics `.movement`
message (`LockScanDiagnostics.swift:20`) is also count-blind. Given the
history — repeated prompts were read as resets — a user who finishes movement
1 and sees a new movement named with no framing will reasonably conclude the
first one failed.

Proposed improvement: surface the gate's existing count in the caption, e.g.
append "· 1 of 2" to the presented prompt (or a small progress mark beside the
symbol), reusing `challengeGate.completedActions + 1 / requiredActions`
already computed for the log. One-movement mode stays exactly as-is (no suffix).
Keep the hidden-return rule: the count applies to outward prompts and retry
captions, not to the hidden animated return.

Acceptance: offscreen renders of attached/island/ear, animated and reduced,
show the count on outward prompts in two-movement mode and none in
one-movement mode; `GuidanceCaptionTests`-style size-continuity holds (one
physical pixel tolerance); VoiceOver label includes the count; no threshold,
gate or broadcast change.

### 2. After password submission the panel shows the resting padlock — "sent, waiting" looks like "nothing happened"

Evidence: on submission the loop reports `.submissionPending` but sets
`capsule.update(phase: .locked)` (`LockWatcher.swift:707-710`) — visually
identical to the resting state. The `.success` tick phase exists
(`NotchCapsule.swift:35`) and its documented semantics are exactly this moment
("the tick is this app saying 'that was you, here is your password'",
`:38-43`), but the Mac unlock path never presents it (only `AutofillService`
and the `LockScreenShoot` harness use `.success`). The distinct
`.submissionUnconfirmed` diagnostics message exists, yet the lock screen never
distinguishes pending from idle during the grace window. A user watching the
notch sees the padlock they started with and cannot tell the attempt is in
flight.

Lead decision: show a neutral pending state labelled "Waiting for macOS"
between submission and confirmation. Do not reuse the success tick: despite the
old comment, a success symbol can be mistaken for a completed unlock. Keep the
padlock closed until the confirmed `.unlocked` event.

Acceptance: submission shows neutral waiting feedback; confirmed unlock still
shows the padlock opening; unconfirmed-expiry behavior, submission, timings and
broadcast remain unchanged.

### 3. Every guidance withdrawal shows the same retry caption, with the return cue's own symbol

Evidence: `resetMovementGuidance` always presents `"Face the camera to retry"`
with symbol `"viewfinder"` (`LockWatcher.swift:363-371`) for six different
causes (frame gap, face unavailable, frame quality, camera continuity, stale
inference, identity mismatch). `"viewfinder"` is also the return-to-rest
symbol (`LivenessChallenge.swift:103`), blurring the designed distinction
between a genuine return (deliberately captionless) and a retry (captioned).
The diagnostics layer already records the distinction the panel discards:
`recordMovementFailure` keeps `returning` (`LockWatcher.swift:550-554`), and
`MovementFailure.message` phrases phase and comparison separately
(`LockScanDiagnostics.swift:58-69`) — but that text lives in the settings
popover, not on the lock screen. A user interrupted mid-return sees the same
words and symbol as a user whose face left the frame, with no hint of which
movement to redo.

Proposed improvement: keep one retry slot, but (a) give it a symbol that is
not the return cue's `viewfinder` (e.g. the action's own symbol or
`arrow.counterclockwise`), and (b) when the reset interrupted a return
(`challenge.isReturningToRest`, already captured for diagnostics), say what to
redo, e.g. "Face the camera, then try that movement again". Cause-specific
wording beyond the returning/not-returning split is explicitly out of scope.

Acceptance: retry caption and symbol differ from the return cue in all three
layouts; returning-interrupt copy names the redo; caption size-continuity and
Reduce Motion behavior unchanged; no gate change.

### 4. Challenge timeout is indistinguishable from rejection on the lock screen

Evidence: on `challengeGate.expired` the loop reports `.notRecognized`,
posts failed/lockedOut, shows `.notRecognised`, rotates the action and cools
down (`LockWatcher.swift:465-477`) — the same panel state as a stranger
rejection (`:563-573`) or an anti-spoof rejection's aftermath. The only
timeout-specific record is a log line ("Challenge not answered in time").
The diagnostics `.notRecognized` message ("did not complete… return to rest
between movements", `LockScanDiagnostics.swift:26`) covers slowness in
settings, but at the lock screen a slow complier sees the rejected face and
can reasonably conclude *they* were rejected rather than *timed out*.

Proposed improvement: reuse the retry caption slot for the post-timeout beat
with timeout-specific words, e.g. "That one timed out — face the camera to try
again", instead of dropping straight to the generic rejected face. No timing,
expiry, lockout-count, or retry-budget change.

Acceptance: an expired challenge shows the timeout retry caption (not the bare
rejected face) before the next attempt; all other rejection paths unchanged;
no gate or lockout change.

### 5. The lock-screen caption is fixed 11pt with no Dynamic Type path, and the lock screen itself never names the manual fallback

Evidence: the caption is `.system(size: 11, weight: .medium)`, `lineLimit(2)`
(`NotchCapsule.swift:470-473`) with 30pt of reserved room in attached mode and
zero reserved room in island mode (`NotchCapsuleController.swift:174`,
`challengeRoom`), overlaid at the island's bottom (`NotchCapsule.swift:372-376`).
The fixed 11pt font is a readability concern, not a measured clipping failure.
macOS text-size behavior needs a live check. Because the font is fixed, larger
text preferences do not by themselves prove that the current caption grows and
clips. Zero extra controller room for the island also does not prove zero
caption space: the view lays its caption out within the existing island. Separately, every "use your password
or Touch ID / unlock manually" sentence lives in `LockScanDiagnostics`
(`:21-28, 30, 32`) — visible only in the settings popover *after* unlocking.
The lock screen's failure vocabulary is the rejected face alone; a user who
does not know Gaze has given up gets no on-screen pointer back to the password
field in front of them. (The island caption overlay and ear capsule,
`NotchCapsule.swift:435-443`, are otherwise sound: they retain layout space
and hide the return cue consistently — keep that construction.)

Proposed improvement: (a) make the caption honor Dynamic Type (scaled font,
minimum-scale or wrapping within the reserved room, re-asserting the
one-pixel size-continuity per layout); (b) after a terminal-for-this-lock
outcome (rejection committed, lockout, camera failure), append a short
fallback pointer to the lock-screen caption area, e.g. "Use your password or
Touch ID", mirroring the diagnostics strings that already exist.

Acceptance: caption scales with text size without clipping or companion
resize in attached/island/ear (offscreen renders at default and larger
sizes); terminal outcomes name the manual fallback on the lock screen;
return-caption hiding, Reduce Motion, and VoiceOver behavior unchanged.

## Explicit non-findings (checked, kept as-is)

- Initial-movement understanding: outward prompts name the action
  ("Turn slightly left/right", "Nod your head", "Blink", "Open your mouth"),
  the face mark demonstrates it (`demonstratesAction`,
  `GazeFaceMark.swift:42-47`), and the practice view holds the companion at
  rest with "Face the camera and hold still." until the baseline is ready
  (`RecognitionTestView.swift:105-117, 144-153`). No change proposed.
- Return: hidden animated caption + onboarding-taught return + retained
  Reduce Motion / VoiceOver cues (above). No change proposed.
- Reduce Motion: written return cue retained, animations nilled, island
  travel/scale disabled (`NotchCapsule.swift:212-213, 377-384, 423-449`).
  No change proposed.
- VoiceOver: mark carries the live prompt as its label (`GazeFaceMark.swift:109-124`);
  decorative symbols hidden (`NotchCapsule.swift:468`). No change proposed,
  except the Dynamic Type scaling in finding 5.
- No inference about animation choppiness or unlock reliability is made here;
  per the investigation record those need supervised live reproduction with
  `RenderTiming`, not this review.
