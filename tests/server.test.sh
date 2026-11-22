#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

# No server listening.
out="$(omamode status --json)"; code=$?
assert_eq 0 "$code" "status exits 0 with no server"
assert_eq "stopped" "$(jq -r .server <<<"$out")" "server stopped"
assert_eq "null" "$(jq -c .loaded <<<"$out")" "nothing loaded"
assert_eq "work" "$(jq -r .mode <<<"$out")" "default mode"

# Router with two models, A loaded.
t_router_start
t_router_ctl '{"models":["A","B"],"loaded":"A"}'
out="$(omamode status --json)"
assert_eq "running" "$(jq -r .server <<<"$out")" "server running"
assert_eq "A" "$(jq -r .loaded.id <<<"$out")" "A loaded"

# Busy check.
source "$OMAMODE"
t_router_ctl '{"busy":true}'
om_server_busy A; assert_eq 0 $? "busy when a slot is processing"
t_router_ctl '{"busy":false}'
om_server_busy A; assert_eq 1 $? "idle when no slot is processing"
t_router_stop

# A llama-server in single-model mode (Review Focus 2).
t_router_start --single-model
out="$(omamode status --json)"; code=$?
assert_eq 0 "$code" "status exits 0 for a single-model server"
assert_eq "not-router" "$(jq -r .server <<<"$out")" "not-router"
assert_contains "$(jq -r .error <<<"$out")" "not in router mode" "explains the problem"

t_done
