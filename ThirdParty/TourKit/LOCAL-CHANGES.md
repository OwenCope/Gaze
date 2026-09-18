# TourKit local changes

Pinned base: https://github.com/rampatra/TourKit @
`4f2b109506650151d87cd5e84bb9fe2623938781` (MIT; see LICENSE).

Public API unchanged. No animation-timing, artwork, dependency, or
CTA/Return-behavior changes.

1. Back button (`TourSlideshowView.topControls`): explicit
   `accessibilityLabel`/`help` "Previous page". At `currentIndex == 0`
   the button keeps its alignment slot (still laid out, `.opacity(0)`)
   but is `.disabled` and `.accessibilityHidden`, so the invisible
   button is not focusable.
2. Close button (`TourSlideshowView.topControls`): icon changed
   `checkmark` → `xmark`, with `accessibilityLabel`/`help`
   "Close introduction". The `onClose`/`dismiss` callback behavior is
   unchanged, as is the `present(onClose:)`/`onFinish` wiring in
   `TourKitWindowController`.
3. Slide artwork (`TourSlideshowView.imageSection`): marked
   `.accessibilityHidden(true)` because the slide's title and
   description carry its meaning.
4. `PageIndicator`: verified already compliant — it combines its dots
   into one element (`.accessibilityElement(children: .ignore)`) with a
   spoken "Page N of M" label. No change made.

Also updated the `TourKitWindowController.present` doc comment
("checkmark" → "close button") to match the new close icon.

5. `TourSlideshowPresentation` (`.card` / `.windowContent`) with appended
   `TourSlideshowView` initializer arguments `presentation: .card` and
   `contentHeight: nil` (all existing arguments and defaults preserved).
   The image/bottom-panel `VStack` is a shared `content` property. `.card`
   keeps the dark background, 20-point clipping, border, and close X.
   `.windowContent` fills the supplied frame with the same dark
   background, no rounded clipping, no border, and no close X (the host
   window's native controls and Escape handling own closing). With a
   `contentHeight`, `imageHeight` is
   `max(120, min(width / imageAspectRatio, contentHeight - 220))`,
   rounded. Aspect preservation, indicator, page state, transition
   timing, and callbacks are unchanged. Gaze's `GazeWelcomeTour` passes
   its `GeometryReader` width/height (clamped above zero) with
   `.windowContent` so the tour fills the setup window with no inset
   frame or outer padding.

6. Optional per-page live media (`TourSlideshowView` initializer
   arguments `pageMedia: ((Int) -> AnyView?)? = nil` and
   `onPageChange: ((Int) -> Void)? = nil`, both stored; all existing
   arguments, defaults, non-generic public type, and `.windowContent`
   behavior preserved; `AnyView` type erasure lives only at this
   heterogeneous media boundary). `imageSection` evaluates `pageMedia`
   once for `currentIndex`: when it returns a view, that view renders in
   the existing width/`imageHeight` media region with the same
   `.id(currentIndex)` + `.transition(.opacity)` identity, active page
   only (apart from the transition lifetime), with its own accessibility
   and hit testing intact (no artwork `.accessibilityHidden`, no fading
   gradient); when it returns nil, the static image and gradient render
   exactly as before. `PageIndicator`, `topControls`, `bottomPanel`, and
   the primary action button remain single shared instances. `body` adds
   `.onChange(of: currentIndex)` forwarding the new index to
   `onPageChange`; clamping and navigation semantics unchanged, and the
    notification never calls finish/close.

7. Compact `.windowContent` artwork/footer styling (640x520 host):
    `imageHeight` reserves 260 points for the lower panel (260-point
    media region at the host; `.card` sizing unchanged). Static
    `.windowContent` artwork keeps the existing Image loader with
    `resizable`/`scaledToFit` (no crop or stretch), a continuous
    16-point `RoundedRectangle` clip immediately after `scaledToFit`
    (before padding/outer frame) plus a matching 0.5-point
    white-at-10% `strokeBorder`, then horizontal 32 / vertical 16
    padding and the outer width/`imageHeight` frame; the dark gradient
    overlay is removed only in `.windowContent` (`.card`
    artwork/gradient unchanged). `PageIndicator` renders only in
    `.card` image sections; `topControls` stays in both modes (hidden
    initial Back, no `.windowContent` close-X). The new
    `.windowContent` bottom panel is top-aligned with a text VStack
    (8-point spacing; title 24 semibold white, description 14
    white-70% with lineSpacing 2, same table/bundle lookups; 440 max
    width, 100 min height), 12-point top padding, then the single
    `PageIndicator` (+12), the primary action (+16), and 24-point
    bottom padding, with no expanding Spacer (`.card` panel
    unchanged). The `.windowContent` primary action keeps the same
    title/action/`defaultAction` shortcut as native
    `.borderedProminent`, large, capsule, `.accentColor` (label 14
    semibold, 140 min width); the 220-point gradient pill remains only
    in `.card`.
