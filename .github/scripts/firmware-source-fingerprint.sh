#!/usr/bin/env bash
# Hash the moving upstream revisions that can change ZMK build outputs even
# when this repository only changes its keymap.
set -euo pipefail

manifest_json="$(yq -oj '.' config/west.yml)"
projects_json="$(jq -ce '
  .manifest as $m |
  ($m.remotes | map({key: .name, value: .["url-base"]}) | from_entries) as $remotes |
  [$m.projects[] |
    "\($remotes[.remote])/\(.name)@\(.revision // $m.defaults.revision)"]
' <<< "$manifest_json")"
[[ "$(jq -r 'length' <<< "$projects_json")" -ge 3 ]] || exit 1
mapfile -t projects < <(jq -r '.[]' <<< "$projects_json")

# The reusable workflow itself follows @main and can also change the build.
projects+=("https://github.com/urob/zmk-actions@main")

{
  for item in "${projects[@]}"; do
    if [[ ! "$item" =~ ^https://github.com/([^/]+)/([^@]+)@(.+)$ ]]; then
      echo "Cannot fingerprint upstream source: $item" >&2
      exit 1
    fi
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    revision="${BASH_REMATCH[3]}"
    sha="$(gh api "repos/$owner/$repo/commits/$revision" --jq '.sha')"
    if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      echo "Invalid upstream commit: $item" >&2
      exit 1
    fi
    printf '%s/%s %s\n' "$owner" "$repo" "$sha"
  done
} | sha256sum | cut -d ' ' -f1
