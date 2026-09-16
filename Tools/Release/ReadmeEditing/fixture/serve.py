#!/usr/bin/env python3
"""Localhost-only static server for the fixture. No production data."""
import functools
import http.server
import sys
from pathlib import Path

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8471
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(Path(__file__).resolve().parent))
srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
print(f"fixture on http://127.0.0.1:{port}/index.html", flush=True)
srv.serve_forever()
