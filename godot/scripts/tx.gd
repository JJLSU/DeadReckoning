class_name Tx
## Shared procedural textures (puffs, glows, trees, plane sprites, grain).

static var PUFF: Texture2D
static var YPUFF: Texture2D
static var GPUFF: Texture2D
static var DPUFF: Texture2D
static var SPUFF: Texture2D
static var LPUFF: Texture2D
static var GRAIN: Texture2D
static var glows := {}
static var TREES: Array = []
static var PSPR := {}   # "Kestrel" / "Kestrel_s" -> texture

static func _grad_tex(stops: Array, size: int = 128) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

static func make_puff(r: int, g: int, b: int) -> Texture2D:
	return _grad_tex([[0.0, U.rgb(r, g, b, 1)], [0.55, U.rgb(r, g, b, 0.55)], [1.0, U.rgb(r, g, b, 0)]])

static func init_basic() -> void:
	YPUFF = make_puff(150, 140, 70)
	GPUFF = make_puff(130, 160, 70)
	PUFF = make_puff(242, 240, 234)
	DPUFF = make_puff(36, 40, 52)
	SPUFF = make_puff(0, 0, 0)
	LPUFF = make_puff(190, 205, 255)
	var im := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	for y in 160:
		for x in 160:
			var v := randf()
			im.set_pixel(x, y, Color(v, v, v, 60.0 / 255.0 if randf() < 0.5 else 0.0))
	GRAIN = ImageTexture.create_from_image(im)

## Glow sprite: radial rgba(k,1) -> rgba(k,0). key like "255,60,30".
static func glow(key: String) -> Texture2D:
	if glows.has(key): return glows[key]
	var p := key.split(",")
	var c := U.rgb(float(p[0]), float(p[1]), float(p[2]))
	var t := _grad_tex([[0.0, c], [1.0, Color(c.r, c.g, c.b, 0)]], 64)
	glows[key] = t
	return t

static func bake_all(baker: Baker) -> void:
	for v in 3:
		TREES.append(await baker.bake(Vector2i(128, 128), func(p: Pen): _draw_tree(p, v)))
	for P in D.PLANES:
		PSPR[P.name] = await baker.bake(Vector2i(512, 512), func(p: Pen): _draw_plane_sprite(p, P, false))
		PSPR[P.name + "_s"] = await baker.bake(Vector2i(512, 512), func(p: Pen): _draw_plane_sprite(p, P, true))

static func _draw_tree(g: Pen, v: int) -> void:
	var Rn := U.Mulberry.new(v * 99 + 5)
	var b: Array = [[46, 70, 34], [56, 80, 38], [40, 60, 32]][v]
	for k in 9:
		var a := Rn.next() * TAU
		var dd := Rn.next() * 24
		var x := 64 + cos(a) * dd
		var y := 64 + sin(a) * dd
		var r := 22 + Rn.next() * 16
		g.radial(x, y, [[2.0, U.rgb(b[0] + 40, b[1] + 46, b[2] + 20)], [r * 0.72, U.rgb(b[0], b[1], b[2])], [r, U.rgb(b[0] - 15, b[1] - 20, b[2] - 12, 0)]], 28, Vector2(-r * 0.35, -r * 0.35))

## Linear gradient colour lookup: stops [[t, Color]].
static func lg(stops: Array, t: float) -> Color:
	if t <= stops[0][0]: return stops[0][1]
	for i in range(1, stops.size()):
		if t <= stops[i][0]:
			var k: float = (t - stops[i - 1][0]) / maxf(0.0001, stops[i][0] - stops[i - 1][0])
			return (stops[i - 1][1] as Color).lerp(stops[i][1], k)
	return stops[stops.size() - 1][1]

static func _grad_poly(g: Pen, pts: PackedVector2Array, stops: Array, axis: Vector2, a0: float, a1: float) -> void:
	var cols := PackedColorArray()
	for p in pts:
		var t := (p.dot(axis) - a0) / (a1 - a0)
		cols.append(lg(stops, t))
	g.poly_grad(pts, cols)

static func _quad_path(p0: Vector2, cp: Vector2, p1: Vector2, n: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, n + 1):
		var t := float(i) / n
		out.append(p0 * (1 - t) * (1 - t) + cp * 2 * (1 - t) * t + p1 * t * t)
	return out

