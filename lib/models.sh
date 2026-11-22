# shellcheck shell=bash
# Models on disk, merged with what the router knows.

# Helper files that live beside models but are not models themselves.
om_is_helper_gguf() { # basename
  case "$1" in
    mmproj-*|mtp-*|dflash-*) return 0 ;;
    *) return 1 ;;
  esac
}

# Split-model shard name: <stem>-NNNNN-of-MMMMM.gguf
om_shard_total() { # basename -> MMMMM as a number, or empty
  [[ "$1" =~ -[0-9]{5}-of-([0-9]{5})\.gguf$ ]] && echo $((10#${BASH_REMATCH[1]}))
}

# One "id<TAB>bytes<TAB>complete" line per model in models_dir. A model is
# incomplete while it is still downloading: a partial file sits beside it,
# or a split model has fewer shards than its names say.
om_disk_models() {
  local dir f base id bytes total
  dir="$(om_config_get models_dir)"
  [[ -d "$dir" ]] || return 0
  declare -A sizes=() shards=() want=() partial=()
  for f in "$dir"/*.gguf "$dir"/*.gguf.part "$dir"/*.gguf.partial "$dir"/*.gguf.download; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    om_is_helper_gguf "$base" && continue
    id="${base%%.gguf*}"
    id="$(sed -E 's/-[0-9]{5}-of-[0-9]{5}$//' <<<"$id")"
    if [[ "$base" != *.gguf ]]; then
      partial[$id]=1
      sizes[$id]=$(( ${sizes[$id]:-0} + 0 ))
      continue
    fi
    bytes="$(stat -Lc %s "$f")"
    sizes[$id]=$(( ${sizes[$id]:-0} + bytes ))
    total="$(om_shard_total "$base")"
    if [[ -n "$total" ]]; then
      shards[$id]=$(( ${shards[$id]:-0} + 1 ))
      want[$id]=$total
    fi
  done
  local d
  for d in "$dir"/*/; do
    [[ -d "$d" ]] || continue
    id="$(basename "$d")"
    local sum=0 found=0 count=0 need=0 part=0
    for f in "$d"*; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      om_is_helper_gguf "$base" && continue
      case "$base" in
        *.gguf) ;;
        *.gguf.part|*.gguf.partial|*.gguf.download|*.incomplete) part=1; found=1; continue ;;
        *) continue ;;
      esac
      sum=$(( sum + $(stat -Lc %s "$f") ))
      found=1
      total="$(om_shard_total "$base")"
      if [[ -n "$total" ]]; then count=$((count + 1)); need=$total; fi
    done
    (( found )) || continue
    sizes[$id]=$sum
    (( part )) && partial[$id]=1
    if (( need > 0 )); then shards[$id]=$count; want[$id]=$need; fi
  done
  local complete
  for id in "${!sizes[@]}"; do
    complete=true
    [[ -n "${partial[$id]:-}" ]] && complete=false
    if [[ -n "${want[$id]:-}" ]] && (( ${shards[$id]:-0} < ${want[$id]} )); then complete=false; fi
    printf '%s\t%s\t%s\n' "$id" "${sizes[$id]}" "$complete"
  done | sort
}

om_disk_models_json() {
  om_disk_models | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {id: .[0], bytes: (.[1] | tonumber), complete: (.[2] == "true")})'
}

om_model_bytes() { # id
  om_disk_models | awk -F'\t' -v id="$1" '$1 == id { print $2 }'
}

om_model_complete() { # id
  ! om_disk_models | awk -F'\t' -v id="$1" '$1 == id && $3 == "false" { found = 1 } END { exit !found }'
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
    | ($disk | map({(.id): .complete}) | add // {}) as $complete
    | [ $ids[] as $id | {
        id: $id,
        sizeGB: (if $bytes[$id] then ($bytes[$id] / 1e8 | round / 10) else null end),
        default: ($id == $default),
        loaded: ($st[$id] == "loaded" or $st[$id] == "loading"),
        fits: (if $bytes[$id] then ($fits | index($id)) != null else true end),
        known: ($st[$id] != null),
        complete: ($complete[$id] != false)
      } ]'
}
