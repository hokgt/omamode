#!/usr/bin/env bash
# Which models folder omamode uses: the running server's, else the config's.
source "$(dirname "$0")/lib.sh"
t_sandbox

cfg="$OMAMODE_HOME/models"          # the configured default
srv="$T/drive/llama.cpp"            # where the server was started
mkdir -p "$srv"
truncate -s 1000000000 "$cfg/OnDisk.gguf"
truncate -s 2000000000 "$srv/OnDrive.gguf"
info() { omamode status --json | jq -r ".modelsDir.$1"; }

# No server: the configured folder.
assert_eq "config" "$(info source)" "no server: config"
assert_eq "$cfg" "$(info path)" "no server: config path"
assert_eq "false" "$(info mismatch)" "no server: no mismatch"

# Server started elsewhere (e.g. by another script): its folder wins and the
# disagreement is reported.
t_router_start --models-dir "$srv"
t_router_ctl '{"models":["OnDrive"]}'
assert_eq "server" "$(info source)" "server running: server's folder"
assert_eq "$srv" "$(info path)" "server path read from its command line"
assert_eq "$cfg" "$(info config)" "config still reported"
assert_eq "true" "$(info mismatch)" "mismatch reported"
assert_eq "OnDrive" "$(omamode models --json | jq -r '.[].id' | tr '\n' ' ' | xargs)" "listed from the server's folder"
assert_eq "2" "$(omamode models --json | jq -r '.[0].sizeGB')" "sizes from the server's folder"
assert_contains "$(omamode status)" "differs" "plain status mentions the mismatch"

# Adopt the server's folder.
assert_exit 0 omamode models-dir --use-server
assert_eq "$srv" "$(omamode config get models_dir)" "config set from the server"
assert_eq "false" "$(info mismatch)" "no mismatch after adopting"
t_router_stop

# --models-dir=PATH form.
t_router_start "--models-dir=$srv"
assert_eq "$srv" "$(info path)" "--models-dir=PATH parsed"
t_router_stop

# Setting the folder by hand: must exist.
assert_exit 2 omamode models-dir "$T/nope"
assert_contains "$(cat "$T/last.err")" "Models folder not found" "refuses a missing folder"
assert_exit 0 omamode models-dir "$cfg"
assert_eq "$cfg" "$(omamode config get models_dir)" "folder set"
assert_eq "$cfg" "$(omamode models-dir)" "prints the folder in use"

# The drive is not mounted: clear message, empty list, no crash.
omamode config set models_dir "\"$T/unmounted/llama.cpp\""
out="$(omamode status --json)"; code=$?
assert_eq 0 "$code" "status still works"
assert_eq "false" "$(jq -r .modelsDir.exists <<<"$out")" "folder missing"
assert_contains "$(jq -r .error <<<"$out")" "Models folder not found: $T/unmounted/llama.cpp" "status explains"
assert_eq "[]" "$(omamode models --json)" "empty list"
omamode config set models_dir "\"$cfg\""

t_done
