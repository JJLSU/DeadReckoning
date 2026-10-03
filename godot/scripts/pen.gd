class_name Pen
extends RefCounted
## A small canvas-2D style wrapper over CanvasItem drawing, so the port can follow the
## original HTML canvas code closely (save/restore, translate/rotate/scale, globalAlpha).

static var fonts := {}  # key "600" / "700" / "900d" -> Font

var ci: CanvasItem
var xf := Transform2D.IDENTITY
var stack: Array = []
var ga := 1.0

func _init(c: CanvasItem) -> void:
	ci = c
	ci.draw_set_transform_matrix(xf)

static func font(w: String) -> Font:
	if fonts.has(w): return fonts[w]
	var f := SystemFont.new()
	if w.ends_with("d"):
		f.font_names = PackedStringArray(["Big Shoulders Stencil Display", "Impact", "Arial Narrow", "Arial Black"])
		f.font_weight = int(w.trim_suffix("d"))
	elif w == "impact":
		f.font_names = PackedStringArray(["Impact", "Arial Black"])
		f.font_weight = 900
	else:
		f.font_names = PackedStringArray(["IBM Plex Sans Condensed", "Roboto Condensed", "Arial Narrow", "Segoe UI", "Arial"])
		f.font_weight = int(w)
	f.font_stretch = 100
	f.fallbacks = [_emoji_font()]
	fonts[w] = f
	return f

static func _emoji_font() -> Font:
	if fonts.has("emoji"): return fonts["emoji"]
	var e := SystemFont.new()
	e.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Segoe UI Symbol"])
	fonts["emoji"] = e
	return e

# ---------- transform stack ----------
func reset(t: Transform2D = Transform2D.IDENTITY) -> void:
	xf = t
	stack.clear()
	ci.draw_set_transform_matrix(xf)

func set_xf(t: Transform2D) -> void:
	xf = t
	ci.draw_set_transform_matrix(xf)

func save() -> void:
	stack.push_back([xf, ga])

func restore() -> void:
	var s = stack.pop_back()
	xf = s[0]
	ga = s[1]
	ci.draw_set_transform_matrix(xf)

func translate(x: float, y: float) -> void:
	xf = xf * Transform2D(0.0, Vector2(x, y))
	ci.draw_set_transform_matrix(xf)

func rotate(a: float) -> void:
	xf = xf * Transform2D(a, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)

func scale(sx: float, sy: float) -> void:
	xf = xf * Transform2D(0.0, Vector2(sx, sy), 0.0, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)

## Equivalent of ctx.setTransform(s,0,0,s,ox,oy) (without DPR).
func set_view(s: float, ox: float, oy: float) -> void:
	set_xf(Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(ox, oy)))

func c(col: Color) -> Color:
	if ga >= 0.999: return col
	return Color(col.r, col.g, col.b, col.a * ga)

# ---------- primitives ----------
func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	if w < 0: x += w; w = -w
	if h < 0: y += h; h = -h
	ci.draw_rect(Rect2(x, y, w, h), c(col))

func stroke_rect(x: float, y: float, w: float, h: float, col: Color, lw: float) -> void:
	ci.draw_rect(Rect2(x, y, w, h), c(col), false, lw)

func circle(x: float, y: float, r: float, col: Color) -> void:
	if r <= 0: return
	ci.draw_circle(Vector2(x, y), r, c(col), true, -1.0, true)

func ring(x: float, y: float, r: float, col: Color, lw: float) -> void:
	if r <= 0: return
	ci.draw_arc(Vector2(x, y), r, 0, TAU, maxi(12, int(r * 0.6)) if r < 200 else 96, c(col), lw, true)

func arc(x: float, y: float, r: float, a0: float, a1: float, col: Color, lw: float) -> void:
	if r <= 0: return
	var seg := maxi(6, int(absf(a1 - a0) * maxf(6.0, r * 0.15)))
	ci.draw_arc(Vector2(x, y), r, a0, a1, mini(seg, 128), c(col), lw, true)

