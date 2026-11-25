#!/usr/bin/env bash
# The agent that uses the local model, opencode's settings, and `use`.
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 22000000000 "$m/A.gguf"
truncate -s 20000000000 "$m/B.gguf"
truncate -s 94000000000 "$m/big.gguf"
mkdir -p "$OMAMODE_PI_DIR"
pi="$OMAMODE_PI_DIR/settings.json"
printf '{"defaultProvider": "llama.cpp", "defaultModel": "A"}\n' >"$pi"
oc_dir="$XDG_CONFIG_HOME/opencode"
oc="$oc_dir/opencode.json"

# pi is the agent unless another is picked.
assert_eq "pi" "$(omamode agent)" "pi by default"
assert_eq "pi" "$(omamode status --json | jq -r .agent)" "status reports the agent"
assert_eq "true" "$(omamode agent --json | jq -r '.[] | select(.id == "pi") | .installed')" "pi found by its folder"
assert_eq "false" "$(omamode agent --json | jq -r '.[] | select(.id == "opencode") | .installed')" "opencode not installed"

assert_exit 2 omamode agent hermes
assert_contains "$(cat "$T/last.err")" "supported: pi,opencode" "lists the supported agents"
assert_exit 3 omamode agent opencode
assert_contains "$(cat "$T/last.err")" "opencode is not installed" "refuses a missing agent"
assert_eq "pi" "$(omamode agent)" "still pi"

# An opencode program on the PATH counts as installed.
mkdir -p "$T/agent-bin"; printf '#!/bin/sh\n' >"$T/agent-bin/opencode"; chmod +x "$T/agent-bin/opencode"
assert_eq "true" "$(omamode agent --json | jq -r '.[] | select(.id == "opencode") | .installed')" "opencode found on the PATH"
rm -f "$T/agent-bin/opencode"

# Switching to opencode writes the current default into its settings, and
# keeps everything else in them.
mkdir -p "$oc_dir"
cat >"$oc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "theme": "system",
  "provider": {
    "llama.cpp": {"options": {"apiKey": "keep-me", "baseURL": "http://old:1/v1"}, "models": {"old": {}}},
    "other": {"npm": "x", "models": {"m": {}}}
  }
}
EOF
omamode config set default_model '"A"'
assert_exit 0 omamode agent opencode
assert_eq "opencode" "$(omamode agent)" "agent switched"
assert_eq "llama.cpp/A" "$(jq -r .model "$oc")" "opencode default set"
assert_eq "$OMAMODE_SERVER_URL/v1" "$(jq -r '.provider["llama.cpp"].options.baseURL' "$oc")" "points at llama-server"
assert_eq "keep-me" "$(jq -r '.provider["llama.cpp"].options.apiKey' "$oc")" "its other options kept"
assert_eq "@ai-sdk/openai-compatible" "$(jq -r '.provider["llama.cpp"].npm' "$oc")" "OpenAI-compatible provider"
assert_eq '["A"]' "$(jq -c '.provider["llama.cpp"].models | keys' "$oc")" "lists the default model only"
assert_eq "65536" "$(jq -r '.provider["llama.cpp"].models.A.limit.context' "$oc")" "context size from server_args"
assert_eq "system" "$(jq -r .theme "$oc")" "other settings kept"
assert_eq "x" "$(jq -r .provider.other.npm "$oc")" "other providers kept"
assert_file_contains "$oc.omamode-bak" '"http://old:1/v1"' "backup kept"

# With opencode picked, the default follows into opencode, not pi.
assert_exit 0 omamode default B
assert_eq "llama.cpp/B" "$(jq -r .model "$oc")" "opencode follows the default"
assert_eq "A" "$(jq -r .defaultModel "$pi")" "pi left alone"

# opencode settings with comments (JSONC) are never rewritten.
printf '{\n  // mine\n  "theme": "system"\n}\n' >"$oc"
cp "$oc" "$T/oc.jsonc"
assert_exit 0 omamode default A
cmp -s "$oc" "$T/oc.jsonc"; assert_eq 0 $? "JSONC file untouched"
assert_contains "$(cat "$T/last.out")" "not plain JSON" "explains"

# No opencode.json yet: created.
rm -f "$oc"
assert_exit 0 omamode default B
assert_eq "llama.cpp/B" "$(jq -r .model "$oc")" "created with the default"

# Back to pi: pi gets the current default.
assert_exit 0 omamode agent pi
assert_eq "B" "$(jq -r .defaultModel "$pi")" "pi gets the default on switch"

# `use`: default for omamode and the agent, then loaded.
t_router_start
t_router_ctl '{"models":["A","B","big"]}'
loaded() { t_router_get | jq -r '.loaded // "none"'; }
assert_exit 0 omamode use A
assert_eq "A" "$(omamode config get default_model)" "use sets the default"
assert_eq "A" "$(jq -r .defaultModel "$pi")" "use sets pi's default"
assert_eq "A" "$(loaded)" "use loads"

assert_exit 0 omamode use B
assert_eq "B" "$(loaded)" "use swaps"

# Too big: refused before anything changes.
assert_exit 3 omamode use big
assert_contains "$(cat "$T/last.err")" "big needs" "says why"
assert_eq "B" "$(omamode config get default_model)" "default unchanged"
assert_eq "B" "$(jq -r .defaultModel "$pi")" "pi unchanged"
assert_eq "B" "$(loaded)" "still loaded"

# Gaming mode: becomes the default only.
source "$OMAMODE"
om_state_set mode '"gaming"'
assert_exit 0 omamode use A
assert_eq "A" "$(omamode config get default_model)" "default set in gaming mode"
assert_eq "B" "$(loaded)" "nothing loaded in gaming mode"
assert_contains "$(cat "$T/last.out")" "loads when you switch to work mode" "explains"

assert_exit 2 omamode use
assert_exit 2 omamode use nope

t_done
