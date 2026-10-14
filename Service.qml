import QtQuick
import Quickshell
import Quickshell.Io

// Owns Podbay's state, once for all bars/monitors. Runs bin/podbay-daemon
// (BlueZ + AAP) and talks JSON lines with it: state in, commands out.
//
//   prefs  ~/.config/omarchy/omarchy-podbay.json
//          {autoConnect, autoPair, notify, useOutput, useMic, order, manualOnly, lastSeen}
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string prefsPath: home + "/.config/omarchy/omarchy-podbay.json"
  readonly property string themePath: home + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string binDir: String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, "")

  // ---- State from the daemon ------------------------------------------------
  property var devices: []      // paired AirPods
  property var pairable: []     // unpaired AirPods in pairing mode
  property var nearby: []       // proximity adverts (case open / Max out)
  property var adapter: ({ present: false, powered: false, discovering: false })
  property real pairUntil: 0
  property var inPairingMode: []  // pairs that broadcast "pairing mode" right now
  property string error: ""
  property bool daemonUp: false
  property string daemonError: ""
  property real now: Date.now() / 1000

  // ---- Preferences ------------------------------------------------------------
  property bool autoConnect: true
  property bool autoPair: true
  property bool notify: true
  property bool useOutput: true   // sound to the AirPods when they connect
  property bool useMic: true      // and their microphone
  property bool soundReactive: true  // pixels dance to the music (panel open only)
  property bool panelOpen: false
  property var levels: []         // 8 bands 0..1 from bin/podbay-levels
  property var order: []          // addresses, most preferred first
  property var manualOnly: []     // addresses that never auto-connect
  property var lastSeen: ({})     // address -> epoch of last connection

  // ---- Theme palette (colors.toml), for the pixel art -------------------------
  property var themeColors: ({})

  // ---- Derived ------------------------------------------------------------------
  readonly property var connected: devices.filter(function(d) { return d.connected })
  // The pair the bar shows: connected first, then one that is nearby, then any.
  readonly property var primary: {
    if (connected.length) return connected[0]
    for (var i = 0; i < devices.length; i++) if (devices[i].nearby) return devices[i]
    return devices.length ? devices[0] : null
  }
  readonly property var newNearby: nearby.filter(function(n) { return !n.paired })
  readonly property bool lookingForPair: pairUntil > now
  readonly property bool pairing: pairable.some(function(p) { return p.pairing }) || inPairingMode.length > 0

  // ---- Public API (bar widgets, panel, IPC) -------------------------------------

  function send(obj) {
    if (!daemon.running) return
    daemon.write(JSON.stringify(obj) + "\n")
  }

  function setMode(address, mode) { send({ cmd: "mode", address: address, mode: mode }) }
  function connectDevice(address) { send({ cmd: "connect", address: address }) }
  function disconnectDevice(address) { send({ cmd: "disconnect", address: address }) }
  function pairDevice(address) { send({ cmd: "pair", address: address }) }
  function forgetDevice(address) { send({ cmd: "forget", address: address }) }
  function watch(on) {
    panelOpen = !!on
    send({ cmd: "watch", on: !!on })
  }
  function lookForPair(seconds) { send({ cmd: "pairwindow", seconds: seconds || 60 }) }
  function clearError() { send({ cmd: "clearerror" }) }
  function routeAudio(address) { send({ cmd: "route", address: address }) }

  // The saved order, plus paired pairs it doesn't mention yet (at the end).
  function effectiveOrder() {
    var out = order.filter(function(a) { return devices.some(function(d) { return d.address === a }) })
    devices.forEach(function(d) { if (out.indexOf(d.address) < 0) out.push(d.address) })
    return out
  }

  function moveDevice(address, delta) {
    var o = effectiveOrder(), i = o.indexOf(address), j = i + delta
    if (i < 0 || j < 0 || j >= o.length) return
    o.splice(i, 1)
    o.splice(j, 0, address)
    order = o
    savePrefs()
    sendSettings()
  }

  function setDeviceAuto(address, on) {
    var m = manualOnly.filter(function(a) { return a !== address })
    if (!on) m.push(address)
    manualOnly = m
    savePrefs()
    sendSettings()
  }

  function lastSeenText(address) {
    var t = Number(lastSeen[address] || 0)
    if (!t) return "never connected here"
    var mins = Math.round((Date.now() / 1000 - t) / 60)
    if (mins < 2) return "just now"
    if (mins < 60) return mins + " min ago"
    if (mins < 60 * 24) return Math.round(mins / 60) + " h ago"
    return Math.round(mins / 1440) + " days ago"
  }

  // How to wake / pair a given kind, in words.
  function wakeHint(kind) {
    if (kind === "max") return "take the Max out of its case"
    if (kind === "pro" || kind === "buds") return "open the case"
    return "open the case or take the Max out"
  }
  function pairHint(kind) {
    if (kind === "max") return "Hold the noise control button until the light flashes white"
    if (kind === "pro" || kind === "buds") return "Open the case and hold the button on the back until the light flashes white"
    return "Open the case and hold its button (AirPods Max: the noise control button) until the light flashes white"
  }
  // The kind all your AirPods share, or "" when you have different ones.
  readonly property string commonKind: {
    var kinds = {}
    devices.forEach(function(d) { kinds[d.kind] = true })
    nearby.forEach(function(n) { kinds[n.kind] = true })
    var k = Object.keys(kinds)
    return k.length === 1 ? k[0] : ""
  }
  function powerOn() { send({ cmd: "power", on: true }) }

  // Next mode in the device's own list, skipping "off" (as the stem/button does).
  function cycleMode(dev) {
    dev = dev || primary
    if (!dev || !dev.connected || !dev.modes || !dev.modes.length) return
    var order = dev.modes.filter(function(m) { return m !== "off" })
    if (!order.length) return
    var i = order.indexOf(dev.mode)
    setMode(dev.address, order[(i + 1) % order.length])
  }

  function toggleConnection(dev) {
    dev = dev || primary
    if (!dev) return
    if (dev.connected) disconnectDevice(dev.address)
    else connectDevice(dev.address)
  }

  function setPref(name, value) {
    root[name] = value
    savePrefs()
    sendSettings()
  }

  function modeLabel(mode) {
    return ({ anc: "Noise Cancellation", transparency: "Transparency", adaptive: "Adaptive", off: "Off" })[mode] || ""
  }

  function modeShort(mode) {
    return ({ anc: "ANC", transparency: "Transparency", adaptive: "Adaptive", off: "Off" })[mode] || ""
  }

  // Lowest battery among the parts in use (buds, or the single Max battery).
  function batteryLevel(dev) {
    if (!dev || !dev.battery) return -1
    var b = dev.battery
    var vals = ["single", "left", "right"].map(function(k) { return b[k] }).filter(function(v) { return v !== null && v !== undefined })
    return vals.length ? Math.min.apply(null, vals) : -1
  }

  function statusText() {
    var d = primary
    if (!d) return newNearby.length ? newNearby[0].model + " nearby" : "No AirPods"
    var parts = [d.name, d.connected ? "connected" : (d.nearby ? "nearby" : "not connected")]
    var lvl = batteryLevel(d)
    if (lvl >= 0) parts.push((d.batteryApprox ? "~" : "") + lvl + "%")
    if (d.connected && d.mode) parts.push(modeLabel(d.mode))
    return parts.join(" · ")
  }

  // ---- Internals ------------------------------------------------------------------

  function sendSettings() {
    send({ cmd: "settings", autoConnect: autoConnect, autoPair: autoPair, useOutput: useOutput, useMic: useMic,
           order: effectiveOrder(), manualOnly: manualOnly })
  }

  function savePrefs() {
    prefsFile.setText(JSON.stringify({
      autoConnect: autoConnect, autoPair: autoPair, notify: notify, useOutput: useOutput, useMic: useMic,
      order: order, manualOnly: manualOnly, lastSeen: lastSeen, soundReactive: soundReactive
    }, null, 2) + "\n")
  }

  function loadPrefs(text) {
    var p = {}
    try { p = JSON.parse(text) } catch (e) { p = {} }
    if (typeof p.autoConnect === "boolean") autoConnect = p.autoConnect
    if (typeof p.autoPair === "boolean") autoPair = p.autoPair
    if (typeof p.notify === "boolean") notify = p.notify
    if (typeof p.useOutput === "boolean") useOutput = p.useOutput
    if (typeof p.useMic === "boolean") useMic = p.useMic
    if (typeof p.soundReactive === "boolean") soundReactive = p.soundReactive
    if (Array.isArray(p.order)) order = p.order.filter(function(a) { return typeof a === "string" }).slice(0, 32)
    if (Array.isArray(p.manualOnly)) manualOnly = p.manualOnly.filter(function(a) { return typeof a === "string" }).slice(0, 32)
    if (p.lastSeen && typeof p.lastSeen === "object") lastSeen = p.lastSeen
    sendSettings()
  }

  function loadTheme(text) {
    var out = {}
    String(text).split("\n").forEach(function(line) {
      var m = line.match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
      if (m) out[m[1]] = m[2]
    })
    themeColors = out
  }

  property var lastConnected: ({})
  property var notifiedNearby: ({})

  function notifyUser(title, body) {
    if (!notify) return
    notifyProc.command = ["omarchy-notification-send", "-g", "󰋋", String(title).slice(0, 80), String(body).slice(0, 160)]
    notifyProc.running = true
  }

  function onState(s) {
    var before = lastConnected
    devices = Array.isArray(s.devices) ? s.devices : []
    pairable = Array.isArray(s.pairable) ? s.pairable : []
    nearby = Array.isArray(s.nearby) ? s.nearby : []
    adapter = s.adapter || adapter
    pairUntil = Number(s.pairUntil) || 0
    inPairingMode = Array.isArray(s.inPairingMode) ? s.inPairingMode : []
    error = String(s.error || "")

    var nowConnected = {}
    devices.forEach(function(d) {
      if (!d.connected) return
      nowConnected[d.address] = true
      if (!before[d.address]) {
        var seen = {}
        for (var k in lastSeen) seen[k] = lastSeen[k]
        seen[d.address] = Math.round(Date.now() / 1000)
        lastSeen = seen
        savePrefs()
        var lvl = batteryLevel(d)
        notifyUser(d.name, "Connected" + (lvl >= 0 ? " · " + lvl + "%" : ""))
      }
    })
    lastConnected = nowConnected

    // A pair you don't have here yet: say how to pair it, once per 10 minutes.
    var t = Date.now() / 1000
    newNearby.forEach(function(n) {
      if (t - (notifiedNearby[n.modelId] || 0) < 600) return
      notifiedNearby[n.modelId] = t
      notifyUser(n.model + " nearby",
        autoPair ? (n.kind === "max" ? "Hold the noise control button to pair them here"
                                     : "Hold the button on the case to pair them here")
                 : "Open Podbay to pair them")
    })
  }

  function onEvent(e) {
    if (e.event === "paired") notifyUser(String(e.title || "AirPods"), "Paired")
  }

  Process {
    id: daemon
    command: ["python3", root.binDir + "/podbay-daemon"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.type === "state") root.onState(msg)
        else if (msg.type === "event") root.onEvent(msg)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        if (line.indexOf("bluez unavailable") >= 0) root.daemonError = "Bluetooth service not running"
        console.log("[jvdp.podbay]", line)
      }
    }
    onRunningChanged: {
      root.daemonUp = running
      if (running) {
        root.daemonError = ""
        Qt.callLater(root.sendSettings)
      } else {
        restartTimer.start()
      }
    }
  }

  // The daemon exits when BlueZ restarts or the adapter vanishes: retry.
  Timer {
    id: restartTimer
    interval: 5000
    onTriggered: daemon.running = true
  }

  Timer {
    interval: 1000
    running: root.lookingForPair
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }
  onPairUntilChanged: now = Date.now() / 1000

  FileView {
    id: prefsFile
    path: root.prefsPath
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadPrefs(text())
  }

  FileView {
    id: themeFile
    path: root.themePath
    printErrors: false
    watchChanges: true
    onLoaded: root.loadTheme(text())
    onFileChanged: reload()
  }

  Process { id: notifyProc }

  // Sound levels, only while someone can see them.
  Process {
    id: levelsProc
    command: ["python3", root.binDir + "/podbay-levels"]
    running: root.soundReactive && root.panelOpen && root.connected.length > 0
    stdout: SplitParser {
      onRead: function(line) {
        var v = line.trim().split(" ").map(Number)
        if (v.length === 8 && v.every(function(x) { return x >= 0 && x <= 1 })) root.levels = v
      }
    }
    onRunningChanged: if (!running) root.levels = []
  }

  Component.onCompleted: {
    if (root.home === "") return
    prefsFile.reload()
    themeFile.reload()
  }

  // omarchy-shell jvdp.podbay <method> [args]
  IpcHandler {
    target: "jvdp.podbay"

    function status(): string {
      return JSON.stringify({ text: root.statusText(), devices: root.devices, nearby: root.nearby })
    }
    function mode(m: string): void { if (root.primary) root.setMode(root.primary.address, m) }
    function cycle(): void { root.cycleMode() }
    function toggle(): void { root.toggleConnection() }
    function pair(): void { root.lookForPair(90) }
  }
}
