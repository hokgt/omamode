#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 22000000000 "$m/A.gguf"
t_router_start
t_router_ctl '{"models":["A"],"loaded":"A"}'

# Stand-in Steam: records argv; "running" while its pid file exists.
export OMAMODE_STEAM_PIDFILE="$T/steam.pid"
cat >"$T/bin/steam" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/steam.log"
if [[ "${1:-}" == -shutdown ]]; then
  [[ -e "$T/steam-stuck" ]] || rm -f "$T/steam.pid"
  exit 0
fi
echo $$ >"$T/steam.pid"
EOF
chmod +x "$T/bin/steam"
export OMAMODE_STEAM_BIN="$T/bin/steam"
: >"$T/steam.log"

# Stand-in hyprctl: prints $T/clients.json.
echo '[]' >"$T/clients.json"
cat >"$T/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
cat "$T/clients.json"
EOF
chmod +x "$T/bin/hyprctl"
export OMAMODE_HYPRCTL="$T/bin/hyprctl"
export OMAMODE_STEAM_CLOSE_TIMEOUT=1

wait_for_file() { local i; for i in $(seq 50); do [[ -e "$1" ]] && return 0; sleep 0.1; done; return 1; }
mode() { omamode status --json | jq -r .mode; }
loaded() { t_router_get | jq -r '.loaded // "none"'; }

# Gaming: unload, start Steam, notify.
assert_exit 0 omamode gaming
assert_eq "none" "$(loaded)" "model unloaded"
assert_eq "gaming" "$(mode)" "gaming mode"
wait_for_file "$T/steam.pid"; assert_eq 0 $? "Steam started"
assert_eq "1" "$(grep -cv -- -shutdown "$T/steam.log")" "Steam started once"
assert_file_contains "$T/notify.log" "Gaming mode: model unloaded, opening Steam." "gaming notification"
assert_eq "true" "$(omamode status --json | jq -r .steam)" "status shows Steam"

# Gaming again with Steam running: no-op (Review Focus 4).
assert_exit 0 omamode gaming
assert_eq "1" "$(grep -cv -- -shutdown "$T/steam.log")" "no second Steam start"

# Loading is refused in gaming mode.
assert_exit 3 omamode load A

# The Steam launcher entry in gaming mode starts Steam with its arguments.
rm -f "$T/steam.pid"
assert_exit 0 omamode steam steam://open/games
wait_for_file "$T/steam.pid"
assert_file_contains "$T/steam.log" "steam://open/games" "launcher passes arguments"

# User quits Steam by hand: still gaming, nothing loads.
rm -f "$T/steam.pid"
assert_eq "gaming" "$(mode)" "still gaming after Steam quits"
assert_eq "false" "$(omamode status --json | jq -r .steam)" "Steam not running"
assert_eq "none" "$(loaded)" "nothing loaded behind the user's back"
echo $$ >"$T/steam.pid"

# Work with a game running: ask first, stay in gaming mode.
echo '[{"class":"steam_app_570","title":"Dota 2"}]' >"$T/clients.json"
: >"$T/notify.log"
assert_exit 3 omamode work
assert_file_contains "$T/notify.log" "A game is running. Close Steam and the game?" "game prompt"
assert_file_contains "$T/notify.log" "Close and switch" "close button"
assert_file_contains "$T/notify.log" "Cancel" "cancel button"
assert_eq "gaming" "$(mode)" "still gaming after the prompt"
grep -q -- -shutdown "$T/steam.log"; assert_eq 1 $? "Steam not closed before confirming"

# Steam that will not close: stay in gaming mode, never force-kill.
touch "$T/steam-stuck"
assert_exit 1 omamode work --confirmed
assert_eq "gaming" "$(mode)" "still gaming when Steam hangs"
assert_eq "Steam did not close; still in gaming mode" "$(omamode status --json | jq -r .error)" "hang error"
[[ -e "$T/steam.pid" ]]; assert_eq 0 $? "Steam not killed"
rm -f "$T/steam-stuck"

# Confirmed: Steam closes, work mode, nothing loads.
: >"$T/notify.log"
assert_exit 0 omamode work --confirmed
assert_eq "work" "$(mode)" "work mode"
[[ -e "$T/steam.pid" ]]; assert_eq 1 $? "Steam closed"
assert_file_contains "$T/notify.log" "Work mode: Steam closed." "work notification"
assert_eq "none" "$(loaded)" "work mode loads nothing"

# Work when Steam is not running: fine (Review Focus 4).
echo '[]' >"$T/clients.json"
assert_exit 0 omamode work
assert_eq "work" "$(mode)" "still work"

# The Steam launcher entry in work mode only offers to switch.
: >"$T/notify.log"; : >"$T/steam.log"
assert_exit 0 omamode steam steam://open/games
sleep 0.3
assert_eq "" "$(cat "$T/steam.log")" "Steam not started in work mode"
assert_file_contains "$T/notify.log" "Steam is available in gaming mode" "work-mode prompt"
assert_file_contains "$T/notify.log" "Switch to gaming mode" "switch button"

# Steam opened some other way in work mode: one prompt per Steam run.
echo $$ >"$T/steam.pid"
: >"$T/notify.log"
omamode steam-detected
omamode steam-detected
assert_eq "1" "$(grep -c "Steam is available in gaming mode" "$T/notify.log")" "one prompt"
[[ -e "$T/steam.pid" ]]; assert_eq 0 $? "watcher never kills Steam"
# Steam quits and is opened again later (new process): prompt again.
echo 424242 >"$T/steam.pid"
omamode steam-detected
assert_eq "2" "$(grep -c "Steam is available in gaming mode" "$T/notify.log")" "new Steam run prompts again"

# Reboot: a fresh runtime folder is work mode.
export OMAMODE_RUNTIME_DIR="$T/run-after-reboot"
assert_eq "work" "$(mode)" "work mode after reboot"

t_done
