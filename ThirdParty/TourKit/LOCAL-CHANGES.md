# TourKit local changes

Base: https://github.com/rampatra/TourKit at
`4f2b109506650151d87cd5e84bb9fe2623938781` (MIT; see LICENSE).

The September 18 polish pass preserves TourKit's layout, page state,
Back/Next/finish/close actions, aspect ratio and uniform host scaling.
The user's latest request calls for native Liquid Glass and live movement
content. These are the only presentation extensions to the pinned source:

1. `TourSlideshowView` appends optional `pageMedia: ((Int) -> AnyView)? = nil`.
   When supplied, only the active page's content is mounted in the existing
   media region, with 48-point horizontal and 36/40-point top/bottom clearance
   for the unchanged navigation controls. Type erasure is limited to this
   heterogeneous content slot; `TourPage` is unchanged. Existing callers still
   render their static image. Gaze's movement guide supplies its real renderer.
2. The card uses the system `glassEffect(.regular, in:)`. The primary action
   uses `.glassProminent`, and icon buttons use `.glass` on macOS/iOS 26+.
   Earlier platforms use system material and bordered controls. The painted
   blue button, handmade blur circles, opaque dark fill and fading scrim are
   removed. Foreground styles and page dots adapt to the system appearance.
3. Page cross-fades are disabled under Reduce Motion. The live renderer
   separately handles explicit pause, reduced motion, background and detach.
4. Invisible initial Back is disabled and hidden from accessibility. Close
   retains the checkmark and callback, with label `Close tour` and identifier
   `tour-close`. Static artwork is hidden from accessibility; live controls
   remain accessible.

The wrapper is still a 720×680 card scaled uniformly from width 660. No
window-controller or navigation behavior was replaced. The existing
`TourBottomPanelSizingView` continues to reserve the upstream 42-point action
height for automatic standalone-window sizing.
