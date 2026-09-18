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
