# shellcheck shell=bash
# Client for the llama.cpp router server.

om_server_url() {
  if [[ -n "${OMAMODE_SERVER_URL:-}" ]]; then
    printf '%s\n' "$OMAMODE_SERVER_URL"
  else
    printf 'http://127.0.0.1:%s\n' "$(om_config_get port)"
  fi
}

# HTTP request. Prints the body. Returns 0 for 2xx, 1 when the server cannot
# be reached, 2 for any other HTTP status.
om_http() { # method path [json-body] [timeout]
  local method="$1" path="$2" data="${3:-}" timeout="${4:-5}" tmp code
  tmp="$(mktemp)"
  local args=(-sS --max-time "$timeout" -o "$tmp" -w '%{http_code}' -X "$method")
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$data")
  code="$(curl "${args[@]}" "$(om_server_url)$path" 2>/dev/null)"
  cat "$tmp"; rm -f "$tmp"
  case "$code" in
    2??) return 0 ;;
    000|"") return 1 ;;
    *) return 2 ;;
  esac
}

om_http_error_message() { # body
  jq -r '.error.message // .error // empty' 2>/dev/null <<<"$1"
}

om_server_state() {
  om_http GET /health "" 2 >/dev/null || { echo stopped; return; }
  local body
  if body="$(om_http GET /models "" 3)" && jq -e '.data | type == "array"' >/dev/null 2>&1 <<<"$body"; then
    echo running
  else
    echo not-router
  fi
}

# The router's model list as a JSON array of {id, status}.
om_server_models_json() {
  local body
  body="$(om_http GET /models "" 3)" || { echo '[]'; return; }
  jq -c '[.data[]? | {id, status: (.status.value // "unknown")}]' <<<"$body" 2>/dev/null || echo '[]'
}

om_server_models() { om_server_models_json | jq -r '.[].id'; }

# The loaded (or loading) model id, empty when none.
om_server_loaded() {
  om_server_models_json | jq -r '[.[] | select(.status == "loaded" or .status == "loading")][0].id // empty'
}

om_server_status_of() { # id
  om_server_models_json | jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "missing"'
}

# Exit 0 when any slot of the model is processing a request.
om_server_busy() { # id
  local q body
  q="$(jq -rn --arg m "$1" '$m | @uri')"
  body="$(om_http GET "/slots?model=$q" "" 3)" || return 1
  jq -e 'any(.[]?; .is_processing == true)' >/dev/null 2>&1 <<<"$body"
}

om_server_pid_file() { printf '%s/server.pid\n' "$(om_runtime_dir)"; }

om_server_start() {
  [[ "$(om_server_state)" == running ]] && return 0
  [[ "$(om_server_state)" == not-router ]] && om_die 1 "llama-server is not in router mode; stop it and let omamode start it"
  local bin models port log
  bin="$(om_config_get server_bin)"
  models="$(om_config_get models_dir)"
  port="$(om_config_get port)"
  log="$(om_log_dir)/llama-server.log"
  [[ -x "$bin" ]] || om_die 1 "llama-server not found at $bin (set server_bin in $(om_config_file))"
  local -a extra
  mapfile -t extra < <(om_config_json | jq -r '.server_args[]?')
  setsid "$bin" --models-dir "$models" --no-models-autoload --port "$port" "${extra[@]}" \
    >>"$log" 2>&1 </dev/null &
  echo $! >"$(om_server_pid_file)"
  disown 2>/dev/null || true
  local i
  for i in $(seq 60); do
    [[ "$(om_server_state)" == running ]] && return 0
    sleep 0.5
  done
  om_die 1 "llama-server did not start within 30 s. Last log lines: $(tail -n 5 "$log" | tr '\n' ' ')"
}

om_server_stop() {
  local pidf pid
  pidf="$(om_server_pid_file)"
  pid="$(cat "$pidf" 2>/dev/null)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    om_die 1 "llama-server was not started by omamode; stop it with the tool that started it"
  fi
  kill "$pid" 2>/dev/null
  local i
  for i in $(seq 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  rm -f "$pidf"
  kill -0 "$pid" 2>/dev/null && om_die 1 "llama-server did not stop"
  return 0
}

# Poll the router until the model reaches one of the wanted states.
om_server_wait_status() { # id timeout-seconds wanted-regex
  local id="$1" timeout="$2" want="$3" start status
  start="$(date +%s)"
  while :; do
    status="$(om_server_status_of "$id")"
    [[ "$status" =~ $want ]] && return 0
    (( $(date +%s) - start >= timeout )) && return 1
    sleep "$(om_poll_interval)"
  done
}

om_server_load() { # id
  local id="$1" body data
  data="$(jq -cn --arg m "$id" '{model: $m}')"
  if ! body="$(om_http POST /models/load "$data" 30)"; then
    om_die 1 "llama-server could not load $id: $(om_http_error_message "$body")"
  fi
  # Give the router a moment to report "loading", then wait for the result.
  local start status
  start="$(date +%s)"
  while :; do
    status="$(om_server_status_of "$id")"
    [[ "$status" == loaded ]] && return 0
    if [[ "$status" != loading ]] && (( $(date +%s) - start >= 5 )); then
      om_die 1 "llama-server failed to load $id; see $(om_log_dir)/llama-server.log"
    fi
    (( $(date +%s) - start >= 600 )) && om_die 1 "Loading $id took longer than 10 minutes"
    sleep "$(om_poll_interval)"
  done
}

om_server_unload() { # id
  local id="$1" body data
  data="$(jq -cn --arg m "$id" '{model: $m}')"
  if ! body="$(om_http POST /models/unload "$data" 30)"; then
    om_die 1 "llama-server could not unload $id: $(om_http_error_message "$body")"
  fi
  om_server_wait_status "$id" 120 '^(unloaded|missing|sleeping|failed)$' \
    || om_die 1 "llama-server did not unload $id within 2 minutes"
}
