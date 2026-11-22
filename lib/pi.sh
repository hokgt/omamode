# shellcheck shell=bash
# Keep pi's default model in step with omamode's, when pi uses the local
# llama.cpp provider.

om_pi_dir() { printf '%s\n' "${OMAMODE_PI_DIR:-$(om_home)/.pi/agent}"; }
om_pi_settings() { printf '%s/settings.json\n' "$(om_pi_dir)"; }

om_pi_provider() {
  jq -r '.defaultProvider // empty' "$(om_pi_settings)" 2>/dev/null
}

# Never fails: reports what it did and always returns 0.
om_pi_set_default() { # id
  local id="$1" f provider
  f="$(om_pi_settings)"
  if [[ ! -f "$f" ]]; then
    om_info "pi settings not updated: $f does not exist"
    return 0
  fi
  if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    om_info "pi settings not updated: $f is not valid JSON"
    return 0
  fi
  provider="$(om_pi_provider)"
  if [[ "$provider" != llama.cpp ]]; then
    om_info "pi uses ${provider:-no default provider}; pi settings left alone"
    return 0
  fi
  if ! cp -pL "$f" "$f.omamode-bak"; then
    om_info "pi settings not updated: could not back up $f"
    return 0
  fi
  # Build the new content first; write only if it is valid JSON. Writing in
  # place (not a rename) keeps the file's mode and any symlink.
  local updated
  updated="$(jq --arg m "$id" '.defaultModel = $m' "$f" 2>/dev/null)"
  if [[ -z "$updated" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$updated"; then
    om_info "pi settings not updated: could not read $f"
    return 0
  fi
  if printf '%s\n' "$updated" >"$f"; then
    om_info "pi's default model is now $id"
  else
    om_info "pi settings not updated: could not write $f"
  fi
  return 0
}
