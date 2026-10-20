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
## On foot: the original three tree sprites (Greg, 2026-10-15: on-foot trees back as they were).
static var FOOT_TREES: Array = []
## Trees rendered from 3D models in Blender (Environments thread, 2026-10-18, a test for Greg):
## per tree [full, low, middle, top] sprites from res://sprites/trees3d/t<i>_<layer>.png. The full
## one is its shadow silhouette; the three height layers stack and lean in flight.
static var T3D: Array = []
const T3D_N := 9
const T3D_FALL := 6   # trees from this index on are fall colours
static var PSPR := {}   # "Kestrel" / "Kestrel_s" -> texture
## Pre-rendered frames from a 3D model, per plane name: res://sprites/planes/<name>/pR_bNN.png.
## R is the pitch row (0 = level, then nose up to PITCH_DEG), NN runs from full left bank (00)
## through level to full right bank. PBANK[name] = [row][bank] textures. Planes without them use PSPR.
static var PBANK := {}
const BANK_DEG := 40.0    # bank angle of the outermost frame, reached at full stick (F.bank = +-1)
const PITCH_DEG := 24.0   # nose-up angle of the last pitch row, reached at F.pitch = 1
## Where the prop hub, wingtip lights and tail light sit in each frame (sprite units, same order
## as the frames): points.json next to the frames, written by the render script. PPTS[name] = its data.
static var PPTS := {}

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

## A PNG as a texture: imported if Godot has imported it, else read straight from the file.
static func _png(path: String) -> Texture2D:
	if ResourceLoader.exists(path): return load(path)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img else null

