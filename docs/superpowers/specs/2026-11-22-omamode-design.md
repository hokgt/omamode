# omamode: Work and Gaming modes for Omarchy

Date: 2026-11-22
Status: ready for approval

## Intent

The laptop (AMD Ryzen AI Max+ 395 "Strix Halo", 128 GB unified memory) runs
large local LLMs through llama.cpp, and the user also plays games through
Steam. Both compete for the same unified memory. A 90 GB model and a game
cannot run together without pushing the system into swap or out-of-memory
kills.

omamode gives the desktop two explicit modes so the model and games never
compete:

- **Work mode:** the local model may be loaded (by the user, on demand).
- **Gaming mode:** the model is unloaded and Steam is running.

It is one Omarchy shell plugin with one bar button. Clicking the button opens
a pop-up panel, styled like Omarchy's own Tailscale, Bluetooth and Network
panels, from which the user switches modes and loads, unloads or swaps models.

Success: the user never has to remember to unload the model before gaming,
never gets a slow or crashing game because a model is still in memory, and
never opens pi to find the local model silently missing.

## Goals

1. One bar button that shows the current mode; clicking it opens a panel.
2. Panel contents:
   - Mode toggle: Work / Gaming.
   - Model dropdown listing every `.gguf` model in the models folder
     (`~/models` by default), always pre-selected on the default model.
   - "Set as default" for the selected model.
   - Load and Unload buttons (work mode only).
   - A status line: current mode, which model is loaded and how much memory
     it uses, or what omamode is doing right now ("Waiting for pi to
     finish…", "Switching from A to B…", "Loading…").
3. Switching to **gaming mode**:
   1. If the local model is answering a request, wait until it finishes, up
      to 2 minutes. While waiting, the panel shows "Waiting for pi to
      finish…". After 2 minutes, ask the user whether to stop the model
      anyway.
   2. Unload the model.
   3. Start Steam (window and tray icon appear).
   4. Notify: "Gaming mode: model unloaded, opening Steam."
4. Switching to **work mode**:
   1. If a game window (`steam_app_*`) is open, ask first: "A game is
      running. Close Steam and the game?" with "Close and switch" and
      "Cancel". Cancel stays in gaming mode.
   2. Close Steam. If Steam is still running after 30 s, stay in gaming mode
      and show an error. Never force-kill Steam.
   3. Do **not** load a model. The model loads only when the user presses
      Load (or accepts the pi prompt, see 7).
   4. Notify: "Work mode: Steam closed."
5. **Load** with a different model already loaded swaps them: wait for any
   in-flight answer (same 2-minute rule), unload the current model, check
   that the new one fits, load it. Only one model is ever loaded.
6. **Opening Steam in work mode** (from the app launcher or any other way)
   prompts: "Steam is available in gaming mode", with a "Switch to gaming
   mode" action button.
7. **Starting pi, or sending it a prompt, when the model pi asks for is not
   the loaded one** (and pi's current model is on the local llama.cpp
   provider) prompts inside pi. pi always requests one specific model id,
   so "some model is loaded" is not enough; the check is "pi's model is
   loaded":
   - In work mode, nothing loaded: "Load <pi's model>".
   - In work mode, a different model loaded: "Swap to <pi's model>" (same
     swap as goal 5, including waiting for answers in flight).
   - In gaming mode: "Switch to work mode and load <pi's model>" (closes
     Steam as in goal 4, then loads).
   - Plus "Continue without loading".
8. **Keep pi in sync with the default:** "Set as default" in the panel also
   sets pi's default model (`defaultModel` in `~/.pi/agent/settings.json`)
   when pi's default provider is the local llama.cpp provider, and makes
   sure pi knows the model (registered under its llama.cpp provider). If
   pi's default provider is a remote one, omamode leaves pi's settings
   alone.
9. **Too-big model:** before loading, check that the model fits in the
   GPU's memory limit (GTT, 61 GB today). If it does not, show a clear
   message ("Flash-Next needs ~98 GB; the GPU limit is 61 GB") and load
   nothing.
10. **After a reboot:** work mode, no model loaded. The last mode is not
   restored, so Steam never opens on its own at login.
11. **Quitting Steam manually in gaming mode** keeps gaming mode. Nothing
    loads automatically.
12. Every mode change shows a short desktop notification.
13. Packaged as an Omarchy plugin in the public repo
    `github.com/hokgt/omamode`, installable and removable with
    `omarchy plugin` commands, with a complete README and a GitHub repo
    description.

## Non-goals

- Detecting or blocking individual games. The trigger is Steam opening,
  because intercepting a game before it starts would need per-game launch
  options in Steam.
- Loading a model automatically when entering work mode or after boot.
- Running more than one model at a time.
- Changing kernel parameters (the GTT limit). omamode only reports the
  limit; raising it stays a manual step documented in the README.
- Managing non-Steam games or launchers (Heroic, Lutris, RetroArch).
- Remote or cloud models. pi prompts only when pi is using the local
  llama.cpp provider.

## Anti-goals (would be a failure even if it "works")

- Cutting off an answer pi is in the middle of without asking.
- Loading a model behind the user's back.
- Preventing Steam from starting in gaming mode, or leaving the user unable
  to start Steam at all if omamode breaks. Removing the plugin must restore
  normal Steam launching.
- Leaving files behind (launcher entries, pi extension links) after
  uninstall.
- Editing Omarchy's packaged files under `/usr/share/omarchy/`.

## Constraints and facts about the target system

- Omarchy 4.5, Hyprland (Lua config), Omarchy shell (Quickshell/QML) bar.
  User plugins live in `~/.config/omarchy/plugins/<plugin-id>/`; the bar
  layout is in `~/.config/omarchy/shell.json` and hot-reloads.
- llama.cpp server: `~/strix-halo/vulkan/bin/llama-server` (Vulkan build
  tuned for Strix Halo), router mode with `--models-dir ~/models
  --no-models-autoload`, port 8080. Today it is started by the user's own
  script `~/.local/bin/llama-local`, which also loads a hard-coded model.
  - Load: `POST /models/load {"model": "<id>"}`. Unload: `POST
    /models/unload {"model": "<id>"}` (to be confirmed during build).
  - Status: `GET /models` lists models with `status.value`
    (`loaded`, `loading`, `unloaded`…).
  - Busy check: `GET /slots?model=<id>` returns slots with
    `is_processing`. Verified working.
  - `--models-max` defaults to 4; omamode enforces one model by always
    unloading before loading.
- pi 1.6.0 (`~/.pi/agent/`), default provider `llama.cpp` at
  `http://127.0.0.1:8080/v1`. Global extensions are auto-discovered from
  `~/.pi/agent/extensions/*.ts`; extensions can use `ctx.ui.select` /
  `confirm` / `notify` and `pi.exec`.
- GPU memory limit: `/sys/class/drm/card*/device/mem_info_gtt_total`
  (61 GiB today) and `mem_info_gtt_used`.
- Steam: `/usr/bin/steam`, launcher entry
  `/usr/share/applications/steam.desktop`. Steam runs games as
  `steam_app_<appid>` windows. Steam does not autostart today.
- Notifications: Omarchy's notification service supports action buttons.
  `omarchy-notification-send --action <label> <program> [args]` gives up to
  three buttons that each run a program as an argv (no shell), which suits
  "Switch to gaming mode" without a process waiting on the notification.
  `notify-send -A` also works (prints the chosen action); notifications from
  `notify-send` are not kept in history.
- Omarchy plugin contract (from `/usr/share/omarchy/shell` and
  `omarchy-plugin-*`):
  - `manifest.json` at the repo root: `schemaVersion` 1 (a number), `id`
    matching `^[A-Za-z0-9][A-Za-z0-9._-]*$` (not `omarchy.*`), `name`,
    `version`, `kinds: ["bar-widget"]`, `entryPoints.barWidget`, and a
    `barWidget` block (`displayName`, `description`, `category`,
    `defaultSection`, `allowMultiple`, `defaults`).
  - `omarchy plugin add <git-url>` clones into
    `~/.config/omarchy/plugins/<id>/` (folder named after the manifest id,
    not the repo), validates, and with `--enable` adds the widget to
    `shell.json`. **It runs no install hook, and `omarchy plugin remove`
    runs no uninstall hook.**
  - Symlinks are refused anywhere inside the plugin folder.
  - Any write inside the plugin folder hot-reloads the plugin, so state and
    logs must live outside it.
  - Panels build on `Panel`, `BarIconButton`, `KeyboardPanel` and
    `PanelKeyCatcher` from `qs.Ui`; controls include `ButtonGroup` (two-state
    toggle), `Dropdown`, `Button`, `PanelHero`, `PanelSectionHeader`. Commands
    run through Quickshell `Process` with argv arrays (`Util.execArgv` for
    anything built from input). Strings go in `i18n/en.json`.
  - A plugin can expose an IPC target (`ShellIpc`), reachable as
    `omarchy-shell <target> <function>`, which a Hyprland keybinding can
    call.
  - `Dropdown` opens a popup; whether it renders correctly inside a
    `KeyboardPanel` card is untested in Omarchy's own code.
- Cold disk read is ~3.3 GB/s, so a 94 GB model takes ~30–40 s to load and
  a 22 GB model ~7 s.

## Approaches considered

**A. Full Omarchy plugin with its own panel (chosen).** A QML bar-widget
plugin for the button and panel, a bash command `omamode` that does all the
work, a Steam launcher override plus a watcher for other Steam launches, and
a small pi extension. Matches "a pop-up like the other buttons" and "managed
as a plugin". Most code, mainly the panel.

**B. Script button plus Omarchy menu.** A command-type bar button (like the
existing sing-box one) opening a list in Omarchy's menu. About half the
work, but no panel, no dropdown, no live status, and not a plugin.
Rejected: fails the panel and plugin requirements.

**C. Like A, plus an always-on background service.** Slightly more robust
long waits, but a permanently running process and more to maintain. A
covers long waits by running each switch as its own background job.
Rejected as unnecessary.

The user chose A.

## Design

### Components

All shipped in the repo, which is the plugin folder (manifest at the root):

| Component | What it does |
|---|---|
| `manifest.json` | Omarchy plugin manifest: one `bar-widget` |
| `Panel.qml` (+ helpers) | Bar icon and pop-up panel; calls `omamode` and renders its JSON status |
| `bin/omamode` | The command that does all the work; also usable from a terminal |
| `steam/steam.desktop.in` | Template for the launcher entry that overrides Steam's, routing launches through `omamode steam` |
| `pi/omamode.ts` | pi extension: checks the local model before a run and prompts |
| `i18n/en.json` | Panel and notification strings |
| `tests/` | Tests for `omamode` (stubbed `curl`, `steam`, sysfs) and a manifest check |
| `README.md`, `LICENSE` | Full user documentation; licence |

Plugin id: `hokgt.omamode`, so it installs to
`~/.config/omarchy/plugins/hokgt.omamode/`.

### The `omamode` command

```
omamode status [--json]     current mode, loaded model, memory, activity
omamode work                switch to work mode (closes Steam)
omamode gaming              switch to gaming mode (wait, unload, start Steam)
omamode models [--json]     list models in the models folder, mark the default
omamode load [model]        load model (default model if omitted); swaps if another is loaded
omamode unload              unload the loaded model (waits for in-flight answers)
omamode default <model>     set the default model
omamode steam [args...]     used by the Steam launcher entry: start Steam in
                            gaming mode, otherwise prompt
omamode setup | uninstall   place or remove the external links
```

Long operations (`gaming`, `load`, `unload`) run as a detached background
job so they keep going if the panel closes. The job writes its progress to
the state, which the panel shows.

A lock (one operation at a time) prevents a Load and a Gaming switch racing
each other. A second request while one is running is refused with a clear
message.

### State and config

- **Runtime state** in `$XDG_RUNTIME_DIR/omamode/state.json` (a tmpfs
  cleared on reboot): `mode`, `activity` (idle / waiting-for-pi / unloading /
  loading / starting-steam / closing-steam / error), `activity_detail`,
  `updated_at`. Because the folder is cleared on reboot, a fresh boot is
  always work mode with no activity, which satisfies goal 10 with no extra
  logic.
- **Config** in `~/.config/omamode/config.json`: `default_model`,
  `models_dir` (default `~/models`), `server` (binary path, port, extra
  arguments; defaults match the current `llama-local` flags), `wait_timeout`
  (default 120 s).
- What is loaded is never stored; it is always read live from
  llama-server, so omamode cannot disagree with reality.

### llama-server lifecycle

- omamode talks to whatever llama-server is listening on the configured
  port, regardless of who started it (omamode or `llama-local`).
- Load when no server is running: omamode starts the router server with the
  configured flags (detached, logging to a file), waits for `/health`, then
  loads the model.
- Unload: unload the model through the API. The router process itself stays
  running (it uses ~0.1 GB). Gaming mode does not need to kill it.

### Waiting for pi

Before any unload (gaming switch, swap, Unload button), poll
`/slots?model=<loaded>` every 2 s. If any slot `is_processing`, set activity
to waiting-for-pi. After `wait_timeout` (120 s), show a notification with
actions "Stop the model now" and "Keep waiting" (another 2 minutes) and
"Cancel" (stay in the current mode, nothing unloaded).

### Memory check before Load

Required memory = model file size + an allowance for context and working
buffers (estimate from the server's context size; ~4 GB at 64k context for
current models). Available = GTT total minus GTT used by everything else
(measured after any unload). If required > available, refuse with the
message from goal 9, including both numbers.

### Steam

- **Launcher override:** a user launcher entry with the same id as Steam's
  (`~/.local/share/applications/steam.desktop`) whose `Exec` runs `omamode
  steam %U`, preserving Steam's other actions. In gaming mode it runs
  `/usr/bin/steam` with the same arguments. In work mode it shows the
  notification from goal 6 and does not start Steam.
- **Watcher for other launches** (for example a `steam://` link): the
  plugin, which runs inside the always-running shell, watches Hyprland for
  a Steam window appearing while in work mode and shows the same
  notification. omamode does not kill Steam in that case. The prompt only
  offers to switch.
- **Starting Steam** in gaming mode: detached, so it is not a child of the
  panel or the job.
- **Closing Steam** in work mode: first check for open game windows
  (`steam_app_*` in Hyprland). If any, ask before going on (goal 4). Then
  `steam -shutdown` and wait up to 30 s for the Steam processes to exit. If
  Steam is still running, stay in gaming mode and notify "Steam did not
  close; still in gaming mode". Never force-kill.

### pi extension

- Loaded from `~/.pi/agent/extensions/omamode.ts` (a copy placed by setup).
- On `before_agent_start` (and once on session start), if pi's current
  model is on the local llama.cpp provider, ask `omamode status --json`
  which model is loaded, and compare it with pi's model id.
- If pi's model is not the loaded one and pi has a UI, show a
  `ctx.ui.select` prompt with the options from goal 7. Choosing an option
  runs `omamode load <pi's model>` (which swaps if needed) or `omamode work`
  then `omamode load <pi's model>`, and waits for the model before the run
  continues, showing progress in pi's status line.
- Without a UI (`pi -p`), print a one-line notice and continue.
- pi's local classifier model (used only by pi's optional code-mode
  scripts) does not trigger the prompt. Its requests still count as
  "answering" when omamode waits before an unload, because the busy check
  looks at every request on the loaded model.

