# shellcheck shell=bash
# Test helpers for omamode. Source from a tests/*.test.sh file.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMAMODE="$REPO/bin/omamode"
export PATH="$REPO/bin:$PATH"
T_FAILS=0
T_ROUTER_PID=""

omamode() { "$OMAMODE" "$@"; }

# Fresh sandbox: nothing a test does touches the real system.
t_sandbox() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/omamode-test.XXXXXX")"
  export T
  export OMAMODE_HOME="$T/home"
  export OMAMODE_RUNTIME_DIR="$T/run"
  export OMAMODE_PI_DIR="$T/home/.pi/agent"
  export OMAMODE_DRM_DIR="$T/drm"
  export OMAMODE_FOREGROUND=1
  export OMAMODE_POLL=0.1
  export OMAMODE_SERVER_URL="http://127.0.0.1:9"   # nothing listens here
  export XDG_CONFIG_HOME="$T/home/.config"
  export XDG_STATE_HOME="$T/home/.local/state"
  export XDG_DATA_HOME="$T/home/.local/share"
  mkdir -p "$OMAMODE_HOME/models" "$OMAMODE_RUNTIME_DIR" "$OMAMODE_DRM_DIR" "$T/bin"
  echo 65200000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_total"
  echo 3000000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_used"
  cat >"$T/bin/notify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/notify.log"
EOF
  chmod +x "$T/bin/notify"
  export OMAMODE_NOTIFY="$T/bin/notify"
  : >"$T/notify.log"
  trap t_cleanup EXIT
}

t_cleanup() {
  t_router_stop
  [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"
}

# Start the fake router on a free port.
t_router_start() {
  local port
  port="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 -I "$REPO/tests/fake_router.py" --port "$port" "$@" >"$T/router.log" 2>&1 &
  T_ROUTER_PID=$!
  export OMAMODE_SERVER_URL="http://127.0.0.1:$port"
  local i
  for i in $(seq 50); do
    curl -fsS --max-time 1 "$OMAMODE_SERVER_URL/health" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "fake router did not start" >&2
  cat "$T/router.log" >&2
  return 1
}

t_router_stop() {
  if [[ -n "$T_ROUTER_PID" ]]; then
    kill "$T_ROUTER_PID" 2>/dev/null
    wait "$T_ROUTER_PID" 2>/dev/null
    T_ROUTER_PID=""
  fi
}

# Change the fake router's state, e.g. t_router_ctl '{"loaded":"A"}'
t_router_ctl() {
  curl -fsS --max-time 2 -X POST -H 'Content-Type: application/json' \
    -d "$1" "$OMAMODE_SERVER_URL/_ctl" >/dev/null
}

t_router_get() {
  curl -fsS --max-time 2 "$OMAMODE_SERVER_URL/_ctl"
}

_t_fail() {
  T_FAILS=$((T_FAILS + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

assert_eq() { # expected actual [message]
  [[ "$1" == "$2" ]] || _t_fail "${3:-assert_eq}: expected [$1] got [$2]"
}

assert_contains() { # haystack needle [message]
  [[ "$1" == *"$2"* ]] || _t_fail "${3:-assert_contains}: [$2] not in [$1]"
}

assert_not_contains() { # haystack needle [message]
  [[ "$1" != *"$2"* ]] || _t_fail "${3:-assert_not_contains}: [$2] found in [$1]"
}

assert_file_contains() { # file needle [message]
  if [[ ! -f "$1" ]]; then _t_fail "${3:-assert_file_contains}: missing file $1"; return; fi
  grep -qF -- "$2" "$1" || _t_fail "${3:-assert_file_contains}: [$2] not in $1"
}

assert_exit() { # code cmd...
  local want="$1"; shift
  "$@" >"$T/last.out" 2>"$T/last.err"
  local got=$?
  [[ "$got" == "$want" ]] || _t_fail "assert_exit: [$*] exited $got, wanted $want; stderr: $(cat "$T/last.err")"
}

t_done() {
  if (( T_FAILS > 0 )); then
    echo "FAILED $(basename "$0") ($T_FAILS)"
    exit 1
  fi
  echo "PASS $(basename "$0")"
}
