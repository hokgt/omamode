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

# The operation lock is held on fd 9. Programs omamode starts (Steam,
# llama-server, notifications) must never inherit it: spawn them with 9>&-
# (see om_spawn), or the lock would outlive the operation.

# Take the lock (non-blocking). If fd 9 is already open and locked (a job
# started by om_run_job inherits it), this succeeds on the same lock.
om_take_lock() {
  if ! { : >&9; } 2>/dev/null; then
    exec 9>>"$(om_lock_file)"
  fi
  flock -n 9 || om_die 3 "Another omamode operation is running"
}

# Run a command while holding the operation lock.
om_with_lock() {
  om_take_lock
  "$@"
}

# Start a program detached from omamode, without the lock fd.
om_spawn() { # log-file command args...
  local log="$1"; shift
  setsid "$@" >>"$log" 2>&1 </dev/null 9>&- &
  disown 2>/dev/null || true
}

# Run a job function (om_job_*) under the lock, detached from the caller so
# it keeps going when the panel or terminal closes. The caller takes the
# lock first, so a second operation is refused right away, and the job
# inherits it. Inline when OMAMODE_FOREGROUND=1 (used by the tests).
om_run_job() { # name function args...
  local name="$1"; shift
  om_take_lock
  if [[ "${OMAMODE_FOREGROUND:-0}" == 1 ]]; then
    "$@"
    return
  fi
  setsid "$OM_SELF" __job "$@" >>"$(om_log_dir)/$name.log" 2>&1 </dev/null &
  disown 2>/dev/null || true
  exec 9>&-
  om_info "Started $name in the background"
}