### Keeping pi's default in sync

- "Set as default" writes omamode's config and, when pi's
  `defaultProvider` is the local llama.cpp provider, also sets pi's
  `defaultModel` in `~/.pi/agent/settings.json`. The edit changes only that
  key, keeps the rest of the file as it is, and makes a backup first.
- No registration is needed: pi's llama.cpp provider discovers models
  from the router itself (pi lists a llama.cpp model once the router has
  it loaded). Confirmed from pi's documentation during the build.
- If pi's default provider is remote, pi's settings are left alone; the
  pi prompt still loads whichever local model pi asks for.

### Bar button and panel

- Icon reflects the mode (work vs gaming) and shows a busy state during
  long operations.
- Panel layout, top to bottom: title and status line; Work / Gaming toggle;
  model dropdown (pre-selected on the default) with "Set as default";
  Load / Unload buttons, disabled in gaming mode and while busy; any error
  from the last operation.
- The panel refreshes from `omamode status --json` while open and on
  every action.
- Follows Omarchy panel conventions (theme colours, fonts, spacing) as used
  by the built-in panels, so it updates with theme changes.
- Built from `qs.Ui` parts: `ButtonGroup` for Work / Gaming, `Dropdown` for
  the model, `Button` for Set as default, Load and Unload, `PanelHero` for
  the status. If `Dropdown` does not render properly inside the panel card,
  fall back to a short list of selectable model rows.
