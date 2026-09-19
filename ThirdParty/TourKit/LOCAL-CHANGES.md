# TourKit local changes

Base: https://github.com/rampatra/TourKit at
`4f2b109506650151d87cd5e84bb9fe2623938781` (MIT; see LICENSE).

The user explicitly reaffirmed TourKit's preset styling after seeing the custom
Liquid Glass version. The upstream opaque dark card, border, rounded clipping,
image fade, blue gradient primary button, icon circles, typography, colors and
page indicators have been restored. Do not replace them with a custom glass skin.

Remaining extensions:

1. `TourSlideshowView` appends optional `pageMedia: ((Int) -> AnyView)? = nil`.
   Only active-page content mounts in the original media region, with 48-point
   horizontal and 36/40-point top/bottom clearance for navigation. It inherits
   the dark appearance of the preset card. Type erasure stays at this media
   boundary; `TourPage` and the navigation callbacks are unchanged.
   Static artwork uses the upstream fade. Live media omits that fade so its
   playback controls remain readable and clickable.
2. Reduce Motion disables page cross-fades. The renderer separately handles
   explicit pause, backgrounding and detach.
3. Invisible initial Back is disabled and hidden from accessibility. Close
   retains the checkmark and callback, with label `Close tour` and identifier
   `tour-close`. Static artwork is hidden from accessibility; live controls
   remain accessible.

Gaze still uniformly scales the 660-point preset to its 720×680 card.
The centered live movement guide is retained. Its extra Pause/Play control uses
its original system bordered style rather than the rejected glass style.

## Later explicit control changes

The user specifically rejected the outlined Back/checkmark circles. The glyphs
now have clear 32-point hit areas, no circle/background/stroke, and a lighter
14-point medium weight. Close uses xmark, retains its accessible identifier and
onClose callback, and responds to Escape. The preset card, text, primary button,
page layout and indicator remain. The movement content now autoplays without
extra Play/Pause controls or the separate camera-off caption, as requested.

## Latest explicit request: native Liquid Glass tour navigation

The user asked for Apple-style circular Liquid Glass Back and Close controls
(Clock-editor reference: neutral translucent X, accent-filled white checkmark),
with Gaze's completion circle in blue rather than orange. `topControls` and
`iconButton` now use genuine system `.glass` circular buttons
(`.buttonBorderShape(.circle)`, `.controlSize(.large)`, ~36-40pt) instead of
faked glass, gradients, outlines or blur layers. Every page keeps the
neutral glass X (`tour-close`, Escape to close). The final page of a multi-page tour adds a
circular blue `.glassProminent` checkmark (`tour-finish`) that calls
`advance()`, running exactly the same onFinish fallback chain as the bottom
final action; its accessible label follows the localized `finishButtonTitle`
so 'Start setup'/'Done' stay truthful. Escape always closes via
the Close button's onClose/dismiss action and never triggers the checkmark. Bottom CTA, card, image
fade, typography, indicators and timing are unchanged. Controls-only
exception to the styling preference above; the card itself stays opaque.

Single-page setup results retain only the X so closing never retries capture or
starts the optional recognition test. The final tour page keeps X beside the
completion checkmark, making cancel and completion separate visible actions.

## Correction: visible glass at rest

The user reported the circular Back/X buttons looked flat until hovered and
explicitly asked for visible Apple Liquid Glass at rest. The top controls now
use an explicit, always-present native glass surface on each 40pt circular
label instead of relying on the default `.glass`/`.glassProminent` button
bezel: Back/Close use `.glassEffect(.regular.interactive(), in: .circle)` and
completion uses the same real glass tinted system blue, with `.buttonStyle(.plain)`
so no second bezel stacks over the glass. The effect is applied
unconditionally, never keyed off hover. The controls sit in one
`GlassEffectContainer(spacing: 8)` with the existing HStack 12pt spacing,
insets, and invisible first-page Back slot preserved. Card, artwork,
typography, page transitions, and all actions/labels/shortcuts are unchanged.
