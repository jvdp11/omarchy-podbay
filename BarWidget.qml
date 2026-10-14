import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Sprites.js" as Sprites
import "Palette.js" as Palette

// Bar button + panel for jvdp.podbay. State lives in Service.qml.
//
// Bar: pixel AirPods (Max or Pro) and the battery while connected; accent
// while noise cancelling, pulsing while a new pair is around to pair.
//   left = panel · right = next listening mode · middle = connect/disconnect
Panel {
  id: root
  moduleName: "jvdp.podbay"
  ipcTarget: "jvdp.podbay.panel"

  readonly property var svc: bar && bar.shell && bar.shell.serviceFor ? bar.shell.serviceFor("jvdp.podbay") : null
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- Bar --------------------------------------------------------------------
  readonly property var primary: svc ? svc.primary : null
  readonly property bool barConnected: !!(primary && primary.connected)
  readonly property bool barQuiet: barConnected && (primary.mode === "anc" || primary.mode === "adaptive")
  readonly property bool barCalling: !!svc && (svc.pairable.length > 0 || svc.newNearby.length > 0 || svc.pairing)
  readonly property int barBattery: barConnected && svc ? svc.batteryLevel(primary) : -1
  readonly property string barKind: primary ? primary.kind
    : (svc && svc.newNearby.length ? svc.newNearby[0].kind : "max")

  // ---- Panel focus: which pair the stage shows ----------------------------------
  property string selectedAddress: ""
  readonly property var focusDevice: {
    if (!svc) return null
    for (var i = 0; i < svc.devices.length; i++)
      if (svc.devices[i].address === selectedAddress) return svc.devices[i]
    return svc.primary
  }
  readonly property var focusNew: svc && !focusDevice
    ? (svc.pairable.length ? svc.pairable[0] : (svc.newNearby.length ? svc.newNearby[0] : null)) : null
  readonly property string stageKind: focusDevice ? focusDevice.kind : (focusNew ? focusNew.kind : "max")
  readonly property var palette: Palette.make(fg, Color.background, accentColor, svc ? svc.themeColors : {})

  function statusLine(d) {
    if (!svc) return ""
    if (!svc.adapter.powered) return "Bluetooth is off"
    if (!d) {
      if (svc.pairable.some(function(p) { return p.pairing })) return "Pairing…"
      if (svc.inPairingMode.length) return "Pairing mode · finding it over Bluetooth…"
      if (svc.pairable.length) return "Ready to pair"
      if (svc.newNearby.length) return svc.newNearby[0].model + " nearby · not paired here"
      if (svc.lookingForPair) return "Looking for AirPods in pairing mode"
      return "No AirPods paired yet"
    }
    if (d.connected) {
      var parts = ["Connected"]
      if (d.mode) parts.push(svc.modeLabel(d.mode))
      if (d.ear && d.ear.length && d.kind !== "max") {
        var inEar = d.ear.filter(function(e) { return e === "ear" }).length
        parts.push(inEar === 2 ? "In ears" : inEar === 1 ? "One in ear" : "Out of ears")
      }
      return parts.join(" · ")
    }
    if (d.nearby) return d.kind === "max" ? "Nearby · connect to use" : "Case open · connect to use"
    return "Not connected"
  }


  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    active: root.barConnected
    tooltipText: root.opened || !root.svc ? "" : root.svc.statusText()
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.spaceReal(horizontalMargin) * 2
    horizontalMargin: 7

    onPressed: function(b) {
      if (!root.svc) return
      if (b === Qt.RightButton) root.svc.cycleMode()
      else if (b === Qt.MiddleButton) root.svc.toggleConnection()
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      PixelIcon {
        id: barIcon
        anchors.verticalCenter: parent.verticalCenter
        rows: root.barKind === "max" ? Sprites.iconMax : Sprites.iconPro
        size: Style.font.icon
        color: root.barCalling || root.barQuiet ? root.accentColor : root.fg
        alpha: root.barConnected || root.barCalling ? 1 : 0.55

        SequentialAnimation on opacity {
          running: root.barCalling
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
          onRunningChanged: if (!running) barIcon.opacity = 1
        }
      }

      Text {
        visible: root.barBattery >= 0 && !button.vertical
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.barBattery + "%"
        color: root.barBattery <= 20 ? Color.urgent : root.fg
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }

  // ---- Panel ----------------------------------------------------------------------
  // Three tabs: Now (the pair in use), Devices (remembered pairs, order,
  // pairing), Settings.
  property string tab: "now"           // now | devices | settings | help
  property bool pairOpen: false        // "+ Pair new AirPods" expanded
  readonly property bool showPairing: !!svc && (svc.devices.length === 0 || pairOpen
    || svc.pairable.length > 0 || svc.inPairingMode.length > 0 || svc.lookingForPair)
  onOpenedChanged: {
    if (svc) svc.watch(opened)
    if (!opened) { pairOpen = false; if (tab === "help") tab = "now" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Title + tabs ----------
        Item {
          width: parent.width
          implicitHeight: tabs.implicitHeight

          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: "PODBAY"
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            font.letterSpacing: 3
          }
          Button {
            id: helpButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "?"
            active: root.tab === "help"
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            tooltipText: "How Podbay works"
            onClicked: root.tab = root.tab === "help" ? "now" : "help"
          }
          ButtonGroup {
            id: tabs
            anchors.right: helpButton.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            options: [
              { value: "now", label: "Now" },
              { value: "devices", label: "Devices" + (root.svc && root.svc.devices.length ? " " + root.svc.devices.length : "") },
              { value: "settings", label: "Settings" }
            ]
            value: root.tab
            foreground: root.fg
            accent: root.accentColor
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onChanged: function(v) { root.tab = v }
          }
        }

        Text {
          visible: !!root.svc && (!root.svc.daemonUp || !root.svc.adapter.powered || root.svc.error !== "")
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: !root.svc ? "" : !root.svc.daemonUp ? (root.svc.daemonError || "Starting…")
            : !root.svc.adapter.powered ? "Bluetooth is off" : root.svc.error
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // =============================== NOW ===============================
        Column {
          visible: root.tab === "now"
          width: parent.width
          spacing: Style.space(14)

          PodStage {
            id: stage
            width: parent.width
            height: Math.round(width * 0.62)
            kind: root.stageKind
            palette: root.palette
            connected: !!(root.focusDevice && root.focusDevice.connected)
            present: !!(root.focusDevice ? (root.focusDevice.connected || root.focusDevice.nearby) : root.focusNew)
            lidOpen: !!(root.focusDevice && root.focusDevice.lidOpen) || !!(root.focusNew && root.focusNew.lidOpen)
            mode: root.focusDevice ? root.focusDevice.mode : ""
            ear: root.focusDevice && root.focusDevice.ear ? root.focusDevice.ear : []
            levels: root.svc && root.focusDevice && root.focusDevice.connected ? root.svc.levels : []
            searching: !!root.svc && (root.svc.pairing || (!root.focusDevice && (root.svc.lookingForPair || !!root.focusNew)))
          }

          // Name + status
          Column {
            width: parent.width
            spacing: Style.space(3)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.focusDevice ? root.focusDevice.name
                : root.focusNew ? (root.focusNew.name || root.focusNew.model) : "AirPods"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.statusLine(root.focusDevice).toUpperCase()
              color: root.focusDevice && root.focusDevice.connected ? root.accentColor : Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          // Battery
          Row {
            id: batteryRow
            visible: !!root.focusDevice && Object.keys(root.focusDevice.battery || {}).length > 0
            width: parent.width
            spacing: Style.space(10)
            readonly property var parts: {
              var d = root.focusDevice
              if (!d) return []
              var b = d.battery || {}, c = d.charging || {}, out = []
              if (b.single !== undefined && b.single !== null) out.push({ label: d.kind === "max" ? "Battery" : "Buds", level: b.single, charging: !!c.single })
              if (b.left !== undefined && b.left !== null) out.push({ label: "Left", level: b.left, charging: !!c.left })
              if (b.right !== undefined && b.right !== null) out.push({ label: "Right", level: b.right, charging: !!c.right })
              if (b.case !== undefined && b.case !== null) out.push({ label: "Case", level: b.case, charging: !!c.case })
              return out
            }
            readonly property real cellWidth: parts.length ? (width - spacing * (parts.length - 1)) / parts.length : width

            Repeater {
              model: batteryRow.parts
              BatteryPixels {
                required property var modelData
                width: batteryRow.cellWidth
                label: modelData.label
                level: modelData.level
                charging: modelData.charging
                approximate: !!root.focusDevice && root.focusDevice.batteryApprox
                foreground: root.fg
                accent: root.accentColor
                fontFamily: root.fontFamily
              }
            }
          }

          // Listening mode
          Column {
            visible: !!root.focusDevice && root.focusDevice.modes && root.focusDevice.modes.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LISTENING MODE"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Row {
              id: modeRow
              width: parent.width
              spacing: Style.space(6)
              readonly property var modes: root.focusDevice && root.focusDevice.modes ? root.focusDevice.modes : []
              readonly property real cellWidth: modes.length ? (width - spacing * (modes.length - 1)) / modes.length : 0
              readonly property bool live: !!root.focusDevice && root.focusDevice.connected && root.focusDevice.aap

              Repeater {
                model: modeRow.modes
                ModeButton {
                  required property var modelData
                  width: modeRow.cellWidth
                  mode: modelData
                  active: modeRow.live && root.focusDevice.mode === modelData
                  enabled: modeRow.live
                  foreground: root.fg
                  accent: root.accentColor
                  background: Color.background
                  fontFamily: root.fontFamily
                  onClicked: root.svc.setMode(root.focusDevice.address, modelData)
                }
              }
            }

            Text {
              visible: !!root.focusDevice && !modeRow.live
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.focusDevice && root.focusDevice.connected ? "Waiting for the AirPods to report their mode…" : "Connect to change the listening mode"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            visible: !!root.focusDevice
            width: parent.width
            iconText: root.focusDevice && root.focusDevice.connected ? "󰂲" : "󰂱"
            text: root.focusDevice && root.focusDevice.connected ? "Disconnect" : "Connect"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.svc.toggleConnection(root.focusDevice)
          }

          // A pair to pair right now: say so here too, not only under Devices.
          Item {
            visible: !!root.svc && !root.focusDevice && root.svc.pairable.length > 0
            width: parent.width
            implicitHeight: pairNow.implicitHeight
            Button {
              id: pairNow
              width: parent.width
              iconText: "󰂰"
              text: root.svc && root.svc.pairable.length && root.svc.pairable[0].pairing ? "Pairing…" : "Pair " + (root.svc && root.svc.pairable.length ? root.svc.pairable[0].name : "")
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.svc.pairDevice(root.svc.pairable[0].address)
            }
          }

          Text {
            visible: !!root.svc && !root.focusDevice && root.svc.pairable.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.svc ? root.svc.pairHint(root.focusNew ? root.focusNew.kind : root.svc.commonKind) : ""
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ============================= DEVICES =============================
        Column {
          visible: root.tab === "devices"
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            visible: !!root.svc && root.svc.devices.length > 0
            text: "YOUR AIRPODS · TOP CONNECTS FIRST"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Repeater {
            id: deviceList
            model: root.svc ? root.svc.devices : []

            Rectangle {
              id: row
              required property var modelData
              required property int index
              width: parent.width
              height: rowCol.implicitHeight + Style.space(16)
              radius: 0
              readonly property bool selected: !!root.focusDevice && root.focusDevice.address === modelData.address
              color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
              border.width: selected ? Math.max(1, Math.round(Style.space(2))) : 0
              border.color: root.accentColor

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectedAddress = row.modelData.address; root.tab = "now" }
              }

              Column {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(rowIcon.implicitHeight, rowText.implicitHeight)

                  PixelIcon {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    rows: row.modelData.kind === "max" ? Sprites.iconMax : Sprites.iconPro
                    size: Style.font.title
                    color: row.modelData.connected ? root.accentColor : root.fg
                    alpha: row.modelData.connected || row.modelData.nearby ? 1 : 0.5
                  }
                  Column {
                    id: rowText
                    anchors.left: rowIcon.right
                    anchors.leftMargin: Style.space(12)
                    anchors.right: rankButtons.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: (row.index + 1) + ". " + row.modelData.name
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: (row.modelData.connected ? "CONNECTED" : row.modelData.nearby ? "NEARBY" : root.svc.lastSeenText(row.modelData.address).toUpperCase())
                        + " · " + row.modelData.model.toUpperCase()
                      color: row.modelData.connected ? root.accentColor : Qt.darker(root.fg, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 0.8
                      elide: Text.ElideRight
                    }
                  }
                  Row {
                    id: rankButtons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)
                    Button {
                      text: "▲"
                      enabled: row.index > 0
                      opacity: enabled ? 1 : 0.3
                      fontSize: Style.font.caption
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      bordered: true
                      tooltipText: "Prefer this pair"
                      onClicked: root.svc.moveDevice(row.modelData.address, -1)
                    }
                    Button {
                      text: "▼"
                      enabled: row.index < deviceList.count - 1
                      opacity: enabled ? 1 : 0.3
                      fontSize: Style.font.caption
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      bordered: true
                      onClicked: root.svc.moveDevice(row.modelData.address, 1)
                    }
                  }
                }

                Row {
                  id: rowActions
                  width: parent.width
                  spacing: Style.space(6)
                  readonly property real cellWidth: (width - spacing * 2) / 3

                  Button {
                    width: rowActions.cellWidth
                    text: row.modelData.connected ? "Disconnect" : "Connect"
                    fontSize: Style.font.caption
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    bordered: true
                    onClicked: root.svc.toggleConnection(row.modelData)
                  }
                  Button {
                    width: rowActions.cellWidth
                    text: row.modelData.autoConnect ? "Auto" : "Manual"
                    active: row.modelData.autoConnect
                    fontSize: Style.font.caption
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    bordered: true
                    tooltipText: row.modelData.autoConnect
                      ? "Connects when you " + root.svc.wakeHint(row.modelData.kind) + ". Click: only connect by hand"
                      : "Only connects by hand. Click: connect when you " + root.svc.wakeHint(row.modelData.kind)
                    onClicked: root.svc.setDeviceAuto(row.modelData.address, !row.modelData.autoConnect)
                  }
                  Button {
                    id: forgetButton
                    property bool armed: false
                    width: rowActions.cellWidth
                    text: armed ? "Sure?" : "Forget"
                    fontSize: Style.font.caption
                    foreground: armed ? Color.urgent : root.fg
                    fontFamily: root.fontFamily
                    bordered: true
                    onClicked: {
                      if (!armed) { armed = true; disarm.restart(); return }
                      armed = false
                      root.svc.forgetDevice(row.modelData.address)
                      if (root.selectedAddress === row.modelData.address) root.selectedAddress = ""
                    }
                    Timer { id: disarm; interval: 3000; onTriggered: forgetButton.armed = false }
                  }
                }
              }
            }
          }

          Text {
            visible: !!root.svc && root.svc.devices.length > 1
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "When two pairs show up, the higher one connects; a higher pair takes over from a lower one, never the other way round."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item { width: 1; height: Style.space(6) }

          Button {
            visible: !root.showPairing
            width: parent.width
            iconText: "󰐕"
            text: "Pair new AirPods"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: { root.pairOpen = true; root.svc.lookForPair(90) }
          }

          Column {
          visible: root.showPairing
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "PAIR NEW AIRPODS"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.svc ? root.svc.pairable : []
            Item {
              id: pairRow
              required property var modelData
              width: parent.width
              implicitHeight: pairButton.implicitHeight

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)
                PixelIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  rows: pairRow.modelData.kind === "max" ? Sprites.iconMax : Sprites.iconPro
                  size: Style.font.icon
                  color: root.accentColor
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: pairRow.modelData.name
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
              Button {
                id: pairButton
                anchors.right: parent.right
                text: pairRow.modelData.pairing ? "Pairing…" : "Pair"
                enabled: !pairRow.modelData.pairing
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.svc.pairDevice(pairRow.modelData.address)
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: {
              if (!root.svc) return ""
              var s = root.svc
              if (s.pairable.length) return s.autoPair ? "Pairing automatically…" : "Click Pair to use them here"
              if (s.inPairingMode.length) return "Pairing mode seen · finding " + s.inPairingMode[0].model + " over Bluetooth…"
              var kind = s.newNearby.length ? s.newNearby[0].kind : ""
              var hint = s.pairHint(kind)
              if (s.lookingForPair) return hint + " · " + Math.max(0, Math.round(s.pairUntil - s.now)) + " s"
              return hint + (s.autoPair ? ". Podbay pairs them automatically." : ".")
            }
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            visible: !!root.svc && !root.svc.lookingForPair && root.svc.pairable.length === 0
            width: parent.width
            iconText: "󰂰"
            text: "Look for AirPods"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.svc.lookForPair(90)
          }
          }
        }

        // =============================== HELP ==============================
        Column {
          visible: root.tab === "help"
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: [
              { h: "PAIR", t: "AirPods Pro: open the case and hold the button on the back until the light flashes white. AirPods Max: hold the noise control button until the light flashes white. Podbay finds them and pairs them by itself (Settings → Pair automatically)." },
              { h: "CONNECT", t: "Open the case or take the Max out of its case: paired AirPods connect here. Disconnect by hand and Podbay leaves them alone until you put them away and take them out again." },
              { h: "SOUND & MIC", t: "When AirPods connect, sound and microphone move to them; when they disconnect, back to what you had. While the AirPods mic is in use, Bluetooth drops to call quality." },
              { h: "SEVERAL PAIRS", t: "Devices: the higher pair in the list wins when both show up, and takes over from a lower one. Manual pairs only connect when you click Connect." },
              { h: "LISTENING MODE", t: "Now: Off, Transparency, Adaptive or ANC. Changing it on the AirPods shows up here too." },
              { h: "BAR", t: "Click: this panel. Right click: next listening mode. Middle click: connect or disconnect. The icon turns accent while noise cancelling and pulses when AirPods are around to pair." }
            ]
            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(3)
              Text {
                text: modelData.h
                color: root.accentColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: modelData.t
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ============================= SETTINGS ============================
        Column {
          visible: root.tab === "settings"
          width: parent.width
          spacing: Style.space(8)

          Toggle {
            width: parent.width
            label: "Connect when they appear"
            description: root.svc ? "When you " + root.svc.wakeHint(root.svc.commonKind) + ", they connect here" : ""
            checked: root.svc ? root.svc.autoConnect : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("autoConnect", !root.svc.autoConnect)
          }
          Toggle {
            width: parent.width
            label: "Pair automatically"
            description: "AirPods put in pairing mode near this PC are paired without asking"
            checked: root.svc ? root.svc.autoPair : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("autoPair", !root.svc.autoPair)
          }
          Toggle {
            width: parent.width
            label: "Sound to AirPods"
            description: "Switch audio output when they connect, back when they leave"
            checked: root.svc ? root.svc.useOutput : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("useOutput", !root.svc.useOutput)
          }
          Toggle {
            width: parent.width
            label: "Use their microphone"
            description: "Bluetooth drops to call quality while the mic is in use"
            checked: root.svc ? root.svc.useMic : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("useMic", !root.svc.useMic)
          }
          Toggle {
            width: parent.width
            label: "Dance to the music"
            description: "The pixel AirPods move with what is playing (only while this panel is open)"
            checked: root.svc ? root.svc.soundReactive : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("soundReactive", !root.svc.soundReactive)
          }
          Toggle {
            width: parent.width
            label: "Notifications"
            description: "When AirPods connect, pair, or show up nearby"
            checked: root.svc ? root.svc.notify : true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.svc.setPref("notify", !root.svc.notify)
          }
        }
      }
    }
  }
}
