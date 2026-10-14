import QtQuick
import qs.Commons

// A square, pixel-styled button for one listening mode: a pixel icon over
// a short label. The active mode is filled with the accent colour.
Item {
  id: root

  property string mode: "off"
  property bool active: false
  property bool enabled: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color background: Color.background
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property var icons: ({
    off: [
      "..ooooo..",
      ".o.....o.",
      "o.......o",
      "o.......o",
      "o.......o",
      "o.......o",
      "o.......o",
      ".o.....o.",
      "..ooooo..",
    ],
    transparency: [
      "..ooooo..",
      ".o.....o.",
      "o..o.o..o",
      "o.......o",
      "o.o.o.o.o",
      "o.......o",
      "o..o.o..o",
      ".o.....o.",
      "..ooooo..",
    ],
    adaptive: [
      "..ooooo..",
      ".o..ooo..",
      "o...oooo.",
      "o...ooooo",
      "o...ooooo",
      "o...ooooo",
      "o...oooo.",
      ".o..ooo..",
      "..ooooo..",
    ],
    anc: [
      "..ooooo..",
      ".ooooooo.",
      "oo.....oo",
      "oo.ooo.oo",
      "oo.ooo.oo",
      "oo.ooo.oo",
      "oo.....oo",
      ".ooooooo.",
      "..ooooo..",
    ],
  })
  readonly property var labels: ({ off: "Off", transparency: "Transp.", adaptive: "Adaptive", anc: "ANC" })
  readonly property color ink: active ? background : foreground

  implicitHeight: box.implicitHeight
  opacity: enabled ? 1 : 0.4

  Rectangle {
    id: box
    anchors.fill: parent
    implicitHeight: content.implicitHeight + Style.space(16)
    radius: 0
    color: root.active ? root.accent
      : mouse.containsMouse && root.enabled ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      : "transparent"
    border.width: Math.max(1, Math.round(Style.space(2)))
    border.color: root.active ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

    Column {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      PixelIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        rows: root.icons[root.mode] || root.icons.off
        color: root.ink
        size: Style.font.title * 1.1
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: (root.labels[root.mode] || root.mode).toUpperCase()
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
