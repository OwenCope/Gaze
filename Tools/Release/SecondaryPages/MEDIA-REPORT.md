# Homepage setup previews

The homepage gallery now uses four first-party native setup renders from `build/gaze-usability-final-onboarding`. They were produced by Gaze's synthetic setup-render workflow rather than captured from a user's desktop or camera. The exported WebP files contain no recording or user data.

Each image was resized proportionally with Pillow's Lanczos resampler and saved as WebP at quality 90, without cropping or changing the visible interface:

- `welcome-dark.png` → `public/product/setup-welcome.webp` (880 × 660)
- `meetGaze-dark.png` → `public/product/setup-companion.webp` (880 × 660)
- `how-dark.png` → `public/product/setup-how.webp` (880 × 660)
- `lesson-turnLeft-dark.png` → `public/product/setup-movement.webp` (560 × 380)

These static previews show the native setup UI with the camera off. They do not demonstrate live camera output, recognition accuracy, liveness detection, movement tracking, unlock behavior, or runtime performance.

The updated component and media are mirrored under `files/src/components` and `files/public/product`. No build or browser verification was run in this task; combined verification belongs to the root task.
