#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 22000000000 "$m/A.gguf"
truncate -s 20000000000 "$m/B.gguf"
truncate -s 94000000000 "$m/big.gguf"
t_router_start
t_router_ctl '{"models":["A","B","big"]}'
omamode config set default_model '"A"'

loaded() { t_router_get | jq -r '.loaded // "none"'; }

# Load the default with nothing loaded.
assert_exit 0 omamode load
assert_eq "A" "$(loaded)" "default loaded"
assert_eq "idle" "$(omamode status --json | jq -r .activity)" "idle after load"

# Already loaded: a no-op (Review Focus 4).
assert_exit 0 omamode load A
assert_contains "$(cat "$T/last.out")" "already loaded" "says already loaded"

# Swap while a request is in flight: waits, then swaps.
t_router_ctl '{"busy":true}'
( sleep 0.4; t_router_ctl '{"busy":false}' ) &
assert_exit 0 omamode load B
assert_eq "B" "$(loaded)" "swapped to B"
assert_not_contains "$(cat "$T/notify.log")" "Stop the model now" "no 2-minute prompt for a short wait"

# Stuck request: prompt after wait_timeout; Cancel keeps the model.
omamode config set wait_timeout 1
t_router_ctl '{"busy":true}'
omamode load A >"$T/bg.out" 2>"$T/bg.err" &
bg=$!
for _ in $(seq 50); do grep -q "Stop the model now" "$T/notify.log" && break; sleep 0.1; done
assert_file_contains "$T/notify.log" "Keep waiting" "prompt has Keep waiting"
assert_file_contains "$T/notify.log" "Stop the model now" "prompt has Stop"
assert_file_contains "$T/notify.log" "Cancel" "prompt has Cancel"
assert_eq "waiting" "$(omamode status --json | jq -r .activity)" "activity while waiting"
assert_eq "Waiting for pi to finish…" "$(omamode status --json | jq -r .detail)" "waiting detail"
omamode decide cancel
wait "$bg"; assert_eq 3 $? "cancelled load exits 3"
assert_eq "B" "$(loaded)" "B still loaded after cancel"
assert_eq "Cancelled; nothing was unloaded" "$(omamode status --json | jq -r .error)" "cancel recorded"

# Stuck request: Stop the model now swaps anyway.
: >"$T/notify.log"
omamode load A >"$T/bg.out" 2>&1 &
bg=$!
for _ in $(seq 50); do grep -q "Stop the model now" "$T/notify.log" && break; sleep 0.1; done
omamode decide stop
wait "$bg"; assert_eq 0 $? "stop then load exits 0"
assert_eq "A" "$(loaded)" "A loaded after stop"
assert_eq "null" "$(omamode status --json | jq -c .error)" "error cleared by next operation"
t_router_ctl '{"busy":false}'
omamode config set wait_timeout 120

# Too big: refused before anything is unloaded.
assert_exit 3 omamode load big
assert_eq "A" "$(loaded)" "A kept when big is refused"
assert_contains "$(omamode status --json | jq -r .error)" "big needs ~98 GB" "too-big message recorded"

# Gaming mode refuses loading.
source "$OMAMODE"
om_state_set mode '"gaming"'
assert_exit 3 omamode load B
assert_contains "$(cat "$T/last.err")" "Switch to work mode to load a model" "gaming refusal"
om_state_set mode '"work"'

# Lock held: refused (Review Focus 3).
exec 8>>"$OMAMODE_RUNTIME_DIR/lock"
flock -n 8
assert_exit 3 omamode load B
assert_contains "$(cat "$T/last.err")" "Another omamode operation is running" "lock refusal"
assert_eq "A" "$(loaded)" "nothing changed while locked"
flock -u 8; exec 8>&-

# Unload, then unload again (Review Focus 4).
assert_exit 0 omamode unload
assert_eq "none" "$(loaded)" "unloaded"
assert_exit 0 omamode unload
assert_contains "$(cat "$T/last.out")" "No model loaded" "unload no-op"

# Unknown model.
assert_exit 2 omamode load nope

# A model the router does not know yet needs a restart; the router was not
# started by omamode, so it explains instead of killing it.
truncate -s 1000000000 "$m/C.gguf"
assert_exit 1 omamode load C
assert_contains "$(cat "$T/last.err")" "not started by omamode" "restart refused"

# A job that died leaves no stuck activity.
om_state_set activity '"loading"'
om_state_set pid 999999
assert_eq "idle" "$(omamode status --json | jq -r .activity)" "dead job reads as idle"

t_done