- The Steam watcher lives in the panel plugin, which runs inside the
  always-running shell, using Quickshell's Hyprland integration to see new
  windows.

### Notifications

Short desktop notifications for every mode change, the Steam-in-work-mode
prompt, the too-big message, and the 2-minute wait prompt. Notifications
with a choice use `omarchy-notification-send --action`, so each button runs
an `omamode` subcommand directly and no process has to wait on the
notification. The 2-minute prompt's buttons are "Stop the model now", "Keep
waiting" and "Cancel".

### Installation and removal

Omarchy runs no install or uninstall step, so the design must stay safe
even when the plugin folder disappears without warning.

- Install: `omarchy plugin add https://github.com/hokgt/omamode.git
  --enable`. The panel calls `omamode` by its absolute path inside the
  plugin folder, so the button and panel work immediately.
- Setup of the pieces outside the plugin folder (`omamode setup`,
  idempotent):
  - `~/.local/bin/omamode`: a tiny wrapper script (not a link) that runs
    the plugin's `bin/omamode`, or prints how to reinstall or clean up if
    the plugin is gone.
  - `~/.local/share/applications/steam.desktop`: a generated **copy** of
    Steam's entry whose `Exec` lines run omamode **only if it still exists**,
    and otherwise run `/usr/bin/steam` directly. If the plugin is removed
    without `omamode uninstall`, Steam still launches normally.
  - `~/.pi/agent/extensions/omamode.ts`: a **copy** of the pi extension that
    does nothing if `omamode` is missing, so a removed plugin never breaks
    pi.
  - Each placed file carries a marker comment so uninstall only removes
    files omamode created.
