#!/usr/bin/env python3
"""Validate the actual light/dark PNG resources before asset-catalog compilation."""
import hashlib
import json
import struct
from pathlib import Path

assets = Path(__file__).resolve().parents[1] / 'Amp' / 'Assets.xcassets'
by_catalog = []
for catalog in ['AppIcon.appiconset', 'AmpLogo.imageset']:
    root = assets / catalog
    entries = json.loads((root / 'Contents.json').read_text())['images']
    light = [entry for entry in entries if not entry.get('appearances')]
    dark = [entry for entry in entries if {'appearance': 'luminosity', 'value': 'dark'} in entry.get('appearances', [])]
    assert len(light) == len(dark) == 1, f'{catalog}: expected one default and one dark resource'
    digests = []
    for appearance, entry in zip(['light', 'dark'], [light[0], dark[0]]):
        path = root / entry['filename']
        data = path.read_bytes()
        assert data[:16] == b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR', f'{path}: invalid PNG'
        width, height, depth, color = struct.unpack('>IIBB', data[16:26])
        assert (width, height, depth, color) == (1024, 1024, 8, 2), f'{path}: expected opaque 1024x1024 RGB8'
        digest = hashlib.sha256(data).hexdigest()
        digests.append(digest)
        print(f'{catalog} {appearance}: 1024x1024 RGB, SHA-256 {digest}')
    assert digests[0] != digests[1], f'{catalog}: dark must have its own artwork'
    by_catalog.append(digests)
assert by_catalog[0] == by_catalog[1], 'Home Screen and in-app logos must use the same master images'
print('Brand asset validation passed: both appearances are opaque and consistent.')
