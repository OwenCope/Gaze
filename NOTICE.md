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

## Design references

### Glance — the 'Beside the camera' layout and the Dynamic Island capsule

`Sources/LockScreen/NotchCapsule.swift` (ear flank and dynamic island shapes)

The 'Beside the camera' layout and the Dynamic Island capsule were inspired by
the minimal unlock style in **Glance**
by Jonathan Zhou (<https://github.com/jonnyoo/glance> — MIT licence,
© 2026 Jonathan Zhou): a silhouette that widens sideways to flank the notch,
with a lock glyph on one side and the unlock mark on the other. Reimplemented
here in Gaze's own panel structure and style; no Glance code was copied.

### Atoll — the Dynamic Island's expansion behaviour

`Sources/LockScreen/NotchCapsule.swift` (dynamic island morph)

The Dynamic Island's expansion behaviour — a small resting capsule morphing
into a larger rounded panel on a spring, with the content fading in after the
shape has mostly grown — was informed by studying **Atoll** by Ebullioscopic
(<https://github.com/Ebullioscopic/Atoll> — GPL-3.0). Reimplemented here in
Gaze's own structure and style; no Atoll code is included.

## Third-party code

### TourKit

Onboarding tour UI, vendored from **TourKit** by Ram Patra:

<https://github.com/rampatra/TourKit> — MIT licence, © 2026 Ram Patra

Pinned at commit `4f2b109506650151d87cd5e84bb9fe2623938781`; the vendored
source (`ThirdParty/TourKit/TourKit.swift`) and licence (`ThirdParty/TourKit/LICENSE`)
are verbatim copies of upstream `Sources/TourKit/TourKit.swift` and `LICENSE` — see
`ThirdParty/TourKit/SOURCE.json` for hashes. The source is compiled into the Gaze
module directly (no separate TourKit module), and the licence ships in the bundle as
`Contents/Resources/TourKit-LICENSE.txt`.

## Model and asset redistribution status

### The recognition model

The recognition model is **ArcFace** (`w600k_r50`) by **InsightFace**
([deepinsight/insightface](https://github.com/deepinsight/insightface)). Its
weights are licensed for non-commercial research use. The Core ML build shipped
with the app comes from **Sapphire** ([sapphire-app.tech](https://sapphire-app.tech/),
by cshariq), which bundles the same model.

The build prefers `Resources/FaceEmbedding.mlmodelc` over the raw package.
It is InsightFace's ArcFace (`w600k_r50`) by deepinsight
(https://github.com/deepinsight/insightface), first obtained via
[Sapphire](https://github.com/cshariq/Sapphire), which bundles the same model
(commit `ee56de09a0c5ab2cbf442858de36780a0cb151b2`; Git blob SHA-1
`004ee9ab6fbfb4fd0c4c34a2bc89be4db624ddf8` for the 87,197,184-byte weight file;
SHA-256 `c28620613d146a56565eadaacc22bbe9dd54533000ba79a6d666995a123c1545`).
InsightFace's model weights are licensed for non-commercial research use; the
owner has emailed InsightFace about permission and is waiting for a reply.

The repository's pinned LICENSE is **AGPL-3.0**, correcting the earlier GPL-3.0
reference. The matching bytes identify an available source, not who trained the
model or which upstream rights cover it. The inspected README and model metadata
provide no separate weight licence or training provenance. Gaze's MIT licence
has not been changed. Matching bytes alone do not establish redistribution rights.

The raw `Resources/FaceEmbedding.mlpackage` is different: its 7,408,704-byte weight
file has SHA-256 `f9145f919e28153bee573651d9681d9917858be038998f59233bc7bd28c00da9`.
Its provenance remains unresolved. Do not use its fingerprint as a substitute for
the precompiled model actually bundled by the build.

ArcFace names an architecture, not a licence for particular weights. If these
weights descend from InsightFace, its pretrained-model restrictions need to be
resolved separately from its MIT code licence. See
https://github.com/deepinsight/insightface#license and https://www.insightface.ai/.
Likewise, AGPL-covered material requires analysis of applicable source, licence
and notice obligations for the intended distribution; attribution alone does
not settle those questions.

Evidence and inspected-source limits are recorded in
[the Sapphire source report](docs/licensing/sapphire.md).
The model was first obtained via Sapphire, which bundles the same model; the
owner's September 18, 2026 permission note from Shariq is kept as a historical
record. See [the permission record](docs/licensing/sapphire-permission.md).
The installed model still matches the weight hash above.
That evidence does not cover the different raw package or establish upstream
weight/training rights; those questions remain separate from Shariq's permission.
The upstream question is now identified: the bundled mlmodelc is InsightFace
buffalo_l `w600k_r50` (ResNet-50 trained on WebFace600K), converted to Core ML fp16 —
exact operator-count match plus cosine > 0.997 against the official ONNX weights on
three test inputs. InsightFace's pretrained weights are non-commercial research only,
so shipping them needs InsightFace's permission (recognition-oss-pack@insightface.ai)
or a replacement model; Shariq's permission does not cover InsightFace's upstream
rights. See [the InsightFace evidence report](docs/licensing/insightface.md).
The source-archive script excludes model inputs. The geometry fallback is not an
approved substitute for the Mac-unlock recognition model.

### The spoof-detection training data

`Resources/Spoof.mlmodel` is a model the Gaze author trained, not a third-party
model being redistributed: it was trained on the author's own machine with
`scripts/train_spoof.swift`, a CreateML object detector, and compiled into the app
by `build.sh`. What is third-party is the data it learned from — **Face Spoof
Detection** (<https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika>),
provided by a Roboflow user and exported via roboflow.com on 19 August 2026
(30,351 images across train/valid/test splits). That dataset is licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), which is why this
notice names it. The bundled weights are a derivative work trained on the
dataset, not a copy of it: the gigabytes of training images stay on the author's
machine (`Data/spoof-detection/`, deliberately git-ignored) and never ship with
the app.

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
