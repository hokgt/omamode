# shellcheck shell=bash
# The coding agent that uses the local model. omamode keeps that agent's
# default model in step with its own. Supported: pi, opencode.

om_agent_ids() { printf '%s\n' pi opencode; }

om_agent_supported() { # id
  om_agent_ids | grep -qxF -- "$1"
}

# Where agent programs are looked up (tests point this at a sandbox).
om_agent_path() { printf '%s\n' "${OMAMODE_AGENT_PATH:-$PATH}"; }

om_agent_installed() { # id
  local dir
  case "$1" in
    pi) dir="$(om_pi_dir)" ;;
    opencode) dir="$(om_opencode_dir)" ;;
    *) return 1 ;;
  esac
  [[ -d "$dir" ]] && return 0
  PATH="$(om_agent_path)" command -v "$1" >/dev/null 2>&1
}

# The selected agent (pi unless set).
om_agent() {
  local a
  a="$(om_config_get agent)"
  if [[ -z "$a" || "$a" == null ]] || ! om_agent_supported "$a"; then
    a=pi
  fi
  printf '%s\n' "$a"
}

# [{id, installed, selected}] for every supported agent.
om_agents_json() {
  local current id rows=()
  current="$(om_agent)"
  while IFS= read -r id; do
    rows+=("$(jq -cn --arg id "$id" \
      --argjson installed "$(om_agent_installed "$id" && echo true || echo false)" \
      --argjson selected "$([[ "$id" == "$current" ]] && echo true || echo false)" \
      '{id: $id, installed: $installed, selected: $selected}')")
  done < <(om_agent_ids)
  printf '%s\n' "${rows[@]}" | jq -sc .
}

# Point the selected agent at this model. Never fails.
om_agent_set_default() { # id
  case "$(om_agent)" in
    pi) om_pi_set_default "$1" ;;
    opencode) om_opencode_set_default "$1" ;;
  esac
  return 0
}
