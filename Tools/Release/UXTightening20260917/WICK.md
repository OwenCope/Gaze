# WICK.md — How trywick.co renders its glass

Final URL/title: **https://trywick.co — "Wick — Right On Time."** (Next.js static export + Tailwind; marketing site for Wick, a free native Mac Clock app — Timers/Stopwatches/Alarms. Not affiliated with getwick.dev, the unrelated "Wick" agent-browser tool.)

## Method limitation (read first)

BrowserOS Neo CUA tools are not present in this worker's toolset, and per the brief no AppleScript/headless-browser/screencapture substitutes were used, so **no live-pixel visual inspection was performed and no screenshots were taken**. Everything below comes from fetched public source: the served HTML, the two CSS bundles, and the page JS bundle. "Observed" = present in fetched markup/CSS; "inferred" = reconstructed from minified JS call sites. The reference tab was not opened (no browser tool available); root should keep/verify it.

## Where the glass is (observed markup)

The only glass-bearing surfaces are **inside the hero's interactive app-window mockup** — a live DOM recreation of the native app, not a screenshot or video:

- `div.wick-mockup > div[data-testid="app-window"] > div[data-testid="wick-window-body"]` (aspect-ratio 1000/700, `background:#2f3030`, radius ~23.3px).
- Inside it: iOS-style toggle switches ("Use Custom Volume", "Snooze") and orange horizontal sliders (volume/brightness). Their **knobs/thumbs are the glass elements**.
- Every `<canvas aria-hidden>` in the static HTML carries `display:none` (Base-UI slider/switch internals) — the visible controls are plain divs plus runtime-created WebGL canvases (see mechanism).
- The rest of the site chrome is flat: solid fills (`#fffdfa` page, `#2f3030` window, `#e5e5e5` toggles, `rgba(255,255,255,0.16)` grooves), a `linear-gradient(to bottom, transparent, #2f3030)` sticky bottom fade, `inset` box-shadows. **No `backdrop-filter` is applied to any element in the shipped CSS** (the only occurrences of the word are Tailwind boilerplate). There is no glass nav bar and no glass CTA.

## Mechanism (source inference from public assets)

Asset: `https://trywick.co/_next/static/chunks/app/page-278b1fa504bde1f3.js` (115,387 bytes; all glass code lives here — no other chunk contains any of it).

1. **Bespoke WebGL1 refraction renderer, per knob.** A factory (`function x(e)`) takes a canvas, calls `getContext("webgl", {alpha:!1, premultipliedAlpha:!1, antialias:!0, depth:!1, stencil:!1, preserveDrawingBuffer:!1})`, compiles a fullscreen-quad GLSL program, and exposes `setImage / resize / render / dispose`. It throws `Error("WebGL not supported")` when context creation fails.
2. **The "backdrop" is a synthetic 2D scene, not the live page.** Each control first paints its own track into an offscreen 2D canvas, then hands that canvas to the lens as its texture (`setImage` reads `naturalWidth||width`; upload path uses `texImage2D` + `UNIFORM …FLIP_Y`; mapping uniforms are documented as `object-fit: cover draw top-left`, `u_imageOffset`/`u_imageDrawSize`).
   - Switch (`function S(e)` — props `on/defaultOn/onChange/onColor:"#34c759"/offColor:"#5b5b62"/knobColor:"#ffffff"`): 2D callback paints the track (`roundRect` + `fillStyle=k(s,o,…)` color ramp, or a `#0e0f14` + hairline-grid default), then `f&&r.setImage(f), r.resize(l,c,v), r.render({dpr, containerSizePx:{x:D,y:L}, capsuleTopLeftPx:{x:u,y:d}, capsuleSizePx:{x:l,y:c}, borderRadiusPx:h, glass:ei(i)})`.
   - Slider (`function A(e)` — props `value/onChange/surface:"#404141"/onColor:"#ff9e0a"/grooveColor:"rgba(255,255,255,0.16)"/knobColor:"#e9e9ea"`): 2D callback paints the 6px groove (`roundRect(0,9,e,6,3)`) and orange fill, then `c&&t.setImage(c), t.resize(r,a,f), t.render({…, containerSizePx:{x:j,y:24}, …, glass:{…b(.16,p,n), innerRefractionAmount:-12.16, innerRefractionHeight:4.752, outerRefractionAmount:2.4, centerZoom:.1*n}})`.
