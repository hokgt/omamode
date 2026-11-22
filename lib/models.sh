# shellcheck shell=bash
# Models on disk, merged with what the router knows.

# Helper files that live beside models but are not models themselves.
om_is_helper_gguf() { # basename
  case "$1" in
    mmproj-*|mtp-*|dflash-*) return 0 ;;
    *) return 1 ;;
  esac
}

# One "id<TAB>bytes" line per model in models_dir.
om_disk_models() {
  local dir f base id bytes
  dir="$(om_config_get models_dir)"
  [[ -d "$dir" ]] || return 0
  declare -A sizes=()
  for f in "$dir"/*.gguf; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    om_is_helper_gguf "$base" && continue
    id="${base%.gguf}"
    id="$(sed -E 's/-[0-9]{5}-of-[0-9]{5}$//' <<<"$id")"
    bytes="$(stat -Lc %s "$f")"
    sizes[$id]=$(( ${sizes[$id]:-0} + bytes ))
  done
  for d in "$dir"/*/; do
    [[ -d "$d" ]] || continue
    id="$(basename "$d")"
    local total=0 found=0
    for f in "$d"*.gguf; do
      [[ -f "$f" ]] || continue
      om_is_helper_gguf "$(basename "$f")" && continue
      total=$(( total + $(stat -Lc %s "$f") ))
      found=1
    done
    (( found )) && sizes[$id]=$total
  done
  for id in "${!sizes[@]}"; do
    printf '%s\t%s\n' "$id" "${sizes[$id]}"
  done | sort
}

om_disk_models_json() {
  om_disk_models | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {id: .[0], bytes: (.[1] | tonumber)})'
}

om_model_bytes() { # id
  om_disk_models | awk -F'\t' -v id="$1" '$1 == id { print $2 }'
}

om_model_size_gb() { # id
  local b
  b="$(om_model_bytes "$1")"
  [[ -n "$b" ]] || return 1
  awk -v b="$b" 'BEGIN { printf "%.1f\n", b / 1e9 }'
}

# Hook for the fit check; replaced by lib/memory.sh.
declare -F om_model_fits >/dev/null || om_model_fits() { return 0; }

om_models_json() {
  local disk router default fits_list id
  disk="$(om_disk_models_json)"
  router="$(om_server_models_json)"
  default="$(om_config_get default_model)"
  [[ "$default" == null ]] && default=""
  fits_list="$(jq -r '.[].id' <<<"$disk" | while IFS= read -r id; do
    om_model_fits "$id" >/dev/null 2>&1 && echo "$id"
  done | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  jq -n -c --argjson disk "$disk" --argjson router "$router" \
    --arg default "$default" --argjson fits "$fits_list" '
    ($router | map({(.id): .status}) | add // {}) as $st
    | ([$disk[].id] + [$router[].id] | unique) as $ids
    | ($disk | map({(.id): .bytes}) | add // {}) as $bytes
    | [ $ids[] as $id | {
        id: $id,
        sizeGB: (if $bytes[$id] then ($bytes[$id] / 1e8 | round / 10) else null end),
        default: ($id == $default),
        loaded: ($st[$id] == "loaded" or $st[$id] == "loading"),
        fits: (if $bytes[$id] then ($fits | index($id)) != null else true end),
        known: ($st[$id] != null)
      } ]'
}
