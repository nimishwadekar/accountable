#!/usr/bin/env python3
"""Serve the CSV web audit build with an SPA fallback for Flutter paths."""

from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class SpaFallbackHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, directory: str, **kwargs):
        self.root = Path(directory).resolve()
        super().__init__(*args, directory=str(self.root), **kwargs)

    def do_GET(self) -> None:
        request_path = urlsplit(self.path).path
        candidate = (self.root / request_path.lstrip("/")).resolve()
        if not candidate.is_relative_to(self.root):
            self.send_error(403)
            return
        if not candidate.is_file() and not Path(request_path).suffix:
            query = urlsplit(self.path).query
            self.path = "/index.html" + (f"?{query}" if query else "")
        super().do_GET()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="build/mobile-ui-p2")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9020)
    arguments = parser.parse_args()

    root = Path(arguments.directory).resolve()
    if not root.is_dir():
        parser.error(f"Build directory does not exist: {root}")
    handler = partial(SpaFallbackHandler, directory=str(root))
    server = ThreadingHTTPServer((arguments.host, arguments.port), handler)
    print(f"Serving {root} at http://{arguments.host}:{arguments.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
