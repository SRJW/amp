"""Verify a compatibility copy without changing the normal IPA or its identity."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

LOAD_WEAK_DYLIB = 0x80000018
PATCH = "@rpath/zxPluginsInject.dylib"


def macho(data):
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected the arm64 64-bit Mach-O produced by amp's device build")
    count = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    loads, entitlements = [], None
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command in (0xC, LOAD_WEAK_DYLIB, 0x8000001C):
            position = struct.unpack_from("<I", data, offset + 8)[0]
            name = data[offset + position:offset + size].split(b"\0", 1)[0].decode()
            loads.append((command, name))
        if command == 0x1D:
            start, length = struct.unpack_from("<II", data, offset + 8)
            blob = data[start:start + length]
            magic, _, slots = struct.unpack_from(">III", blob)
            if magic != 0xFADE0CC0:
                raise ValueError("Invalid code signature superblob")
            for slot in range(slots):
                kind, position = struct.unpack_from(">II", blob, 12 + slot * 8)
                if kind == 5:
                    _, length = struct.unpack_from(">II", blob, position)
                    entitlements = plistlib.loads(blob[position + 8:position + length])
        offset += size
    return loads, entitlements


def verify(original, patched):
    result = []
    with zipfile.ZipFile(original) as source, zipfile.ZipFile(patched) as target:
        source_names, target_names = set(source.namelist()), set(target.namelist())
        infos = sorted(n for n in source_names if n.endswith((".app/Info.plist", ".appex/Info.plist")))
        if not any(n.endswith(("AmpPlayerWidget.appex/Info.plist", "ErhuPlayerWidget.appex/Info.plist")) for n in infos):
            raise ValueError("The source IPA is missing the widget extension")
        executables = set()
        for name in infos:
            before, after = plistlib.loads(source.read(name)), plistlib.loads(target.read(name))
            if before != after:
                raise ValueError(f"Bundle metadata changed: {name}")
            executable = name.rsplit("/", 1)[0] + "/" + before["CFBundleExecutable"]
            executables.add(executable)
            original_loads, original_entitlements = macho(source.read(executable))
            patched_loads, patched_entitlements = macho(target.read(executable))
            if any(path == PATCH for _, path in original_loads):
                raise ValueError("The input IPA was already patched")
            if patched_loads.count((LOAD_WEAK_DYLIB, PATCH)) != 1:
                raise ValueError(f"Expected exactly one patch load in {executable}")
            if original_loads != [entry for entry in patched_loads if entry != (LOAD_WEAK_DYLIB, PATCH)]:
                raise ValueError(f"Unrelated loader commands changed: {executable}")
            if original_entitlements != patched_entitlements:
                raise ValueError(f"Entitlements changed: {executable}")
            if not patched_entitlements or not patched_entitlements.get("com.apple.security.application-groups"):
                raise ValueError(f"App Group declaration missing: {executable}")
            rpath = "@executable_path/../../Frameworks" if ".appex/" in name else "@executable_path/Frameworks"
            if (0x8000001C, rpath) not in patched_loads:
                raise ValueError(f"The injected library cannot be resolved: {executable}")
            result.append({"bundle": before["CFBundleIdentifier"], "build": before["CFBundleVersion"],
                           "patch_loads": 1, "entitlements_preserved": True})
        app_info = next(n for n in infos if n.endswith(".app/Info.plist"))
        library = app_info.rsplit("/", 1)[0] + "/Frameworks/zxPluginsInject.dylib"
        if library not in target_names:
            raise ValueError("Injected library missing")
        if source_names - target_names:
            raise ValueError("Files were removed from the normal IPA")
        for name in source_names:
            if name in executables or "/_CodeSignature/" in name:
                continue
            if source.read(name) != target.read(name):
                raise ValueError(f"Unrelated bundle resource changed: {name}")
        additions = {n for n in target_names - source_names if not n.endswith("/") and "/_CodeSignature/" not in n}
        if additions != {library}:
            raise ValueError(f"Unexpected files added: {sorted(additions)}")
        info = plistlib.loads(source.read(app_info))
    return {"release": info.get("AmpReleaseTag") or info["ErhuReleaseTag"], "bundles": result,
            "source_sha256": hashlib.sha256(Path(original).read_bytes()).hexdigest(),
            "patched_sha256": hashlib.sha256(Path(patched).read_bytes()).hexdigest()}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_flarestore_patch.py normal.ipa patched.ipa")
    print(json.dumps(verify(*sys.argv[1:]), indent=2))
