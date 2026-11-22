#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

# Work on a copy of the plugin, so "the plugin was removed" can be tested.
P="$T/plugin"
mkdir -p "$P"
cp -r "$REPO/bin" "$REPO/lib" "$REPO/pi" "$REPO/manifest.json" "$P/"
PCLI="$P/bin/omamode"

cp /usr/share/applications/steam.desktop "$T/steam.desktop" 2>/dev/null || cat >"$T/steam.desktop" <<'EOF'
[Desktop Entry]
Name=Steam
Exec=/usr/bin/steam %U
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
Actions=Store;

[Desktop Action Store]
Name=Store
Exec=/usr/bin/steam steam://store
EOF
export OMAMODE_STEAM_DESKTOP="$T/steam.desktop"

# Stand-in Steam.
cat >"$T/bin/steam" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/steam.log"
EOF
chmod +x "$T/bin/steam"
export OMAMODE_STEAM_BIN="$T/bin/steam"
export OMAMODE_STEAM_PIDFILE="$T/steam.pid"
: >"$T/steam.log"

apps="$XDG_DATA_HOME/applications"
desk="$apps/steam.desktop"
exe="$XDG_DATA_HOME/omamode/steam-exec"
wrap="$OMAMODE_HOME/.local/bin/omamode"
ext="$OMAMODE_PI_DIR/extensions/omamode.ts"

assert_exit 0 "$PCLI" setup
for f in "$desk" "$exe" "$wrap" "$ext"; do
  [[ -f "$f" ]] || _t_fail "setup did not create $f"
done
assert_file_contains "$desk" "X-Omamode-Managed=true" "launcher marker"
assert_file_contains "$exe" "# managed-by: omamode" "steam-exec marker"
assert_file_contains "$wrap" "# managed-by: omamode" "wrapper marker"
assert_eq "// managed-by: omamode" "$(head -n1 "$ext")" "pi extension marker"
grep -q '^Exec=/usr/bin/steam' "$desk"; assert_eq 1 $? "no direct Steam Exec lines left"
assert_file_contains "$desk" "MimeType=x-scheme-handler/steam;" "steam:// links still handled"
assert_file_contains "$desk" "[Desktop Action Store]" "actions kept"
assert_file_contains "$desk" "Exec=$exe steam://store" "action routed through omamode"
[[ -x "$exe" && -x "$wrap" ]]; assert_eq 0 $? "scripts executable"

# The launcher entry goes through omamode: in gaming mode Steam starts.
OMAMODE_HOME="$OMAMODE_HOME" "$PCLI" config get port >/dev/null
source "$OMAMODE"; om_state_set mode '"gaming"'
"$exe" steam://store
sleep 0.3
assert_file_contains "$T/steam.log" "steam://store" "steam-exec runs omamode steam"
# The wrapper runs the plugin's CLI.
assert_eq "$(jq -r .version "$P/manifest.json")" "$("$wrap" --version)" "wrapper runs the plugin"

# setup --if-needed does nothing the second time.
: >"$T/notify.log"
"$PCLI" setup --if-needed >/dev/null
assert_eq "" "$(cat "$T/notify.log")" "no second setup"

# Uninstall removes only what setup created.
mkdir -p "$OMAMODE_PI_DIR/extensions"
echo "// mine" >"$OMAMODE_PI_DIR/extensions/other.ts"
assert_exit 0 "$PCLI" uninstall
for f in "$desk" "$exe" "$wrap" "$ext"; do
  [[ -e "$f" ]] && _t_fail "uninstall left $f"
done
[[ -e "$OMAMODE_PI_DIR/extensions/other.ts" ]]; assert_eq 0 $? "user's own extension kept"
assert_exit 0 "$PCLI" uninstall

# A launcher entry the user made is never overwritten.
mkdir -p "$apps"
printf '[Desktop Entry]\nName=My Steam\nExec=/usr/bin/steam -silent\n' >"$desk"
cp "$desk" "$T/mine.desktop"
assert_exit 0 "$PCLI" setup
assert_contains "$(cat "$T/last.out")" "Skipped" "reports the skip"
cmp -s "$desk" "$T/mine.desktop"; assert_eq 0 $? "user's launcher untouched"
rm -f "$desk"; "$PCLI" uninstall >/dev/null; "$PCLI" setup >/dev/null

# A plugin path with a space and an ampersand still works (quoting).
"$PCLI" uninstall >/dev/null
Q="$T/my plugins & co/plugin"
mkdir -p "$(dirname "$Q")"; cp -r "$P" "$Q"
assert_exit 0 "$Q/bin/omamode" setup
bash -n "$exe"; assert_eq 0 $? "steam-exec is valid bash"
: >"$T/steam.log"
"$exe" steam://store >"$T/exe.out" 2>&1
sleep 0.3
assert_file_contains "$T/steam.log" "steam://store" "steam-exec reaches omamode under an odd path"
assert_not_contains "$(cat "$T/exe.out")" "command not found" "no word splitting"
assert_eq "$(jq -r .version "$P/manifest.json")" "$("$wrap" --version)" "wrapper works under an odd path"
"$Q/bin/omamode" uninstall >/dev/null
rm -rf "$T/my plugins & co"

# A data folder with a space: the launcher's Exec value is quoted per the
# desktop entry spec.
XDG_DATA_HOME="$T/data dir" "$PCLI" setup >/dev/null
assert_file_contains "$T/data dir/applications/steam.desktop" \
  "Exec=\"$T/data dir/omamode/steam-exec\" %U" "Exec path quoted"
XDG_DATA_HOME="$T/data dir" "$PCLI" uninstall >/dev/null
"$PCLI" setup >/dev/null

# Plugin removed without uninstall: Steam and the wrapper still behave.
rm -rf "$P"
: >"$T/steam.log"
"$exe" steam://open/games
sleep 0.3
assert_file_contains "$T/steam.log" "steam://open/games" "falls back to Steam directly"
"$wrap" status >"$T/w.out" 2>&1; code=$?
assert_eq 1 "$code" "wrapper fails clearly"
assert_contains "$(cat "$T/w.out")" "omamode was removed" "wrapper explains"

t_done
