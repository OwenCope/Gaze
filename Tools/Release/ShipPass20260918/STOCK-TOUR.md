# Stock TourKit checkpoint

The installed app uses the unmodified upstream TourKit source with five pages.
The 660-point stock view scales uniformly to a 720x680 panel, including its
buttons and text. The 760x680 host is transparent and borderless; the welcome
step adds no visible header, footer, or second Skip control. Rounded PNG variants
preserve the original artwork dimensions, RGB values, and aspect-fit behavior.
Enrollment, password, and permission functions remain in the setup flow.

Installed at `build/Gaze.app` and relaunched on 2026-09-18 at 08:41 UTC.
One new agent process, PID 17938, was verified at that executable path.

- Executable SHA-256: `d60d756c8b167fed9cacd10275803e029b6269c44407217308d742a016f98b60`
- TourKit source SHA-256, matching the pinned upstream: `4d67d1f9eaa13dd63d5dc72044b5a9d28cb707117e0a39ef6070ca6187a76207`
- Build: `build/gaze-ship-20260918/stock-tour-build.log`
- Build and bundled-artwork checks: `build/gaze-ship-20260918/stock-tour-build-result.json`
- Installation receipt: `build/gaze-ship-20260918/stock-tour-install-result.json`
- Previous app: `build/archive/2026-09-18/before-stock-tour-20260918T084118Z/Gaze.app`
- Artwork provenance: [tour-rounded-art.json](tour-rounded-art.json)

The integrated build, signing requirement, bundled artwork hashes, and relaunch
passed. Hank 7 repaired the upstream interaction fixture. Root then connected
the rounded assets and actual760x680 borderless host: all five pages, one set of
navigation controls, Back, Next, completion, Close, and no clipping passed.
Captures and bounds are under `build/gaze-ship-20260918/stock-tour-interaction`;
the run log is `stock-tour-fixture.log`. Dragging, live camera/unlock, Escape,
and restoration are not covered by this fixture. Earlier nine-page screenshots
do not describe this version. The earlier DMG has not been repackaged.
