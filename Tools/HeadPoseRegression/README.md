# Head pose direction regression

Run the production pose math and challenge detector without camera or credentials:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/HeadPoseRegression/run.sh
```

The scalar fixtures come from the September 15 score-sweep recording. They check
that left/right demonstrations accept the corresponding raw yaw, still require
two excursion samples and a return, and lose completion on reset. They do not
authenticate an identity or establish unlock reliability.

To repeat the image audit on this workspace:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/HeadPoseRegression/run.sh /tmp/gaze-preview-direction-audit
```

The optional directory contains `camera-0.png` through `camera-9.png`, extracted
from the supplied recording at the times and crop rectangle recorded in
`CHALLENGE-INVESTIGATION.md`. Images are kept outside the repository. This check
runs Vision and the production landmark fallback on the same pixels, compares
their directions with the video readout, and verifies the mirrored challenge
and enrollment-ring mapping. It checks sign agreement, not calibrated pose
magnitudes or recognition accuracy.
