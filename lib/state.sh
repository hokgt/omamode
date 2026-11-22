# shellcheck shell=bash
# Runtime state in $XDG_RUNTIME_DIR/omamode/state.json. That folder is a
# tmpfs cleared on reboot, so a fresh boot is always work mode and idle.

om_state_file() { printf '%s/state.json\n' "$(om_runtime_dir)"; }

om_state_defaults() {
  echo '{"mode":"work","activity":"idle","detail":"","error":null,"pid":null}'
}

om_state_json() {
  local f
  f="$(om_state_file)"
  if [[ -s "$f" ]] && jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    jq -c -s '.[0] * .[1]' <(om_state_defaults) "$f"
  else
    om_state_defaults
  fi
}

# Strings print raw, other values as JSON.
om_state_get() { # key
  om_state_json | jq -r --arg k "$1" '.[$k] | if type == "string" then . else tojson end'
}

om_state_set() { # key json-value
  local f current
  f="$(om_state_file)"
  current="$(om_state_json)"
  jq -c --arg k "$1" --argjson v "$2" '.[$k] = $v' <<<"$current" | om_write_file "$f"
}

om_activity() { # activity [detail]
  local f current
  f="$(om_state_file)"
  current="$(om_state_json)"
  jq -c --arg a "$1" --arg d "${2:-}" --argjson pid "$$" \
    '.activity = $a | .detail = $d | .pid = (if $a == "idle" then null else $pid end)' \
    <<<"$current" | om_write_file "$f"
}

# Activity as the panel should see it: a job that died is idle.
om_state_live_json() {
  local json pid
  json="$(om_state_json)"
  pid="$(jq -r '.pid // empty' <<<"$json")"
  if [[ "$(jq -r .activity <<<"$json")" != idle ]] && { [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; }; then
    json="$(jq -c '.activity = "idle" | .detail = "" | .pid = null' <<<"$json")"
  fi
  printf '%s\n' "$json"
}

# Start of every job: clear the last error.
om_job_begin() {
  OM_IN_JOB=1
  om_state_set error null
}

# Called by om_die. Inside a job, record the failure for the panel and
# tell the user, since the job may be running in the background.
om_on_die() { # code message
  [[ "${OM_IN_JOB:-0}" == 1 ]] || return 0
  local msg="$2"
  om_state_set error "$(jq -cn --arg m "$msg" '$m')"
  om_activity idle
  om_notify "omamode" "$msg"
}

om_fail() { # message [code]
  om_die "${2:-1}" "$1"
}
