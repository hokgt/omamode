#!/usr/bin/env bash
# The plugin folder must pass Omarchy's validator and contain no symlinks.
source "$(dirname "$0")/lib.sh"
t_sandbox

links="$(find "$REPO" -type l -not -path '*/.git/*' -not -path '*/.superpowers/*')"
assert_eq "" "$links" "no symlinks in the plugin folder"

if command -v omarchy >/dev/null 2>&1; then
  assert_exit 0 omarchy plugin validate "$REPO"
else
  echo "SKIP omarchy plugin validate (omarchy not installed)"
fi

assert_eq "hokgt.omamode" "$(jq -r .id "$REPO/manifest.json")" "manifest id"
assert_eq "Panel.qml" "$(jq -r .entryPoints.barWidget "$REPO/manifest.json")" "entry point"

t_done
