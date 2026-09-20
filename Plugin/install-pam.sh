#!/bin/bash
set -euo pipefail

printf '%s\n' \
	'Face-only sudo authentication is disabled pending request-bound owner approval.' \
	'This installer makes no changes. Existing installations are not removed.' \
	'See SECURITY.md and Plugin/README.md before changing an existing PAM configuration.' >&2
exit 1
