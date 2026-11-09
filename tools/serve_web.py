"""Serves a web export locally for testing: python tools/serve_web.py [port] [directory]   (default: build/web)

Python's default server can map .js to text/plain on Windows, which breaks Godot's audio worklets,
so the JavaScript and WebAssembly types are set explicitly (as a real host like Vercel does).
"""
import http.server
import json
import mimetypes
import sys
from functools import partial
from pathlib import Path

mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
directory = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "build" / "web"
received = directory.parent / "received_events.jsonl"


class Handler(http.server.SimpleHTTPRequestHandler):
    """Static files, plus a stand-in for the real /api/ingest: it appends every received event to
    build/received_events.jsonl (no validation, unlike the real endpoint) so the sender can be tested locally."""

    def do_POST(self):
        if self.path != "/api/ingest":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            events = json.loads(body)["events"]
        except (ValueError, KeyError, TypeError):
            self.send_error(400)
            return
        with received.open("a", encoding="utf-8") as out:
            for event in events:
                out.write(json.dumps(event, separators=(",", ":")) + "\n")
        self.send_response(204)
        self.end_headers()


handler = partial(Handler, directory=str(directory))
print(f"Serving {directory} at http://127.0.0.1:{port}/index.html  (POST /api/ingest -> {received})")
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
