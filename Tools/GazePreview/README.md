# Gaze Preview

## Render timing diagnostics

The shared renderer supports opt-in timing logs, including the real lock-screen
wrapper. Restart the main app with `./script/build_and_run.sh --render-diagnostics`
(`--no-build` reuses a verified existing build). Omit the flag on the next launch
to disable it. The launcher passes the environment explicitly through `open`;
no preference or authentication setting is changed.

```sh
/usr/bin/log show --predicate 'subsystem == "com.gazeunlock.Gaze" AND category == "RenderTiming"' --last 10m --style compact
```

Logs report callback/submission counts, busy-frame skips, unavailable resources,
encoding failures, callback interval p95/max, total draw-call max, and time spent
obtaining `currentDrawable`. `windowVisible` is AppKit's occlusion state at report
time. It is not proof that a lock-screen space is visible to the user. Samples
flush every two seconds and when a context ends or pauses, so brief movement
attempts remain observable. No face images, templates or credentials are logged.
These measurements do **not** measure GPU completion or presented-frame timing.

For a camera-free measurement of the production renderer in a native event loop:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/GazePreview/probe-render-timing.sh 30
```

This displays a temporary simulated window and measures four 30-second segments:
recognition-sized and notch-sized companions, each with a steady parent and with
30 Hz parent updates. An optional second argument, `--reverse`, reverses that order.
The final check verifies that Reduce Motion pauses rendering and clears timing
history. Run it separately from GPU/render tests or builds. It excludes camera,
inference and actual lock-screen composition, so it cannot certify unlock smoothness.

## Current review

**Preview-only expressive idle:** options 2 and 3 now use an authored eight-second performance: rest, anticipate, compress, scoot, stretch, land, settle, and pause for an inquisitive lean. Option 2 uses 65% of option 3's energy. The eyes remain attached and neutral, with no blinking or fake success smile. The same approved material is unchanged. This experiment lives entirely in `Tools/GazePreview/Studies/CompanionIdlePerformance.swift`; shared/main-app idle, guidance, and result motion are not changed by this revision. Use `test-soft-3d.sh <output> --idle-video` to export the pair; `test-studies.sh` checks phase order, continuity, interruptions and Reduce Motion. The Metal tests verify actual silhouette deformation and clipping bounds, not only pose values.

Idle now wanders gently side to side in a shallow upward arc, then returns to center between glances. Translation moves the complete 3D volume and its attached features; no blink, facial sliding, or shape change is added. Guidance and results remain centered, interruptions blend from the current position, and Reduce Motion stays static. The Metal regression checks visible translation, frame bounds, and attached features; the sampler regression checks bounded travel and seamless loops. This revision is available in the rebuilt standalone preview; the main app bundle has not been rebuilt for it.

- Build with `bash Tools/GazePreview/build.sh`, then reopen `build/Gaze Preview.app` to load the new executable.
- **Studies → Animation Studies** (Shift–Command–A): compare options 2 and 3 with the rounded-square, semi-transparent 3D companion. Idle makes a tiny whole-body glance with anchored eyes and no blinking. Result expressions use deliberate preview timing, not the lock screen's authentication budget.
- **Studies → Recognition Layout…** (Shift–Command–R): inspect the refreshed Test Recognition layout using simulated data. No camera, recognition, password entry, or unlocking runs here.
- Shared companion rendering is in `Sources/Companion`. The notch overlay (including the main preview canvas), setup result, Test Recognition, and option 3 now use the same smile-and-nod / sad-shake choreography. Variant controls remain developer-only.
- Run `test-studies.sh` for sampled motion/interruptions and `test-soft-3d.sh` for Metal renders, transparency, volume, and recognition-layout snapshots. Rendered video and GPU time are not measurements of live recognition performance.

The user's real left/right challenge mismatch and repeated incorrect lock-screen password submissions are still unresolved. Do not use a preview to sign off either issue.

### Continuous body and anchored idle — September 12

The painted ring around the front surface has been removed from the Metal material. Rim light now follows the outside silhouette, with continuous charcoal shading across the sidewalls and back. The upper-left soft reflection, thick capsule eyes, lowered smile, full volume and transparency remain. No geometry or authentication thresholds are changed.

Idle now turns the entire body a few degrees rather than sliding the eyes across its curved surface; no blinking, bobbing, or breathing is added. This supersedes the earlier gaze-only notes below. The studies retain their individual timing, and the deliberate challenge turns remain much larger than idle glances. Toolbar pointer-follow behavior is unchanged.

`test-soft-3d.sh <output> --body-video` checks idle silhouette movement, rigidly attached features at front/three-quarter angles, and the absence of the old narrow interior highlight on either turn. It exports a 60 fps idle/turn review; this is GPU-rendered evidence, not a display-FPS or authentication test.

### Inactive-window result fix — September 12

The shared companion now observes playback changes during SwiftUI body evaluation and submits a static final expression whenever animation is paused. Changing window focus no longer restarts the success/failure choreography; explicit Replay still does. The 3D charcoal material also picks up the reference's soft upper-left sheen and restrained light rim, without changing the eyes, smile geometry, body opacity, or toolbar assets.

`test-companion-integration.sh` now mounts the actual recognition panel with simulated inputs, transitions from guidance through success/failure under frequent readout updates, and tests focus changes, Replay, and Reduce Motion. It reproduces the old inactive-window neutral-face failure. Its `active-final-drawable.png` and `inactive-final-drawable.png` read back real paused Metal drawable textures and assert visible smile pixels; other layout images remain offline composites. This proves UI rendering, not camera recognition or lock-screen authentication. No credentials are used and the main app is not launched by the harness.

### Shared success integration — September 12

The notch and setup previously used older, separate faces. They now use the same 3D volume and expressive result as option 3: unchanged thick capsule eyes, a thicker smile set below them, a downward nod for success, and a frown/shake for failure. Idle/scanning only move the eyes; no implicit blink. The notch adapts the choreography to 440 ms and eases the smile in over 140 ms, fitting inside the **unchanged** existing 480 ms authentication delay. Setup and Test Recognition retain the longer 1.4-second nod. None of these views delays, approves, or retries authentication.

The approved companion stays charcoal glass with white eyes and a lowered white smile in every theme, including the black notch housing. The rejected pearl/white companion is not used. Only the small Settings navigation icon switches white/black with the app theme; that toolbar-only treatment must not propagate to the animations. Reduce Motion is static; Reduce Transparency makes the volume opaque. Metal-unavailable fallback keeps the same capsule eyes and smile rather than returning to checkmarks.

Run `bash Tools/GazePreview/test-companion-integration.sh /absolute/output` to inspect actual instantiated notch, setup, and recognition-companion wrappers with fake visual state. It checks renderer connections, inactive lock-panel animation, paused/hidden/reduced states, materials, and result poses. The harness composites offline Metal renders at the actual hosted view bounds because normal AppKit bitmap captures omit Metal layers. Its images/video are deterministic visual evidence, **not screen recordings or actual lock/unlock tests**. The `success-frames` export compares the long result to the shorter notch beat at 60 fps.

The historical review notes below describe earlier iterations. Their statements that the lock overlay is unchanged/no longer uses the shared renderer are superseded by this integration.

An independent native app for staging notch recordings. It compiles the same `NotchCapsule`, shape and preview canvas as Gaze; it does not start Gaze’s services or access its preferences, camera, enrollment, Keychain, passwords, lock screen or network.

The shared dimensional face demonstrates left/right turns, nodding, blinking, and opening the mouth. Select **Movement**, then choose the action in Playback. These are demonstrations, not recognition tests. Each movement phase plays for at least three seconds. With Reduce Motion enabled, the face stays still and the written instruction remains visible.

The **Reduce motion** preview toggle lets you check that fallback without changing macOS settings. It never disables the system's accessibility preference. The main Notch settings page shows only a live appearance preview; phase selection and playback remain in this separate tool.

Scanning includes quiet gaze shifts and occasional blinking. Verified smiles and nods once; Rejected frowns and shakes its head once. Both then settle, without check/cross badges. The success nod fits the existing 480ms lock-screen success beat; no authentication timing is changed. Reduce Motion keeps a static smile or frown and preserves accessible status labels.

Build with `bash Tools/GazePreview/build.sh`, then open `build/Gaze Preview.app`. The script uses the macOS 26.5 SDK; set `SDKROOT` to select another compatible SDK. macOS 26 or newer is required.

- The stage is on the left; the inspector on the right holds Notch, Playback and Canvas controls.
- Select a phase below the stage to stop playback and inspect that state. Press **Space** or click **Play sequence** to run all phases.
- Enable looping and set the time per phase in Playback for repeatable takes.
- The toolbar button or **Shift–Command–H** hides or restores the inspector and playback strip. **Escape** also restores them. The Recording menu remains available when controls are hidden.
- Use macOS full screen or record just the window with your capture tool.
- Choose a background image or System, White, Black or Green screen. Background images are read locally, not copied or uploaded.
- Shape, material, ear placement and sizing only affect the preview. All settings reset when it quits, apart from the window geometry macOS saves.
- Ear placement hides material, contrast, transparency and height controls. Floating keeps the mark in the panel. Transparency appears only for Semi Liquid Glass; contrast appears only for translucent styles.

This app stages animations; it does not capture or export video itself. Screenshots and recordings contain simulated authentication states, not a real recognition attempt.

## Animation studies

### Latest: approved video appearance with depth only

The user approved the earlier face in `CleanShot 2026-09-12 at 10.32.11 AM.mp4`, not the subsequent glossy blob. That video is now the reference: rounded-square silhouette, dark diagonal gradient, inset rim, capsule eyes, and restrained highlights. The renderer adds rounded sidewalls and a rear surface; it no longer changes the face into an inflated blob. Existing study choreography is unchanged by this depth refinement, and idle remains gaze-only.

The body uses partial alpha with opaque face features; pixels outside the shape are transparent. **Backdrop** shows a two-tone transparency check. **View angle** in single-option view covers a full rotation for inspecting real side thickness and the back. The test harness’s `--depth-video` mode exports a neutral turntable explicitly labelled as an inspection, not a verification gesture. Tests check alpha, backside feature occlusion, visible side-on thickness, and restrained back highlights. Earlier descriptions below are retained as review history, not current appearance specifications.

Sidewalls and the back now share the front's charcoal tonal range and soft reflection instead of dropping to near-black. Front eyes, smile, silhouette, and translucency are unchanged. The depth turntable uses a pure-black background, and the Metal regression compares body luminance at 45°, 90°, 180°, and −90° against the front at 36/72/520 px. This changes the shared 3D companion in the studies and Test Recognition, not the separate SwiftUI lock-overlay face.

### Current review: small glossy black slime (2 & 3)

The studies window now opens **Curious Companion** and **Soft Bounce** side by side, both using the same tiny black, reflective 3D body and thick rounded eyes. The first emphasizes eye-led guidance and a deliberate nod; the second adds soft compression and follow-through. The grey, box-like direction was rejected. The main app and its lock-screen renderer have not been changed by this refinement.

Idle/scanning in these studies **only shift gaze**: eyes remain open, body stays still, no blinking, bobbing, or squash. Blink remains an explicit guidance action. New regression assertions sample the full loop to enforce that distinction.

These are longer review performances: happy motion settles around 1.3–1.4 seconds and holds; sad movement finishes by 1.9 seconds. This intentionally does **not** fit the main app’s existing 480 ms success beat. Do not copy the timings into authentication or delay password submission; production integration needs a separate decision about safe presentation timing.

`SoftFaceMetalView` drives the 3D face through MetalKit, independently of the 20 Hz controls scrubber. The GPU shader intersects an actual rounded volume and derives lighting, perspective, feature occlusion, and deformation from it. It is not a rotated sprite. Render resources are retained; paused, reduced-motion, inactive, and removed views stop continuous rendering. The display request is 120 Hz, not a guarantee. **Frame timing** reports measured callback cadence and p95 intervals, retaining the last sample while paused; this is not presented-frame measurement.

Build with the same preview build script. Use `bash Tools/GazePreview/test-soft-3d.sh <output-directory> --video` for Metal shader compilation, both variants at 36/72/520 pixels, expression weight, backside occlusion, GPU-only timing, and an actual GPU-rendered comparison. `test-studies.sh` still validates the pure samplers, blends, timing, reduced motion and gaze-only idle; its older SwiftUI card renders are not evidence of the new Metal face. No credentials or lock services are used by either harness.

The following records the original three-option round; its old timing and idle descriptions do not describe the current 2 & 3 revision.

Open **Animation Studies** from the preview toolbar or **Studies → Animation Studies** (Shift–Command–A). The controls remain developer-only. The shared 3D renderer and option 3 motion also serve Test Recognition; the lock overlay is unchanged.

- **01 Quiet Focus:** eye-led idle, a small happy nod, a restrained sad shake. Least distracting, but more subtle at notch size.
- **02 Curious Companion:** the eyes glance before the head follows, with a tilt and more deliberate nod. More personality and more head movement.
- **03 Soft Bounce:** brief squash/stretch, blink compression and soft follow-through. Most expressive, deliberately less restrained.

Compare the three in sync, or select one to inspect it larger. Each includes a fixed 36 pt readability sample; these samples are not the real lock overlay. Select Idle, Guide (five gestures), Success, or Try again; use Replay, Pause, the scrubber, and ¼×–1½× speed. Results play once and hold. Options 2 and 3 use 2.4-second success and 2.6-second retry review scenes; no authentication timing is altered. New events blend from the currently displayed pose. Reduce Motion shows static expressions and written guidance, and cannot override the system setting.

These are animation directions for review, not a shipped selection setting. Verify the pure samplers, interrupted playback, and rendered comparison with `bash Tools/GazePreview/test-studies.sh [output-directory]`.
