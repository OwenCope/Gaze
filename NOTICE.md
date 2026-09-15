# Credits and third-party notices

Gaze is MIT licensed — see `LICENSE`. This file records other people's work that
Gaze is built on, borrows from, or deliberately leaves out.

## Borrowed ideas

### Glance — the notch panel's flared top

`Sources/LockScreen/NotchPanelShape.swift`

The panel used to be a rounded rectangle with square top corners, which reads as a
box hanging below the notch rather than as the notch growing. The fix — a concave
flare at each top corner, turning outward into the screen edge so there is no corner
where the panel meets it — came from reading **Glance** by Jonathan Zhou:

<https://github.com/jonnyoo/glance> — MIT licence, © 2026 Jonathan Zhou

Glance's `NotchShape` goes further than ours: it lifts the real continuous-curvature
control points out of a rendered `UnevenRoundedRectangle` and rebuilds the outline
from them. Ours composes that primitive instead, so the geometry is Apple's without
the path surgery. The implementation is therefore not a copy, but the observation
that the flare is what makes a notch panel look attached is theirs, and it is the
part that mattered.

Glance solves the same problem as Gaze — face unlock for the Mac — and reached the
same conclusion about the only route macOS leaves open: there is no API that lets a
third-party app authorise a login, so the password is typed. Worth reading if you
are here for how any of this works.

## Not ours to redistribute

### The recognition model

`Resources/FaceEmbedding.mlpackage` — the model faces are matched against. It is
reported to come from **Sapphire**, by cshariq, but the source and licensing of
these exact weights have not been verified:
the file carries no embedded author, licence, or source URL (Manifest author is
`com.apple.CoreML`; embedded build metadata says only that it was converted from
TorchScript with coremltools on 2026-06-15), and how it arrived in this working
copy is unrecorded. As fingerprinted 2026-09-15:

- `Data/com.apple.CoreML/model.mlmodel` (184,289 bytes): SHA-256
  `b8992d7979904fb5d6b0cf9ec452f158d9257cd820730328de9242eb6652f494`
- `Data/com.apple.CoreML/weights/weight.bin` (7,408,704 bytes): SHA-256
  `f9145f919e28153bee573651d9681d9917858be038998f59233bc7bd28c00da9`

The source-archive script excludes and re-checks for this package. A geometry
fallback exists for practice features, but the current Mac-unlock path refuses
it; it is not an approved substitute for a validated recognition model.

ArcFace names a model architecture, not the license of a particular weight file.
Code and model licenses must be checked separately. Upstream references checked
on 2026-09-15: [InsightFace README](https://github.com/deepinsight/insightface#license)
and [InsightFace licensing](https://www.insightface.ai/).

- If the weights descend from InsightFace: the **code** is MIT, but the
  **pretrained recognition models (and the training data behind them) are for
  non-commercial research only**. Commercial use needs a separate licence —
  upstream names `recognition-oss-pack@insightface.ai` for the open-source
  recognition packs. Crediting the authors does not grant redistribution or
  commercial-use rights.
- If the file came via Sapphire, whose repository is GPL-3.0: GPL is copyleft,
  not credit-only. Bundling a GPL-covered file in an MIT-labelled distribution
  needs a proper licence analysis, not an attribution line.

Either way, a credit line is not permission. The launch gate stays open until a
per-model permission or licence, tied to the hashes above and the intended
distribution scope, is recorded here.

### FaceIDKit

The animations in setup are **Aviorrok's**, licensed to this app alone and explicitly
not for redistribution. Kept out of git entirely rather than merely out of the public
repository, because history is forever. `SetupMark` substitutes system symbols when
the framework is absent, so setup works and simply looks plainer.

### SkyLight window server

Used by Gaze for the lock-screen capsule only (`Sources/LockScreen/LockScreenSpace.swift`):
it opens SkyLight privately and moves the capsule window into a lock-screen-level space
via undocumented symbols (`SLSMainConnectionID`, `SLSSpaceCreate`,
`SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`,
`SLSRemoveWindowsFromSpaces`), adapted from the same approach as **Lakr233/SkyLightWindow**
(MIT) used by Glance. These APIs position the panel; they do not authenticate the user.
If they are unavailable, `canPresentGuidance` is false and the current unlock flow
refuses password submission rather than presenting an invisible movement challenge.
The symbols can change or be removed in any macOS release.
