"""Installs only the Godot web export templates, without downloading the whole 1+ GB templates archive.

The official .tpz is a zip file and the server supports HTTP range requests, so this reads the zip index and
fetches just the web templates (about 40 MB). Their CRCs are verified while reading.

Usage: python tools/fetch_web_templates.py --version 4.7.2 --dest <export_templates>/4.7.2.stable
  Windows: %APPDATA%/Godot/export_templates/4.7.2.stable    Linux: ~/.local/share/godot/export_templates/4.7.2.stable
"""
import argparse
import io
import urllib.request
import zipfile
from pathlib import Path

URL = "https://downloads.godotengine.org/?version={version}&flavor=stable&slug=export_templates.tpz&platform=templates"
# The Godot download host answers 403 to urllib's default User-Agent.
HEADERS = {"User-Agent": "coin-collector-template-fetch/1.0 (+https://github.com/LutherNogueira/coin-collector)"}
WANTED = ["version.txt", "web_nothreads_release.zip", "web_nothreads_debug.zip", "web_release.zip", "web_debug.zip"]


class RangeFile(io.RawIOBase):
    """A read-only, seekable file backed by HTTP range requests."""

    def __init__(self, url: str) -> None:
        head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD", headers=HEADERS))
        self.url = head.geturl()   # the redirect target
        self.size = int(head.headers["Content-Length"])
        self.pos = 0
        self.downloaded = 0

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence]
        self.pos = base + offset
        return self.pos

    def read(self, n: int = -1) -> bytes:
        if n < 0 or self.pos + n > self.size:
            n = self.size - self.pos
        if n <= 0:
            return b""
        request = urllib.request.Request(self.url, headers={**HEADERS, "Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        data = urllib.request.urlopen(request).read()
        self.pos += len(data)
        self.downloaded += len(data)
        return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True, help="Godot version, e.g. 4.7.2")
    parser.add_argument("--dest", required=True, type=Path, help="export_templates/<version>.stable folder")
    args = parser.parse_args()

    remote = RangeFile(URL.format(version=args.version))
    archive = zipfile.ZipFile(remote)
    args.dest.mkdir(parents=True, exist_ok=True)
    for name in WANTED:
        data = archive.read("templates/" + name)   # raises if the CRC does not match
        (args.dest / name).write_bytes(data)
        print(f"{name}: {len(data) / 1048576:.1f} MiB")
    print(f"downloaded {remote.downloaded / 1048576:.1f} MiB of a {remote.size / 1048576:.0f} MiB archive")


if __name__ == "__main__":
    main()
