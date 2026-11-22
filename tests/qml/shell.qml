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
    onTriggered: {
      console.log("ran=" + svc.lastArgs.join(" "))
      console.log("actionError=" + svc.actionError)
      dropdownTest.start()
    }
  }

  // Dropdown: open the panel, pick a model the way a click does (Dropdown
  // sets its own value, then emits changed), close, reopen: it must start on
  // the default again. Then the picked model disappears: back to default.
  property int step: 0
  Timer {
    id: dropdownTest
    interval: 400
    repeat: true
    onTriggered: {
      var dd = panel.modelDropdown
      switch (shell.step++) {
      case 0: panel.open(); break
      case 1:
        if (!dd) { console.log("dropdown=missing"); Qt.quit(); return }
        console.log("dropdownOpen=" + dd.value)
        dd.value = "A"; dd.changed("A")
        console.log("dropdownPicked=" + dd.value + "/" + panel.selectedModel)
        panel.close()
        break
      case 2: panel.open(); break
      case 3:
        console.log("dropdownReopen=" + dd.value)
        dd.value = "A"; dd.changed("A")
        svc.models = svc.models.filter(function(m) { return m.id !== "A" })
        break
      case 4:
        console.log("dropdownAfterRemoval=" + dd.value)
        stop(); Qt.quit()
        break
      }
    }
  }

  Timer { interval: 200; running: !shell.reported; repeat: true; onTriggered: shell.report() }

  Timer { interval: 12000; running: true; onTriggered: { console.log("timeout"); Qt.quit() } }
}
