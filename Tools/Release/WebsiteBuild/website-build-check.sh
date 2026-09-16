#!/bin/sh
# Build and smoke-test an isolated website copy, never the production configuration.
# Usage: website-build-check.sh [site-dir] [out-dir] [--smoke]
set -eu
SITE_DIR=/Users/owencope/Developer/gaze-site
OUTPUT_DIR=build/website-build-check
SMOKE=0
POSITION=0
for argument in "$@"; do
  case "$argument" in
    --smoke) SMOKE=1 ;;
    --help|-h) echo "Usage: $0 [site-dir] [out-dir] [--smoke]"; exit 0 ;;
    --*) echo "Unknown option: $argument" >&2; exit 2 ;;
    *) POSITION=$((POSITION + 1))
       case "$POSITION" in 1) SITE_DIR="$argument" ;; 2) OUTPUT_DIR="$argument" ;; *) echo 'Too many arguments' >&2; exit 2 ;; esac ;;
  esac
done
for tool in rsync python3 node curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 2; }
done
[ -x "$SITE_DIR/node_modules/.bin/next" ] || { echo "No installed Next.js at $SITE_DIR" >&2; exit 2; }
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_COPY="$(mktemp -d /tmp/gaze-site-build-XXXXXX)"
SERVER_PID=''
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$BUILD_COPY"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Copy only inputs needed by Next, excluding private configuration and real content.
rsync -a --exclude='.env*' --exclude='.npmrc' \
  --include='/src/***' --include='/public/***' \
  --include='/package.json' --include='/package-lock.json' \
  --include='/next.config.*' --include='/next-env.d.ts' \
  --include='/tsconfig.json' --include='/postcss.config.*' \
  --include='/tailwind.config.*' --include='/components.json' \
  --include='/middleware.*' --include='/proxy.*' --include='/instrumentation.*' \
  --exclude='*' "$SITE_DIR/" "$BUILD_COPY/"
# Turbopack requires dependencies inside its project root.
rsync -a "$SITE_DIR/node_modules/" "$BUILD_COPY/node_modules/"
mkdir -p "$BUILD_COPY/data"
FIXTURE_NAME="Synthetic build fixture ${BUILD_COPY##*/}"
python3 - "$BUILD_COPY/data" "$FIXTURE_NAME" <<'PY'
import json, sys
from pathlib import Path
root=Path(sys.argv[1])
(root/'releases.json').write_text(json.dumps([{
    'tag':'0.0-buildcheck', 'name':sys.argv[2], 'date':'2026-01-01T00:00:00.000Z',
    'body':'Synthetic fixture only; not a release or downloadable artifact.',
    'images':[], 'videos':[], 'contributors':[], 'prerelease':False, 'draft':False
}]))
(root/'settings.json').write_text(json.dumps({'releasesRequireSignIn':False}))
PY

# Do not inherit Blob/OAuth/email credentials, Vercel flags, NODE_OPTIONS or .env.
STATUS=0
(cd "$BUILD_COPY" && env -i PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
  NODE_ENV=production CI=1 NEXT_TELEMETRY_DISABLED=1 \
  AUTH_SECRET=build-check-synthetic-not-a-secret AUTH_TRUST_HOST=true \
  ./node_modules/.bin/next build) >"$OUTPUT_DIR/build.log" 2>&1 || STATUS=$?
tail -60 "$OUTPUT_DIR/build.log"
[ "$STATUS" = 0 ] || exit "$STATUS"

if [ "$SMOKE" = 1 ]; then
  PORT="$(python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(('127.0.0.1',0))
    print(s.getsockname()[1])
PY
)"
  (cd "$BUILD_COPY" && exec env -i PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
    NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 \
    AUTH_SECRET=build-check-synthetic-not-a-secret AUTH_TRUST_HOST=true \
    ./node_modules/.bin/next start --hostname 127.0.0.1 -p "$PORT") >"$OUTPUT_DIR/serve.log" 2>&1 &
  SERVER_PID=$!
  ATTEMPT=0
  until curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:$PORT/api/latest" >"$BUILD_COPY/feed.json" 2>/dev/null; do
    kill -0 "$SERVER_PID" 2>/dev/null || { cat "$OUTPUT_DIR/serve.log"; exit 1; }
    ATTEMPT=$((ATTEMPT + 1))
    [ "$ATTEMPT" -lt 40 ] || { echo 'Local server did not become ready' >&2; exit 1; }
    sleep 0.25
  done
  kill -0 "$SERVER_PID" 2>/dev/null || { echo 'Build-check server exited' >&2; exit 1; }
  python3 - "$PORT" "$FIXTURE_NAME" >"$OUTPUT_DIR/smoke.log" 2>&1 <<'PY'
import json, sys, urllib.request, urllib.error
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
for path, expected in [('/',200),('/releases',200),('/api/latest',200),('/dl/Gaze-0.3.dmg',404),('/admin',302)]:
    try: response=opener.open('http://127.0.0.1:'+sys.argv[1]+path, timeout=5)
    except urllib.error.HTTPError as error: response=error
    with response:
        status=response.code
        body=response.read(2_000_000)
        assert status == expected, (path,status,expected)
        if path == '/api/latest':
            value=json.loads(body)
            assert value['latest']['name'] == sys.argv[2], 'Response came from a different server or data source'
            assert value['latest']['download'] is None
            assert response.headers.get('Cache-Control') == 'no-store'
        if path.startswith('/dl/'):
            assert json.loads(body) == {'error':'Not found'}
            assert response.headers.get('Location') is None
            assert response.headers.get('Cache-Control') == 'no-store'
        if path == '/admin':
            assert '/signin' in response.headers.get('Location',''), 'Unauthenticated admin must be redirected to sign-in'
        print(path, '->', status, 'PASS')
PY
  cat "$OUTPUT_DIR/smoke.log" | tee -a "$OUTPUT_DIR/serve.log"
fi
printf '\nPASS: isolated production build%s. Production configuration and data were not used.\n' "$( [ "$SMOKE" = 1 ] && printf ' and HTTP assertions' || true )"
