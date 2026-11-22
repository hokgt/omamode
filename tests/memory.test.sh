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

t_done
