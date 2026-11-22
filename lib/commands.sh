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
  jq -n -c \
    --argjson state "$state" \
    --argjson gpu "$(om_gpu_json)" \
    --arg server "$server" \
    --argjson loaded "$loaded_json" \
    --argjson err "$err" \
    --arg default "$default" \
    '{
      mode: $state.mode,
      activity: $state.activity,
      detail: $state.detail,
      error: ($state.error // $err),
      server: $server,
      loaded: $loaded,
      default: (if $default == "null" then null else $default end),
      gpu: $gpu,
      steam: false
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
  jq -r '.[] | "\(if .loaded then "*" else " " end) \(.id)  \(.sizeGB // "?") GB\(if .default then "  (default)" else "" end)\(if .fits then "" else "  (too big)" end)\(if .known then "" else "  (new: loads after a server restart)" end)"' <<<"$json"
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
  local id="$1" timeout start decision
  om_server_busy "$id" || return 0
  timeout="$(om_config_get wait_timeout)"
  rm -f "$(om_decision_file)"
  om_activity waiting "Waiting for pi to finish…"
  start="$(date +%s)"
  while om_server_busy "$id"; do
    if (( $(date +%s) - start >= timeout )); then
      if [[ ! -e "$(om_decision_file).asked" ]]; then
        : >"$(om_decision_file).asked"
        om_notify "The local model is still answering" \
          "pi has been busy for $timeout s. Stop it now, or keep waiting?" \
          --action "Keep waiting" "$OM_SELF" decide wait \
          --action "Stop the model now" "$OM_SELF" decide stop \
          --action "Cancel" "$OM_SELF" decide cancel
      fi
      decision="$(cat "$(om_decision_file)" 2>/dev/null)"
      case "$decision" in
        stop) rm -f "$(om_decision_file)" "$(om_decision_file).asked"; return 0 ;;
        wait) rm -f "$(om_decision_file)" "$(om_decision_file).asked"; start="$(date +%s)" ;;
        cancel) rm -f "$(om_decision_file)" "$(om_decision_file).asked"
                om_fail "Cancelled; nothing was unloaded" 3 ;;
      esac
    fi
    sleep "$(om_poll_interval)"
  done
  rm -f "$(om_decision_file)" "$(om_decision_file).asked"
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