## Filled pie slice (moveTo center, arc, close).
func pie(x: float, y: float, r: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(x, y)])
	var n := 16
	for i in n + 1:
		var a := a0 + (a1 - a0) * i / n
		pts.append(Vector2(x + cos(a) * r, y + sin(a) * r))
	ci.draw_colored_polygon(pts, c(col))

static var UNIT := {}
static func unit_circle(n: int) -> PackedVector2Array:
	if UNIT.has(n): return UNIT[n]
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a), sin(a)))
	UNIT[n] = pts
	return pts

func ellipse_pts(x: float, y: float, rx: float, ry: float, rot: float, n: int = 18) -> PackedVector2Array:
	return Transform2D(rot, Vector2(rx, ry), 0.0, Vector2(x, y)) * unit_circle(n)

func ellipse(x: float, y: float, rx: float, ry: float, rot: float, col: Color) -> void:
	if rx <= 0 or ry <= 0: return
	# draw a unit circle under a local transform: robust triangulation and no per-point script work
	ci.draw_set_transform_matrix(xf * Transform2D(rot, Vector2(rx, ry), 0.0, Vector2(x, y)))
	ci.draw_colored_polygon(unit_circle(18 if maxf(rx, ry) < 40 else 32), c(col))
	ci.draw_set_transform_matrix(xf)

func stroke_ellipse(x: float, y: float, rx: float, ry: float, rot: float, col: Color, lw: float) -> void:
	var p := ellipse_pts(x, y, rx, ry, rot, 24)
	p.append(p[0])
	ci.draw_polyline(p, c(col), lw, true)

func line(x0: float, y0: float, x1: float, y1: float, col: Color, lw: float) -> void:
	ci.draw_line(Vector2(x0, y0), Vector2(x1, y1), c(col), lw, true)

func lines(pts: PackedVector2Array, col: Color, lw: float) -> void:
	if pts.size() >= 2: ci.draw_multiline(pts, c(col), lw)

func polyline(pts: PackedVector2Array, col: Color, lw: float) -> void:
	if pts.size() >= 2: ci.draw_polyline(pts, c(col), lw, true)

func poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3: ci.draw_colored_polygon(pts, c(col))

