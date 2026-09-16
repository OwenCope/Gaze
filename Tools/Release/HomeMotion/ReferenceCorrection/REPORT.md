# Correcting the website preview reference, September 16, 2026

The owner's two clips showed website previews. Solid and Semi glass used the
current 3D companion; Liquid glass used an older native recording with the flat
face. This mixed generations and backgrounds, and the generated panel was oversized.

Measured reference geometry: logical screen 1470x956 at 2x; physical cutout 179x32;
production default expanded panel rounds to 280x128. The old studio ratio was
400/960 = 41.7% of screen width; the corrected ratio is 280/1470 = 19.0%.
No actual Gaze app dimensions, preferences or security behavior were changed.

StudioRenderer.swift now uses that geometry and a cleaned background derived from
the provided lock-screen screenshot. Clock, status icons, avatar, account name and
password UI were removed. prepare-background.sh checks the source hash before
applying its measured cleanup; the raw screenshot was not added to the site.
These videos remain synthetic animation previews, not authentication recordings.

Normal and Semi glass were regenerated at 1470x956, 30fps, eight seconds. Both use
the same current production companion, backdrop and choreography. A 900x560 close-up
from the same normal video serves the explanatory section. Media/apply-assets.sh
copies these three media pairs. Hashes: Studio/assets/SHASUMS.txt.

The old flat-face native video has been taken out of the comparison. Both hidden
and visible OWN-window cacheDisplay probes lost the Liquid Glass material; the
screen-capture preflight was false and no permission was requested. Liquid Glass
is pending a current faithful capture. The owner's screenshot shows the background
but not the Gaze panel. Do not restore the old clip or ship the material-less probe
as current native appearance. Historical footage remains preserved in NativeGlassCrop.

Applied site sources: mac-screen.tsx, notch-video.tsx, live-demo.tsx. Final copies
and reference-preview.patch are in this folder. The patch is for the captured
pre-correction source, not an already updated checkout.

Validation: full decode and metadata checks pass for all three clips; 240 frames,
30fps, correct dimensions, faststart. TypeScript and scoped lint pass. The isolated
production build and all five HTTP checks pass. Browser inspection confirms two
current materials, new media loaded, no horizontal overflow and no page errors.
Current localhost preview: http://127.0.0.1:55523, exec session 28853, logs
build/website-reference-preview. Nothing deployed. No app, camera or lock test run.
