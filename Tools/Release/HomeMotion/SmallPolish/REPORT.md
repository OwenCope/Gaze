# Small homepage polish, September 16, 2026

The four Hydra tasks automatically stopped for inactivity without landing edits.
Root applied their bounded changes directly. No stopped worktree source was
recovered. Read-only existence checks found the prepared files in Juno 3 and
Ezra 3's worktrees; the underlying execution failure remains undiagnosed.

Four website files changed:

- live-demo.tsx: explanation beside the video on desktop, stacked on mobile.
  Existing copy, media, captions, controls and no-autoplay behavior preserved.
- theme-toggle.tsx: a 140ms opacity/scale transition on pointer-triggered icon
  changes. Initial rendering, keyboard use and reduced motion remain static.
- features-carousel.tsx: scoped ArrowLeft/ArrowRight/Home/End navigation. Modified
  keys and nested targets are not intercepted. Zero/one-card guard added.
- ui/footer-section.tsx: 14px links, 13px group headings and 44px link targets.
  Note text, destinations, landmarks and focus styling preserved.

Full production build and TypeScript pass; scoped lint and all five synthetic
HTTP checks pass. Actual BrowserOS neo checks measured desktop demo columns at
413/619px, native controls present and autoplay false. Footer links measure
14px/44px. Theme icon has no initial animation, a 140ms pointer animation and no
keyboard/reduced-motion animation. Feature ArrowRight moves 420px; End reaches
580/580px and Home returns to zero. Modified and nested events remain unconsumed.
At 390px the demo stacks with no horizontal overflow; browser errors were empty.

Source copies match the live local checkout. small-polish.patch applies to the
recorded baseline with zero fuzz and reproduces all four files. Do not apply it
again to the already integrated site. Logs: build/website-small-polish. Preview:
http://127.0.0.1:55523. No real services, data, app binaries or deployment changed.
