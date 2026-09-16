# Gallery pacing

Otto 4 replaced the padded frame and thumbnail strip with an editorial split layout, a fixed 16:10 dark stage, and four text tabs.

- The four existing lossless detail sources, dimensions, and alt text are unchanged. Images remain unoptimized, object-contained, and capped at half their source width.
- Pointer selection crossfades stationary image layers over 400 ms. The selected pill moves with a 380 ms cubic-bezier(0.32, 0.72, 0, 1) transform transition. Keyboard and reduced-motion selection are instant; initial content does not animate.
- Tabs support Left, Right, Home, End, and roving focus, with the selected panel labelled by its tab.
- The native dialog retains Escape, backdrop dismissal, focus restoration, and body scroll cleanup. Its width follows the selected image display width plus 32 px, bounded by the viewport.
- Focused ESLint check passed: `./node_modules/.bin/eslint src/components/screenshot-gallery.tsx`. Browser and full build verification remain with the parent task.

Source: `/Users/owencope/Developer/gaze-site/src/components/screenshot-gallery.tsx`.
Mirror: `Tools/Release/SecondaryPages/files/src/components/screenshot-gallery.tsx`.

Root slowed the hero's NotchVideo playback/defaultPlaybackRate to 0.6, so the
eight-second source now takes about 13.3 seconds per cycle. This applies to both
materials; pause intent, viewport/visibility pauses, phase-preserving switching
and reduced-motion behavior remain. The caption explicitly says Slowed panel
preview. App recognition speed and source video/choreography were not changed.

## Root integration correction

Runtime testing found that the Framer reduced-motion hook did not react to a
preference change during the open session, so pointer selection still faded.
Root replaced the image/pill motion with CSS opacity/transform transitions.
The site's prefers-reduced-motion rule cancels CSS transitions immediately,
including changes during an in-flight transition. Keyboard changes explicitly
set transition:none. This also avoids recreating animated layers on selection.

The initial in-page timer probe did not reliably expose intermediate compositor
frames. Separate wall-clock samples did: incoming opacity .085 at75ms, .983
at341ms, and1 at790ms; stage height stayed443.75px. The final CSS correction is
checked again in build/website-gallery-pacing-final. No app or source-video
choreography changed, and no real camera/authentication was used.

## Final verification

Production build, TypeScript, focused ESLint and five isolated HTTP assertions
passed. The final browser checks passed: 400ms opacity crossfade with unchanged
stage dimensions; instant keyboard switching; enabling reduced motion mid-fade
settles immediately; no mobile overflow; 44px tab heights; native dialog Escape
and focus restoration. See BROWSER-CHECKS.json and the two screenshots.

Hero playback was measured at0.6x, and explicit Pause remained effective across
material selection. The eight-second source therefore takes roughly13.3seconds
to play. User input and native app timing were not changed. The latest preview
server is localhost55523, runner exec11541, logs build/website-gallery-pacing-final.
No deployment was performed.
