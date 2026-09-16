#!/bin/sh
cd "$(dirname "$0")/../.."
exec python3 -c '
import functools
import http.server

class NoStoreHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

handler = functools.partial(NoStoreHandler, directory="out")
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler).serve_forever()
'
