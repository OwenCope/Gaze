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

The build prefers `Resources/FaceEmbedding.mlmodelc` over the raw package.
Its 87,197,184-byte weight file matches the ArcFace weights in
[Sapphire](https://github.com/cshariq/Sapphire) at commit
`ee56de09a0c5ab2cbf442858de36780a0cb151b2` (Git blob SHA-1
`004ee9ab6fbfb4fd0c4c34a2bc89be4db624ddf8`; SHA-256
`c28620613d146a56565eadaacc22bbe9dd54533000ba79a6d666995a123c1545`).

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
[the Sapphire source report](Tools/Release/ModelClearance/SAPPHIRE-EVIDENCE-20260916.md).
The owner supplied Shariq's permission to use the Sapphire ArcFace model with
credit on September 18, 2026. The installed model still matches the Sapphire
weight hash above. See [the permission record](Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md).
That evidence does not cover the different raw package or establish upstream
weight/training rights; those questions remain separate from Shariq's permission.
The source-archive script excludes model inputs. The geometry fallback is not an
approved substitute for the Mac-unlock recognition model.

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
