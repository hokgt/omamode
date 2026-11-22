#!/usr/bin/env bash
# Load the panel and its service in Quickshell with a stub omamode CLI.
source "$(dirname "$0")/lib.sh"
t_sandbox

shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
if ! command -v qs >/dev/null 2>&1 || [[ ! -d "$shell_dir/Ui" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "SKIP qml.test.sh (needs Quickshell, the Omarchy shell and a Wayland session)"
  t_done; exit 0
fi

preview="$T/preview"
mkdir -p "$preview"
# Links live only in this temporary folder, never in the repo.
ln -s "$shell_dir/Commons" "$preview/Commons"
ln -s "$shell_dir/Ui" "$preview/Ui"
cp "$REPO/Panel.qml" "$REPO/OmamodeService.qml" "$preview/"
cp -r "$REPO/i18n" "$preview/i18n"
cp "$REPO/tests/qml/shell.qml" "$preview/shell.qml"

cat >"$T/bin/omamode" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/cli.log"
case "$1 ${2:-}" in
  "status --json") echo '{"mode":"work","activity":"idle","detail":"","error":null,"server":"running","loaded":{"id":"A","sizeGB":22.1},"default":"B","gpu":{"limitGB":65.2,"usedGB":24},"steam":false,"modelsDir":{"path":"/srv/models","source":"server","config":"/home/me/models","server":"/srv/models","mismatch":true,"exists":true}}' ;;
  "models --json") echo '[{"id":"A","sizeGB":22.1,"default":false,"loaded":true,"fits":true,"known":true,"complete":true},{"id":"B","sizeGB":20,"default":true,"loaded":false,"fits":true,"known":true,"complete":true}]' ;;
  "load B") echo "omamode: Another omamode operation is running" >&2; exit 3 ;;
  *) echo ok ;;
esac
STUB
chmod +x "$T/bin/omamode"
: >"$T/cli.log"

out="$(OMAMODE_TEST_CLI="$T/bin/omamode" QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software \
  timeout 20 qs -p "$preview" 2>&1)"
printf '%s\n' "$out" >"$T/qs.log"

assert_not_contains "$out" "ReferenceError" "no ReferenceError"
assert_not_contains "$out" "TypeError" "no TypeError"
assert_not_contains "$out" "is not a type" "all types resolve"
assert_not_contains "$out" "timeout" "harness finished"
assert_contains "$out" "mode=work" "status parsed"
assert_contains "$out" "models=A,B" "models parsed"
assert_contains "$out" "icon=󰧑" "work-mode icon"
assert_contains "$out" "selected=B" "dropdown starts on the default"
assert_contains "$out" "ran=load B" "actions run the CLI"
assert_file_contains "$T/cli.log" "load B" "CLI received the action as argv"
assert_contains "$out" "actionError=Another omamode operation is running" "refusal shown in the panel"
assert_contains "$out" "folder=/srv/models" "panel shows the folder in use"
assert_contains "$out" "folderMismatch=true" "panel notices the mismatch"
assert_contains "$out" "ranFolder=models-dir /new/place" "changing the folder runs the CLI"
assert_contains "$out" "dropdownOpen=B" "dropdown opens on the default"
assert_contains "$out" "dropdownPicked=A/A" "a pick updates the selection"
assert_contains "$out" "dropdownReopen=B" "reopening goes back to the default"
assert_contains "$out" "dropdownAfterRemoval=B" "a removed pick falls back to the default"
(( T_FAILS )) && sed -n 1,40p "$T/qs.log" >&2
[[ -n "${QML_TEST_SHOW:-}" ]] && cat "$T/qs.log"

t_done