- Setup runs automatically the first time the panel loads (and when the
  plugin version changes), and shows one notification saying what it
  placed. It can also be run by hand.
- Remove: `omamode uninstall`, then `omarchy plugin remove hokgt.omamode`.
  Uninstall removes exactly what setup created and leaves the system as it
  was. Even if a user skips `uninstall`, the fallbacks above keep Steam and
  pi working.
- Optional keybinding: the panel's IPC target lets a user bind a key to
  `omarchy-shell hokgt.omamode toggle` (documented in the README, not set up
  automatically).
- README covers: what it does, requirements, install, usage (panel and
  CLI), config file, how each prompt behaves, raising the GPU memory limit
  for large models (manual), troubleshooting, uninstall.

## Decided by the user

- Option A (full plugin with its own panel).
- Trigger is Steam opening, not individual games.
- Gaming mode waits for pi to finish; work mode closes Steam; work mode does
  not auto-load; Load swaps models.
- Panel lists every model, with a default that is always pre-selected.
- Edge cases 10–12 and the 2-minute wait as above.
- pi's model must be the loaded one; "Set as default" keeps pi's default
  in sync; pi's prompt offers to swap to pi's model.
- Switching to work mode asks first if a game is running, and stays in
  gaming mode if Steam does not close within 30 s. Nothing is force-killed.
