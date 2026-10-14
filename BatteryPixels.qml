import QtQuick
import qs.Commons

// One pixel battery: label, ten blocks and the percentage. Blocks fill with
// the accent colour (urgent at 20 % or less); a charging part pulses its
// next block.
Item {
  id: root

  property string label: ""
  property int level: -1              // 0..100, -1 = unknown
  property bool charging: false
  property bool approximate: false    // advert-based: 10 % steps
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property int blocks: level < 0 ? 0 : Math.max(level > 0 ? 1 : 0, Math.round(level / 10))
  readonly property color fill: level >= 0 && level <= 20 ? urgent : accent
  property bool pulse: false

  implicitHeight: col.implicitHeight
  implicitWidth: col.implicitWidth

  Timer {
    interval: 500
    running: root.charging && root.visible && root.level < 100
    repeat: true
    onTriggered: root.pulse = !root.pulse
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: labelText.implicitHeight

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.label.toUpperCase() + (root.charging ? " ϟ" : "")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.level < 0 ? "—" : (root.approximate ? "~" : "") + root.level + "%"
        color: root.level >= 0 && root.level <= 20 ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Row {
      id: cells
      width: parent.width
      spacing: Math.max(1, Math.round(Style.space(2)))
      readonly property real cell: Math.floor((width - spacing * 9) / 10)

      Repeater {
        model: 10
        Rectangle {
          required property int index
          width: cells.cell
          height: Math.max(6, Math.round(Style.space(7)))
          radius: 0
          color: index < root.blocks ? root.fill
            : (root.charging && index === root.blocks && root.pulse) ? Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.55)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
        }
      }
    }
  }
}
