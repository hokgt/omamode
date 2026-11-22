# shellcheck shell=bash
# Subcommand implementations. bin/omamode dispatches `omamode <cmd>` to
# om_cmd_<cmd> (dashes become underscores).

om_status_json() {
  local server loaded loaded_json err default
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
    --argjson gpu "$(om_gpu_json)" \
    --arg server "$server" \
    --argjson loaded "$loaded_json" \
    --argjson err "$err" \
    --arg default "$default" \
    '{
      mode: "work",
      activity: "idle",
      detail: "",
      error: $err,
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
