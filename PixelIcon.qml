import QtQuick

// A one-colour pixel icon from rows of characters ("." = empty). Pixels snap
// to whole device pixels so the art stays crisp at any bar size.
Item {
  id: root

  property var rows: []
  property color color: "white"
  property real size: 16           // target height in px
  property real alpha: 1

  readonly property int gw: rows.length ? rows[0].length : 1
  readonly property int gh: rows.length || 1
  readonly property int px: Math.max(1, Math.floor(size / gh))

  implicitWidth: gw * px
  implicitHeight: gh * px

  onRowsChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onAlphaChanged: canvas.requestPaint()
  onPxChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.globalAlpha = root.alpha
      ctx.fillStyle = root.color
      for (var y = 0; y < root.rows.length; y++) {
        var row = root.rows[y], x = 0
        while (x < row.length) {
          if (row[x] === ".") { x++; continue }
          var start = x
          while (x < row.length && row[x] !== ".") x++
          ctx.fillRect(start * root.px, y * root.px, (x - start) * root.px, root.px)
        }
      }
    }
  }
}
