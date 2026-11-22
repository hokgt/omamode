# shellcheck shell=bash
# config.json with defaults.

om_config_file() { printf '%s/config.json\n' "$(om_config_dir)"; }

om_config_defaults() {
  local home
  home="$(om_home)"
  jq -n --arg home "$home" '{
    default_model: null,
    models_dir: ($home + "/models"),
    port: 8080,
    server_bin: ($home + "/strix-halo/vulkan/bin/llama-server"),
    server_args: ["--jinja","--host","127.0.0.1","-ngl","999","-c","65536",
                  "-fa","on","-ctk","q4_0","-ctv","q4_0","-b","1024","-ub","1024"],
    wait_timeout: 120,
    context_allowance_gb: 4
  }'
}

# The merged config (defaults overlaid with the user's file) as JSON.
om_config_json() {
  local f
  f="$(om_config_file)"
  if [[ -s "$f" ]] && jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    jq -s '.[0] * .[1]' <(om_config_defaults) "$f"
  else
    om_config_defaults
  fi
}

# Print one value: strings raw, everything else as compact JSON.
om_config_get() { # key
  om_config_json | jq -r --arg k "$1" \
    '.[$k] | if type == "string" then . else tojson end'
}

om_config_set() { # key json-value
  local key="$1" value="$2" f current
  jq -e . >/dev/null 2>&1 <<<"$value" || om_die 2 "Invalid JSON value for $key: $value"
  f="$(om_config_file)"
  current="{}"
  if [[ -s "$f" ]] && jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    current="$(cat "$f")"
  fi
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' <<<"$current" | om_write_file "$f"
}
