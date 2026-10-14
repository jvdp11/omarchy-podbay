import QtQuick
import Quickshell
import ".."
import "../Palette.js" as Palette

// Dev preview: renders PodStage in several states off-screen and writes PNGs.
//   QT_QPA_PLATFORM=offscreen quickshell -p tools/StagePreview.qml
// Output: $PODBAY_PREVIEW_DIR (default /tmp)/stage-<name>-<frame>.png
ShellRoot {
  id: shell
  readonly property string outDir: Quickshell.env("PODBAY_PREVIEW_DIR") || "/tmp"
  readonly property var cases: [
    { name: "max-anc", kind: "max", connected: true, present: true, mode: "anc" },
    { name: "max-transparency", kind: "max", connected: true, present: true, mode: "transparency" },
    { name: "max-away", kind: "max", connected: false, present: false, mode: "" },
    { name: "pro-adaptive", kind: "pro", connected: true, present: true, mode: "adaptive", lidOpen: true, ear: ["ear", "ear"] },
    { name: "pro-search", kind: "pro", connected: false, present: true, searching: true, lidOpen: false },
  ]
  property int caseIndex: 0
  property int shot: 0

  FloatingWindow {
    implicitWidth: 400
    implicitHeight: 260
    color: "#1c1c1e"

    PodStage {
      id: stage
      anchors.fill: parent
      palette: Palette.make("#f5f5f7", "#1c1c1e", "#ff9f0a", { cyan: "#a6dcef" })
    }

    Timer {
      interval: 300
      running: true
      repeat: true
      onTriggered: {
        if (shell.caseIndex >= shell.cases.length) { Qt.quit(); return }
        var c = shell.cases[shell.caseIndex]
        if (shell.shot === 0) {
          stage.kind = c.kind; stage.connected = !!c.connected; stage.present = !!c.present
          stage.mode = c.mode || ""; stage.searching = !!c.searching
          stage.lidOpen = !!c.lidOpen; stage.ear = c.ear || []
        }
        var name = c.name + "-" + shell.shot
        stage.grabToImage(function(r) { r.saveToFile(shell.outDir + "/stage-" + name + ".png") })
        shell.shot++
        if (shell.shot >= 3) { shell.shot = 0; shell.caseIndex++ }
      }
    }
  }
}
