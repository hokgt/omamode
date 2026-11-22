#!/usr/bin/env bash
# Regression tests for findings from the final review.
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 1000000000 "$m/A.gguf"
truncate -s 1000000000 "$m/B.gguf"
loaded() { t_router_get | jq -r '.loaded // "none"'; }

# --- #1: programs omamode starts must not inherit its lock ---------------
# A Steam that keeps running (a background child holds every inherited fd).
cat >"$T/bin/steam" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/steam.log"
if [[ "${1:-}" == -shutdown ]]; then rm -f "$T/steam.pid"; exit 0; fi
echo $$ >"$T/steam.pid"
sleep 20 &
echo $! >"$T/steam-child.pid"
EOF
chmod +x "$T/bin/steam"
export OMAMODE_STEAM_BIN="$T/bin/steam" OMAMODE_STEAM_PIDFILE="$T/steam.pid"
echo '[]' >"$T/clients.json"
printf '#!/usr/bin/env bash\ncat "$T/clients.json"\n' >"$T/bin/hyprctl"; chmod +x "$T/bin/hyprctl"
export OMAMODE_HYPRCTL="$T/bin/hyprctl"

t_router_start
t_router_ctl '{"models":["A","B"]}'
assert_exit 0 omamode gaming
for _ in $(seq 30); do [[ -e "$T/steam.pid" ]] && break; sleep 0.1; done
assert_exit 0 omamode work
assert_eq "work" "$(omamode status --json | jq -r .mode)" "work mode while Steam's children still run"
kill "$(cat "$T/steam-child.pid" 2>/dev/null)" 2>/dev/null

# A llama-server omamode starts must not hold the lock either.
t_router_stop
port="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
export OMAMODE_SERVER_URL="http://127.0.0.1:$port"
cat >"$T/bin/llama-server" <<EOF
#!/usr/bin/env bash
exec python3 -I "$REPO/tests/fake_router.py" --port $port
EOF
chmod +x "$T/bin/llama-server"
omamode config set server_bin "\"$T/bin/llama-server\""
( for _ in $(seq 50); do curl -fsS --max-time 1 "$OMAMODE_SERVER_URL/health" >/dev/null 2>&1 && break; sleep 0.1; done
  t_router_ctl '{"models":["A","B"]}' ) &
assert_exit 0 omamode load A
wait
assert_eq "A" "$(loaded)" "omamode started the server and loaded A"
assert_exit 0 omamode load B
assert_eq "B" "$(loaded)" "next operation not blocked by the server"
kill "$(cat "$OMAMODE_RUNTIME_DIR/server.pid")" 2>/dev/null

# --- #3: a real single-model llama-server answers /models without status --
t_router_start --single-model
out="$(omamode status --json)"
assert_eq "not-router" "$(jq -r .server <<<"$out")" "single-model server is not a router"
assert_exit 3 omamode gaming
assert_contains "$(cat "$T/last.err")" "not in router mode" "gaming refuses rather than leaving the model in memory"
t_router_stop

# --- #2: two operations at once on the real (detached) path ---------------
t_router_start
t_router_ctl '{"models":["A","B"],"load_delay":1.5}'
unset OMAMODE_FOREGROUND
assert_exit 0 omamode load A
assert_exit 3 omamode load B
assert_contains "$(cat "$T/last.err")" "Another omamode operation is running" "second detached operation refused"
for _ in $(seq 60); do [[ "$(loaded)" == A ]] && break; sleep 0.1; done
assert_eq "A" "$(loaded)" "first operation finished"
for _ in $(seq 30); do omamode status --json | jq -e '.activity == "idle"' >/dev/null && break; sleep 0.1; done
export OMAMODE_FOREGROUND=1

# --- #8: a dismissed "still answering" prompt is shown again --------------
t_router_ctl '{"busy":true,"load_delay":0}'
omamode config set wait_timeout 1
: >"$T/notify.log"
omamode load B >/dev/null 2>&1 &
bg=$!
for _ in $(seq 60); do (( $(grep -c "Stop the model now" "$T/notify.log") >= 2 )) && break; sleep 0.1; done
assert_eq "2" "$(grep -c "Stop the model now" "$T/notify.log")" "prompt repeats after another wait_timeout"
omamode decide cancel
wait "$bg"

# --- live check: a job that has not yet recorded its activity is busy ----
exec 8>>"$OMAMODE_RUNTIME_DIR/lock"; flock -n 8
source "$OMAMODE"; om_state_set activity '"idle"'
assert_eq "working" "$(omamode status --json | jq -r .activity)" "lock held reads as busy"
flock -u 8; exec 8>&-
assert_eq "idle" "$(omamode status --json | jq -r .activity)" "idle once the lock is free"

t_done
