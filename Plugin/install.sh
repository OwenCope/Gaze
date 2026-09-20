#!/bin/bash
set -euo pipefail

printf '%s\n' \
	'The legacy face-only authorization plugin is disabled pending a security redesign.' \
	'This installer makes no changes. Existing installations are not removed.' \
	'See SECURITY.md and Plugin/README.md before changing an existing authorization policy.' >&2
exit 1
