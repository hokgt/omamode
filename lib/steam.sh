# shellcheck shell=bash
# Steam: is it running, start it, close it, and spot open games.

om_steam_bin() { printf '%s\n' "${OMAMODE_STEAM_BIN:-/usr/bin/steam}"; }

om_steam_running() {
  if [[ -n "${OMAMODE_STEAM_PIDFILE:-}" ]]; then
    [[ -e "$OMAMODE_STEAM_PIDFILE" ]]
    return
  fi
  # The Steam client's main process is called "steam".
  pgrep -u "$(id -u)" -x steam >/dev/null 2>&1
}

# The Steam client's process id (empty when not running).
om_steam_pid() {
  if [[ -n "${OMAMODE_STEAM_PIDFILE:-}" ]]; then
    cat "$OMAMODE_STEAM_PIDFILE" 2>/dev/null
    return
  fi
  pgrep -o -u "$(id -u)" -x steam 2>/dev/null
}

# Window classes of open Steam games (Proton and native games run as
# steam_app_<appid>).
om_game_windows() {
  "${OMAMODE_HYPRCTL:-hyprctl}" clients -j 2>/dev/null \
    | jq -r '.[]?.class // empty | select(test("^steam_app_"))' 2>/dev/null
}

# Start Steam detached from omamode, the panel and the terminal.
om_steam_start() { # [args...]
  local bin
  bin="$(om_steam_bin)"
  if [[ -z "${OMAMODE_STEAM_BIN:-}" ]] && command -v uwsm-app >/dev/null 2>&1; then
    om_spawn /dev/null uwsm-app -- "$bin" "$@"
  else
    om_spawn /dev/null "$bin" "$@"
  fi
}

# Ask Steam to quit and wait for it. Never force-kills.
om_steam_shutdown() {
  local timeout="${OMAMODE_STEAM_CLOSE_TIMEOUT:-30}" start
  om_steam_running || return 0
  om_spawn /dev/null "$(om_steam_bin)" -shutdown
  start="$(date +%s)"
  while om_steam_running; do
    (( $(date +%s) - start >= timeout )) && return 1
    sleep "$(om_poll_interval)"
  done
  return 0
}

om_steam_prompt() {
  om_notify "Steam is available in gaming mode" \
    "Switch to gaming mode to play. omamode unloads the AI model first." \
    --action "Switch to gaming mode" "$OM_SELF" gaming
}