- Two-step removal (`omamode uninstall`, then `omarchy plugin remove`) is
  acceptable, as long as skipping the first step never breaks Steam or pi.
- Published as a plugin in `github.com/hokgt/omamode` with a complete README
  and a repo description.

## Builder's calls (proposed by Claude, open to correction)

- Plugin id, command name `omamode`, file layout, state in
  `$XDG_RUNTIME_DIR`, config in `~/.config/omamode/`.
- Implementation language: bash for `omamode`, QML for the panel,
  TypeScript for the pi extension.
- The pi prompt appears inside pi, not as a desktop notification.
- Steam opened by a route other than the launcher is detected through
  Hyprland windows and only prompted, never killed.
- `llama-local` is left untouched; omamode coexists with it.
- Setup runs automatically on first panel load, with a notification.
- Placed files are copies with fallbacks, not links, so removing the plugin
  without `uninstall` never breaks Steam or pi.
- Test approach: bash tests with stubbed `curl`, `steam` and sysfs files for
  `omamode`; `omarchy plugin validate` for the manifest; a `qs -p` load check
  for the QML, following the pattern of existing third-party plugins.
- Licence: MIT, like Omarchy and the plugins it ships.

- pi's local classifier model does not trigger the pi prompt, but its
  requests count as busy when waiting.

## Open questions

None. The reviewer check raised four questions: three were answered by the
user (above), and one (the classifier) was settled as a builder's call.
