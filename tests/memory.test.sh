#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 22000000000 "$m/A.gguf"
truncate -s 94000000000 "$m/big.gguf"
source "$OMAMODE"

out="$(om_fit_check A)"; code=$?
assert_eq 0 "$code" "22 GB model fits in 65 GB"

out="$(om_fit_check big)"; code=$?
assert_eq 3 "$code" "94 GB model does not fit"
assert_eq "big needs ~98 GB; the GPU limit is 65 GB" "$out" "too-big message"

echo 50000000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_used"
om_fit_check A 22000000000 >/dev/null; assert_eq 0 $? "fits once the loaded model is freed"
om_fit_check A >/dev/null; assert_eq 3 $? "does not fit while 50 GB is used"
echo 3000000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_used"

assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .fits')" "big flagged too big"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .fits')" "A fits"
assert_eq "65.2" "$(omamode status --json | jq -r .gpu.limitGB)" "status gpu limit"
assert_eq "3" "$(omamode status --json | jq -r .gpu.usedGB)" "status gpu used"

# Unknown limit never blocks loading.
export OMAMODE_DRM_DIR="$T/no-such-dir"
om_fit_check big >/dev/null; assert_eq 0 $? "unknown limit: allowed"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .fits')" "unknown limit: fits"
assert_eq "null" "$(omamode status --json | jq -c .gpu)" "unknown limit: gpu null"

# The loaded model fits: the memory in use is the model itself. (Seen live:
# a 93.7 GB model loaded with 68.5 GB used and a 111.7 GB limit showed as
# "too big".)
export OMAMODE_DRM_DIR="$T/drm"
echo 111669149696 >"$OMAMODE_DRM_DIR/mem_info_gtt_total"
echo 68500000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_used"
t_router_start
t_router_ctl '{"models":["A","big"],"loaded":"big"}'
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .fits')" "loaded model is not too big"
om_fit_check big >/dev/null; assert_eq 0 $? "fit check passes for the loaded model"

# Swapping: the file size of the loaded model can exceed the memory it uses
# (mmap), so what the swap frees never makes room beyond the GPU limit.
echo 65200000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_total"
echo 50000000000 >"$OMAMODE_DRM_DIR/mem_info_gtt_used"
truncate -s 100000000000 "$m/huge.gguf"
t_router_ctl '{"models":["A","big","huge"],"loaded":"big"}'
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="huge") | .fits')" "swap never exceeds the limit (list)"
om_fit_check huge 94000000000 >/dev/null; assert_eq 3 $? "swap never exceeds the limit (load)"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .fits')" "a smaller model still fits after the swap"

t_done