static func _draw_plane_sprite(g: Pen, P: Dictionary, sh: bool) -> void:
	g.translate(256, 256)
	g.scale(400, 400)
	var col := U.hx(P.col)
	var acc := U.hx(P.acc)
	var blk := Color.BLACK
	# wing
	var wing := g.rr_pts(0.08, -0.6, 0.19, 1.2, 0.05)
	if sh: g.poly(wing, blk)
	else: _grad_poly(g, wing, [[0.0, U.shade(col, .82)], [0.5, U.shade(col, 1.1)], [1.0, U.shade(col, .78)]], Vector2(0, 1), -0.6, 0.6)
	if not sh:
		var ln := PackedVector2Array()
		for y in [-0.42, -0.24, 0.24, 0.42]:
			ln.append(Vector2(0.08, y)); ln.append(Vector2(0.27, y))
		ln.append(Vector2(0.115, -0.58)); ln.append(Vector2(0.115, -0.3)); ln.append(Vector2(0.115, 0.3)); ln.append(Vector2(0.115, 0.58))
		g.lines(ln, Color(0, 0, 0, 0.2), 0.005)
		g.rect(0.08, -0.6, 0.19, 0.07, acc)
		g.rect(0.08, 0.53, 0.19, 0.07, acc)
		g.rect(0.25, -0.58, 0.018, 1.16, Color(1, 1, 1, 0.28))
	if P.twin:
		var cc := blk if sh else U.shade(col, .92)
		g.rr(0.12, -0.3, 0.32, 0.09, 0.04, cc)
		g.rr(0.12, 0.21, 0.32, 0.09, 0.04, cc)
		if not sh:
			g.rect(0.36, -0.3, 0.08, 0.09, acc); g.rect(0.36, 0.21, 0.08, 0.09, acc)
			g.rect(0.12, -0.29, 0.06, 0.07, Color(20 / 255.0, 20 / 255.0, 20 / 255.0, 0.35)); g.rect(0.12, 0.22, 0.06, 0.07, Color(20 / 255.0, 20 / 255.0, 20 / 255.0, 0.35))
	# tailplane
	var tp := PackedVector2Array([Vector2(-.36, -.03), Vector2(-.44, -.21), Vector2(-.49, -.21), Vector2(-.47, -.03), Vector2(-.47, .03), Vector2(-.49, .21), Vector2(-.44, .21), Vector2(-.36, .03)])
	g.poly(tp, blk if sh else U.shade(col, .96))
	# fuselage
	var fu := PackedVector2Array([Vector2(.5, 0)])
	fu.append_array(_quad_path(Vector2(.5, 0), Vector2(.47, -.09), Vector2(.32, -.09)))
	fu.append(Vector2(-.42, -.035)); fu.append(Vector2(-.49, 0)); fu.append(Vector2(-.42, .035)); fu.append(Vector2(.32, .09))
	var tail := _quad_path(Vector2(.32, .09), Vector2(.47, .09), Vector2(.5, 0))
	tail.remove_at(tail.size() - 1)
	fu.append_array(tail)
	if sh: g.poly(fu, blk)
	else: _grad_poly(g, fu, [[0.0, U.shade(col, .72)], [0.35, U.shade(col, 1.2)], [1.0, U.shade(col, .68)]], Vector2(0, 1), -0.09, 0.09)
	if not sh:
		var nose := PackedVector2Array([Vector2(.5, 0)])
		nose.append_array(_quad_path(Vector2(.5, 0), Vector2(.47, -.085), Vector2(.41, -.085)))
		nose.append(Vector2(.41, .085))
		var n2 := _quad_path(Vector2(.41, .085), Vector2(.47, .085), Vector2(.5, 0))
		n2.remove_at(n2.size() - 1)
		nose.append_array(n2)
		g.poly(nose, acc)
		g.rect(-0.42, -0.05, 0.8, 0.012, acc)
		g.rect(-0.42, 0.038, 0.8, 0.012, acc)
		var can := g.ellipse_pts(0.27, 0, 0.075, 0.055, 0, 24)
		var axis := Vector2(0.14, 0.1).normalized()
		_grad_poly(g, can, [[0.0, U.hx("#26343c")], [0.5, U.hx("#7597a8")], [1.0, U.hx("#172026")]], axis, Vector2(0.2, -0.05).dot(axis), Vector2(0.34, 0.05).dot(axis))
		g.ellipse(0.29, -0.022, 0.026, 0.011, -0.3, Color(1, 1, 1, 0.5))
		g.rect(-0.49, -0.013, 0.15, 0.026, U.shade(acc, .9))
		g.ellipse(0.3, 0.07, 0.08, 0.012, 0, Color(30 / 255.0, 25 / 255.0, 20 / 255.0, 0.28))
		g.lines(PackedVector2Array([Vector2(-.1, -.07), Vector2(-.1, .07), Vector2(.1, -.08), Vector2(.1, .08)]), Color(0, 0, 0, 0.18), 0.005)
