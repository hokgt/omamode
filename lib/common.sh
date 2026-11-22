# shellcheck shell=bash
# Paths, messages, JSON helpers, the operation lock and the job runner.

om_home() { printf '%s\n' "${OMAMODE_HOME:-$HOME}"; }

om_runtime_dir() {
  local d="${OMAMODE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omamode}"
  mkdir -p "$d" && printf '%s\n' "$d"
}

om_config_dir() {
  local d="${XDG_CONFIG_HOME:-$(om_home)/.config}/omamode"
  mkdir -p "$d" && printf '%s\n' "$d"
}

om_log_dir() {
  local d="${XDG_STATE_HOME:-$(om_home)/.local/state}/omamode"
  mkdir -p "$d" && printf '%s\n' "$d"
}

om_poll_interval() { printf '%s\n' "${OMAMODE_POLL:-2}"; }

om_die() { # code message
  local code="$1"; shift
  printf 'omamode: %s\n' "$*" >&2
  if declare -F om_on_die >/dev/null; then om_on_die "$code" "$*"; fi
  exit "$code"
}

om_info() { printf '%s\n' "$*"; }

om_json_get() { # file jq-path
  jq -r "$2 // empty" "$1" 2>/dev/null
}

# Atomically write stdin to a file.
om_write_file() { # path
  local tmp
  tmp="$(mktemp "$1.XXXXXX")" || return 1
  cat >"$tmp" && mv -f "$tmp" "$1"
}

om_lock_file() { printf '%s/lock\n' "$(om_runtime_dir)"; }

# True when no omamode operation holds the lock.
om_lock_free() {
  local f
  f="$(om_lock_file)"
  (flock -n 9) 9>>"$f"
}

# Run a command while holding the operation lock (non-blocking).
om_with_lock() {
  exec 9>>"$(om_lock_file)"
  flock -n 9 || om_die 3 "Another omamode operation is running"
  "$@"
}

# Run a job function (om_job_*) under the lock, detached from the caller so
# it keeps going when the panel or terminal closes. Inline when
# OMAMODE_FOREGROUND=1 (tests, and the pi extension waiting for a load).
om_run_job() { # name function args...
  local name="$1"; shift
  om_lock_free || om_die 3 "Another omamode operation is running"
  if [[ "${OMAMODE_FOREGROUND:-0}" == 1 ]]; then
    om_with_lock "$@"
    return
  fi
  setsid "$OM_SELF" __job "$@" >>"$(om_log_dir)/$name.log" 2>&1 </dev/null &
  disown 2>/dev/null || true
  om_info "Started $name in the background"
}