3. **The shader does genuine refraction, modeled on Apple's private filters.** GLSL comments name `CAFilter "glassBackground"` refraction inputs, a `CASDFGlassHighlightEffect approximation (amount, angle, curvature, spread)`, and a `glassForeground aberration path, matched to the NATIVE ABERRATION capture`. Per-pixel work: rounded-capsule SDF → normal-directed UV displacement (`u_innerRefractionAmount/Height`, `u_outerRefractionAmount/Height`, `u_lensCurve`, `u_centerZoom` minification) → per-channel chromatic-aberration shift (uniform `aberrationAmount/Spread` plus fixed-direction foreground fringe) → 5-stop SDF blur ramp (`u_blurDist[5]`/`u_blurOp[5]`) → face-fill color remap over the refracted sample → dual specular highlights + rim bleed + drop shadow. Shared defaults object `v` includes `innerRefractionAmount:-52.2, innerRefractionHeight:16.53, aberrationAmount:2.088, aberrationSpread:.03, lensCurve:1.1, fgAberrationEnabled:!0, …, shadowOffsetY:7, shadowOpacity:.1, shadowRadius:8`.
4. **Knobs are spring-animated** (stiffness/damping pairs `_={k:520,c:42}`, `j={k:490,c:44}` in the switch; equivalent loop in the slider), re-rendering the lens each animation frame.
5. **Fallback is flat, never fake blur.** Creation is guarded — `if(p)try{n=x(e)}catch(e){n=null}` — and with no renderer the knob stays a plain div with `style.backgroundColor` set from the on/off ramp. There is no `backdrop-filter` or SVG-filter fallback path anywhere in CSS or JS.
6. **Unrelated effects, do not mistake for glass:**
   - `Showcase_grain` (in `/_next/static/css/3a6319a5cb12475a.css`) is an SVG `feTurbulence` film-grain overlay (`opacity:.025`), not glass.
   - All `blur(…)` hits in the page JS are entrance animations (`filter:"blur(6px)"→"blur(0px)"`) and DOM `.blur()` calls, not material blur.
   - `:root` defines `--wick-mat-filter:blur(34px) saturate(1.7) brightness(.92)` plus `--wick-mat-tint/base/solid/edge` flat dark tokens in the same CSS file, but **no `var(--wick-mat…)` consumer exists in either CSS bundle or the page JS** — vestigial token, not the rendered mechanism.

## Library / license

No third-party liquid-glass library detected: no `liquid-glass`/`LiquidGlass` identifiers, package banners, or attribution strings in any fetched bundle — the renderer is bespoke (Apple's private filter names appear only in comments as the thing being approximated). No license text was found in the fetched assets. **Do not copy the shader or assets**; the recommendations below are clean-room takeaways, not ports.

## Recommendations for Gaze (max three)

Scope note: `src/components/mac-screen.tsx` and `src/components/ui/liquid-glass-button.tsx` do not exist in this (Swift) worktree — these target the website codebase as named in the brief.

1. **Refraction reads as edge-weighted displacement + chromatic fringe over a real sampled backdrop, not as layered translucency.** Wick bends hardest at the capsule rim (inner −52.2px-class amounts vs minified center), adds a ~2px-class per-channel shift, and ramps blur 0→opaque across five SDF stops — while the page behind is genuinely sampled. If Gaze's web material switcher cannot sample and displace, prefer a single honest treatment (tinted blur *or* flat solid) over stacking borders/gradients; extra layers without displacement will keep reading as "generic layered pills," which is exactly what the user dislikes.
2. **At button/knob sizes the specular pair does most of the work.** Wick lights every capsule with two diagonal highlights (angles ≈ 2.356 and −0.785 rad, height ≈ 9 device px at 1x, spread 0.3) plus a faint rim, even when refraction is subtle. For `liquid-glass-button.tsx`, implement one asymmetric diagonal highlight pair with differing intensities rather than a uniform inner glow or symmetrical border — that asymmetry is the cheapest convincing-glass cue in the reference.
3. **Ship a flat-solid fallback, not a degraded blur.** Wick's no-WebGL path is a flat `backgroundColor` knob — no `backdrop-filter`, no SVG displacement stand-in — and its blur is never uniform (opaque center, blur only at the rim). Give the material switcher an explicit solid fallback tier and avoid uniform-`backdrop-blur` pills as the "safe" option; uniform blur reads frosted-acrylic, which is precisely *not* the refractive look in this reference. And do not label any web implementation "native macOS Liquid Glass": Wick's own shader comments call it an *approximation* of private `CAFilter`/`CASDFGlassHighlightEffect` behavior — a web imitation, same category as anything Gaze ships on the web.
