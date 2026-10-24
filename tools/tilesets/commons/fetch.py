#!/usr/bin/env python3 -I
"""Download the source SVGs for the "commons" tileset from Wikimedia Commons.

The SVGs are committed, so this only needs re-running to refresh them.
Usage: python3 -I tools/tilesets/commons/fetch.py
"""
import json
import pathlib
import time
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
UA = "dumbmahjong-tileset-fetch/0.1 (https://github.com/thepaul/dumbmahjong)"


def get(url):
    for attempt in range(5):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code != 429 and e.code < 500:
                raise
        time.sleep(2 ** attempt)
    raise RuntimeError(f"giving up on {url}")


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    for face, entry in manifest["faces"].items():
        name = entry["source"]
        dest = HERE / "svg" / name
        if dest.exists():
            continue
        url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(name)
        data = get(url)
        if not data.lstrip().startswith((b"<?xml", b"<svg")):
            raise RuntimeError(f"{name}: not an SVG")
        dest.write_bytes(data)
        print("fetched", name)
        time.sleep(1)


if __name__ == "__main__":
    main()
