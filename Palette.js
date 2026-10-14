.pragma library

// Maps the sprite palette roles (see tools/sprites.py) onto theme colours.
// AirPods are "white" in a dark theme and "ink" in a light one: the body is
// always the theme foreground, shading steps towards the background.

function parse(c) {
  // Accepts a QML color or "#rrggbb".
  if (c && c.r !== undefined) return { r: c.r, g: c.g, b: c.b }
  var s = String(c || "#ffffff").replace("#", "")
  if (s.length === 8) s = s.slice(2)
  return { r: parseInt(s.slice(0, 2), 16) / 255, g: parseInt(s.slice(2, 4), 16) / 255, b: parseInt(s.slice(4, 6), 16) / 255 }
}

function mix(a, b, t) {
  return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t }
}

function css(c, alpha) {
  return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (alpha === undefined ? 1 : alpha) + ")"
}

function luminance(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

// fg, bg, accent: theme colours; extra: colors.toml map (for cyan/blue).
function make(fg, bg, accent, extra) {
  var F = parse(fg), B = parse(bg), A = parse(accent)
  var dark = luminance(F) > luminance(B)
  var white = { r: 1, g: 1, b: 1 }
  var cool = parse((extra && (extra.cyan || extra.blue)) || accent)
  return {
    o: css(mix(F, B, 0.62)),
    w: css(F),
    h: css(dark ? mix(F, white, 0.6) : mix(F, B, 0.18)),
    s: css(mix(F, B, 0.25)),
    m: css(mix(F, B, 0.5)),
    k: css(mix(F, B, 0.8)),
    a: css(A),
    // Effect colours.
    accent: A, cool: cool, fg: F, bg: B,
  }
}
