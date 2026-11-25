# shellcheck shell=bash
# Point opencode at the local llama.cpp server: a "llama.cpp" provider in
# opencode.json whose one model is omamode's default, and opencode's own
# default model set to it. omamode owns that provider entry; every other
# setting is left as it was.

OM_OPENCODE_PROVIDER="llama.cpp"

om_opencode_dir() {
  printf '%s\n' "${OMAMODE_OPENCODE_DIR:-${XDG_CONFIG_HOME:-$(om_home)/.config}/opencode}"
}
om_opencode_config() { printf '%s/opencode.json\n' "$(om_opencode_dir)"; }

# The context size llama-server is started with (from server_args), or empty.
om_server_ctx_size() {
  om_config_json | jq -r '
    (.server_args // []) as $a
    | [range(0; ($a | length) - 1) | select($a[.] == "-c" or $a[.] == "--ctx-size") | $a[. + 1]][0] // empty
    | select(test("^[0-9]+$"))'
}

# Never fails: reports what it did and always returns 0.
om_opencode_set_default() { # id
  local id="$1" dir f current url ctx updated
  dir="$(om_opencode_dir)"
  f="$(om_opencode_config)"
  if [[ ! -d "$dir" ]]; then
    om_info "opencode settings not updated: $dir does not exist"
    return 0
  fi
  current='{"$schema": "https://opencode.ai/config.json"}'
  if [[ -e "$f" ]]; then
    # opencode also accepts comments (JSONC); omamode never rewrites those.
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
      om_info "opencode settings not updated: $f is not plain JSON"
      return 0
    fi
    if ! cp -pL "$f" "$f.omamode-bak"; then
      om_info "opencode settings not updated: could not back up $f"
      return 0
    fi
    current="$(cat "$f")"
  fi
  url="$(om_server_url)/v1"
  ctx="$(om_server_ctx_size)"
  updated="$(jq --arg p "$OM_OPENCODE_PROVIDER" --arg m "$id" --arg url "$url" --arg ctx "${ctx:-}" '
    (.provider[$p] // {}) as $old
    | .provider[$p] = ($old * {
        npm: "@ai-sdk/openai-compatible",
        name: "llama.cpp (omamode)",
        options: {baseURL: $url}
      })
    | .provider[$p].models = {($m): ({name: $m}
        + (if $ctx == "" then {} else {limit: {context: ($ctx | tonumber), output: ([($ctx | tonumber), 32768] | min)}} end))}
    | .model = ($p + "/" + $m)' <<<"$current" 2>/dev/null)"
  if [[ -z "$updated" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$updated"; then
    om_info "opencode settings not updated: could not read $f"
    return 0
  fi
  # Writing in place (not a rename) keeps the file's mode and any symlink.
  if printf '%s\n' "$updated" >"$f"; then
    om_info "opencode's default model is now $OM_OPENCODE_PROVIDER/$id"
  else
    om_info "opencode settings not updated: could not write $f"
  fi
  return 0
}
