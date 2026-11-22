import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

// Talks to the omamode CLI: reads its status and model list, runs actions
// (always as argv arrays), and notices Steam windows that open in work mode.
Item {
  id: root

  // The CLI inside this plugin folder.
  property string cliPath: decodeURIComponent(Qt.resolvedUrl("bin/omamode").toString().replace(/^file:\/\//, ""))
  // Run `omamode setup --if-needed` once when the shell loads the plugin.
  property bool runSetup: true
  // Poll faster while the panel is open or an operation is running.
  property bool fast: false

  property var status: ({})
  property var models: []
  property var lastArgs: []

  readonly property string mode: status && status.mode ? status.mode : "work"
  readonly property bool busy: !!(status && status.activity && status.activity !== "idle")
  readonly property var loaded: status && status.loaded ? status.loaded : null

  function parseJson(text, fallback) {
    try {
      var v = JSON.parse(text)
      return v === null || v === undefined ? fallback : v
    } catch (e) {
      return fallback
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!modelsProc.running) modelsProc.running = true
  }

  function run(args) {
    lastArgs = args
    actionProc.command = [cliPath].concat(args)
    if (!actionProc.running) actionProc.running = true
    refreshSoon.restart()
  }

  Process {
    id: statusProc
    command: [root.cliPath, "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.status = root.parseJson(text, root.status) }
  }

  Process {
    id: modelsProc
    command: [root.cliPath, "models", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.models = root.parseJson(text, root.models) }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: setupProc
    command: [root.cliPath, "setup", "--if-needed"]
  }

  Process {
    id: steamProc
    command: [root.cliPath, "steam-detected"]
  }

  Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }

  Timer {
    interval: root.fast || root.busy ? 2000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A Steam window opened some other way while in work mode: let the CLI
  // decide whether to show its prompt. It never closes Steam.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "openwindow") return
      var parts = String(event.data).split(",")
      var cls = parts.length > 2 ? parts[2] : ""
      if (cls.toLowerCase() === "steam" && root.mode === "work" && !steamProc.running) steamProc.running = true
    }
  }

  Component.onCompleted: if (runSetup) setupProc.running = true
}
