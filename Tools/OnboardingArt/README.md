# OnboardingArt

Deterministic offscreen generator for the tour/onboarding illustrations in
`Resources/Art`. Replaces the dated Settings/onboarding screenshots with
consistent native illustrations.

## Regenerate

```bash
./Tools/OnboardingArt/run.sh
```

This compiles `Generate.swift` together with the real companion renderer
sources (verbatim — see `manifest.json` for paths and hashes), renders the 11
PNGs into `Resources/Art`, writes `manifest.json` here, and drops a contact
sheet at `build/vera-7/contact-sheet.png` (ignored build output, for visual
inspection only).

No app launch, no camera, no screenshots of user windows, no network.

## What the pictures are

Instructional illustrations rendered from app code — not recordings, not
screenshots, and not proof of a real face check. Every face tile is encoded
through the real `SoftFaceGPU` Metal pipeline (`GazeCompanionShader`,
`GazeCompanionMotion`, `GazeFaceMotion` poses) offscreen; only the layout and
the monochrome SF Symbols around them are new.

Canvas: 1440×900 RGBA, transparent. Intro/completion subjects are centered at y=450,
matching the current TourKit media region. Legacy three-pose strips remain at y=310;
the live movement guide no longer displays those strips. No text, buttons, windows,
navigation dots, personal data, coloured backdrops or card frames.

| File | Subject |
| --- | --- |
| `onboarding-recognition.png` | Resting face, 360px at (720, 450) |
| `onboarding-local.png` | Resting face 320px + `lock.fill` side by side |
| `onboarding-unlock.png` | `camera.fill` → face → `key.fill`, `arrow.right` connectors |
| `onboarding-choice.png` | Resting face 320px + `key.fill`; no fake toggle |
| `onboarding-success.png` | Accepted still pose (expression +1), same 360px position |
| `onboarding-failure.png` | Rejected still pose (expression −1), same 360px position |
| `movement-left/right/nod/blink/mouth.png` | Resting / peak motion / resting, 280px at x 330/720/1110 y 310, small `arrow.right` connectors |

Movement middles use the real motion enum (`.turnLeft`, `.turnRight`, `.nod`,
`.blink`, `.openMouth`) sampled at the plateau of the app's own guidance loop
via `GazeCompanionMotion.pose(for:at:)` (t=1.35s for turn/mouth, t=0.95s for
nod/blink), so the illustrated direction matches what the app demonstrates.
Note: the motions' `stillPose` is neutral by design (it is the settle target),
which is why the middle frame samples the guidance peak instead.

Symbols are native SF Symbols only (`camera.fill`, `lock.fill`, `key.fill`,
`arrow.right`), recoloured white at restrained opacity (0.62 subjects, 0.50
arrows). No sparkle/glow decoration.

## Ownership

This directory owns `Generate.swift`, `run.sh`, `README.md`, `manifest.json`
and the 11 new PNGs listed above. Wiring image names into TourKit, setup
views, tests or `build.sh` belongs to other heads/root.
