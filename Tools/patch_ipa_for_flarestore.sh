#!/usr/bin/env bash
set -euo pipefail
: "${IPAPATCH:?Set IPAPATCH to the pinned, verified patcher executable}"
input=$1
output=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$2")
report=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$3")
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
"$IPAPATCH" --input "$input" --output "$temporary/patched.ipa" --noconfirm
mkdir "$temporary/original" "$temporary/patched"
unzip -q "$input" -d "$temporary/original"
unzip -q "$temporary/patched.ipa" -d "$temporary/patched"
app=$(find "$temporary/patched/Payload" -maxdepth 1 -type d -name '*.app')
test -n "$app"
original="$temporary/original/${app#"$temporary/patched/"}"
codesign --force --sign - "$app/Frameworks/zxPluginsInject.dylib"
while IFS= read -r -d '' extension; do
  source_extension="$temporary/original/${extension#"$temporary/patched/"}"
  codesign --display --xml --entitlements - "$source_extension" > "$temporary/extension.entitlements"
  codesign --force --sign - --generate-entitlement-der --entitlements "$temporary/extension.entitlements" "$extension"
done < <(find "$app/PlugIns" -depth -type d -name '*.appex' -print0)
codesign --display --xml --entitlements - "$original" > "$temporary/app.entitlements"
codesign --force --sign - --generate-entitlement-der --entitlements "$temporary/app.entitlements" "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$(dirname "$output")" "$(dirname "$report")"
(cd "$temporary/patched" && zip -qry "$output" Payload)
python3 Tools/verify_flarestore_patch.py "$input" "$output" > "$report"
cat "$report"
