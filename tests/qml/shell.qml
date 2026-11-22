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
  }

  Panel {
    id: panel
    bar: fakeBar
    service: svc
  }

  function report() {
    if (reported || !svc.status.mode || !svc.models.length || panel.selectedModel === "") return
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
    onTriggered: { console.log("ran=" + svc.lastArgs.join(" ")); console.log("actionError=" + svc.actionError); Qt.quit() }
  }

  Timer { interval: 200; running: !shell.reported; repeat: true; onTriggered: shell.report() }

  Timer { interval: 8000; running: true; onTriggered: { console.log("timeout"); Qt.quit() } }
}
