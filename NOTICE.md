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

`Resources/FaceEmbedding.mlpackage` — the model faces are matched against. It comes
from **Sapphire**, by cshariq, and its licence is unknown, so it is not included in
published source archives. Without it the app falls back to comparing facial
landmarks directly, which is much weaker: it can tell you from a stranger, and not
much more.

### FaceIDKit

The animations in setup are **Aviorrok's**, licensed to this app alone and explicitly
not for redistribution. Kept out of git entirely rather than merely out of the public
repository, because history is forever. `SetupMark` substitutes system symbols when
the framework is absent, so setup works and simply looks plainer.

### SkyLight window server

Not used by Gaze today, and noted because it is the known answer to a problem Gaze
has not solved: making a window appear on the real macOS lock screen. Glance uses it,
adapted from **Lakr233/SkyLightWindow** (MIT). It calls undocumented private symbols
that Apple can change or remove in any release.
