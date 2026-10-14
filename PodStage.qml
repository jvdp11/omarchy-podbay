import QtQuick
import "Sprites.js" as Sprites
import "Palette.js" as Palette

// The animated pixel scene in the panel: AirPods Max or AirPods Pro (with
// case) in theme colours, plus what they are doing:
//
//   anc           accent rings closing in around the cups / buds
//   transparency  cool-coloured sound pixels drifting in
//   adaptive      both, taking turns
//   searching     radar ripples (looking for a pair in pairing mode)
//   levels        music: sound waves off the Max's cups; for the Pro an
//                 8-band pixel equalizer between the buds, which bounce
//
// Everything sits on one 56 x 40 pixel grid scaled to whole pixels.
Item {
  id: root

  property string kind: "max"          // max | pro | buds
  property string mode: ""             // anc | transparency | adaptive | off | ""
  property bool connected: false
  property bool present: false         // nearby or connected
  property bool lidOpen: false
  property bool searching: false
  property var ear: []                 // AAP ear detection ["ear"|"out"|"case", ...]
  property var levels: []              // 8 bands 0..1 (bass..treble), empty = silent
  property var palette: Palette.make("#f5f5f7", "#1c1c1e", "#ff9f0a", {})

  readonly property int gw: 56
  readonly property int gh: 40
  readonly property int px: Math.max(2, Math.floor(Math.min(width / gw, height / gh)))
  readonly property bool animating: visible && (present || searching)

  property int frame: 0
  // Lid position for the case, eased between 0 (closed) and 2 (open).
  property int lid: 0
  readonly property int lidTarget: (connected || lidOpen) ? 2 : 0

  implicitHeight: gh * 4

  onFrameChanged: canvas.requestPaint()
  onKindChanged: canvas.requestPaint()
  onModeChanged: canvas.requestPaint()
  onPresentChanged: canvas.requestPaint()
  onPaletteChanged: canvas.requestPaint()
  onPxChanged: canvas.requestPaint()
  onLidChanged: canvas.requestPaint()
  onLevelsChanged: canvas.requestPaint()

  // 10 fps while something moves; still otherwise.
  Timer {
    interval: 100
    running: root.animating || root.lid !== root.lidTarget
    repeat: true
    onTriggered: {
      root.frame = (root.frame + 1) % 2400
      if (root.frame % 2 === 0 && root.lid !== root.lidTarget)
        root.lid += root.lid < root.lidTarget ? 1 : -1
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var P = root.px
      var ox = Math.floor((width - root.gw * P) / 2)
      var oy = Math.floor((height - root.gh * P) / 2)
      var pal = root.palette
      var f = root.frame

      function dot(x, y, color) {
        if (x < 0 || y < 0 || x >= root.gw || y >= root.gh) return
        ctx.fillStyle = color
        ctx.fillRect(ox + x * P, oy + y * P, P, P)
      }

      function sprite(rows, sx, sy, alpha) {
        ctx.globalAlpha = alpha === undefined ? 1 : alpha
        for (var y = 0; y < rows.length; y++) {
          var row = rows[y]
          for (var x = 0; x < row.length; x++) {
            var c = row[x]
            if (c === ".") continue
            ctx.fillStyle = pal[c]
            ctx.fillRect(ox + (sx + x) * P, oy + (sy + y) * P, P, P)
          }
        }
        ctx.globalAlpha = 1
      }

      // Pixel circle (midpoint), drawn as dashes that rotate with `phase`.
      function ring(cx, cy, r, color, phase, dashed) {
        var x = r, y = 0, err = 1 - r, pts = []
        while (x >= y) {
          pts.push([x, y], [y, x], [-y, x], [-x, y], [-x, -y], [-y, -x], [y, -x], [x, -y])
          y++
          if (err < 0) err += 2 * y + 1
          else { x--; err += 2 * (y - x) + 1 }
        }
        for (var i = 0; i < pts.length; i++) {
          var a = Math.atan2(pts[i][1], pts[i][0])
          if (dashed && Math.floor((a + Math.PI + phase) / (Math.PI / 6)) % 2) continue
          dot(Math.round(cx + pts[i][0]), Math.round(cy + pts[i][1]), color)
        }
      }

      var A = pal.accent, C = pal.cool
      function tint(c, alpha) { return Palette.css(c, alpha) }
      function blend(a, b, t) { return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t } }

      // Music: levels drive a bounce, an equalizer and waves.
      var lv = root.connected && root.levels && root.levels.length === 8 ? root.levels : null
      var loud = lv ? lv.reduce(function(a, b) { return a + b }, 0) / 8 : 0
      var music = lv !== null && loud > 0.06
      var beat = music && lv[0] > 0.78 ? 1 : 0

      // 8 bars from `bottom` up; `step` = bar width + gap; `inside(x, y)`
      // clips them to a shape (the space under the Max's headband).
      function equalizer(x0, bottom, maxH, barW, step, inside) {
        for (var i = 0; i < 8; i++) {
          var h = Math.max(1, Math.round(lv[i] * maxH))
          for (var y = 0; y <= h; y++) {
            var c = y === h ? tint(pal.fg, 0.55 * lv[i])  // peak cap
              : tint(blend(A, C, y / Math.max(1, maxH - 1)), 0.45 + 0.55 * (y + 1) / h)
            for (var w = 0; w < barW; w++) {
              var x = x0 + i * step + w
              if (!inside || inside(x, bottom - y)) dot(x, bottom - y, c)
            }
          }
        }
      }

      // Where sound "happens": cup or bud-head centres, set per kind below.
      var centres = []
      var dim = root.present || root.searching ? 1 : 0.38

      if (root.kind === "max") {
        var bob = 0  // the Max stays put; the waves carry the music
        sprite(Sprites.max, 11, 6 + bob, dim)
        centres = [[17, 28 + bob], [38, 28 + bob]]
        if (music) {
          // Waves off the outer side of each cup: more and brighter when louder.
          var nw = Math.min(3, Math.round(loud * 4))
          for (var wv = 0; wv < nw; wv++) {
            var a2 = (1 - wv / 3) * (0.4 + loud * 0.6)
            for (var yy = -3 - wv; yy <= 3 + wv; yy++) {
              var bend = Math.round(Math.abs(yy) * Math.abs(yy) / (6 + wv * 3))
              dot(10 - wv * 2 + bend, 28 + bob + yy, tint(A, a2 * (1 - Math.abs(yy) / (5 + wv))))
              dot(45 + wv * 2 - bend, 28 + bob + yy, tint(A, a2 * (1 - Math.abs(yy) / (5 + wv))))
            }
          }
        }
      } else {
        var lidRows = [Sprites.case0, Sprites.case1, Sprites.case2][root.lid]
        sprite(lidRows, 15, 17, dim)
        var inEars = root.ear.length && root.ear.every(function(e) { return e === "ear" })
        if (root.connected || root.lid === 2) {
          // Buds float out of the case, bobbing out of step.
          var lift = root.connected ? 0 : 6
          var b1 = music ? beat : Math.floor(f / 6) % 2
          var b2 = music ? (lv[2] > 0.75 ? 1 : 0) : Math.floor(f / 6 + 1) % 2
          if (music) equalizer(20, 14, 12, 2, 2)
          sprite(Sprites.budL, 4, 2 + lift + b1, root.connected ? 1 : 0.85)
          sprite(Sprites.budR, 39, 2 + lift + b2, root.connected ? 1 : 0.85)
          centres = [[10, 7 + lift + b1], [45, 7 + lift + b2]]
          if (inEars && root.connected) {
            // Little notes over the buds while they are in your ears.
            var n = Math.floor(f / 5) % 6
            dot(14, 3 - (n % 3), tint(A, 1 - n / 7)); dot(15, 2 - (n % 3), tint(A, 1 - n / 7))
            dot(40, 4 - ((n + 2) % 3), tint(A, 1 - n / 7))
          }
        }
      }

      // ---- Listening mode ----
      var m = root.connected ? root.mode : ""
      var showRings = m === "anc" || (m === "adaptive" && Math.floor(f / 25) % 2 === 0)
      var showDrift = m === "transparency" || (m === "adaptive" && Math.floor(f / 25) % 2 === 1)
      var big = root.kind === "max"
      if (showRings) {
        // Rings close in: sound kept out.
        for (var i = 0; i < centres.length; i++) {
          var cx = centres[i][0], cy = centres[i][1]
          var t = (f % 12) / 12
          var r = Math.round((big ? 9 : 7) - t * 3)
          ring(cx, cy, r, tint(A, 0.35 + t * 0.65), f * 0.12 * (i ? -1 : 1), true)
          ring(cx, cy, (big ? 10 : 8), tint(A, 0.25), 0, false)
        }
      }
      if (showDrift) {
        // Sound pixels drift in from outside and fade at the ear.
        for (var j = 0; j < centres.length; j++) {
          for (var k = 0; k < 6; k++) {
            var ang = (k / 6) * Math.PI * 2 + j
            var life = ((f + k * 7) % 20) / 20
            var dist = (big ? 14 : 10) * (1 - life) + 3
            dot(Math.round(centres[j][0] + Math.cos(ang) * dist),
                Math.round(centres[j][1] + Math.sin(ang) * dist * 0.8),
                tint(C, 0.25 + 0.75 * (1 - Math.abs(life - 0.5) * 2)))
          }
        }
      }

      // ---- Searching: radar ripples from the middle ----
      if (root.searching) {
        for (var w = 0; w < 3; w++) {
          var life2 = ((f + w * 10) % 30) / 30
          ring(28, 20, Math.round(4 + life2 * 24), tint(A, (1 - life2) * 0.8), f * 0.05, w % 2 === 1)
        }
      }
    }
  }
}
