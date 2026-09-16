# Gaze panel studio previews — Hank 3 (2026-09-16)

**Simulated panel previews, not real unlock recordings.** Every frame is a
synthetic `NSHostingView` rendered offscreen by the production views
(`NotchCapsule`, `GazeFaceMark`, the Companion Metal renderer) driven by a
hardcoded synthetic `NotchCapsuleModel`. No desktop, camera, screen lock,
Keychain, vault, enrolment, live app, or live preferences appear anywhere
in the pipeline. No security state was touched to make this footage.

## Deliverables (`assets/`, tracked)

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `gaze-panel-normal.mp4` | 51454 | `04a73ea1f2acafa5373645c43064ebd5c27586d231de9243db1a997c74a4ccef` |
| `gaze-panel-semi-liquid-glass.mp4` | 50712 | `6a618d56f4230ef9af59e0b113caac26e310b8a69623ad7bcf21f6a2f33bc682` |
| `gaze-panel-liquid-glass.mp4` | 50967 | `4b89e0e6c3d10294c05cf3e22bbcc4748273fb7db44fea9dd72f0b3f2e244b43` |
| `gaze-panel-normal-poster.png` | 18988 | `5e0c5b7a8d7ab2fe0ee5e7f2b1d9a1616a4e30251868fc8a66899178c88e6273` |
| `gaze-panel-semi-liquid-glass-poster.png` | 20177 | `ba2e6df49b979de6d19c33c7d00110741b3d4a530570a6d14afe033bb471c074` |
| `gaze-panel-liquid-glass-poster.png` | 18124 | `bddcd44d3d5f774467f1bd1ef33d1934ff123d0f3a9fcce17a298fe014f27284` |

(All three clips far under the 3 MB aim at CRF 19 with no detail
destruction — the stage is mostly static gradient.)

## Rendering recipe

