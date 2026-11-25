import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// omamode bar button and panel: switch between work mode (local model) and
// gaming mode (Steam), pick the agent that uses the local model, and pick
// a model (which loads it and makes it the default), or unload it.
Panel {
  id: root
  moduleName: "hokgt.omamode"
  ipcTarget: "hokgt.omamode"

  // The service can be passed in (tests); otherwise the panel owns one.
  property var service: ownService
  property string selectedModel: ""

  readonly property bool gaming: service.mode === "gaming"
  readonly property bool busy: service.busy
  readonly property string iconText: gaming ? "󰊴" : "󰧑"
  readonly property var st: service.status || ({})
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property var modelsDirInfo: st.modelsDir || ({})
  readonly property string modelsFolder: modelsDirInfo.path || ""
  readonly property bool folderMismatch: modelsDirInfo.mismatch === true
  readonly property string agent: st.agent || ""
  // Agents to offer: the installed ones, plus the selected one in any case.
  readonly property var agentOptions: (st.agents || [])
    .filter(function(a) { return a.installed || a.selected })
    .map(function(a) { return { value: a.id, label: a.id } })
  property bool editingFolder: false

  function setModelsDir(path) {
    var p = String(path || "").trim()
    if (p === "") return
    editingFolder = false
    service.run(["models-dir", p])
  }

  // The dropdowns while the panel's content is loaded (used by tests).
  readonly property var modelDropdown: panel.loadedContent ? panel.loadedContent.modelDropdown : null
  readonly property var agentDropdown: panel.loadedContent ? panel.loadedContent.agentDropdown : null
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  OmamodeService {
    id: ownService
    fast: root.opened
  }

  function defaultModel() {
    var models = service.models || []
    for (var i = 0; i < models.length; i++) if (models[i].default) return models[i].id
    return models.length ? models[0].id : ""
  }

  function modelInfo(id) {
    var models = service.models || []
    for (var i = 0; i < models.length; i++) if (models[i].id === id) return models[i]
    return null
  }

  function modelLabel(m) {
    var text = m.id
    if (m.default) text = strings.t("model.default").arg(text)
    if (!m.complete) return strings.t("model.downloading").arg(text)
    if (!m.fits) return strings.t("model.tooBig").arg(text)
    return text
  }

  // The dropdown always starts on the default model.
  function resetSelection() { selectedModel = defaultModel() }
  onOpenedChanged: if (opened) { resetSelection(); editingFolder = false; service.refresh() }
  Connections {
    target: root.service
    function onModelsChanged() { if (root.selectedModel === "" || !root.modelInfo(root.selectedModel)) root.resetSelection() }
  }
  Component.onCompleted: resetSelection()

  readonly property string heroMeta: {
    if (st.server === "stopped" && !gaming) return strings.t("status.serverStopped")
    if (service.loaded) return strings.t("status.loaded").arg(service.loaded.id).arg(Commons.I18n.formatNumber(service.loaded.sizeGB || 0))
    return gaming ? strings.t("status.gamingHint") : strings.t("status.noModel")
  }

  // Picking a model loads it and makes it the default (for the agent too).
  // Picking the loaded default again does nothing.
  function pickModel(id) {
    selectedModel = id
    var m = modelInfo(id)
    if (!m || busy) return
    if (m.default && service.loaded && service.loaded.id === id) return
    service.run(["use", id])
  }

  function pickAgent(id) {
    if (id && id !== agent && !busy) service.run(["agent", id])
  }

  readonly property bool canLoad: {
    var m = modelInfo(selectedModel)
    return !gaming && !busy && !!m && m.complete && m.fits && !(service.loaded && service.loaded.id === selectedModel)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconText
    opacity: root.busy ? 0.6 : 1.0
    tooltipText: root.gaming ? strings.t("tooltip.gaming")
      : (root.service.loaded ? strings.t("tooltip.workLoaded").arg(root.service.loaded.id) : strings.t("tooltip.work"))
    onPressed: function(b) { root.toggle() }

    Behavior on opacity { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      property alias modelDropdown: modelDropdown
      property alias agentDropdown: agentDropdown
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: mode icon · title · loaded model / activity ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.iconText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.gaming ? strings.t("title.gaming") : strings.t("title.work")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: (root.busy && root.st.detail ? root.st.detail : root.heroMeta).toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        // ---------- Work / Gaming ----------
        ButtonGroup {
          enabled: !root.busy
          opacity: enabled ? 1.0 : 0.5
          foreground: root.fg
          fontFamily: root.fontFamily
          options: [
            { value: "work", label: strings.t("mode.work"), icon: "󰧑" },
            { value: "gaming", label: strings.t("mode.gaming"), icon: "󰊴" }
          ]
          value: root.service.mode
          onChanged: function(v) { if (v !== root.service.mode) root.service.run([v]) }
        }

        // ---------- Agent ----------
        Dropdown {
          id: agentDropdown
          width: parent.width
          label: strings.t("agent.label")
          enabled: !root.busy && root.agentOptions.length > 0
          fontFamily: root.fontFamily
          options: root.agentOptions
          onChanged: function(v) { root.pickAgent(v) }
        }

        Binding {
          target: agentDropdown
          property: "value"
          value: root.agent
        }

        // ---------- Model ----------
        Dropdown {
          id: modelDropdown
          width: parent.width
          label: strings.t("model.label")
          enabled: !root.busy && (root.service.models || []).length > 0
          fontFamily: root.fontFamily
          options: (root.service.models || []).map(function(m) { return { value: m.id, label: root.modelLabel(m) } })
          onChanged: function(v) { root.pickModel(v) }
        }

        // Dropdown assigns its own value when the user picks an entry, which
        // would break a plain binding; this Binding keeps following
        // selectedModel (e.g. back to the default when the panel reopens).
        Binding {
          target: modelDropdown
          property: "value"
          value: root.selectedModel
        }

        Text {
          visible: (root.service.models || []).length > 0
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("model.hint").arg(root.agent || "the agent")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Text {
          visible: (root.service.models || []).length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("model.none")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: strings.t("action.load")
            iconText: "󰐊"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.canLoad
            opacity: enabled ? 1.0 : 0.5
            onClicked: root.service.run(["load", root.selectedModel])
          }

          Button {
            text: strings.t("action.unload")
            iconText: "󰓛"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: !root.busy && !!root.service.loaded
            opacity: enabled ? 1.0 : 0.5
            onClicked: root.service.run(["unload"])
          }
        }

        // ---------- Models folder ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("folder.label").arg(root.modelsFolder || "—")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Text {
            visible: root.folderMismatch
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("folder.mismatch").arg(root.modelsDirInfo.config || "")
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Row {
            spacing: Style.space(8)
            visible: !root.editingFolder

            Button {
              visible: root.folderMismatch
              text: strings.t("folder.useServer")
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              enabled: !root.busy
              opacity: enabled ? 1.0 : 0.5
              onClicked: root.service.run(["models-dir", "--use-server"])
            }

            Button {
              text: strings.t("folder.change")
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              enabled: !root.busy
              opacity: enabled ? 1.0 : 0.5
              onClicked: { folderField.text = root.modelsDirInfo.config || root.modelsFolder; root.editingFolder = true; folderField.forceActiveFocus() }
            }
          }

          Row {
            spacing: Style.space(8)
            visible: root.editingFolder
            width: parent.width

            TextField {
              id: folderField
              width: parent.width - saveFolder.width - Style.space(8)
              placeholderText: strings.t("folder.placeholder")
              onAccepted: root.setModelsDir(text)
            }

            Button {
              id: saveFolder
              text: strings.t("folder.save")
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.setModelsDir(folderField.text)
            }
          }
        }

        // ---------- Last error ----------
        Text {
          readonly property string message: root.service.actionError || root.st.error || ""
          visible: message !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: message
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
