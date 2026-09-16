# Native Liquid Glass preview, September 16, 2026

Root recovered the native panel from the existing `public/clips/liquidGlass.mp4`
recording after the delegated attempts stopped without edits. No new desktop,
camera, lock screen or credentials were captured.

The material and glyph are recorded pixels, cropped at x520/y0, 240x128, then
scaled to 400x214 at the top of a 960x600 studio frame. The first 4.5 seconds are
selected; the encoded result contains 134 frames, 4.466667 seconds at 30 fps.
The last portion of the original six-second recording is excluded because its
retracting panel reveals menu icons beside the crop. The original is 1280x832.

The surrounding studio backdrop is reconstructed from fixed empty wallpaper
samples with a cubic color surface (make_backdrop.py, Python standard library).
This avoids stretching a narrow strip into visible seams. A fade from crop row
100 through 128 joins only the wallpaper below the panel to the studio backdrop;
the native glass panel above it is not repainted. This is a composed appearance
preview, not a newly measured unlock or an authentication-success claim. The
recording predates the current synthetic panel choreography.

`extract.sh` is the reproducible recipe; default input is the original local
recording. H.264/yuv420p, 960x600, 30 fps, CRF18, no audio, faststart confirmed by
box parsing, and full decode passes. Cropped contact sheets and start/middle/end
inspection found no cursor, desktop files, weather widget or menu text in the
selected panel region. Source recording and unredacted frames are not shipped.

The website names the option Liquid glass and labels it Recorded appearance.
Other options keep the current synthetic panel animation; switching between
them and the recording restarts the corresponding timeline. Pause, visibility
and reduced-motion behavior are preserved.

Hashes are recorded in assets/SHASUMS.txt. Media metadata:

{
  "programs": [],
  "stream_groups": [],
  "streams": [
    {
      "width": 960,
      "height": 600,
      "pix_fmt": "yuv420p",
      "avg_frame_rate": "30/1",
      "nb_frames": "134"
    }
  ],
  "format": {
    "duration": "4.466667",
    "size": "65164"
  }
}
