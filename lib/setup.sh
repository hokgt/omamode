# shellcheck shell=bash
# Place and remove the pieces that live outside the plugin folder. Every
# placed file carries a marker; files without it are never touched.

OM_MARKER="managed-by: omamode"
OM_DESKTOP_MARKER="X-Omamode-Managed=true"

om_data_dir() { printf '%s\n' "${XDG_DATA_HOME:-$(om_home)/.local/share}"; }
om_setup_paths() {
  local data
  data="$(om_data_dir)"
  OM_P_DESKTOP="$data/applications/steam.desktop"
  OM_P_EXEC="$data/omamode/steam-exec"
  OM_P_WRAPPER="$(om_home)/.local/bin/omamode"
  OM_P_PIEXT="$(om_pi_dir)/extensions/omamode.ts"
}

om_is_managed() { # file
  [[ -f "$1" ]] && grep -qF -e "$OM_MARKER" -e "$OM_DESKTOP_MARKER" "$1"
}

# Write stdin to path unless an unmanaged file is already there.
om_place() { # path mode description
  local path="$1" mode="$2" what="$3" content
  content="$(cat)"
  if [[ -e "$path" ]] && ! om_is_managed "$path"; then
    om_info "Skipped $path: not created by omamode"
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" | om_write_file "$path" && chmod "$mode" "$path"
  om_info "Placed $what: $path"
}

# Quote a path for a desktop entry Exec key: double-quote it when it holds
# reserved characters, escaping " ` $ and \ (and doubling backslashes for
# the key-file layer); % becomes %%.
om_desktop_quote() { # path
  local p="${1//%/%%}"
  if [[ "$p" =~ [[:space:]\"\'\\\>\<~\|\&\;\$\*\?\#\(\)\`] ]]; then
    p="${p//\\/\\\\\\\\}"
    p="${p//\"/\\\\\"}"
    p="${p//\`/\\\\\`}"
    p="${p//\$/\\\\\$}"
    printf '"%s"\n' "$p"
  else
    printf '%s\n' "$p"
  fi
}

om_setup_version_file() { printf '%s/setup-version\n' "$(om_config_dir)"; }

om_cmd_setup() { # [--if-needed]
  local version placed=()
  version="$(jq -r .version "$OM_ROOT/manifest.json")"
  if [[ "${1:-}" == --if-needed && "$(cat "$(om_setup_version_file)" 2>/dev/null)" == "$version" ]]; then
    return 0
  fi
  om_setup_paths
  local cli steam_bin src
  cli="$OM_ROOT/bin/omamode"
  steam_bin="$(om_steam_bin)"

  # Paths are shell-quoted with printf %q; never pass them through sed.
  cat <<EOS | om_place "$OM_P_EXEC" 755 "Steam launcher helper"
#!/usr/bin/env bash
# $OM_MARKER
# Steam's launcher entry runs this. It sends Steam launches through omamode
# (which offers gaming mode in work mode), and falls back to Steam itself if
# omamode has been removed, so Steam always keeps working.
cli=$(printf '%q' "$cli")
if [[ -x "\$cli" ]]; then
  exec "\$cli" steam "\$@"
fi
exec $(printf '%q' "$steam_bin") "\$@"
EOS

  src="${OMAMODE_STEAM_DESKTOP:-/usr/share/applications/steam.desktop}"
  if [[ -f "$src" ]]; then
    awk -v exe="$(om_desktop_quote "$OM_P_EXEC")" -v marker="$OM_DESKTOP_MARKER" '
      /^Exec=\/usr\/bin\/steam( |$)/ { sub(/^Exec=\/usr\/bin\/steam/, "Exec=" exe) }
      { print }
      /^\[Desktop Entry\]$/ && !done { print marker; done = 1 }
    ' "$src" | om_place "$OM_P_DESKTOP" 644 "Steam launcher entry" && placed+=("Steam launcher entry")
    command -v update-desktop-database >/dev/null 2>&1 \
      && update-desktop-database "$(dirname "$OM_P_DESKTOP")" >/dev/null 2>&1 || true
  else
    om_info "Skipped the Steam launcher entry: $src not found (is Steam installed?)"
  fi

  cat <<EOW | om_place "$OM_P_WRAPPER" 755 "omamode command" && placed+=("omamode command")
#!/usr/bin/env bash
# $OM_MARKER
cli=$(printf '%q' "$cli")
if [[ -x "\$cli" ]]; then
  exec "\$cli" "\$@"
fi
echo "omamode was removed. Reinstall with: omarchy plugin add https://github.com/hokgt/omamode.git, or delete \$0" >&2
exit 1
EOW

  { echo "// $OM_MARKER"; cat "$OM_ROOT/pi/omamode.ts"; } \
    | om_place "$OM_P_PIEXT" 644 "pi extension" && placed+=("pi extension")

  printf '%s\n' "$version" >"$(om_setup_version_file)"
  if (( ${#placed[@]} )); then
    om_notify "omamode is set up" "Placed: $(IFS=,; echo "${placed[*]}" | sed 's/,/, /g')."
  fi
}

om_cmd_uninstall() {
  om_setup_paths
  local f removed=0
  for f in "$OM_P_DESKTOP" "$OM_P_EXEC" "$OM_P_WRAPPER" "$OM_P_PIEXT"; do
    if om_is_managed "$f"; then
      rm -f "$f" && om_info "Removed $f" && removed=1
    fi
  done
  rmdir "$(dirname "$OM_P_EXEC")" 2>/dev/null || true
  rm -f "$(om_setup_version_file)"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$OM_P_DESKTOP")" >/dev/null 2>&1 || true
  (( removed )) || om_info "Nothing to remove"
  om_info "Now run: omarchy plugin remove hokgt.omamode"
}
