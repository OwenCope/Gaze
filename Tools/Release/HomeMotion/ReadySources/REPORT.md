# Homepage revision — September 16, 2026

Root implemented this revision directly after three rounds of Hydra tasks stopped
for inactivity without landing edits. These source copies and home-revision.patch
match the locally integrated website. BASELINE.json records target paths and hashes;
the patch applies to the recorded pre-revision baseline and reproduces all six
current sources with zero fuzz. Do not apply it again to an integrated site.

Changes:

- The three material choices sit 20px below the complete MacBook prop. Controls
  have 44px minimum targets, themed translucent surfaces, selected-state motion,
  focus rings and reduced-transparency/high-contrast fallbacks. Labels stay on one
  line at narrow widths. Touch scrolling is no longer captured by a drag handler.
- Hover tilt, pointer subscriptions, perspective and tilt springs were removed.
  The existing first-visit entrance and its storage, hydration and reduced-motion
  gates are preserved.
- FAQ answers open in 240ms and close in 180ms, with coordinated plus rotation.
  Repeated input can reverse the transition immediately. Keyboard activation and
  reduced motion are instant. Closed content is inert and aria-hidden; a noscript
  definition list provides the same answers without JavaScript.
- Mobile navigation opens in 200ms and closes in 150ms. Its icon changes through
  transforms; the closed menu is immediately inert. Escape restores trigger focus.
  Desktop navigation, account menu and gallery behavior are unchanged.
- Liquid glass uses the original native recording over a reconstructed clean
  backdrop. It is labelled recorded appearance. The other two materials retain
  their synthetic animation; entering or leaving the recording resets playback
  because its choreography differs. Pause/offscreen/reduced-motion policies stay.

Native media and its reproducible recipe are in ../NativeGlassCrop. The shared
../Media/apply-assets.sh now copies that clip and poster as well as existing media.
The final browser loaded the 4.466667-second native clip with readyState 4;
only that selected video was playing. The browser error log was empty.
No app binary, camera, lock state, credential, public signing or deployment changed.

Validation:

- Full production build: 25/25 static pages; TypeScript passed. All five HTTP
  assertions passed using synthetic data. Scoped lint passed for all six sources.
- Actual browser at 1440px: selector sits exactly 20px below the laptop, buttons
  are 44px high, no horizontal overflow, product transform is none.
- FAQ pointer transition measured an intermediate height (15.5px, then 94.4px)
  before settling at its 102px content height. Mid-flight close/reopen settles
  correctly; close makes the answer inert immediately. Enter closes instantly
  with a computed transition duration of 0s.
- Mobile nav: 58.4px intermediate height, then 261px settled, 200ms transition.
  Escape produces height zero, inert content, 0s transition and trigger focus.
- 390px dark/reduced-motion: FAQ has 0s transition and its full 180px answer;
  all three automatic preview videos are paused; no horizontal overflow.
- The 320px check caught wrapped material labels; smaller narrow-screen padding
  fixes that: the final browser measurement is 44px for all three buttons,
  white-space: nowrap, a 20px gap and no horizontal overflow. Final layout
  evidence is in build/.

Browser evidence uses BrowserOS neo through agent-browser. Reduced motion was
emulated through the browser. The no-JavaScript fallback and reduced-transparency/
high-contrast CSS were inspected in source, not driven in a separate live browser.
Logs: build/website-home-final/{build,serve,smoke}.log. Local preview is
http://127.0.0.1:55523; no production configuration or data was used.
