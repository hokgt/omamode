# shellcheck shell=bash
# Subcommand implementations. bin/omamode dispatches `omamode <cmd>` to
# om_cmd_<cmd> (dashes become underscores).

om_status_json() {
  local server loaded loaded_json err default state
  state="$(om_state_live_json)"
  server="$(om_server_state)"
  loaded=""
  err=null
  case "$server" in
    running) loaded="$(om_server_loaded)" ;;
    not-router) err='"llama-server is not in router mode; omamode needs it started with --models-dir"' ;;
  esac
  loaded_json=null
  if [[ -n "$loaded" ]]; then
    local size
    size="$(om_model_size_gb "$loaded" 2>/dev/null)"
    loaded_json="$(jq -cn --arg id "$loaded" --arg s "${size:-}" \
      '{id: $id, sizeGB: (if $s == "" then null else ($s | tonumber) end)}')"
  fi
  default="$(om_config_get default_model)"
  local mdir
  mdir="$(om_models_dir_json)"
  if [[ "$err" == null ]] && [[ "$(jq -r .exists <<<"$mdir")" == false ]]; then
    err="$(jq -c '"Models folder not found: \(.path) (is the drive mounted?)"' <<<"$mdir")"
  fi
  jq -n -c \
    --argjson mdir "$mdir" \
    --argjson state "$state" \
    --argjson gpu "$(om_gpu_json)" \
    --arg server "$server" \
    --argjson loaded "$loaded_json" \
    --argjson err "$err" \
    --arg default "$default" \
    --argjson steam "$(om_steam_running && echo true || echo false)" \
    '{
      mode: $state.mode,
      activity: $state.activity,
      detail: $state.detail,
      error: ($state.error // $err),
      server: $server,
      loaded: $loaded,
      default: (if $default == "null" then null else $default end),
      gpu: $gpu,
      modelsDir: $mdir,
      steam: $steam
    }'
}

om_cmd_status() {
  local json
  json="$(om_status_json)"
  if [[ "${1:-}" == --json ]]; then
    printf '%s\n' "$json"
    return 0
  fi
  jq -r '
    "Mode:    \(.mode)",
    "Model:   \(if .loaded then "\(.loaded.id) (\(.loaded.sizeGB // "?") GB)" else "none loaded" end)",
    "Default: \(.default // "not set")",
    "Server:  \(.server)",
    "Folder:  \(.modelsDir.path) (\(.modelsDir.source))\(if .modelsDir.mismatch then " — differs from the configured folder \(.modelsDir.config)" else "" end)",
    (if .activity != "idle" then "Doing:   \(.detail)" else empty end),
    (if .error then "Error:   \(.error)" else empty end)' <<<"$json"
}

om_cmd_models() {
  local json
  json="$(om_models_json)"
  if [[ "${1:-}" == --json ]]; then
    printf '%s\n' "$json"
    return 0
  fi
  jq -r '.[] | "\(if .loaded then "*" else " " end) \(.id)  \(.sizeGB // "?") GB\(if .default then "  (default)" else "" end)\(if .fits then "" else "  (too big)" end)\(if .complete then "" else "  (downloading)" end)\(if .known or (.complete | not) then "" else "  (new: loads after a server restart)" end)"' <<<"$json"
}

om_decision_file() { printf '%s/decision\n' "$(om_runtime_dir)"; }

# Answer to the "still answering after 2 minutes" prompt.
om_cmd_decide() { # stop|wait|cancel
  case "${1:-}" in
    stop|wait|cancel) printf '%s\n' "$1" >"$(om_decision_file)" ;;
    *) om_die 2 "usage: omamode decide stop|wait|cancel" ;;
  esac
}

# Wait until the model has no request in flight. After wait_timeout, ask the
# user. Returns 0 to go ahead; exits 3 if the user cancels.
om_wait_idle() { # model-id
  local id="$1" timeout start decision asked_at=0
  om_server_busy "$id" || return 0
  timeout="$(om_config_get wait_timeout)"
  rm -f "$(om_decision_file)"
  om_activity waiting "Waiting for pi to finish…"
  start="$(date +%s)"
  while om_server_busy "$id"; do
    if (( $(date +%s) - start >= timeout )); then
      if (( $(date +%s) - asked_at >= timeout )); then
        asked_at="$(date +%s)"
        om_notify "The local model is still answering" \
          "pi has been busy for $timeout s. Stop it now, or keep waiting?" \
          --action "Keep waiting" "$OM_SELF" decide wait \
          --action "Stop the model now" "$OM_SELF" decide stop \
          --action "Cancel" "$OM_SELF" decide cancel
      fi
      decision="$(cat "$(om_decision_file)" 2>/dev/null)"
      case "$decision" in
        stop) rm -f "$(om_decision_file)"; return 0 ;;
        wait) rm -f "$(om_decision_file)"; start="$(date +%s)"; asked_at=0 ;;
        cancel) rm -f "$(om_decision_file)"
                om_fail "Cancelled; nothing was unloaded" 3 ;;
      esac
    fi
    sleep "$(om_poll_interval)"
  done
  rm -f "$(om_decision_file)"
  return 0
}