## A 3D tree layer with its see-through edge pixels coloured like their neighbours and with
## mipmaps, so it shrinks smoothly from altitude instead of turning jagged (draw layer 0
## samples with mipmaps; Greg, 2026-10-18).
static func _smooth(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null: return t
	if img.is_compressed(): img.decompress()
	img.fix_alpha_edges()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func bake_all(baker: Baker) -> void:
	for v in TREE_GREEN + TREE_WIDE + TREE_FALL:
		TREES.append(await baker.bake(Vector2i(128, 128), func(p: Pen): _draw_tree(p, v)))
	for v in 3:
		FOOT_TREES.append(await baker.bake(Vector2i(128, 128), func(p: Pen): _draw_foot_tree(p, v)))
	for i in T3D_N:
		var t := []
		for n in ["full", "l0", "l1", "l2"]: t.append(_png("res://sprites/trees3d/t%d_%s.png" % [i, n]))
		if not t.has(null): T3D.append(t.map(_smooth))
	for P in D.PLANES:
		PSPR[P.name] = await baker.bake(Vector2i(512, 512), func(p: Pen): _draw_plane_sprite(p, P, false))
		PSPR[P.name + "_s"] = await baker.bake(Vector2i(512, 512), func(p: Pen): _draw_plane_sprite(p, P, true))
		var dir: String = "res://sprites/planes/%s/" % P.name.to_lower()
		var rows: Array = []
		while ResourceLoader.exists(dir + "p%d_b00.png" % rows.size()):
			var frames: Array = []
			while ResourceLoader.exists(dir + "p%d_b%02d.png" % [rows.size(), frames.size()]):
				frames.append(load(dir + "p%d_b%02d.png" % [rows.size(), frames.size()]))
			rows.append(frames)
		if rows.size() > 0 and rows[0].size() > 1: PBANK[P.name] = rows
		if ResourceLoader.exists(dir + "points.json"):
			var j = load(dir + "points.json")
			if j is JSON: PPTS[P.name] = j.data

static var TREE_SHADER: Shader
const TREE_GREEN := 10   # green tree sprites (TREES[0 .. 9])
const TREE_WIDE := 4     # then wide-canopy greens: smaller blobs spread farther out
const KEEP_WIDE := TREE_GREEN + TREE_WIDE - 1   # the wide canopy Greg liked: left as first drawn
const TREE_FALL := 18    # then fall colours (red, orange, amber, yellow, deep orange, brown), three shapes each
const FALL_HSV := [[0.01, 0.76, 0.6], [0.06, 0.66, 0.46], [0.1, 0.72, 0.62], [0.14, 0.7, 0.7], [0.075, 0.56, 0.42], [0.09, 0.42, 0.38]]
## Picks a tree sprite from a 0..1 hash: mostly greens, about one in six wide canopies and
## one in nine in fall colours.
static func tree_pick(h: float) -> int:
	var f := fmod(h * 7.13, 1.0)
	if f < 0.11: return TREE_GREEN + TREE_WIDE + int(h * 977) % TREE_FALL
	if f < 0.27: return TREE_GREEN + int(h * 613) % TREE_WIDE
	return int(h * 1531) % TREE_GREEN

## The base hue a tree sprite is drawn with (the first number _draw_tree takes from its seed).
static func tree_hue(v: int) -> float:
	if v >= TREE_GREEN + TREE_WIDE: return FALL_HSV[(v - TREE_GREEN - TREE_WIDE) % FALL_HSV.size()][0]
	return 0.2 + U.Mulberry.new(v * 131 + 17).next() * 0.13

## Tree sprites: like the original trees, overlapping soft blobs (radial gradients lit from
## the upper left), now with a random number of blobs, many seeds and colours, wide canopies,
## fall trees, and fine leaf grain. Each blob is painted per pixel by shaders/tree_sprite.gdshader.
static func _draw_tree(g: Pen, v: int, shade: float = -1.0) -> void:
	if TREE_SHADER == null: TREE_SHADER = load("res://shaders/tree_sprite.gdshader")
	var Rn := U.Mulberry.new(v * 131 + 17)
	var wide := v >= TREE_GREEN and v < TREE_GREEN + TREE_WIDE
	var fall := v >= TREE_GREEN + TREE_WIDE
	if shade < 0.0: shade = 2.2 if fall else 1.0   # how far the blobs' shades spread (fall trees most)
	var hue := 0.2 + Rn.next() * 0.13
	var sat := 0.42 + Rn.next() * 0.22
	var val := 0.2 + Rn.next() * 0.12
	if fall:
		var fc: Array = FALL_HSV[(v - TREE_GREEN - TREE_WIDE) % FALL_HSV.size()]
		hue = fc[0]
		sat = fc[1] + (Rn.next() - 0.5) * 0.08
		val = fc[2] + (Rn.next() - 0.5) * 0.06
	var n := 10 + int(Rn.next() * 15)   # 10 to 24 blobs
	var spread := 18.0 + Rn.next() * 12.0
	var r0 := 15.0
	var r1 := 17.0
	if wide:   # many small blobs reaching out to the edge
		n = 22 + int(Rn.next() * 7)   # 22 to 28
		spread = 44.0 + Rn.next() * 6.0
		if v != KEEP_WIDE: spread -= 7.0   # keep the outer blobs touching the bigger middle
		r0 = 9.0
		r1 = 9.0
	var bl := PackedVector4Array()
	var cl := PackedVector4Array()
	for k in n:
		var a := Rn.next() * TAU
		var dd := sqrt(Rn.next()) * spread
		var r := r0 + Rn.next() * r1
		# two big middle blobs tie the canopy together: halfway up the stack on the first wide
		# tree (Greg liked it as it is), higher up and bigger on the others
		var mid := n / 2 if v == KEEP_WIDE else (n * 3) / 4
		if wide and (k == mid or k == mid + 1):
			r = (26.0 if v == KEEP_WIDE else 31.0) + Rn.next() * 6.0
			dd = Rn.next() * 10.0
		dd = minf(dd, 62.0 - r)
		bl.append(Vector4(64 + cos(a) * dd, 64 + sin(a) * dd, r, 0))
		# shade spreads the blobs' shades around the tree's colour
		var hk := hue + (Rn.next() - 0.5) * 0.03 * (1.0 + shade * (1.4 if fall else 0.3))   # fall trees mix neighbouring colours
		if fall: hk = clampf(hk, maxf(hue - 0.05, -0.02), minf(hue + 0.05, 0.15))   # but never into green or pink
		var c := Color.from_hsv(fposmod(hk, 1.0), clampf(sat + (Rn.next() - 0.5) * 0.12 * (1.0 + shade * 0.6), 0, 1), clampf(val + (Rn.next() - 0.5) * 0.06 * (1.0 + shade * 1.8), 0, 1))
		cl.append(Vector4(c.r, c.g, c.b, 1))
	var m := ShaderMaterial.new()
	m.shader = TREE_SHADER
	m.set_shader_parameter("blobs", bl)
	m.set_shader_parameter("cols", cl)
	m.set_shader_parameter("count", n)
	m.set_shader_parameter("seed", v * 7 + 1)
	g.ci.material = m
	g.ci.draw_rect(Rect2(0, 0, 128, 128), Color.WHITE)

## The original on-foot tree: nine soft green blobs.
static func _draw_foot_tree(g: Pen, v: int) -> void:
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

## Plane sprites, top-down with the nose along +x, drawn in a box of about +-0.6.
## Each airframe is modelled on a real aircraft (D.PLANES "airframe"); sh draws the black shadow silhouette.
static func _draw_plane_sprite(g: Pen, P: Dictionary, sh: bool) -> void:
	g.translate(256, 256)
	g.scale(400, 400)
	match P.airframe:
		"super_cub": _draw_super_cub(g, P, sh)
		"skymaster": _draw_skymaster(g, P, sh)
		"twin_otter": _draw_twin_otter(g, P, sh)

## Mirror a half outline (the -y side, running from one point on the centreline to another) into a full polygon.
static func _mirror(half: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in half: out.append(p)
	for i in range(half.size() - 1, -1, -1):
		var p: Vector2 = half[i]
		if absf(p.y) > 0.0001: out.append(Vector2(p.x, -p.y))
	return out

## Rounded corner from a to b, bulging towards the corner point c.
static func _corner(a: Vector2, c: Vector2, b: Vector2) -> Array:
	var out: Array = [a]
	out.append_array(_quad_path(a, c, b, 5))
	return out

## Tube-shaded body (fuselage, boom, nacelle) centred on y = cy. st: [[x, half_width], ...] nose to tail.
## Shaded across its width like a cylinder lit from the -y side.
static func _body(g: Pen, st: Array, cy: float, col: Color, sh: bool) -> void:
	var fs := [-1.0, -0.7, -0.35, 0.0, 0.35, 0.7, 1.0]
	var stops := [[0.0, U.shade(col, .68)], [0.28, U.shade(col, 1.16)], [0.5, U.shade(col, 1.04)], [1.0, U.shade(col, .62)]]
	for i in st.size() - 1:
		var x0: float = st[i][0]
		var x1: float = st[i + 1][0]
		var w0: float = maxf(0.002, st[i][1])
		var w1: float = maxf(0.002, st[i + 1][1])
		if sh:
			g.poly(PackedVector2Array([Vector2(x0, cy - w0), Vector2(x1, cy - w1), Vector2(x1, cy + w1), Vector2(x0, cy + w0)]), Color.BLACK)
			continue
		for j in fs.size() - 1:
			var fa: float = fs[j]
			var fb: float = fs[j + 1]
			var ca := lg(stops, (fa + 1) / 2)
			var cb := lg(stops, (fb + 1) / 2)
			g.poly_grad(PackedVector2Array([Vector2(x0, cy + fa * w0), Vector2(x1, cy + fa * w1), Vector2(x1, cy + fb * w1), Vector2(x0, cy + fb * w0)]), PackedColorArray([ca, ca, cb, cb]))

## Elliptical nose or tail cap for _body: stations from the tip (x_tip) to full width w at x_full.
static func _cap(x_tip: float, x_full: float, w: float, n: int = 6) -> Array:
	var out: Array = []
	for i in n + 1:
		var a := PI / 2 * (1.0 - float(i) / n)
		out.append([x_full + (x_tip - x_full) * sin(a), w * cos(a)])
	return out

## Flying surface (wing or tailplane) shaded chordwise, lighter at the leading edge.
static func _surface(g: Pen, pts: PackedVector2Array, col: Color, sh: bool, le: float, te: float, k: float = 1.0) -> void:
	if sh: g.poly(pts, Color.BLACK)
	else: _grad_poly(g, pts, [[0.0, U.shade(col, .8 * k)], [1.0, U.shade(col, 1.14 * k)]], Vector2(1, 0), te, le)

## Windscreen / skylight glass.
static func _glass(g: Pen, pts: PackedVector2Array) -> void:
	var axis := Vector2(0.4, 1).normalized()
	var a0 := INF
	var a1 := -INF
	for p in pts:
		a0 = minf(a0, p.dot(axis)); a1 = maxf(a1, p.dot(axis))
	_grad_poly(g, pts, [[0.0, U.hx("#7597a8")], [0.45, U.hx("#3a4e58")], [1.0, U.hx("#172026")]], axis, a0, a1)

## Port (red, -y) and starboard (green) wingtip lights.
static func _nav_lights(g: Pen, x: float, y: float) -> void:
	g.circle(x, -y, 0.009, U.hx("#e04030"))
	g.circle(x, y, 0.009, U.hx("#40d070"))

static func _draw_super_cub(g: Pen, P: Dictionary, sh: bool) -> void:
	var col := U.hx(P.col)
	var acc := U.hx(P.acc)
	var dark := Color(0, 0, 0, 0.22)
	# tailplane: rounded tips, elevators
	var tp := _mirror([Vector2(-.31, 0), Vector2(-.315, -.12)] + _corner(Vector2(-.33, -.17), Vector2(-.35, -.19), Vector2(-.385, -.185)) + [Vector2(-.41, -.12), Vector2(-.41, 0)])
	_surface(g, tp, col, sh, -.31, -.41, .96)
	if not sh: g.lines(PackedVector2Array([Vector2(-.37, -.175), Vector2(-.37, .175)]), dark, 0.005)
	# big tundra tyres poking out ahead of the wing, on the gear legs
	if not sh:
		for s in [-1, 1]:
			g.line(.25, s * .035, .225, s * .085, U.shade(acc, .7), 0.012)
	for s in [-1, 1]:
		g.ellipse(.225, s * .1, .05, .03, 0, Color.BLACK if sh else U.hx("#1e1c1a"))
		if not sh: g.ellipse(.232, s * .094, .03, .012, 0, Color(1, 1, 1, 0.12))
	# fuselage, then the cowling in the trim colour
	var fu: Array = _cap(.37, .345, .05, 4)
	fu.append_array([[.3, .056], [.2, .057], [.1, .056], [0, .054], [-.1, .046], [-.2, .037], [-.3, .026], [-.38, .015], [-.41, .008]])
	_body(g, fu, 0, col, sh)
	if not sh:
		var cowl: Array = _cap(.37, .345, .05, 4)
		cowl.append_array([[.3, .056], [.27, .056]])
		_body(g, cowl, 0, acc, false)
		g.ellipse(.358, -.026, .008, .01, 0, Color(0, 0, 0, 0.55)); g.ellipse(.358, .026, .008, .01, 0, Color(0, 0, 0, 0.55))
		g.rect(.29, .05, .035, .012, U.hx("#2a2624"))   # exhaust stack
		# cheat line down each side, lightning-bolt style
		for s in [-1, 1]:
			g.polyline(PackedVector2Array([Vector2(.01, s * .045), Vector2(-.38, s * .01)]), acc, 0.01)
		# windscreen between the cowl and the wing
		_glass(g, PackedVector2Array([Vector2(.265, -.04), Vector2(.265, .04), Vector2(.18, .05), Vector2(.18, -.05)]))
		# fin and rudder seen edge-on
		g.rr(-.42, -.007, .14, .014, .006, U.shade(col, .78))
		g.rect(-.42, -.007, .04, .014, U.shade(acc, .9))
	# high wing over the cabin, constant chord, rounded tips
	var wing := _mirror([Vector2(.19, 0), Vector2(.19, -.56)] + _corner(Vector2(.19, -.575), Vector2(.19, -.6), Vector2(.16, -.6)) + _corner(Vector2(.04, -.6), Vector2(.01, -.6), Vector2(.01, -.575)) + [Vector2(.01, 0)])
	_surface(g, wing, col, sh, .19, .01)
	if sh: return
	# fabric ribs, aileron and flap hinges, clear skylight over the cockpit, tip trim
	var ribs := PackedVector2Array()
	var y := 0.07
	while y < 0.57:
		for s in [-1, 1]:
			ribs.append(Vector2(.185, s * y)); ribs.append(Vector2(.015, s * y))
		y += 0.046
	g.lines(ribs, Color(1, 1, 1, 0.06), 0.004)
	g.lines(PackedVector2Array([Vector2(.055, -.58), Vector2(.055, -.06), Vector2(.055, .06), Vector2(.055, .58), Vector2(.055, -.33), Vector2(.015, -.33), Vector2(.055, .33), Vector2(.015, .33)]), dark, 0.005)
	_glass(g, g.rr_pts(.07, -.04, .1, .08, .012))
	for s in [-1, 1]:
		g.circle(.13, s * .1, .008, U.shade(col, .6))   # fuel caps
		g.rect(.03, s * .6 - (.03 if s > 0 else 0), .13, .03, Color(acc, 0.85))
	_nav_lights(g, .1, .6)

static func _draw_skymaster(g: Pen, P: Dictionary, sh: bool) -> void:
	var col := U.hx(P.col)
	var acc := U.hx(P.acc)
	var dark := Color(0, 0, 0, 0.22)
	var by := 0.175   # boom offset
	# tailplane spanning the two booms
	var tp := _mirror([Vector2(-.375, 0), Vector2(-.375, -.195), Vector2(-.39, -.205), Vector2(-.455, -.205), Vector2(-.46, -.19), Vector2(-.46, 0)])
	_surface(g, tp, col, sh, -.375, -.46, .96)
	if not sh: g.lines(PackedVector2Array([Vector2(-.425, -.19), Vector2(-.425, .19)]), dark, 0.005)
	# twin booms running back from the wing to the fins
	var boom: Array = _cap(.24, .21, .024, 4)
	boom.append_array([[.1, .026], [0, .022], [-.2, .017], [-.4, .013], [-.47, .01]])
	for s in [-1, 1]:
		_body(g, boom, s * by, col, sh)
		if not sh:
			g.rr(-.475, s * by - .008, .15, .016, .007, U.shade(col, .76))
			g.rect(-.475, s * by - .008, .045, .016, U.shade(acc, .9))
	# pod: tractor engine in the nose, pusher engine behind the cabin
	var pod: Array = _cap(.475, .43, .056, 5)
	pod.append_array([[.38, .064], [.28, .068], [.15, .068], [.05, .064], [-.05, .054], [-.11, .042], [-.15, .03], [-.165, .016]])
	_body(g, pod, 0, col, sh)
	if not sh:
		var front: Array = _cap(.475, .43, .056, 5)
		front.append_array([[.4, .062], [.385, .063]])
		_body(g, front, 0, U.shade(col, .9), false)
		_body(g, [[-.06, .052], [-.11, .042], [-.15, .03], [-.165, .016]], 0, U.shade(col, .9), false)
		g.lines(PackedVector2Array([Vector2(.385, -.063), Vector2(.385, .063), Vector2(-.06, -.052), Vector2(-.06, .052)]), Color(0, 0, 0, 0.3), 0.005)
		g.ellipse(.462, -.025, .008, .012, 0, Color(0, 0, 0, 0.55)); g.ellipse(.462, .025, .008, .012, 0, Color(0, 0, 0, 0.55))
		g.lines(PackedVector2Array([Vector2(-.09, -.035), Vector2(-.09, .035)]), Color(0, 0, 0, 0.3), 0.005)   # rear air scoop
		_glass(g, PackedVector2Array([Vector2(.355, -.04), Vector2(.355, .04), Vector2(.28, .058), Vector2(.28, -.058)]))
		g.line(.28, 0, .355, 0, U.shade(col, .7), 0.006)   # windscreen centre post
		_glass(g, g.rr_pts(-.05, -.04, .05, .08, .015))   # rear cabin window behind the wing
	# high wing: constant chord between the booms, gently tapered outboard, small rounded tips
	var wing := _mirror([Vector2(.17, 0), Vector2(.17, -.2), Vector2(.15, -.585)] + _corner(Vector2(.15, -.585), Vector2(.148, -.6), Vector2(.13, -.6)) + [Vector2(.04, -.6), Vector2(.03, -.59), Vector2(.0, -.2), Vector2(.0, 0)])
	_surface(g, wing, col, sh, .17, .0)
	if sh: return
	g.lines(PackedVector2Array([
		Vector2(.045, -.585), Vector2(.03, -.37), Vector2(.045, .585), Vector2(.03, .37),   # aileron hinges
		Vector2(.03, -.37), Vector2(.0, -.37), Vector2(.03, .37), Vector2(.0, .37),
		Vector2(.04, -.37), Vector2(.04, -.06), Vector2(.04, .06), Vector2(.04, .37),   # flaps
		Vector2(.04, -.06), Vector2(.0, -.06), Vector2(.04, .06), Vector2(.0, .06)]), dark, 0.005)
	for s in [-1, 1]:
		g.circle(.11, s * .3, .008, U.shade(col, .6))
		g.poly(PackedVector2Array([Vector2(.148, s * .56), Vector2(.15, s * .585), Vector2(.13, s * .6), Vector2(.04, s * .6), Vector2(.032, s * .59), Vector2(.03, s * .56)]), Color(acc, 0.85))
	g.rect(.06, -.2, .1, .4, Color(1, 1, 1, 0.05))
	_nav_lights(g, .09, .6)

static func _draw_twin_otter(g: Pen, P: Dictionary, sh: bool) -> void:
	var col := U.hx(P.col)
	var acc := U.hx(P.acc)
	var dark := Color(0, 0, 0, 0.22)
	var ny := 0.185   # nacelle offset
	# tailplane, mounted part way up the fin
	var tp := _mirror([Vector2(-.375, 0), Vector2(-.39, -.19), Vector2(-.405, -.2), Vector2(-.45, -.2), Vector2(-.46, -.185), Vector2(-.46, 0)])
	_surface(g, tp, col, sh, -.375, -.46, .96)
	if not sh: g.lines(PackedVector2Array([Vector2(-.43, -.195), Vector2(-.43, .195)]), dark, 0.005)
	# engine nacelles: long PT6 cowlings well ahead of the wing
	var nac: Array = _cap(.345, .315, .03, 4)
	nac.append_array([[.25, .033], [.15, .032], [.06, .028], [-.02, .02], [-.06, .008]])
	for s in [-1, 1]:
		_body(g, nac, s * ny, col, sh)
		if not sh:
			_body(g, [[.345, .006], [.34, .02], [.33, .028], [.3, .031]], s * ny, acc, false)
			g.ellipse(.33, s * ny, .006, .016, 0, Color(0, 0, 0, 0.5))   # intake
			g.rr(.24, s * (ny + .03) - .009, .045, .018, .008, U.hx("#2a2624"))   # exhaust stub, outboard
	# long boxy fuselage with the extended nose
	var fu: Array = _cap(.485, .38, .054, 7)
	fu.append_array([[.3, .055], [.1, .055], [-.1, .055], [-.2, .05], [-.3, .04], [-.38, .03], [-.44, .02], [-.485, .009]])
	_body(g, fu, 0, col, sh)
	if not sh:
		# trim stripe down the spine, cockpit windscreen, roof hatch
		g.poly(PackedVector2Array([Vector2(.47, -.012), Vector2(-.47, -.004), Vector2(-.47, .004), Vector2(.47, .012)]), Color(acc, 0.75))
		_glass(g, PackedVector2Array([Vector2(.405, -.04), Vector2(.405, .04), Vector2(.345, .053), Vector2(.345, -.053)]))
		g.lines(PackedVector2Array([Vector2(.405, 0), Vector2(.345, 0), Vector2(.38, -.045), Vector2(.345, -.05), Vector2(.38, .045), Vector2(.345, .05)]), U.shade(col, .7), 0.005)
		g.stroke_rect(.24, -.025, .05, .05, Color(0, 0, 0, 0.18), 0.004)
		# fin seen edge-on, rising above the tailplane
		g.rr(-.49, -.008, .26, .016, .007, U.shade(col, .8))
		g.rect(-.49, -.008, .07, .016, U.shade(acc, .9))
	# high wing: long, straight, constant chord, square tips
	var wing := _mirror([Vector2(.17, 0), Vector2(.17, -.59), Vector2(.162, -.6), Vector2(.058, -.6), Vector2(.05, -.59), Vector2(.05, 0)])
	_surface(g, wing, col, sh, .17, .05)
	if sh: return
	# nacelle tops showing through, full-span double-slotted flaps, ailerons outboard
	for s in [-1, 1]:
		_body(g, [[.17, .03], [.12, .028], [.07, .02], [.05, .012]], s * ny, U.shade(col, .95), false)
	g.lines(PackedVector2Array([Vector2(.085, -.59), Vector2(.085, -.06), Vector2(.085, .06), Vector2(.085, .59),
		Vector2(.085, -.42), Vector2(.05, -.42), Vector2(.085, .42), Vector2(.05, .42),
		Vector2(.085, -.06), Vector2(.05, -.06), Vector2(.085, .06), Vector2(.05, .06)]), dark, 0.005)
	for s in [-1, 1]:
		g.rect(.05, s * .6 - (.025 if s > 0 else 0), .12, .025, Color(acc, 0.85))
		g.circle(.13, s * .3, .008, U.shade(col, .6))
	_nav_lights(g, .11, .6)