- Source: `StudioRenderer.swift`, built by `build-studio.sh`
  (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`,
  `xcrun swiftc -parse-as-library`, macOS SDK, `arm64-apple-macos26.0`).
  Compile set reuses `Tools/GazePreview/PreviewPreferences.swift`,
  `Sources/App/Theme.swift`, `Sources/LockScreen/GazeFaceMark.swift`,
  `NotchCapsule.swift`, `NotchPanelShape.swift`,
  `Sources/Companion/*.swift`, and
  `Tools/GazePreview/Tests/CompanionCapture.swift` — the same
  dependency/model pattern as `test-companion-integration.sh`.
- Stage: 960×600 points, quiet light neutral vertical gradient
  (white 0.965 → 0.895), production `NotchCapsule` 400 wide × 190 high
  (`notchInset` 32, `cutoutWidth` 180 — the production cutout, widened
  panel for legibility), centred at the top. No clock, weather, menu
  bar, Dock, names, files, cursor, or wallpaper.
- One persistent hidden `NSWindow` (never ordered front — it never
  appears on any desktop); per-frame `cacheDisplay` plus real Metal
  renderer pixels overlaid exactly like `CompanionCapture.snapshot`.
  Phases step on a wall-clock 30 fps loop, so SwiftUI springs,
  caption fades, and the companion's `TimelineView`/Metal motion are
  genuinely sampled — not panned stills (proven: consecutive frames
  differ in every animated segment, e.g. scan 40≠41, turn 70≠71).
- The offscreen window renders at backing scale 2, so source frames are
  1920×1200 and the encode downscales to the specified 960×600
  (`-vf scale=960:600`): effectively 2× supersampled text.
- Model mirrors what `NotchCapsuleController.show()` captures on a
  light wallpaper: attached, centred, `transparency` 0.3 (the
  Preferences default), `prefersOpaque` true. Style is the only
  per-variant difference.
- Choreography (all `NotchCapsuleModel` phases, presentation only):

| Time | Phase |
| --- | --- |
| 0–0.7 s | locked (grows out of the notch at ~0.13 s) |
| 0.7–2 s | scanning |
| 2–3.3 s | challenge `Turn slightly left · 1 of 2` (`arrowshape.left.fill`, hintX −1), built with the real `Phase.outwardPrompt(…, 0, 2)` |
| 3.3–4 s | return to starting pose (`viewfinder`, `isReturningToRest: true`, caption hidden by the production path) |
| 4–5.2 s | challenge `Blink · 2 of 2` (`eye.fill`, pulses), via `outwardPrompt(…, 1, 2)` |
| 5.2–6.3 s | pending (`Waiting for macOS`) |
| 6.3–7.1 s | unlocked |
| 7.1–8 s | locked |

- Encode: `ffmpeg -framerate 30 -i frame-%04d.png -vf scale=960:600
  -c:v libx264 -pix_fmt yuv420p -crf 19 -preset medium
  -movflags +faststart -r 30 -an`. Posters are the t = 4.5 s frame
  (blink challenge, panel fully dropped).

## Verification (measured, not reasoned)

- `ffprobe`: all clips 960×600, `avg_frame_rate=30/1`,
  `duration=8.000000`, `codec_name=h264`, `pix_fmt=yuv420p`.
- Faststart: top-level box order `ftyp, moov, free, mdat` (moov before
  mdat) in all three, checked by parsing.
- Full decode: `ffmpeg -i clip -f null -` clean on all three, no errors.
- Captions (on-device Vision OCR over rendered frames): `Turn slightly
  left · 1 of 2`, `Blink · 2 of 2`, and `Waiting for macOS` all read
  back on normal and semi; locked/scanning/unlocked/return frames read
  empty as designed (animated return caption stays hidden; resting and
  confirmed-unlock phases carry no caption). Encoded normal/semi
  posters re-read `Blink · 2 of 2` — the encode preserves the text.
- Geometry: ASCII-raster inspection of start/middle/end frames shows
  the full dropped panel, glyph, and caption inside the frame with
  clean gradient background; resting bars show the closed padlock.
- Exactly one Metal face surface whenever the drop is showing
  (asserted in-render at three timestamps per variant).

## Are the material differences real?

Partly — this is the known offscreen-capture limitation, now measured.
Mean luma inside the dropped panel at the blink challenge
(120×100 crop left of the glyph): **normal 0.0, semi 78.3,
liquid 243.0** against a ~230 background.

- **normal vs semi: real.** Both are explicit production fills and both
  render offscreen: solid black vs `NotchGlass.semiTint(0.3, boost
  0.22) = 0.90` black over `.ultraThinMaterial`. The visible difference
  is the production tint math. (Backdrop blur has nothing to sample
  offscreen, but at 90% opacity the tint dominates, so the semi clip is
  a faithful preview.)
- **liquidGlass: NOT faithfully capturable offscreen — do not present
  it as the on-screen Liquid Glass look.** `.glassEffect` needs the
  live desktop compositor behind the window; offscreen there is nothing
  to refract, so the panel collapses to near-transparent (243 ≈ bare
  background) and only the Metal face, padlock, and faint caption
  remain. The clip is included for choreography completeness with the
  identical framing, with no faked blur or tint added — faking a
  material difference would be worse than showing the limitation.

Recommendation: use the normal and semi clips as site media; either
omit the liquid clip or label it as an offscreen-capture limitation,
not as what Liquid Glass looks like on a real lock screen.

## Deliberate choices / notes for root

- Blink uses `eye.fill`, not the brief's literal `(eye, …)`: the bare
  `eye` symbol maps to *resting* face motion, while `eye.fill` drives
  the real blink demonstration (`GazeFaceMotion.init`, same as
  `MovementProgressTests`). The caption text is exactly `Blink · 2 of 2`.
- In-render Vision OCR proved flaky inside the Metal-heavy render
  process (`e5rtError`) while identical requests succeed from a
  separate process, so caption verification runs post-hoc over saved
  frames (standalone probe pattern); the renderer keeps only the
  cheap face-presence assertions. Also: the deprecated `usesCPUOnly`
  flag breaks Vision in a bare CLI (e5rt error) — omit it.
- `LiveDemo`, `NotchVideo`, `MacScreen`, settings, and website sources
  untouched, per ownership. No integration changes proposed here —
  audit before selecting/applying assets, and keep the website labels
  saying what this is: simulated panel preview.
- Intermediates (720 source PNGs, renderer binary) live in `/tmp`
  only; nothing under ignored `build/` is a deliverable.

## Root integration corrections and selected media

The normal and semi previews were re-rendered after visual inspection found the
offscreen Metal overlay appearing outside the expanding/closing panel. The studio
capture now fades its overlay in after expansion and omits it for compact phases.
This is preview-only composition, not a change to production UI or security.
Posters now use settled scanning at 1.6 seconds. Liquid Glass remains excluded
from the website because its offscreen material is not faithful.

Capture overhead adds wall time beyond the 1/30-second wait. The output has a
30fps timebase and fixed phase durations; its gesture/transition microtiming is
illustrative, not a measurement of on-screen animation cadence. The claims above
about wall-clock 30fps should be read with that limitation. Hashes in the table
and portable SHASUMS.txt reflect the current assets. --site rebuilds only the two
selected variants. Full compile, encode, faststart and decode checks passed.

Site integration uses new /previews paths, so the old personal-desktop clips and
low-detail unlock recording are no longer referenced by the homepage/product tour.
The site labels this material as an animation preview, never a real unlock take.
