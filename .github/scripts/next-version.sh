#!/usr/bin/env bash
# Print the next release version from Conventional Commit messages since the
# last v* tag, or nothing when no commit warrants a release.
#
#   feat           -> minor
#   fix, perf      -> patch
#   type!: / BREAKING CHANGE footer -> major
#   docs, test, ci, chore, refactor, style, build -> no release
#
# With no v* tag yet, the version in manifest.json is the first release.
set -euo pipefail

last="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
if [[ -z "$last" ]]; then
  jq -r .version manifest.json
  exit 0
fi

bump=0 # 0 none, 1 patch, 2 minor, 3 major
while IFS= read -r -d $'\x1e' msg; do
  # git log puts a newline after each separator; drop leading blank lines.
  while [[ "$msg" == $'\n'* ]]; do msg="${msg#$'\n'}"; done
  subject="${msg%%$'\n'*}"
  if [[ "$subject" =~ ^[a-z]+(\([^\)]*\))?!: ]] || grep -qE '^BREAKING[ -]CHANGE:' <<<"$msg"; then
    bump=3
  elif [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
    (( bump < 2 )) && bump=2
  elif [[ "$subject" =~ ^(fix|perf)(\([^\)]*\))?: ]]; then
    (( bump < 1 )) && bump=1
  fi
done < <(git log --format='%B%x1e' "$last..HEAD")

(( bump == 0 )) && exit 0
IFS=. read -r major minor patch <<<"${last#v}"
case "$bump" in
  3) echo "$((major + 1)).0.0" ;;
  2) echo "$major.$((minor + 1)).0" ;;
  1) echo "$major.$minor.$((patch + 1))" ;;
esac
