# shellcheck shell=bash
# Desktop notifications through Omarchy's notifier.
#
#   om_notify <headline> <body> [--action <label> <program> <words...>]...
#
# Action words must be fixed literals (never model names or other input).
# Clicking the card runs the FIRST action, so put the safe choice first.

om_notify() {
  local notifier="${OMAMODE_NOTIFY:-omarchy-notification-send}"
  if ! command -v "$notifier" >/dev/null 2>&1; then
    notifier="notify-send"
    # notify-send has no exec buttons; drop them.
    local args=("$1" "${2:-}")
    "$notifier" -a omamode "${args[@]}" >/dev/null 2>&1 || true
    return 0
  fi
  "$notifier" --app-name omamode -g 󰧑 "$@" >/dev/null 2>&1 || true
}
