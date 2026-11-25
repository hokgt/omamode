# omamode

**Work and gaming modes for [Omarchy](https://omarchy.org).** One bar button switches your machine between:

- **Work mode:** your local [llama.cpp](https://github.com/ggml-org/llama.cpp) model is available for [pi](https://pi.dev) and other tools.
- **Gaming mode:** the model is unloaded and Steam is running.

On machines with unified memory (such as AMD Strix Halo), the GPU and the CPU share one pool of RAM. A 20–90 GB model and a game can't comfortably run together. omamode makes sure they never compete: switching to gaming mode unloads the model before Steam opens, and Steam can't be opened in work mode without offering to switch first.

## What it does

- **One bar button** shows the mode (󰧑 work, 󰊴 gaming). Click it to open a panel with:
  - a **Work / Gaming** toggle,
  - an **agent dropdown** to pick the coding agent that uses the local model (pi or opencode),
  - a **model dropdown** listing every model in your models folder, always opening on your default. Picking a model loads it and makes it the default, for omamode and for the agent,
  - **Load** and **Unload** buttons,
  - a status line: the loaded model and its size, what omamode is doing, or the last error.
- **Switching to gaming mode** waits until the model finishes any answer in progress, unloads it, and opens Steam.
- **Switching to work mode** closes Steam. It asks first if a game is open, and never force-closes Steam. It doesn't load a model: you press **Load** when you need it.
- **Loading a different model swaps them.** Only one model is ever loaded.
- **Opening Steam in work mode** (from the app launcher or a `steam://` link) shows a notification with a **Switch to gaming mode** button instead of opening Steam.
- **The agent follows the default.** omamode writes the default model into the chosen agent's settings: pi's `defaultModel`, or a `llama.cpp` provider and `model` in opencode's `opencode.json`.
- **pi checks before it talks to the local model.** If the model pi uses isn't loaded, pi offers to load it, swap to it, or switch to work mode and load it. After a load, pi refreshes its llama.cpp model list, so it sees models omamode loaded.
- **Models that don't fit are refused up front,** with a clear message such as `Qwen3.8-Flash-Next-UD-IQ4_XS needs ~98 GB; the GPU limit is 65 GB`.
- **Models that are still downloading** are shown as such and can't be loaded.
- **After a reboot** you're always in work mode with no model loaded. Steam never opens on its own.

## Requirements

- Omarchy 4.5 or newer (Hyprland and the Omarchy shell).
- A llama.cpp `llama-server` build that supports **router mode** (`--models-dir`). omamode starts it for you, or uses one that is already running in router mode on the configured port.
- Steam (optional, but it's half the point).
- pi 1.6 or newer (optional), using the `llama.cpp` provider.
- `jq`, `curl`, `flock` and `setsid` (all present on Omarchy).

## Install

```bash
omarchy plugin add https://github.com/hokgt/omamode.git --enable
```

The button appears in the right side of your bar. The first time the plugin loads, it sets up three small pieces outside the plugin folder and shows a notification listing them:

| Placed file | Why |
|---|---|
| `~/.local/share/applications/steam.desktop` | A copy of Steam's launcher entry that routes Steam launches (including `steam://` links) through omamode |
| `~/.local/share/omamode/steam-exec` | The helper that launcher entry runs. If omamode is gone, it starts Steam directly, so Steam always works |
| `~/.local/bin/omamode` | Lets you run `omamode` from a terminal |
| `~/.pi/agent/extensions/omamode.ts` | The pi extension. It does nothing if omamode is gone |

Each file carries an `omamode` marker. omamode never overwrites a file without it: if you already have your own `steam.desktop`, setup skips it and tells you so. You can re-run setup any time:

```bash
omamode setup
```

Then set your default model, either in the panel or with:

```bash
omamode default Qwen3.6-35B-A3B-Q4_K_M
```

## Using the panel

1. Click the 󰧑 / 󰊴 icon in the bar.
2. Choose **Work** or **Gaming**.
3. Pick the **agent** that uses the local model: pi or opencode (only installed ones are listed).
4. Pick a **model**. In work mode it loads straight away (swapping out the loaded one) and becomes the default: the one the dropdown opens on, the one `omamode load` and pi's prompt load, and the agent's own default model. In gaming mode it only becomes the default.
5. **Load** loads the default again after an **Unload**, which frees its memory.

While omamode is busy (waiting for pi, unloading, loading, opening or closing Steam), the icon dims, the status line says what's happening, and the buttons are disabled. Long operations keep running if you close the panel.

### Keyboard shortcut (optional)

The panel answers `omarchy-shell hokgt.omamode toggle`. To open it with a key, add a binding to `~/.config/hypr/bindings.lua`, for example:

```lua
o.bind("SUPER + SHIFT + G", "omamode", "omarchy-shell hokgt.omamode toggle")
```

## Prompts

| When | What you see | Buttons |
|---|---|---|
| Steam is opened in work mode | "Steam is available in gaming mode" | **Switch to gaming mode** |
| Switching to work mode while a game window is open | "A game is running. Close Steam and the game?" | **Cancel**, **Close and switch** |
| The model is still answering 2 minutes after a switch or swap was requested | "The local model is still answering" | **Keep waiting**, **Stop the model now**, **Cancel** |
| pi starts or gets a prompt, and its local model isn't loaded | A choice inside pi | **Load …** / **Swap to …** / **Switch to work mode and load …**, **Continue without loading** |

Clicking a notification card itself runs its first button, so the first button is always the safe choice.

Steam opened some other way while in work mode (not through the launcher) is noticed when its window appears. omamode shows the same prompt once per Steam run, and never closes Steam itself.

## Command line

```
omamode status [--json]          current mode, loaded model, activity
omamode models [--json]          models in the models folder
omamode load [model]             load a model (the default if omitted); swaps if another is loaded
omamode use <model>              make a model the default (also the agent's) and load it
omamode unload                   unload the loaded model
omamode default <model>          set the default model (also the agent's default)
omamode agent [name|--json]      show or pick the agent that uses the local model (pi, opencode)
omamode models-dir [path]        show the models folder, or set it (--use-server adopts the server's)
omamode work [--confirmed]       switch to work mode (closes Steam; loads nothing)
omamode gaming                   switch to gaming mode (unloads the model, opens Steam)
omamode steam [args...]          start Steam in gaming mode; otherwise offer to switch
omamode setup [--if-needed]      place the Steam launcher entry, CLI wrapper and pi extension
omamode uninstall                remove everything setup placed
omamode config get <key>         print a config value
omamode config set <key> <json>  set a config value
omamode --version                print the version
```

Exit codes: `0` ok, `1` failed, `2` usage error, `3` refused (another operation is running, wrong mode, model too big or still downloading, or you cancelled).

`load`, `unload`, `work` and `gaming` run in the background and return straight away. Watch progress with `omamode status`. Only one of them runs at a time; a second one is refused with `Another omamode operation is running`.

`omamode decide stop|wait|cancel` and `omamode steam-detected` are used by the notification buttons and the panel.

## Configuration

`~/.config/omamode/config.json` holds only the keys you change; everything else uses the defaults:

| Key | Default | Meaning |
|---|---|---|
| `default_model` | `null` | Model loaded by `omamode load` and pi's prompt |
| `agent` | `"pi"` | Agent whose default model follows omamode's: `pi` or `opencode` |
| `models_dir` | `~/models` | Folder llama-server reads models from |
| `port` | `8080` | llama-server port (pi's `llama.cpp` provider must use the same) |
| `server_bin` | `~/strix-halo/vulkan/bin/llama-server` | llama-server binary omamode starts |
| `server_args` | `["--jinja","--host","127.0.0.1","-ngl","999","-c","65536","-fa","on","-ctk","q4_0","-ctv","q4_0","-b","1024","-ub","1024"]` | Extra arguments. omamode always adds `--models-dir`, `--no-models-autoload` and `--port` |
| `wait_timeout` | `120` | Seconds to wait for an answer in progress before asking |
| `context_allowance_gb` | `4` | Memory added to a model's file size for context and buffers in the fit check |

For example, to use a q8 KV cache (better quality at long context):

```bash
omamode config set server_args '["--jinja","--host","127.0.0.1","-ngl","999","-c","65536","-fa","on","-ctk","q8_0","-ctv","q8_0","-b","1024","-ub","1024"]'
```

Runtime state lives in `$XDG_RUNTIME_DIR/omamode/`, which is cleared on reboot. Logs are in `~/.local/state/omamode/`.

### Which models folder is used

- **While llama-server is running,** omamode lists models from the folder the server was started with (its `--models-dir`), since that's the only place it can load from. This works even when another script started the server.
- **When it isn't running,** omamode uses `models_dir` from its config, and starts the server with that folder.
- **The panel shows the folder in use.** If the running server uses a different folder from omamode's setting, the panel and `omamode status` say so, and **Use this folder** adopts the server's. **Change…** lets you type a new folder. The same from a terminal:

```bash
omamode models-dir /mnt/ai-model/llama.cpp
```

```bash
omamode models-dir --use-server
```

- **If the folder is missing,** for example a drive that didn't mount, omamode says `Models folder not found: … (is the drive mounted?)` instead of showing an empty list without explanation. It never scans the disk for other folders.

### Model folder layout

Single-file models sit directly in `models_dir`. Split and multimodal models go in a subfolder, which is listed as one model under the folder's name. `mmproj-*`, `mtp-*` and `dflash-*` helper files are never listed as models. Split files left at the top level are listed once, under the first file's name (`model-00001-of-00003`), because that's the name llama-server loads them by.

```
~/models/
├── Qwen3.6-35B-A3B-Q4_K_M.gguf
└── Qwen3.8-Flash-Next-UD-IQ4_XS/
    ├── Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf
    ├── …
    └── mtp-Qwen3.8-Flash-Next-Q4_K_M.gguf
```

llama-server only notices new files when it restarts. omamode handles that: loading a model the running server doesn't know yet unloads the current one, restarts the server, then loads. It can only restart a server it started itself.

## Large models and the GPU memory limit

On AMD unified-memory machines, the GPU can only use part of the RAM: its GTT limit, about half by default. omamode reads it from `/sys/class/drm/card*/device/mem_info_gtt_total` and refuses models that don't fit.

Raising the limit is a manual kernel setting; omamode never changes it. On Omarchy (Limine), add a line to `/etc/default/limine`. For example, about 104 GiB on a 128 GB machine:

```bash
sudo nano /etc/default/limine
```

```
KERNEL_CMDLINE[default]+=" ttm.pages_limit=27262976 amdgpu.gttsize=106496"
```

```bash
sudo limine-update
```

Then reboot. `ttm.pages_limit` is in 4 KiB pages (GiB × 262144) and `amdgpu.gttsize` is in MiB. Leave enough memory for your desktop and apps.

## How it works with other tools

- **pi** gets omamode's default as its `defaultModel` in `~/.pi/agent/settings.json`, but only while pi's default provider is `llama.cpp`. Its `llama.cpp` login must point at the same server (`/login llama.cpp`, then `http://127.0.0.1:<port>`); the pi extension warns when it doesn't.
- **opencode** gets a `llama.cpp` provider in `~/.config/opencode/opencode.json` pointing at `http://127.0.0.1:<port>/v1`, listing the default model, and `model` set to `llama.cpp/<model>`. omamode owns that provider entry; your other settings and providers are kept, and the previous file is saved as `opencode.json.omamode-bak`. A file with comments (JSONC) is never rewritten.

- **pi's `/llama` command** talks to the same server and can load models too. omamode always reads what is actually loaded, so the panel stays correct, but `/llama` doesn't know about gaming mode.
- **Other scripts that start llama-server** (such as a personal `llama-local` script) work alongside omamode, as long as the server runs in router mode on the configured port. omamode won't stop a server it didn't start.

## Troubleshooting

- **"llama-server is not in router mode"**: a server on the port was started with a single `--model`. Stop it and let omamode start one, or start it with `--models-dir`.
- **A new model shows "(new: loads after a server restart)"**: press Load. If omamode didn't start the server, restart the server yourself first.
- **A model shows "(downloading)"**: some of its files are missing or still `.part` files. Wait for the download to finish.
- **"Steam did not close; still in gaming mode"**: Steam was still running 30 s after it was asked to quit, usually because a game or update was holding it. Close it yourself, then switch again.
- **Logs**: `~/.local/state/omamode/` (`load.log`, `gaming.log`, `work.log`, `llama-server.log`, …).
- **Run the tests**: `tests/run.sh` (the QML test needs a Wayland session).

## Uninstall

```bash
omamode uninstall
```

```bash
omarchy plugin remove hokgt.omamode
```

`omamode uninstall` removes exactly the files setup placed (only those with the omamode marker). If you remove the plugin without running it first, nothing breaks: the leftover Steam entry starts Steam directly, the pi extension does nothing, and the `omamode` command tells you how to clean up.

## Versioning and releases

omamode follows [semantic versioning](https://semver.org), and releases are automatic. Every push to `main` runs the tests in GitHub Actions. When they pass and the new commits include a releasable [Conventional Commit](https://www.conventionalcommits.org), the workflow bumps `manifest.json`, tags `vX.Y.Z` and publishes a GitHub release:

| Commit | Release |
|---|---|
| `fix: …`, `perf: …` | patch (0.1.0 → 0.1.1) |
| `feat: …` | minor (0.1.1 → 0.2.0) |
| `feat!: …` or a `BREAKING CHANGE:` footer | major (0.2.0 → 1.0.0) |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:` | no release |

Update an installed copy with `omarchy plugin update hokgt.omamode`. When the version changes, omamode re-runs its setup on the next shell start, so the Steam launcher entry and pi extension stay current.

## License

[MIT](LICENSE)
