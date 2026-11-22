#!/usr/bin/env bash
# The release version is computed from Conventional Commit messages.
source "$(dirname "$0")/lib.sh"
t_sandbox

NEXT="$REPO/.github/scripts/next-version.sh"
R="$T/repo"
git init -q "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
commit() { g commit -q --allow-empty -m "$1"; }

commit "feat: first"
g tag v0.1.0

# Nothing releasable since the tag.
commit "docs: readme"
commit "test: more tests"
commit "chore(release): v0.1.0 [skip ci]"
assert_eq "" "$(cd "$R" && "$NEXT")" "no release for docs/test/chore"

commit "fix: a bug"
assert_eq "0.1.1" "$(cd "$R" && "$NEXT")" "fix -> patch"
commit "perf: faster"
assert_eq "0.1.1" "$(cd "$R" && "$NEXT")" "perf -> patch"
commit "feat(panel): new button"
assert_eq "0.2.0" "$(cd "$R" && "$NEXT")" "feat -> minor"
commit "fix!: change the CLI"
assert_eq "1.0.0" "$(cd "$R" && "$NEXT")" "! -> major"

g tag v1.0.0
commit "feat: x

BREAKING CHANGE: config keys renamed"
assert_eq "2.0.0" "$(cd "$R" && "$NEXT")" "BREAKING CHANGE footer -> major"

# A releasable commit older than the newest one still counts.
g tag v2.0.0
commit "fix(setup): a bug

with a body"
commit "perf: faster"
commit "docs: a newer docs commit"
assert_eq "2.0.1" "$(cd "$R" && "$NEXT")" "older fix/perf commits are seen"

# No tag yet: start from the manifest version, released as is.
R2="$T/repo2"; git init -q "$R2"
echo '{"version":"0.3.0"}' >"$R2/manifest.json"
git -C "$R2" add manifest.json
git -C "$R2" -c user.name=t -c user.email=t@t commit -q -m "feat: start"
assert_eq "0.3.0" "$(cd "$R2" && "$NEXT")" "first release uses the manifest version"

t_done