om_model_exists() { # id
  om_models_json | jq -e --arg id "$1" 'any(.[]; .id == $id)' >/dev/null
}

om_cmd_load() { # [id]
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id="$(om_config_get default_model)"
    [[ "$id" == null || -z "$id" ]] && om_die 2 "No default model set; pick one with: omamode default <model>"
  fi
  [[ "$(om_state_get mode)" == gaming ]] && om_die 3 "Switch to work mode to load a model"
  om_model_exists "$id" || om_die 2 "Unknown model: $id"
  om_model_complete "$id" || om_die 3 "$id is still downloading (files are incomplete)"
  om_run_job load om_job_load "$id"
}

om_job_load() { # id
  local id="$1" state loaded freed=0 msg
  om_job_begin
  state="$(om_server_state)"
  [[ "$state" == not-router ]] && om_fail "llama-server is not in router mode; stop it and let omamode start it"
  loaded=""
  [[ "$state" == running ]] && loaded="$(om_server_loaded)"
  if [[ "$loaded" == "$id" ]]; then
    om_info "$id is already loaded"
    return 0
  fi
  # Check the fit before unloading anything, counting what the swap frees.
  [[ -n "$loaded" ]] && freed="$(om_model_bytes "$loaded")"
  if ! msg="$(om_fit_check "$id" "${freed:-0}")"; then
    om_fail "$msg" 3
  fi
  if [[ -n "$loaded" ]]; then
    om_wait_idle "$loaded"
    om_activity unloading "Switching from $loaded to $id…"
    om_server_unload "$loaded"
  fi
  if [[ "$(om_server_state)" == stopped ]]; then
    om_activity loading "Starting llama-server…"
    om_server_start
  fi
  if ! om_server_models | grep -qxF -- "$id"; then
    om_activity restarting-server "Restarting llama-server to find $id…"
    om_server_stop
    om_server_start
  fi
  om_activity loading "Loading $id…"
  om_server_load "$id"
  om_activity idle
  om_info "Loaded $id"
}

om_cmd_unload() {
  [[ "$(om_server_state)" == not-router ]] && om_die 3 "$om_not_router_msg"
  if [[ "$(om_server_state)" != running || -z "$(om_server_loaded)" ]]; then
    om_info "No model loaded"
    return 0
  fi
  om_run_job unload om_job_unload
}

om_job_unload() {
  local loaded
  om_job_begin
  loaded="$(om_server_loaded)"
  if [[ -z "$loaded" ]]; then
    om_info "No model loaded"
    return 0
  fi
  om_wait_idle "$loaded"
  om_activity unloading "Unloading $loaded…"
  om_server_unload "$loaded"
  om_activity idle
  om_info "Unloaded $loaded"
}

om_not_router_msg="llama-server is not in router mode, so omamode cannot see or unload its model; stop it and let omamode start it"

om_cmd_gaming() {
  [[ "$(om_server_state)" == not-router ]] && om_die 3 "$om_not_router_msg"
  if [[ "$(om_state_get mode)" == gaming ]] && om_steam_running; then
    om_info "Already in gaming mode"
    return 0
  fi
  om_run_job gaming om_job_gaming
}

