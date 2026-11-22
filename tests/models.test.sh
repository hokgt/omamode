#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_sandbox

m="$OMAMODE_HOME/models"
truncate -s 2G "$m/A.gguf"
truncate -s 1G "$m/mmproj-F16.gguf"
truncate -s 1G "$m/mtp-A-Q8_0.gguf"
truncate -s 1G "$m/dflash-A-Q4_0.gguf"
mkdir -p "$m/big"
truncate -s 3G "$m/big/big-00001-of-00002.gguf"
truncate -s 3G "$m/big/big-00002-of-00002.gguf"
truncate -s 1G "$m/big/mmproj-F16.gguf"
touch "$m/notes.txt"

# Review Focus 1: helper files are not models; a folder is one model.
ids="$(omamode models --json | jq -r '.[].id' | tr '\n' ' ')"
assert_eq "A big " "$ids" "model ids"
assert_eq "6.4" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .sizeGB')" "big size"
assert_eq "2.1" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .sizeGB')" "A size"

# Without a server, models are listed from disk and not known to a router.
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .known')" "unknown without router"

t_router_start
t_router_ctl '{"models":["A"]}'
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .known')" "A known"
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .known')" "big needs restart"
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .loaded')" "A not loaded"

t_router_ctl '{"loaded":"A"}'
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .loaded')" "A loaded"
assert_eq "2.1" "$(omamode status --json | jq -r .loaded.sizeGB)" "status shows loaded size"

omamode config set default_model '"big"'
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .default')" "default flag"
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .default')" "not default"
assert_eq "big" "$(omamode status --json | jq -r .default)" "status default"

# A split model still downloading: missing shards or .part files.
mkdir -p "$m/dl"
truncate -s 1G "$m/dl/dl-00001-of-00003.gguf"
truncate -s 1G "$m/dl/dl-00002-of-00003.gguf.part"
assert_eq "false" "$(omamode models --json | jq -r '.[] | select(.id=="dl") | .complete')" "downloading model incomplete"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="big") | .complete')" "complete split model"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="A") | .complete')" "single-file model complete"
assert_contains "$(omamode models)" "(downloading)" "plain listing marks it"
assert_exit 3 omamode load dl
assert_contains "$(cat "$T/last.err")" "still downloading" "load refuses incomplete model"

# Many models: the list asks the server a fixed number of times, not once
# per model.
for i in $(seq 1 20); do truncate -s 1000000 "$m/many-$i.gguf"; done
real_curl="$(command -v curl)"
printf '#!/usr/bin/env bash\necho x >>"%s"\nexec "%s" "$@"\n' "$T/curl.count" "$real_curl" >"$T/shim/curl" 2>/dev/null \
  || { mkdir -p "$T/shim"; printf '#!/usr/bin/env bash\necho x >>"%s"\nexec "%s" "$@"\n' "$T/curl.count" "$real_curl" >"$T/shim/curl"; }
chmod +x "$T/shim/curl"
: >"$T/curl.count"
PATH="$T/shim:$PATH" omamode models --json >/dev/null
calls=$(wc -l <"$T/curl.count")
(( calls <= 4 )); assert_eq 0 $? "models --json makes few server calls (made $calls)"
assert_eq "true" "$(omamode models --json | jq -r '.[] | select(.id=="many-7") | .fits')" "fits still computed"
rm -f "$m"/many-*.gguf

# Human-readable listing.
assert_contains "$(omamode models)" "big" "plain listing"

t_done
