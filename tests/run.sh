#!/usr/bin/env bash
# Run every omamode test. Exits non-zero if any fails.
set -u
cd "$(dirname "$0")/.." || exit 1
fails=0
for t in tests/*.test.sh; do
  [[ -e "$t" ]] || continue
  if ! bash "$t"; then
    fails=$((fails + 1))
  fi
done
shopt -s nullglob
ts=(tests/*.test.ts)
if (( ${#ts[@]} )); then
  if ! node --test "${ts[@]}"; then
    fails=$((fails + 1))
  fi
fi
if (( fails > 0 )); then
  echo "$fails test file(s) failed"
  exit 1
fi
echo "All tests passed"