om_job_gaming() {
  local loaded=""
  om_job_begin
  [[ "$(om_server_state)" == running ]] && loaded="$(om_server_loaded)"
  if [[ -n "$loaded" ]]; then
    om_wait_idle "$loaded"
    om_activity unloading "Unloading $loaded…"
    om_server_unload "$loaded"
  fi
  om_state_set mode '"gaming"'
  local -a pending=()
  if [[ -s "$(om_pending_steam_file)" ]]; then
    mapfile -d '' -t pending <"$(om_pending_steam_file)"
  fi
  rm -f "$(om_pending_steam_file)"
  if ! om_steam_running || (( ${#pending[@]} )); then
    # A running Steam hands a steam:// link to the open client.
    om_activity starting-steam "Opening Steam…"
    om_steam_start "${pending[@]}"
  fi
  om_activity idle
  om_notify "Gaming mode" "Gaming mode: model unloaded, opening Steam."
  om_info "Gaming mode"
}

om_cmd_work() { # [--confirmed]
  local confirmed=0
  [[ "${1:-}" == --confirmed ]] && confirmed=1
  if [[ "$(om_state_get mode)" == gaming ]] && (( ! confirmed )) && [[ -n "$(om_game_windows)" ]]; then
    om_notify "A game is running" "A game is running. Close Steam and the game?" \
      --action "Cancel" /usr/bin/true \
      --action "Close and switch" "$OM_SELF" work --confirmed
    om_die 3 "A game is running; confirm with: omamode work --confirmed"
  fi
  if [[ "$(om_state_get mode)" == work ]] && ! om_steam_running; then
    om_info "Already in work mode"
    return 0
  fi
  om_run_job work om_job_work
}

om_job_work() {
  local had_steam=0
  om_job_begin
  if om_steam_running; then
    had_steam=1
    om_activity closing-steam "Closing Steam…"
    om_steam_shutdown || om_fail "Steam did not close; still in gaming mode"
  fi
  om_state_set mode '"work"'
  om_activity idle
  if (( had_steam )); then
    om_notify "Work mode" "Work mode: Steam closed."
  else
    om_notify "Work mode" "Work mode."
  fi
  om_info "Work mode"
}

# Used by the Steam launcher entry.
om_cmd_steam() { # [args...]
  if [[ "$(om_state_get mode)" == gaming ]]; then
    om_steam_start "$@"
    return 0
  fi
  # Remember what was asked for (e.g. a steam:// link), so switching to
  # gaming mode opens it.
  if (( $# )); then
    printf '%s\0' "$@" >"$(om_pending_steam_file)"
  fi
  om_steam_prompt
  om_info "Steam is available in gaming mode"
}

om_pending_steam_file() { printf '%s/pending-steam-args\n' "$(om_runtime_dir)"; }

# Called by the panel when a Steam window appears. Never closes Steam.
om_cmd_steam_detected() {
  local marker
  marker="$(om_runtime_dir)/steam-prompted"
  if ! om_steam_running; then
    rm -f "$marker"
    return 0
  fi
  [[ "$(om_state_get mode)" == work ]] || return 0
  # One prompt per Steam run: the marker holds the Steam process id.
  local pid
  pid="$(om_steam_pid)"
  [[ -e "$marker" && "$(cat "$marker")" == "$pid" ]] && return 0
  printf '%s\n' "$pid" >"$marker"
  om_steam_prompt
}

om_cmd_default() { # id
  local id="${1:-}"
  [[ -n "$id" ]] || om_die 2 "usage: omamode default <model>"
  om_model_exists "$id" || om_die 2 "Unknown model: $id"
  om_config_set default_model "$(jq -cn --arg m "$id" '$m')"
  om_info "Default model: $id"
  om_pi_set_default "$id"
}

# Show or set the models folder.
#   omamode models-dir [--json]      the folder in use
#   omamode models-dir <path>        use this folder (must exist)
#   omamode models-dir --use-server  adopt the running server's folder
om_cmd_models_dir() {
  case "${1:-}" in
    "") om_models_dir ;;
    --json) om_models_dir_json ;;
    --use-server)
      local server
      server="$(om_server_models_dir)"
      [[ -n "$server" ]] || om_die 3 "llama-server is not running with a models folder"
      om_config_set models_dir "$(jq -cn --arg p "$server" '$p')"
      om_info "Models folder: $server" ;;
    *)
      local path="$1"
      [[ "$path" == "~"* ]] && path="$(om_home)${path:1}"
      [[ -d "$path" ]] || om_die 2 "Models folder not found: $path"
      path="$(readlink -f -- "$path")"
      om_config_set models_dir "$(jq -cn --arg p "$path" '$p')"
      om_info "Models folder: $path"
      [[ -n "$(om_server_models_dir)" && "$(readlink -m -- "$(om_server_models_dir)")" != "$path" ]] \
        && om_info "llama-server is still using $(om_server_models_dir); it uses the new folder after it restarts"
      return 0 ;;
  esac
}
