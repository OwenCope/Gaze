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
