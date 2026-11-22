# shellcheck shell=bash
# GPU memory limit (GTT on AMD unified-memory systems) and the fit check.

om_drm_dir() {
  if [[ -n "${OMAMODE_DRM_DIR:-}" ]]; then
    printf '%s\n' "$OMAMODE_DRM_DIR"
    return
  fi
  local d
  for d in /sys/class/drm/card*/device; do
    [[ -r "$d/mem_info_gtt_total" ]] && { printf '%s\n' "$d"; return; }
  done
}

om_gpu_limit_bytes() {
  local d
  d="$(om_drm_dir)"
  [[ -n "$d" && -r "$d/mem_info_gtt_total" ]] && cat "$d/mem_info_gtt_total"
}

om_gpu_used_bytes() {
  local d
  d="$(om_drm_dir)"
  [[ -n "$d" && -r "$d/mem_info_gtt_used" ]] && cat "$d/mem_info_gtt_used"
}

# {"limitGB": .., "usedGB": ..} or null when the limit is unknown.
om_gpu_json() {
  local limit used
  limit="$(om_gpu_limit_bytes)"
  used="$(om_gpu_used_bytes)"
  if [[ -z "$limit" ]]; then
    echo null
    return
  fi
  jq -cn --argjson l "$limit" --argjson u "${used:-0}" \
    '{limitGB: ($l / 1e8 | round / 10), usedGB: ($u / 1e8 | round / 10)}'
}

# Return 0 when the model fits, 3 (printing why) when it does not.
# freed: bytes that will be released first (the model being swapped out).
om_fit_check() { # id [freed-bytes]
  local id="$1" freed="${2:-0}" size limit used allowance
  limit="$(om_gpu_limit_bytes)"
  [[ -n "$limit" ]] || return 0
  size="$(om_model_bytes "$id")"
  [[ -n "$size" ]] || return 0
  used="$(om_gpu_used_bytes)"
  allowance="$(om_config_get context_allowance_gb)"
  awk -v s="$size" -v a="$allowance" -v l="$limit" -v u="${used:-0}" -v f="$freed" -v id="$id" '
    BEGIN {
      need = s + a * 1e9
      avail = l - (u - f)
      if (need <= avail) exit 0
      printf "%s needs ~%d GB; the GPU limit is %d GB\n", id, int(need / 1e9 + 0.5), int(l / 1e9)
      exit 3
    }'
}

om_model_fits() { # id
  local loaded freed=0
  loaded="$(om_server_loaded 2>/dev/null)"
  if [[ -n "$loaded" && "$loaded" != "$1" ]]; then
    freed="$(om_model_bytes "$loaded")"
  fi
  om_fit_check "$1" "${freed:-0}"
}
