#!/usr/bin/env bash
set -euo pipefail

ipa=${1:-dist/amp.ipa}
: "${GH_REPO:?Missing repository}"
: "${GH_TOKEN:?Missing workflow token}"
: "${IPA_BUILD_NUMBER:?Missing source build number}"
: "${IPA_SOURCE_SHA:?Missing source commit}"
[[ "$IPA_BUILD_NUMBER" =~ ^[0-9]+$ ]]
[[ "$IPA_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
test -s "$ipa"
tag="v1.1.${IPA_BUILD_NUMBER}"
asset_name="amp-${tag}.ipa"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

retry_gh() {
  local attempt=1
  local out=""
  while [ "$attempt" -le 3 ]; do
    if out=$("$@" 2>&1); then
      printf '%s' "$out"
      return 0
    fi
    echo "publish_ipa: attempt $attempt failed for $*: $out" >&2
    attempt=$((attempt + 1))
    sleep 3
  done
  return 1
}

# A republish job uses the original build's version and SHA, not its own run number.
if gh api "repos/$GH_REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
  test "$(retry_gh gh api "repos/$GH_REPO/commits/$tag" --jq '.sha')" = "$IPA_SOURCE_SHA"
else
  retry_gh gh api --method POST "repos/$GH_REPO/git/refs" -f ref="refs/tags/$tag" -f sha="$IPA_SOURCE_SHA" >/dev/null
fi

# Check recent releases (including drafts) without paginating 100+ old releases.
release_id=$(retry_gh gh api "repos/$GH_REPO/releases?per_page=30" \
  --jq ".[] | select(.tag_name == \"$tag\") | .id")
if [ -z "$release_id" ]; then
  python3 - "$temporary/release.json" <<'PY'
import json, os, sys
number = os.environ['IPA_BUILD_NUMBER']
source = os.environ['IPA_SOURCE_SHA']
body = ('AMP v1.1.' + number + ' (iPhone build ' + number + ').\n\n'
        'Re-sign before installing, preserving the same authorized App Group for the app and widget. '
        'Signing requests do not grant provisioning permissions.\n\nSource: ' + source + '.')
if os.environ.get('NATIVE_CHECKS_RESULT') == 'success':
    body += '\nNative player interaction and rendered blend verification passed.'
else:
    body += '\nNative simulator validation is reported separately; this development IPA publication does not certify that those checks passed.'
with open(sys.argv[1], 'w') as output:
    json.dump(dict(tag_name='v1.1.' + number, target_commitish=source,
                   name='amp v1.1.' + number, body=body,
                   draft=True, prerelease=True), output)
PY
  release_id=$(retry_gh gh api --method POST "repos/$GH_REPO/releases" --input "$temporary/release.json" --jq '.id')
fi
[[ "$release_id" =~ ^[0-9]+$ ]]

gh api "repos/$GH_REPO/releases/$release_id/assets" > "$temporary/assets.json"
asset_id=$(ASSET_NAME="$asset_name" python3 - "$temporary/assets.json" <<'PY'
import json, os, sys
target = os.environ['ASSET_NAME']
assets = [a for a in json.load(open(sys.argv[1])) if a['name'] == target]
assert len(assets) <= 1
if assets:
    assert assets[0]['state'] == 'uploaded', 'Existing upload is incomplete; inspect it before replacing it'
    print(assets[0]['id'])
PY
)
if [ -z "$asset_id" ]; then
  curl --fail-with-body --silent --show-error --request POST \
    --header "Authorization: Bearer $GH_TOKEN" \
    --header 'Content-Type: application/octet-stream' \
    --data-binary "@$ipa" \
    "https://uploads.github.com/repos/$GH_REPO/releases/$release_id/assets?name=${asset_name}" > "$temporary/asset.json"
else
  gh api "repos/$GH_REPO/releases/assets/$asset_id" > "$temporary/asset.json"
fi
python3 - "$ipa" "$temporary/asset.json" <<'PY'
import hashlib, json, pathlib, sys
ipa = pathlib.Path(sys.argv[1])
asset = json.load(open(sys.argv[2]))
assert asset['state'] == 'uploaded' and asset['size'] == ipa.stat().st_size
if asset.get('digest'):
    assert asset['digest'] == 'sha256:' + hashlib.sha256(ipa.read_bytes()).hexdigest()
PY
if [ "$(gh api "repos/$GH_REPO/releases/$release_id" --jq '.draft')" = 'true' ]; then
  gh api --method PATCH "repos/$GH_REPO/releases/$release_id" -F draft=false >/dev/null
fi
printf '[Download %s directly](https://github.com/%s/releases/download/%s/%s)\n' \
  "$asset_name" "$GH_REPO" "$tag" "$asset_name" >> "$GITHUB_STEP_SUMMARY"
