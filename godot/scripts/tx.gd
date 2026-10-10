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
