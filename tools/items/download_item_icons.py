"""Restore the approved 128px item art from its recorded Runware URLs.

No inference calls are made. Existing valid downloads are reused.
Run: python tools/items/download_item_icons.py
"""

import json
import struct
import urllib.request
from pathlib import Path

from gen_items import ITEMS

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "graphics/generated/runware/source/items_wc3"
FINAL = ROOT / "graphics/ui/item_icons/warcraft"


def validate_png(data, slug):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        raise ValueError(f"{slug}: expected a nonempty PNG")
    size = struct.unpack(">II", data[16:24])
    if size != (128, 128):
        raise ValueError(f"{slug}: expected 128x128, got {size}")


def main():
    manifest = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    images = sum((manifest[key] for key in ("images", "recovered_images", "new_images")), [])
    expected = {entry[1] for entry in ITEMS}
    actual = {image["slug"] for image in images}
    if actual != expected or len(images) != len(expected):
        raise ValueError(f"Incomplete or duplicate icon set: missing={expected - actual}, extra={actual - expected}")
    FINAL.mkdir(parents=True, exist_ok=True)
    total_bytes = 0
    for image in images:
        slug = image["slug"]
        source = SOURCE / f"item_{slug}_source.png"
        if source.exists():
            data = source.read_bytes()
        else:
            with urllib.request.urlopen(image["url"], timeout=60) as response:
                data = response.read()
            validate_png(data, slug)
            source.write_bytes(data)
        validate_png(data, slug)
        target = FINAL / f"{slug}.png"
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
        total_bytes += len(data)
        print(f"{slug}: 128x128, {len(data)} bytes")
    cost = sum(image["cost"] for image in images)
    print(f"Ready: {len(images)} unique icons; {total_bytes} bytes; selected-image cost ${cost:.5f}.")


if __name__ == "__main__":
    main()
