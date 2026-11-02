"""Serves build/web locally for testing the web export: python tools/serve_web.py [port]

Python's default server can map .js to text/plain on Windows, which breaks Godot's audio worklets,
so the JavaScript and WebAssembly types are set explicitly (as a real host like Vercel does).
"""
import http.server
import mimetypes
import sys
from functools import partial
from pathlib import Path

mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
directory = Path(__file__).resolve().parent.parent / "build" / "web"
handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(directory))
print(f"Serving {directory} at http://127.0.0.1:{port}/index.html")
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
