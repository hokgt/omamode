// Test harness: loads the service and the panel with a stub omamode CLI.
import QtQuick
import Quickshell
import qs.Commons as Commons

ShellRoot {
  id: shell
  property int checks: 0
  property bool reported: false

  QtObject {
    id: fakeBar
    property color foreground: Commons.Color.foreground
    property color barForeground: Commons.Color.foreground
    property string fontFamily: "monospace"
    property bool vertical: false
  }

  OmamodeService {
    id: svc
    cliPath: Quickshell.env("OMAMODE_TEST_CLI")
    runSetup: false
    onStatusChanged: if (status && status.mode) shell.report()
    onModelsChanged: if (models && models.length) shell.report()
  }

  Panel {
    id: panel
    bar: fakeBar
    service: svc
  }

  function report() {
    checks++
    if (checks < 2 || reported || panel.selectedModel === "") return
    reported = true
    console.log("mode=" + svc.status.mode)
    console.log("models=" + svc.models.map(function(m) { return m.id }).join(","))
    console.log("icon=" + panel.iconText)
    console.log("selected=" + panel.selectedModel)
    svc.run(["load", "B"])
    actionCheck.start()
  }

  Timer {
    id: actionCheck
    interval: 800
    onTriggered: { console.log("ran=" + svc.lastArgs.join(" ")); Qt.quit() }
  }

  Timer { interval: 8000; running: true; onTriggered: { console.log("timeout"); Qt.quit() } }
}
