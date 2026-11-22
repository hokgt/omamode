#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

assert_eq "120" "$(omamode config get wait_timeout)" "default wait_timeout"
assert_eq "$OMAMODE_HOME/models" "$(omamode config get models_dir)" "default models_dir"
assert_eq "4" "$(omamode config get context_allowance_gb)" "default allowance"
assert_eq "null" "$(omamode config get default_model)" "no default model yet"

omamode config set default_model '"abc"'
assert_eq "abc" "$(omamode config get default_model)" "set default_model"
assert_exit 0 jq . "$XDG_CONFIG_HOME/omamode/config.json"

assert_exit 2 omamode bogus
assert_exit 2 omamode config set wait_timeout 'not json'

assert_eq "$(jq -r .version "$REPO/manifest.json")" "$(omamode --version)" "version"

t_done
