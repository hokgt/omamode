#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 1000000000 "$m/A.gguf"
truncate -s 1000000000 "$m/B.gguf"
mkdir -p "$OMAMODE_PI_DIR"
pi="$OMAMODE_PI_DIR/settings.json"

# pi uses the local provider: its default follows omamode's.
cat >"$pi" <<'EOF'
{
  "theme": "omarchy-system",
  "defaultProvider": "llama.cpp",
  "defaultModel": "A",
  "modelThinkingLevels": {"llama.cpp/A": "high"}
}
EOF
before="$(jq -S 'del(.defaultModel)' "$pi")"
assert_exit 0 omamode default B
assert_eq "B" "$(omamode config get default_model)" "omamode default"
assert_eq "B" "$(jq -r .defaultModel "$pi")" "pi default synced"
assert_eq "$before" "$(jq -S 'del(.defaultModel)' "$pi")" "other pi settings unchanged"
assert_file_contains "$pi.omamode-bak" '"defaultModel": "A"' "backup kept"

# pi uses a remote provider: left alone.
cat >"$pi" <<'EOF'
{"defaultProvider": "kimi-coding", "defaultModel": "k3"}
EOF
cp "$pi" "$T/pi.orig"
assert_exit 0 omamode default A
cmp -s "$pi" "$T/pi.orig"; assert_eq 0 $? "remote provider: file untouched"
assert_contains "$(cat "$T/last.out")" "pi settings left alone" "explains"
assert_eq "A" "$(omamode config get default_model)" "omamode default still set"

# Review Focus 5: missing or broken pi settings are never overwritten.
rm -f "$pi"
assert_exit 0 omamode default B
[[ -e "$pi" ]]; assert_eq 1 $? "missing file not created"
assert_contains "$(cat "$T/last.out")" "pi settings not updated" "missing explained"
printf '{ "theme": ' >"$pi"
cp "$pi" "$T/pi.broken"
assert_exit 0 omamode default A
cmp -s "$pi" "$T/pi.broken"; assert_eq 0 $? "broken file untouched"
assert_contains "$(cat "$T/last.out")" "pi settings not updated" "broken explained"

# A symlinked settings.json (dotfiles) stays a symlink and keeps its mode.
mkdir -p "$T/dotfiles"
printf '{"defaultProvider": "llama.cpp", "defaultModel": "A", "theme": "x"}\n' >"$T/dotfiles/settings.json"
chmod 644 "$T/dotfiles/settings.json"
rm -f "$pi"; ln -s "$T/dotfiles/settings.json" "$pi"
assert_exit 0 omamode default B
[[ -L "$pi" ]]; assert_eq 0 $? "settings.json is still a symlink"
assert_eq "B" "$(jq -r .defaultModel "$T/dotfiles/settings.json")" "target updated"
assert_eq "644" "$(stat -c %a "$T/dotfiles/settings.json")" "mode kept"
assert_eq "x" "$(jq -r .theme "$T/dotfiles/settings.json")" "other keys kept"

assert_exit 2 omamode default nope
assert_exit 2 omamode default

t_done