func poly_grad(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if ga < 0.999:
		for i in cols.size(): cols[i].a *= ga
	ci.draw_polygon(pts, cols)

func dashed(x0: float, y0: float, x1: float, y1: float, col: Color, lw: float, dash: float, gap: float) -> void:
	var d := Vector2(x1 - x0, y1 - y0)
	var L := d.length()
	if L <= 0: return
	var u := d / L
	var pts := PackedVector2Array()
	var t := 0.0
	while t < L:
		var e := minf(L, t + dash)
		pts.append(Vector2(x0, y0) + u * t)
		pts.append(Vector2(x0, y0) + u * e)
		t += dash + gap
	ci.draw_multiline(pts, c(col), lw)

func dashed_arc(x: float, y: float, r: float, a0: float, a1: float, col: Color, lw: float, dash: float, gap: float) -> void:
	if r <= 0: return
	var circ := r * absf(a1 - a0)
	var step := (dash + gap) / r
	var a := a0
	var cnt := 0
	while a < a1 and cnt < 400:
		var e := minf(a1, a + dash / r)
		var n := maxi(2, int((e - a) * r / 6.0) + 2)
		var pts := PackedVector2Array()
		for i in n:
			var q := a + (e - a) * i / (n - 1)
			pts.append(Vector2(x + cos(q) * r, y + sin(q) * r))
		ci.draw_polyline(pts, c(col), lw, true)
		a += step
		cnt += 1
	if circ < 0: pass

func rr_pts(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	r = minf(r, minf(w, h) / 2.0)
	var pts := PackedVector2Array()
	var corners := [[x + w - r, y + r, -PI / 2], [x + w - r, y + h - r, 0.0], [x + r, y + h - r, PI / 2], [x + r, y + r, PI]]
	for cc in corners:
		for i in 5:
			var a: float = cc[2] + PI / 2 * i / 4.0
			pts.append(Vector2(cc[0] + cos(a) * r, cc[1] + sin(a) * r))
	return pts

func rr(x: float, y: float, w: float, h: float, r: float, col: Color) -> void:
	if w <= 0 or h <= 0: return
	ci.draw_colored_polygon(rr_pts(x, y, w, h, r), c(col))

func stroke_rr(x: float, y: float, w: float, h: float, r: float, col: Color, lw: float) -> void:
	var p := rr_pts(x, y, w, h, r)
	p.append(p[0])
	ci.draw_polyline(p, c(col), lw, true)

func tex(t: Texture2D, x: float, y: float, w: float, h: float, mod: Color = Color.WHITE) -> void:
	if t == null: return
	ci.draw_texture_rect(t, Rect2(x, y, w, h), false, c(mod))

func tex_region(t: Texture2D, dst: Rect2, src: Rect2, mod: Color = Color.WHITE) -> void:
	if t == null: return
	ci.draw_texture_rect_region(t, dst, src, c(mod))

# ---------- text ----------
## align: -1 left, 0 center, 1 right. Vertical: y is the middle of the text (textBaseline=middle).
func text(s: String, x: float, y: float, size: int, col: Color, align: int = -1, weight: String = "600", outline_w: float = 0.0, outline_col: Color = Color(0, 0, 0, 0.65), max_w: float = -1.0) -> void:
	var f := font(weight)
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var sc := 1.0
	if max_w > 0 and tw > max_w:
		sc = max_w / tw
	var x0 := x
	if align == 0: x0 = x - tw * sc / 2.0
	elif align == 1: x0 = x - tw * sc
	var base := y + (f.get_ascent(size) - f.get_descent(size)) / 2.0
	if sc < 1.0:
		save()
		translate(x0, base)
		scale(sc, 1.0)
		if outline_w > 0: ci.draw_string_outline(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline_w), c(outline_col))
		ci.draw_string(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c(col))
		restore()
		return
	if outline_w > 0:
		ci.draw_string_outline(f, Vector2(x0, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline_w), c(outline_col))
	ci.draw_string(f, Vector2(x0, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c(col))

## Alphabetic-baseline text (canvas default textBaseline), used where the original did not set middle.
func text_base(s: String, x: float, y: float, size: int, col: Color, align: int = -1, weight: String = "600") -> void:
	var f := font(weight)
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x0 := x
	if align == 0: x0 = x - tw / 2.0
	elif align == 1: x0 = x - tw
	ci.draw_string(f, Vector2(x0, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c(col))

static func measure(s: String, size: int, weight: String = "600") -> float:
	return font(weight).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func tri(a: Vector2, b: Vector2, cc: Vector2, ca: Color, cb: Color, ccol: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, cc]), PackedColorArray([c(ca), c(cb), c(ccol)]), PackedVector2Array())

## Radial gradient as concentric rings. stops: [[radius, Color], ...] ascending radius.
## center_off: offset of the inner focus (like a two-point canvas gradient).
func radial(x: float, y: float, stops: Array, seg: int = 32, center_off: Vector2 = Vector2.ZERO) -> void:
	var prev_pts: PackedVector2Array
	var prev_col: Color
	for si in stops.size():
		var r: float = stops[si][0]
		var col: Color = stops[si][1]
		var k := 1.0 - float(si) / maxf(1.0, stops.size() - 1)
		var cen := Vector2(x, y) + center_off * k
		var pts := PackedVector2Array()
		for i in seg:
			var a := TAU * i / seg
			pts.append(cen + Vector2(cos(a), sin(a)) * r)
		if si == 0:
			if r > 0.01 and col.a > 0.001:
				ci.draw_colored_polygon(pts, c(col))
		else:
			for i in seg:
				var j := (i + 1) % seg
				ci.draw_primitive(PackedVector2Array([prev_pts[i], prev_pts[j], pts[j], pts[i]]), PackedColorArray([c(prev_col), c(prev_col), c(col), c(col)]), PackedVector2Array())
		prev_pts = pts
		prev_col = col
