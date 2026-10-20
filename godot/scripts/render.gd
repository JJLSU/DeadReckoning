class_name Render
## Drawing for flight mode, ground mode and both HUDs (port of the canvas renderers).

const TS := 32.0
const CH := 1024.0
# Fair-weather clouds in flight mode. The sky is split into 1,700-unit cells and this
# is the share of cells that hold a cloud: 0 = clear skies, 1 = a cloud in every cell.
# (Originally 0.33.) Covers land and ocean alike. Separate from storms (world.gd).
const CLOUD_DENSITY := 1
const SEA := "#1f3543"   # open-ocean colour, matches the terrain shader's deep water
static var CC := {}

# --- height parallax and sun shadows (flight view) ---
# Things with height (trees, buildings, tanks) are drawn as if seen by a camera PAR_K * screen-size
# above the ground, so their tops lean away from the screen centre as you fly over them.
const PAR_K := 0.6
const TREE_H := 0.6       # average tree height as a share of its canopy width (each tree varies)
const HOUSE_H := 14.0     # house wall height, world units
const HANGAR_H := 22.0
const TANK_H := 14.0
const CLOUD_SHADOW := 800.0   # cloud shadow offset per unit of sun shadow length
static var PV := Vector3(0, 0, 1000)   # camera x, y and eye height for lift()
static var SUN := Vector2(0.3, 0.5)    # ground shadow offset per unit of height
static var SUN_ANG := 1.0              # shadow direction
static var SUN_A := 1.0                # shadow strength (fades out at night)
static var MEMO := {}                  # per-frame results shared by the layers (see memo())
static var MEMO_F := -1
static var HOUSES := {}                # (strip id, world seed) -> its town's houses (draw_strip)

static func hc(s: String) -> Color:
	if CC.has(s): return CC[s]
	var c := Color.html(s)
	CC[s] = c
	return c

static func rgba(r: float, g: float, b: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

static func flight_scale(gm, alt: float) -> float:
	return sqrt(gm.Wv * gm.Hv) / (700.0 + maxf(0.0, alt) * 6.0) * FLIGHT_ZOOM

## The flight camera zoom is fixed (Greg, 2026-10-14); the player's zoom setting applies on foot only.
const FLIGHT_ZOOM := 0.69

## Sets the camera for lift() and the sun for shadows, from the view and the clock.
## Sun rises in the east (shadows point west), passes north of the map at noon (shadows point
## down, a little right, like the old fixed shadows) and sets in the west.
static func set_view3d(gm, cx: float, cy: float, sc: float) -> void:
	PV = Vector3(cx, cy, PAR_K * sqrt(gm.Wv * gm.Hv) / sc)
	var h := fmod(gm.G.time / 60.0, 24.0) if gm.G else 10.0
	var u := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	SUN_ANG = lerpf(2.9, -0.2, u)
	var elev := maxf(0.16, sin(PI * u) * 1.08)
	SUN = Vector2.from_angle(SUN_ANG) * clampf(1.0 / tan(elev), 0.4, 2.6)
	SUN_A = 1.0 - (gm.dark() if gm.G else 0.0)
	TROT = Vector2.from_angle(SUN_ANG + PI * 1.75)
	SUN_DIR = Vector2.from_angle(SUN_ANG)
	SUN_LEN = SUN.length()

## Flight helpers that are costly (touchdown prediction runs a 450-step simulation) and are
## asked for by more than one layer each frame: worked out once per frame.
static func memo(gm, key: String):
	var f := Engine.get_process_frames()
	if f != MEMO_F:
		MEMO.clear()
		MEMO_F = f
	if MEMO.has(key): return MEMO[key]
	var v
	var now := Time.get_ticks_msec()
	if key == "range" and now - RANGE_MS < 250 and now >= RANGE_MS and is_same(RANGE_GM, gm):
		MEMO[key] = RANGE_V   # the fuel range is a readout: four times a second is plenty
		return RANGE_V
	match key:
		"approach": v = gm.flight.approach_info()
		"touchdown": v = gm.flight.predict_touchdown()
		"range":
			v = gm.range_now()
			RANGE_V = v; RANGE_MS = now; RANGE_GM = gm
	MEMO[key] = v
	return v
static var RANGE_V = 0.0
static var RANGE_MS := -100000
static var RANGE_GM = null

## The strips the player knows (to label and to show on the minimap), kept until that changes.
static var KNOWN_L: Array = []
static var KNOWN_D = null
static var KNOWN_N := -1
static var KNOWN_S := -1
static func known_strips(gm) -> Array:
	var wd = gm.wd
	if not is_same(KNOWN_D, gm.known) or KNOWN_N != gm.known.size() or KNOWN_S != wd.strips.size():
		KNOWN_D = gm.known; KNOWN_N = gm.known.size(); KNOWN_S = wd.strips.size()
		KNOWN_L = wd.strips.filter(func(s): return gm.known.has(s.id))
	return KNOWN_L

## How far a point at height hgt above (x, y) shifts on screen, in world units.
static func lift(x: float, y: float, hgt: float) -> Vector2:
	var k := hgt / maxf(PV.z - hgt, PV.z * 0.25)
	return Vector2((x - PV.x) * k, (y - PV.y) * k)

## Ground scatter (trees, bushes, rocks, cars, water glints) is worked out once per terrain
## chunk and kept in gm.TCACHE under a Vector2i key. Trees and bushes go into fixed MultiMeshes
## (shaders/trees.gdshader leans them and places their shadows each frame from uniforms), so a
## frame costs a few draw calls per chunk instead of several per tree.
## MultiMesh order per chunk: 0 = shadows (Tx.SPUFF), 1..3 = lower canopy per tree sprite,
## 4..6 = canopy tops per tree sprite.
const SG := 70.0                 # scatter cell size, world units
# Building a chunk's scatter is slow (terrain lookups per cell), so it is spread over frames
# with a time budget: chunks in view get up to SC_VIEW_US per frame, and chunks the plane is
# heading into are built ahead of time with SC_AHEAD_US, so crossing into them costs nothing.
const SC_VIEW_US := 4000
const SC_AHEAD_US := 1500
const SC_AHEAD := 1.2            # look-ahead distance, in chunks, along the heading
const CANOPY_A := 0.6      # flight: tree crowns are this opaque, so overlapping crowns blend softly
## In flight the trees' see-through look follows altitude, not zoom (Greg, 2026-10-13): on the
## ground they look as they did at 79% zoom at the top altitude, at the top altitude as they did
## at 69%, blending smoothly in between. The values assume a 16:9 window.
const TREE_FADE_GROUND := 0.16   # twice the top-altitude value (Greg, 2026-10-14; was 0.42, then 0.24)
## Small trees at a forest's edge are this much more opaque than deep ones (Greg, 2026-10-14).
## Canopy instance colours carry opacity / 2 in alpha; trees.gdshader doubles it back.
const EDGE_OPACITY := 1.4
## Deep forest trees are this much bigger again (Greg, 2026-10-14); the edges keep their size.
const DEEP_GROW := 1.3
const DEEP_SHADOW_FROM := 0.3   # forest depth (dp) where tree shadows start thinning out...
const DEEP_SHADOW_TO := 0.8     # ...and where none are left
const DEEP_LOWER_DARK := 0.6    # lower-layer tint of a tree without a shadow
## Isolated stands of the 3D-rendered test trees (Tx.T3D) in open grass, to compare with the
## crown trees (Greg, 2026-10-18). A grass cell starts a stand with this chance.
const T3D_STAND_P := 0.006
const T3D_FOREST_P := 0.03          # share of forest trees drawn as 3D trees instead of crowns
const T3D_STAND_H := Vector2(0.65, 1.6)   # a stand's height factor ranges over this (trees vary 0.85-1.15 of it)
const T3D_SHADE_W := 1.3            # the dark patch under a 3D tree, times its width...
const T3D_SHADE_A := 0.5            # ...and its opacity
## A green 3D tree's tint: s from -1 (dark, cool green) through 0 (as rendered) to 1 (light, yellow green).
static func _t3_shade(s: float) -> Color:
	if s < 0.0: return Color(1, 1, 1).lerp(Color(0.72, 0.84, 0.78), -s)
	return Color(1, 1, 1).lerp(Color(1.18, 1.12, 0.78), s)
const T3D_TINT := [Color(0.4, 0.42, 0.39), Color(0.66, 0.68, 0.64), Color(1, 1, 1)]   # low, middle, top layers: darker toward the ground (Greg, 2026-10-18)
const TREE_FADE_TOP := 0.08
const TREE_FADE_ALT := 120.0   # the highest a plane climbs (flight.gd caps the target at 120)
static func tree_fade(alt: float) -> float:
	return lerpf(TREE_FADE_GROUND, TREE_FADE_TOP, clampf(alt / TREE_FADE_ALT, 0, 1))
const FLIGHT_LOWER_TINT := Color(0.2, 0.22, 0.19)   # flight: the lower canopy layer, in the crowns' shade
const LOWER_TINT := Color(0.62, 0.66, 0.6)
const CAR_COLS := ["#6b3a2a", "#4a5560", "#7a6a3a", "#2a2826", "#8a8272"]
static var TQUAD: ArrayMesh
static var TREE_MAT: ShaderMaterial
static var TROT := Vector2(1, 0)           # cos/sin of the sprite turn that faces the sun
static var SUN_DIR := Vector2(1, 0)        # unit vector along the shadows
static var SUN_LEN := 1.0                  # SUN.length()

static func _tb_init() -> void:
	if TQUAD: return
	TQUAD = ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	TQUAD.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	TREE_MAT = ShaderMaterial.new()
	TREE_MAT.shader = load("res://shaders/trees.gdshader")

## One quad instance: 2D transform (no turn; the shader turns it), colour, custom data.
static func _q(buf: PackedFloat32Array, x: float, y: float, sz: float, col: Color, h: float, r: float) -> void:
	buf.append_array([sz, 0.0, 0.0, x, 0.0, sz, 0.0, y, col.r, col.g, col.b, col.a, x, y, h, r])

## Works out the scatter of chunk (kx, ky) until the clock passes `deadline` (usec); returns
## the finished chunk, or null while it is still being built (partial state stays cached).
## Tree colours come in stands, like a real forest: the slow noise that paints the autumn
## ground patches (terrain.gdshader) decides where fall stands are, a second one picks each
## stand's colour so neighbours match, and the odd tree is a random standout.
static var STAND_G := []   # green sprite indices, sorted by hue
static var STAND_F := []   # fall sprite indices, sorted by hue
static func _tree_at(x: float, y: float, h: float, seed_v: int) -> int:
	if STAND_G.is_empty():
		var g := []
		var fl := []
		for v in Tx.TREE_GREEN: g.append([Tx.tree_hue(v), v])
		for v in Tx.TREE_FALL: fl.append([Tx.tree_hue(Tx.TREE_GREEN + Tx.TREE_WIDE + v), Tx.TREE_GREEN + Tx.TREE_WIDE + v])
		g.sort(); fl.sort()
		STAND_G = g.map(func(e): return e[1])
		STAND_F = fl.map(func(e): return e[1])
	if fmod(h * 13.7, 1.0) < 0.05: return Tx.tree_pick(h)   # standout
	var au := U.vnoise(x / 650.0, y / 650.0, seed_v + 131)
	var k := clampf((U.vnoise(x / 260.0 + 7.0, y / 260.0 + 7.0, seed_v + 141) - 0.15) / 0.7, 0.0, 0.999)
	k = clampf(k + (fmod(h * 3.71, 1.0) - 0.5) * 0.3, 0.0, 0.999)   # neighbours vary a little
	var f := fmod(h * 7.13, 1.0)
	if f < clampf((au - 0.56) / 0.12, 0.0, 1.0) * 0.9: return STAND_F[int(k * STAND_F.size())]
	if f > 0.85: return Tx.TREE_GREEN + int(h * 613) % Tx.TREE_WIDE
	return STAND_G[int(k * STAND_G.size())]

## In flight a tree's lower layer uses another sprite from its colour family: for a fall tree,
## the other shapes of its colour; for a green or wide tree, the two greens nearest its hue.
static var LOWER_OPTS := []
static func _lower_opts(ti: int) -> Array:
	if LOWER_OPTS.is_empty():
		var ng := Tx.TREE_GREEN + Tx.TREE_WIDE
		var nf: int = Tx.FALL_HSV.size()
		for v in ng + Tx.TREE_FALL:
			var o := []
			if v >= ng:
				for u in range(ng, ng + Tx.TREE_FALL):
					if u != v and (u - ng) % nf == (v - ng) % nf: o.append(u)
			else:
				var by := []
				for u in Tx.TREE_GREEN:
					if u != v: by.append([absf(Tx.tree_hue(u) - Tx.tree_hue(v)), u])
				by.sort()
				o = [by[0][1], by[1][1]]
			LOWER_OPTS.append(o if not o.is_empty() else [v])
	return LOWER_OPTS[ti]

static func _scatter_chunk(gm, kx: int, ky: int, deadline: int):
	var key := Vector2i(kx, ky)
	var ch = gm.TCACHE.get(key)
	if ch != null and ch.done: return ch
	if Time.get_ticks_usec() >= deadline: return null
	var wd: World = gm.wd
	var seed_v: int = wd.SEED
	var gx0 := int(ceil(kx * CH / SG))
	var gx1 := int(ceil((kx + 1) * CH / SG))
	var gy0 := int(ceil(ky * CH / SG))
	var gy1 := int(ceil((ky + 1) * CH / SG))
	if ch == null:
		ch = {"done": false, "i": 0, "glint": PackedFloat32Array(), "car": [], "rock": [], "b": [], "hq": {}}
		for b in 2 + 2 * Tx.TREES.size() + 4 * Tx.T3D.size(): ch.b.append(PackedFloat32Array())   # + the forest mist puffs, the 3D trees
		gm.TCACHE[key] = ch
		if gm.TCACHE.size() > 60000: gm.TCACHE.clear()
	var nx := gx1 - gx0
	var total := nx * (gy1 - gy0)
	var bufs: Array = ch.b
	var NT: int = Tx.TREES.size()
	var tops: Dictionary = ch.hq
	var tree := func(ti: int, x: float, y: float, w: float, op: float, dp: float) -> void:
		var hf := 0.6 + U.hash3(int(x), int(y), seed_v + 215) * 0.9   # 0.6 to 1.5 times the average height
		var hgt := w * TREE_H * hf
		_hq_add(tops, x, y, w * 0.42, hgt)
		# deep in a forest the shadows fall on the near-black floor under other crowns, where they
		# barely show: they thin out from the edge inward (they cost a third of a forest's drawing)
		# (a tree without one has a darker lower layer instead, so the canopy keeps its depth)
		var lt := FLIGHT_LOWER_TINT
		if U.hash3(int(y), int(x), seed_v + 217) >= smoothstep(DEEP_SHADOW_FROM, DEEP_SHADOW_TO, dp):
			_q(bufs[0], x, y, w * 0.84, Color(1, 1, 1, 0.6), hgt, -hgt / (w * 0.84))
		else:
			lt *= DEEP_LOWER_DARK
		var lo: Array = _lower_opts(ti)   # the lower layer is a different sprite of the same colour
		_q(bufs[1 + lo[int(U.hash3(int(y), int(x), seed_v + 216) * lo.size()) % lo.size()]], x, y, w * 0.84,
			Color(lt, op * 0.5), hgt * 0.5, hgt * 0.5 / (w * 0.84))
		_q(bufs[1 + NT + ti], x, y, w, Color(1, 1, 1, op * 0.5), hgt, hgt / w)
	var B3 := 2 + 2 * NT
	# a 3D tree: hf scales its height, tint its colour; a soft dark patch lies on the ground under it
	var t3 := func(v: int, x: float, y: float, w: float, hf: float, tint: Color) -> void:
		var hgt := w * TREE_H * hf
		_hq_add(tops, x, y, w * 0.42, hgt)
		_q(bufs[0], x, y, w * T3D_SHADE_W, Color(1, 1, 1, T3D_SHADE_A), 0.0, -0.001)
		_q(bufs[B3 + v * 4], x, y, w, Color(0, 0, 0, 0.45), hgt, -300.0 - hgt / w)
		for l in 3: _q(bufs[B3 + v * 4 + 1 + l], x, y, w, T3D_TINT[l] * tint, hgt * (0.45 + 0.275 * l), 300.0 + hgt * (0.45 + 0.275 * l) / w)
	while ch.i < total and Time.get_ticks_usec() < deadline:
		var gx: int = gx0 + ch.i % nx
		var gy: int = gy0 + ch.i / nx
		ch.i += 1
		var h := U.hash3(gx, gy, seed_v + 201)
		var wx := (gx + U.hash3(gx, gy, seed_v + 202)) * SG
		var wy := (gy + U.hash3(gx, gy, seed_v + 203)) * SG
		var tt := wd.terr(wx, wy)
		if h > 0.85 and tt != 5 and tt != 6: continue   # forests fill every cell
		if tt <= 1:
			if h < 0.25: ch.glint.append_array([wx, wy, h])
			continue
		if wd.strip_at(wx, wy, 6) or Failsafe.on_farm(wd, wx, wy, 25): continue
		if tt >= 11 and tt <= 13:
			if h < 0.22:
				var rd = wd.road_at(wx, wy)
				if rd: ch.car.append([wx, wy, rd.r.ang + (h - 0.11) * 3, hc(CAR_COLS[int(h * 50) % 5])])
			continue
		if tt == 7 or tt == 8:
			if h < 0.35: ch.rock.append([wx, wy, 5 + h * 22, h * 5, hc("#c8c8c4") if tt == 8 else hc("#8a857a")])
			continue
		if (tt == 3 or tt == 4) and not Tx.T3D.is_empty() and U.hash3(gx, gy, seed_v + 231) < T3D_STAND_P:
			# a stand of 7-16 3D trees; fall ones where the ground has its autumn patches
			# Each stand has its own height, size, green shade and one or two sprites, so its trees
			# look alike and stands differ from each other (Greg, 2026-10-18).
			var n3 := 7 + int(U.hash3(gx, gy, seed_v + 232) * 10)
			var au := U.vnoise(wx / 650.0, wy / 650.0, seed_v + 131)
			var fall := au > 0.6
			var sh := lerpf(T3D_STAND_H.x, T3D_STAND_H.y, U.hash3(gx, gy, seed_v + 237))
			var sw := lerpf(42.0, 74.0, U.hash3(gx, gy, seed_v + 238))
			var stint := _t3_shade(U.hash3(gx, gy, seed_v + 239) * 2.0 - 1.0)
			var sv := int(U.hash3(gx, gy, seed_v + 240) * Tx.T3D_FALL)
			for q in n3:
				var a := U.hash3(gx * 7 + q, gy, seed_v + 234) * TAU
				var rr := sqrt(U.hash3(gx, gy * 7 + q, seed_v + 235)) * (50.0 + n3 * 9.0)
				var tx := wx + cos(a) * rr
				var ty := wy + sin(a) * rr
				var tq := wd.terr(tx, ty)
				if (tq != 3 and tq != 4) or Failsafe.on_farm(wd, tx, ty, 30): continue
				var hv := U.hash3(gx + q * 13, gy - q, seed_v + 236)
				var v := Tx.T3D_FALL + int(hv * (Tx.T3D_N - Tx.T3D_FALL)) if fall and hv < 0.7 else (sv + (1 if fmod(hv * 7.31, 1.0) > 0.7 else 0)) % Tx.T3D_FALL
				var tj := 1.0 + (U.hash3(gx - q, gy + q * 5, seed_v + 241) - 0.5) * 0.12   # a little brightness per tree
				var tint := Color(stint.r * tj, stint.g * tj, stint.b * tj) if v < Tx.T3D_FALL else Color(tj, tj, tj)
				t3.call(mini(v, Tx.T3D.size() - 1), tx, ty, sw * (0.85 + hv * 0.3), sh * (0.85 + fmod(hv * 3.7, 1.0) * 0.3), tint)
			continue
		if tt == 3 and h >= 0.05 and h < 0.16:
			var bs := 10 + h * 40
			var bh := bs * 0.18
			_q(bufs[0], wx, wy, bs * 0.8, Color(1, 1, 1, 0.4), bh, -bh / (bs * 0.8))
			_q(bufs[1 + NT + int(h * 70) % Tx.TREE_GREEN], wx, wy, bs * 0.9, Color(1, 1, 1, 0.5), bh, bh / (bs * 0.9))
			continue
		if tt == 5 or tt == 6:
			# closed canopy: 5 trees per cell. Deep in the forest each tree is 1.0-1.5x its base
			# size, shrinking gradually to 0.5-0.8x at the forest edge (wd.TM is the forest noise
			# terr() just read: 0.53 at the edge, deeper inside as it rises). The small edge trees
			# grow more thickly (up to 11 per cell) so the edge stays filled in.
			var dp := smoothstep(0.53, 0.66, wd.TM)
			var nq := 5 + int((1.0 - dp) * 6.99)
			var op := lerpf(EDGE_OPACITY, 1.0, dp)
			for q in nq:
				var so := 0 if q < 5 else 300   # extra edge trees get their own hashes
				var hq := U.hash3(gx * 3 + q, gy, seed_v + 211 + so)
				var tx := (gx + U.hash3(gx, gy * 3 + q, seed_v + 212 + so)) * SG
				var ty := (gy + U.hash3(gx + q, gy - q, seed_v + 213 + so)) * SG
				var sz := lerpf(lerpf(0.5, 1.0, dp), lerpf(0.8, 1.5, dp), U.hash3(gx * 5 + q, gy * 7 - q, seed_v + 214 + so)) * lerpf(1.0, DEEP_GROW, dp)
				var tw := ((56 if tt == 6 else 50) + hq * 40) * sz
				if not Tx.T3D.is_empty() and U.hash3(gx * 11 + q, gy * 5 - q, seed_v + 242) < T3D_FOREST_P:
					# now and then a 3D tree among the crowns, coloured like its neighbourhood
					var nv := U.vnoise(tx / 260.0, ty / 260.0, seed_v + 141)
					var fv := U.vnoise(tx / 650.0, ty / 650.0, seed_v + 131) > 0.6 and hq < 0.6
					var v3 := Tx.T3D_FALL + int(hq * (Tx.T3D_N - Tx.T3D_FALL)) if fv else int(nv * Tx.T3D_FALL) % Tx.T3D_FALL
					t3.call(mini(v3, Tx.T3D.size() - 1), tx, ty, tw * 0.75, lerpf(0.8, 1.4, U.hash3(gx, gy * 3 + q, seed_v + 243)),
						_t3_shade(nv * 2.0 - 1.0) if v3 < Tx.T3D_FALL else Color.WHITE)
				else:
					tree.call(_tree_at(tx, ty, hq, seed_v), tx, ty, tw, op, dp)
			continue
		if (tt == 3 and h < 0.05) or (tt == 4 and h < 0.012):
			tree.call(_tree_at(wx, wy, fmod(h * 20.0, 1.0), seed_v), wx, wy, 24 + h * 38, 1.0, 0.0)
	if ch.i < total: return null
	var mms := []
	for b in bufs.size():
		var buf: PackedFloat32Array = bufs[b]
		if buf.is_empty():
			mms.append(null)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = TQUAD
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		mms.append(mm)
	ch.mm = mms
	for k in tops: tops[k] = PackedFloat32Array(tops[k])
	ch.erase("b")
	ch.done = true
	return ch

## Treetop index of a chunk, for the plane's shadow: 70-unit cell -> [x, y, radius, height, ...]
## (an Array while the chunk builds, packed once it is done).
static func _hq_add(hq: Dictionary, x: float, y: float, r: float, h: float) -> void:
	var k := Vector2i(int(floor(x / SG)), int(floor(y / SG)))
	if not hq.has(k): hq[k] = []
	hq[k].append_array([x, y, r, h])

## The treetops within r of c, from the finished chunks, as one flat [x, y, radius, height, ...].
static func _trees_near(gm, c: Vector2, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for cy in range(int(floor((c.y - r) / SG)) - 1, int(floor((c.y + r) / SG)) + 2):
		for cx in range(int(floor((c.x - r) / SG)) - 1, int(floor((c.x + r) / SG)) + 2):
			var ch = gm.TCACHE.get(Vector2i(int(floor((cx + 0.5) * SG / CH)), int(floor((cy + 0.5) * SG / CH))))
			if ch == null or not ch.done: continue
			var a = ch.hq.get(Vector2i(cx, cy))
			if a != null: out.append_array(a)
	return out

## Treetop height at (x, y) from a _trees_near() list; crowns are domes, lower toward the rim.
static func _tree_h(t: PackedFloat32Array, x: float, y: float) -> float:
	var h := 0.0
	for i in range(0, t.size(), 4):
		var dx := t[i] - x
		var dy := t[i + 1] - y
		var r2 := t[i + 2] * t[i + 2]
		var d2 := dx * dx + dy * dy
		if d2 < r2: h = maxf(h, t[i + 3] * (0.55 + 0.45 * sqrt(1.0 - d2 / r2)))
	return h

## Height of the hangars, fuel tanks and town houses of the airfields in `near` at p, as
## draw_strip places them (0 elsewhere).
static func _strip_h(near: Array, p0: Vector2, seed_v: int) -> float:
	var h := 0.0
	for s in near:
		var p := Vector2(p0.x - s.x, p0.y - s.y).rotated(-s.ang)
		var L: float = s.len
		var Wd: float = s.wid
		if absf(p.x) > L / 2 + 420 or absf(p.y) > Wd / 2 + 320: continue
		var dirt: bool = s.type == "dirt"
		var hav: bool = s.type == "haven"
		var nh := 4 if hav else (3 if s.type == "airport" else (2 if s.type == "regional" else 1))
		for i in nh:
			if Rect2(-L / 4 - 30 + i * 72, Wd / 2 + (22.0 if dirt else 26.0), 60, 38.0 if dirt else 46.0).has_point(p): h = maxf(h, HANGAR_H)
		if s.fuel and not hav:
			for i in 2:
				if p.distance_to(Vector2(L / 4 + 10 + i * 26, Wd / 2 + 40)) < 11: h = maxf(h, TANK_H)
		if not hav:
			for hs in HOUSES.get(Vector2i(s.id, seed_v), []):
				if Rect2(hs[0], hs[1], hs[2], hs[3]).has_point(p): h = maxf(h, HOUSE_H)
	return h

## Where the plane's shadow is drawn and how big: it lands on whatever is under it (treetops,
## hangars, tanks, town houses, the Failsafe farm), so over them it is drawn at their height,
## leaning with them as the roofs do, a bit bigger, and nearer the plane. Over forest the
## height wobbles from crown to crown. It eases over a few frames so it rides up and down.
const SHADOW_HU := 13.0        # the plane's height per unit of altitude: lower = the shadow pulls in more over tall things (30, then 20; Greg 2026-10-19: stronger again)
const SHADOW_GROW := 2.25      # how much bigger it gets on high surfaces, times the lean's own growth (1.5 before)
const SHADOW_SPREAD := 0.5     # the 4 outer height samples sit this share of the shadow's size out (0.3 before; Greg: coarser)
const SHADOW_JITTER := 0.15    # over treetops the height wobbles by up to this share of it
static var SHD_H := 0.0
static var SHD_T := 0.0
static var SHD_NEAR := []                  # airfields near the shadow (refreshed as it moves)
static var SHD_AT := Vector2(INF, INF)
static var SHD_WD = null
static func plane_shadow(gm, F: Dictionary, psd: Vector2, size: float) -> Vector3:
	var g0 := Vector2(F.x, F.y) + psd
	if SHD_WD != gm.wd or g0.distance_squared_to(SHD_AT) > 250000.0:
		SHD_WD = gm.wd
		SHD_AT = g0
		SHD_NEAR = []
		for s in gm.wd.strips:
			if s.type == "road" or s.get("arch", "") == "family": continue   # family farms and Failsafe have no 3D buildings here
			if absf(s.x - g0.x) < 1300 and absf(s.y - g0.y) < 1300: SHD_NEAR.append(s)
	var a := Vector2.from_angle(F.hdg) * size * SHADOW_SPREAD
	var b := a.orthogonal()
	var trees := _trees_near(gm, g0, size * SHADOW_SPREAD)
	var ht := 0.0
	var hb := 0.0
	var wt := 2.0   # the middle counts double, so single crowns still show
	for o in [Vector2.ZERO, a, -a, b, -b]:
		var p: Vector2 = g0 + o
		ht += _tree_h(trees, p.x, p.y) * wt
		hb += maxf(Failsafe.height_at(gm.wd, p.x, p.y), _strip_h(SHD_NEAR, p, gm.wd.SEED)) * wt
		wt = 1.0
	ht /= 6.0
	hb /= 6.0
	if ht > 0.0: ht *= 1.0 + SHADOW_JITTER * (U.vnoise(g0.x / 16.0, g0.y / 16.0, 77) - 0.5) * 2.0
	var hs := maxf(ht, hb)
	var dt: float = gm.T - SHD_T
	SHD_T = gm.T
	SHD_H = hs if (dt < 0.0 or dt > 0.5) else SHD_H + (hs - SHD_H) * (1.0 - exp(-dt * 22.0))
	var zp := maxf(0.0, F.alt) * SHADOW_HU
	var h := minf(SHD_H, zp)
	var p := Vector2(F.x, F.y) + psd * clampf(1.0 - h / maxf(zp, 1.0), 0.0, 1.0)
	p += lift(p.x, p.y, h)
	return Vector3(p.x, p.y, 1.0 + SHADOW_GROW * h / maxf(PV.z - h, PV.z * 0.25))

## Builds the scatter of the chunks the view will reach next: the view rectangle moved
## SC_AHEAD chunks along the heading (and the view itself, when descending into scatter range).
static func prefetch_scatter(gm, cx: float, cy: float, sc: float, hdg: float) -> void:
	if sc < 0.4: return
	_tb_init()
	var deadline := Time.get_ticks_usec() + SC_AHEAD_US
	var hw: float = gm.Wv / 2 / sc + SG * 1.5
	var hh: float = gm.Hv / 2 / sc + SG * 1.5
	for f in [0.0, 0.5, 1.0]:
		var ax: float = cx + cos(hdg) * CH * SC_AHEAD * f
		var ay: float = cy + sin(hdg) * CH * SC_AHEAD * f
		for ky in range(int(floor((ay - hh) / CH)), int(floor((ay + hh) / CH)) + 1):
			for kx in range(int(floor((ax - hw) / CH)), int(floor((ax + hw) / CH)) + 1):
				if Time.get_ticks_usec() >= deadline: return
				_scatter_chunk(gm, kx, ky, deadline)

## Draws the scatter in view: water glints, rocks and cars directly, then every chunk's tree
## shadows, lower canopies and tops (each as one MultiMesh draw per chunk).
## al fades the glints, rocks, cars and mist in with the view scale; tf is the trees' own alpha.
static func draw_scatter(gm, g: Pen, x0: float, y0: float, x1: float, y1: float, al: float, t: float, tf: float) -> void:
	if g.ci.material != TREE_MAT: g.ci.material = TREE_MAT
	TREE_MAT.set_shader_parameter("cam", Vector2(PV.x, PV.y))
	TREE_MAT.set_shader_parameter("eye", PV.z)
	TREE_MAT.set_shader_parameter("trot", TROT)
	TREE_MAT.set_shader_parameter("sun", SUN)
	TREE_MAT.set_shader_parameter("sun_dir", SUN_DIR)
	TREE_MAT.set_shader_parameter("sun_len", SUN_LEN)
	TREE_MAT.set_shader_parameter("fade", tf)
	TREE_MAT.set_shader_parameter("mist_fade", al)
	TREE_MAT.set_shader_parameter("sun_a", SUN_A)
	TREE_MAT.set_shader_parameter("canopy_a", CANOPY_A)
	TREE_MAT.set_shader_parameter("t3_a", clampf(tf / TREE_FADE_GROUND, 0.5, 1.0))
	var pad := SG * 1.5
	var deadline := Time.get_ticks_usec() + SC_VIEW_US
	var chs := []
	for ky in range(int(floor((y0 - pad) / CH)), int(floor((y1 + pad) / CH)) + 1):
		for kx in range(int(floor((x0 - pad) / CH)), int(floor((x1 + pad) / CH)) + 1):
			var ch = _scatter_chunk(gm, kx, ky, deadline)
			if ch: chs.append(ch)
	g.ga = al
	for ch in (chs if al > 0.01 else []):
		var gl: PackedFloat32Array = ch.glint
		for i in range(0, gl.size(), 3):
			var gxp := gl[i]
			var gyp := gl[i + 1]
			if gxp < x0 - pad or gxp > x1 + pad or gyp < y0 - pad or gyp > y1 + pad: continue
			var kk := 0.5 + 0.5 * sin(t * 2 + gl[i + 2] * 40)
			g.rect(gxp - 9, gyp, 18, 1.6, rgba(220, 235, 240, 0.18 * kk))
		for r in ch.rock:
			if r[0] < x0 - pad or r[0] > x1 + pad or r[1] < y0 - pad or r[1] > y1 + pad: continue
			var rs: float = r[2]
			g.ellipse(r[0] + 3, r[1] + 4, rs, rs * 0.7, r[3], Color(0, 0, 0, 0.28))
			g.ellipse(r[0], r[1], rs, rs * 0.7, r[3], r[4])
			g.ellipse(r[0] - rs * 0.3, r[1] - rs * 0.25, rs * 0.45, rs * 0.3, r[3], Color(1, 1, 1, 0.15))
		for c in ch.car:
			if c[0] < x0 - pad or c[0] > x1 + pad or c[1] < y0 - pad or c[1] > y1 + pad: continue
			g.save(); g.translate(c[0], c[1]); g.rotate(c[2])
			g.rect(-7, -2, 18, 10, Color(0, 0, 0, 0.35))
			g.rect(-9, -4.5, 18, 9, c[3])
			g.rect(-3, -3.5, 4, 7, rgba(15, 18, 20, 0.85)); g.rect(3, -3, 2.5, 6, rgba(15, 18, 20, 0.85))
			g.restore()
	g.ga = 1.0
	if Tx.TREES.size() < 3: return
	var NT: int = Tx.TREES.size()
	g.ci.draw_set_transform_matrix(g.xf)
	for b in 1 + 2 * NT:
		if b == NT + 1:   # forest mist lies over the lower crowns, under the tops
			var fm := 0.0   # forest mist removed (Greg, 2026-10-14); its puffs are no longer built
			TREE_MAT.set_shader_parameter("fmist", fm)
			if fm > 0.01 and al > 0.01:
				for ch in chs:
					if 1 + 2 * NT < ch.mm.size() and ch.mm[1 + 2 * NT]: g.ci.draw_multimesh(ch.mm[1 + 2 * NT], Tx.PUFF)
		var tex: Texture2D = Tx.SPUFF if b == 0 else Tx.TREES[(b - 1) % NT]
		for ch in chs:
			if b >= ch.mm.size(): continue
			var mm = ch.mm[b]
			if mm: g.ci.draw_multimesh(mm, tex)
	# the 3D-rendered test trees: every shadow, then the low, middle and top layers
	var B3 := 2 + 2 * NT
	for l in 4:
		for v in Tx.T3D.size():
			var b := B3 + v * 4 + l
			for ch in chs:
				if b < ch.mm.size() and ch.mm[b]: g.ci.draw_multimesh(ch.mm[b], Tx.T3D[v][l])

## A terrain chunk drawn as a one-instance MultiMesh, so trees.gdshader knows it is ground and
## adds the close-up detail. The MultiMeshes are kept per chunk.
static var CHUNK_MM := {}
static func _detail_chunk(g: Pen, tex: Texture2D, gx: int, gy: int) -> void:
	var k := Vector2i(gx, gy)
	var mm: MultiMesh = CHUNK_MM.get(k)
	if mm == null:
		if CHUNK_MM.size() > 400: CHUNK_MM.clear()
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = TQUAD
		mm.instance_count = 1
		var c := Vector2(gx * CH + (CH + 1) / 2, gy * CH + (CH + 1) / 2)
		mm.set_instance_transform_2d(0, Transform2D(Vector2(CH + 1, 0), Vector2(0, CH + 1), c))
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(c.x, c.y, -2.0, 0.0))
		CHUNK_MM[k] = mm
	g.ci.draw_multimesh(mm, tex)

## Mist and haze (shaders/trees.gdshader works out each pixel). Mist lies in the low ground
## around dawn, lifts by mid-morning and comes back late at night; how thick it gets changes
## from day to day. Haze thickens as you climb, more towards the edges of the view.
static var FOG_MM: MultiMesh
static func mist_amount(gm) -> float:
	if gm.G == null: return 0.0
	var t: float = gm.G.time
	var h := fmod(t / 60.0, 24.0)
	var m := 0.0
	if h < 5.0: m = 0.6
	elif h < 6.5: m = lerpf(0.6, 1.0, (h - 5.0) / 1.5)
	elif h < 10.5: m = 1.0 - smoothstep(7.0, 10.5, h)
	elif h >= 19.0: m = 0.6 * smoothstep(19.0, 23.0, h)
	var day := int(floor((t + 6 * 60) / 1440.0))   # a "day" for the mist runs 6 pm to 6 pm
	return m * (0.6 + 0.4 * U.hash3(day, 3, gm.wd.SEED + 77))

## Forest mist: at dawn (and a little at dusk) mist lies among the trees, over the forest floor
## and the lower crowns but under the treetops, which poke out of it: one soft puff per forest
## cell (_scatter_chunk), drawn by draw_scatter between the lower canopies and the tops.
static func forest_mist_amount(gm) -> float:
	if gm.G == null: return 0.0
	var h := fmod(gm.G.time / 60.0, 24.0)
	var dusk := 0.45 * clampf(1.0 - absf(h - 18.4) / 1.4, 0.0, 1.0)
	return maxf(mist_amount(gm), dusk)

static func draw_fog(gm, g: Pen, cx: float, cy: float, sc: float, alt: float) -> void:
	_tb_init()
	var W: float = gm.Wv
	var H: float = gm.Hv
	var mist := 0.0   # the low-ground mist over water and valleys is off (Greg, 2026-10-13); forest mist is drawn under the treetops instead
	var haze := clampf(alt / 110.0, 0, 1) * 0.26
	if FOG_MM == null:
		FOG_MM = MultiMesh.new()
		FOG_MM.transform_format = MultiMesh.TRANSFORM_2D
		FOG_MM.use_colors = true
		FOG_MM.use_custom_data = true
		FOG_MM.mesh = TQUAD
		FOG_MM.instance_count = 1
	var sz := Vector2(W / sc + 4, H / sc + 4)
	FOG_MM.set_instance_transform_2d(0, Transform2D(Vector2(sz.x, 0), Vector2(0, sz.y), Vector2(cx, cy)))
	FOG_MM.set_instance_color(0, Color.WHITE)
	FOG_MM.set_instance_custom_data(0, Color(cx, cy, -1.0, 0.0))
	if g.ci.material != TREE_MAT: g.ci.material = TREE_MAT
	set_view3d(gm, cx, cy, sc)
	var h := fmod(gm.G.time / 60.0, 24.0) if gm.G else 12.0
	var warm := clampf(1.0 - absf(h - 6.6) / 1.9, 0, 1) + clampf(1.0 - absf(h - 18.1) / 1.8, 0, 1)
	var wind: Vector2 = gm.F.wind if gm.F else Vector2(8, 3)
	TREE_MAT.set_shader_parameter("cam", Vector2(PV.x, PV.y))
	TREE_MAT.set_shader_parameter("eye", PV.z)
	TREE_MAT.set_shader_parameter("seed", gm.wd.SEED)
	TREE_MAT.set_shader_parameter("world_size", D.WORLD)
	TREE_MAT.set_shader_parameter("fog_size", sz)
	TREE_MAT.set_shader_parameter("tsec", gm.T)
	TREE_MAT.set_shader_parameter("drift", wind * 0.35)
	TREE_MAT.set_shader_parameter("mist", mist)
	TREE_MAT.set_shader_parameter("mist_col", Color(0.9, 0.92, 0.94).lerp(Color(1.0, 0.86, 0.76), warm * 0.6))
	TREE_MAT.set_shader_parameter("haze", haze)
	TREE_MAT.set_shader_parameter("haze_col", Color(0.68, 0.75, 0.85).lerp(Color(0.93, 0.78, 0.7), warm * 0.7))
	if haze < 0.01: return   # the uniforms above are still set: the forest mist uses them
	g.set_view(sc, W / 2 - cx * sc, H / 2 - cy * sc)
	g.ci.draw_multimesh(FOG_MM, Tx.SPUFF)

## A box building in the current (possibly rotated) frame. Pass 0 draws its sun shadow, pass 1
## its walls; both return the offset at which to draw its roof. Draw every shadow of a group
## first so a long shadow never lands on top of a neighbour's roof.
## cl = camera in this frame, sl = sun shadow vector in this frame.
static func draw_box3d(g: Pen, ps: int, x: float, y: float, w: float, h: float, hgt: float, cl: Vector2, sl: Vector2, wall: Color) -> Vector2:
	var k := hgt / maxf(PV.z - hgt, PV.z * 0.25)
	var off := (Vector2(x + w / 2, y + h / 2) - cl) * k
	var v := sl * hgt if ps == 0 else off
	if ps == 0 and SUN_A < 0.01: return off
	if ps == 1 and v.length_squared() < 0.25: return off
	# hull of the footprint and its copy moved by v: three corners, then three moved corners
	var c := [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	var s := (3 if v.y >= 0 else 2) if v.x >= 0 else (0 if v.y >= 0 else 1)
	var c0: Vector2 = c[s]
	var c1: Vector2 = c[(s + 1) % 4]
	var c2: Vector2 = c[(s + 2) % 4]
	var c3: Vector2 = c[(s + 3) % 4]
	g.poly(PackedVector2Array([c0, c1, c2, c2 + v, c3 + v, c0 + v]), Color(0, 0, 0, 0.36 * SUN_A) if ps == 0 else wall)
	return off

## A cylinder (fuel tank) seen from above: pass 0 shadow, pass 1 side wall; returns the top offset.
static func draw_cyl3d(g: Pen, ps: int, x: float, y: float, r: float, hgt: float, cl: Vector2, sl: Vector2, wall: Color) -> Vector2:
	var off := (Vector2(x, y) - cl) * (hgt / maxf(PV.z - hgt, PV.z * 0.25))
	var v := sl * hgt if ps == 0 else off
	if ps == 0 and SUN_A < 0.01: return off
	var pts := PackedVector2Array()
	for i in 16:
		var q := Vector2(x, y) + Vector2.from_angle(i * TAU / 16) * r
		pts.append(q); pts.append(q + v)
	g.poly(_hull(pts), Color(0, 0, 0, 0.36 * SUN_A) if ps == 0 else wall)
	return off

static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 3: h.resize(h.size() - 1)   # convex_hull repeats the first point at the end
	return h

# =====================================================================
# shared
# =====================================================================
## Position of a named point ("prop", "prop0", "prop1", "tipL", "tipR", "tail") on a pre-rendered plane
## at this bank (-1..1) and pitch (0..1), in sprite units, blended between frames like the sprite is;
## null if the plane has no data for that point. Twins have one hub per engine, "prop0" (port) and "prop1".
static func plane_pt(P: Dictionary, nm: String, bank: float, pitch: float):
	var d = Tx.PPTS.get(P.name)
	if d == null or not d.pts.has(nm): return null
	var nb: int = int(d.banks)
	var np: int = d.pitches.size()
	var arr: Array = d.pts[nm]
	var fi := (clampf(bank, -1, 1) + 1) * 0.5 * (nb - 1)
	var pr := clampf(pitch, 0, 1) * (np - 1)
	var i0 := clampi(int(floor(fi)), 0, nb - 1)
	var i1 := mini(i0 + 1, nb - 1)
	var r0 := clampi(int(floor(pr)), 0, np - 1)
	var r1 := mini(r0 + 1, np - 1)
	var at := func(r: int, i: int) -> Vector2: return Vector2(arr[r * nb + i][0], arr[r * nb + i][1])
	var a: Vector2 = at.call(r0, i0).lerp(at.call(r0, i1), fi - i0)
	var b: Vector2 = at.call(r1, i0).lerp(at.call(r1, i1), fi - i0)
	return a.lerp(b, pr - r0)

## How much bigger the plane draws at this altitude: 1 + alt/130, times the plane's "top_k"
## (D.PLANES) phased in linearly up to the top altitude, so the size on the runway is unchanged.
## On top of that the plane is pulled up toward the camera (Greg, 2026-10-18): PLANE_LIFT times
## bigger from LIFT_ALT up, eased in from the ground. The shadow and the altimeter don't change.
const PLANE_LIFT := 1.5   # 2.0 at first; Greg: 1.5
const LIFT_ALT := 100.0   # cruise speed climbs to 100
static func plane_grow(P: Dictionary, alt: float) -> float:
	var k: float = lerpf(1.0, P.get("top_k", 1.0), clampf(alt / TREE_FADE_ALT, 0, 1))
	return (1 + alt / 130.0) * k * lerpf(1.0, PLANE_LIFT, smoothstep(0.0, LIFT_ALT, alt))

static func draw_plane(g: Pen, P: Dictionary, size: float, prop: float, shadow: bool, bank: float = 0.0, pitch: float = 0.0) -> void:
	g.save()
	g.scale(size, size)
	if shadow: g.ga *= 0.3
	var rows: Array = Tx.PBANK.get(P.name, [])
	if rows.size() > 0:
		var n: int = rows[0].size() - 1
		var fi := (clampf(bank, -1, 1) + 1) * 0.5 * n
		var pr := clampf(pitch, 0, 1) * (rows.size() - 1)
		var r0 := clampi(int(floor(pr)), 0, rows.size() - 1)
		if shadow:
			g.tex(rows[roundi(pr)][clampi(roundi(fi), 0, n)], -0.64, -0.64, 1.28, 1.28, Color.BLACK)
		else:   # blend the two nearest bank frames, then fade in the next pitch row, so nothing steps
			var i0 := clampi(int(floor(fi)), 0, n)
			var i1 := mini(i0 + 1, n)
			g.tex(rows[r0][i0], -0.64, -0.64, 1.28, 1.28)
			if i1 != i0 and fi - i0 > 0.02: g.tex(rows[r0][i1], -0.64, -0.64, 1.28, 1.28, Color(1, 1, 1, fi - i0))
			if r0 + 1 < rows.size() and pr - r0 > 0.02:
				g.tex(rows[r0 + 1][clampi(roundi(fi), 0, n)], -0.64, -0.64, 1.28, 1.28, Color(1, 1, 1, pr - r0))
	else:
		if bank != 0.0: g.scale(1, 1 - absf(bank) * 0.18)
		g.tex(Tx.PSPR.get(P.name + ("_s" if shadow else "")), -0.64, -0.64, 1.28, 1.28)
	if not shadow:
		for k in P.props.size():   # [x, y, radius] per propeller, set per airframe in D.PLANES
			var b: Array = P.props[k]
			# the prop hub moves with the frame as the plane banks and pitches
			var hub = plane_pt(P, "prop%d" % k, bank, pitch)
			if hub == null: hub = plane_pt(P, "prop", bank, pitch)
			var bx: float = b[0] if hub == null else hub.x
			var by: float = b[1] if hub == null else hub.y
			var br: float = b[2]
			g.ellipse(bx, by, 0.025, br, 0, Color(225 / 255.0, 225 / 255.0, 215 / 255.0, 0.13))
			g.line(bx, by + sin(prop) * (br - 0.01), bx, by - sin(prop) * (br - 0.01), Color(30 / 255.0, 30 / 255.0, 30 / 255.0, 0.7), 0.016)
			g.circle(bx, by, 0.018, hc("#2a2a2a"))
	g.restore()

static func vignette(gm, g: Pen, alpha: float) -> void:
	var m: float = maxf(gm.Wv, gm.Hv)
	g.ga = alpha
	g.radial(gm.Wv / 2, gm.Hv / 2, [[m * 0.32, Color(0, 0, 0, 0)], [m * 0.78, Color(0, 0, 0, 1)]], 40)
	g.ga = 1.0

static func vignette_red(gm, g: Pen, alpha: float) -> void:
	var m: float = maxf(gm.Wv, gm.Hv)
	g.ga = alpha
	g.radial(gm.Wv / 2, gm.Hv / 2, [[m * 0.25, rgba(150, 0, 0, 0)], [m * 0.7, rgba(150, 0, 0, 1)]], 40)
	g.ga = 1.0

static func grade(gm, g: Pen) -> void:
	if gm.G == null: return
	g.set_xf(Transform2D.IDENTITY)
	var ox := randf() * 160
	var oy := randf() * 160
	g.ga = 0.1
	g.ci.draw_texture_rect(Tx.GRAIN, Rect2(-ox, -oy, gm.Wv + 160, gm.Hv + 160), true, Color(1, 1, 1, 0.1))
	g.ga = 1.0
	update_grade(gm)

## The time-of-day colour grade (shaders/grade.gdshader), a screen-wide pass after layer 2 and
## its sub-layers, so it covers the world but not the HUD. Looks by hour: [hour, shadow tint,
## highlight tint, saturation, contrast, exposure]; the hours in between blend.
const GRADES := [
	[0.0, Color(0.92, 0.96, 1.1), Color(0.9, 0.95, 1.08), 0.72, 1.0, 1.0],     # night
	[4.5, Color(0.92, 0.96, 1.1), Color(0.9, 0.95, 1.08), 0.72, 1.0, 1.0],
	[6.3, Color(0.93, 0.95, 1.08), Color(1.12, 0.97, 0.84), 0.9, 1.04, 1.03],   # sunrise: cool shade, warm light
	[8.5, Color(0.98, 0.99, 1.03), Color(1.05, 1.0, 0.93), 1.0, 1.04, 1.02],    # morning
	[12.0, Color(0.99, 1.0, 1.02), Color(1.02, 1.01, 0.98), 1.04, 1.06, 1.03],  # noon: bright and clear
	[15.5, Color(0.99, 0.99, 1.02), Color(1.05, 1.0, 0.92), 1.04, 1.05, 1.02],
	[17.6, Color(0.95, 0.94, 1.05), Color(1.16, 0.98, 0.78), 1.1, 1.06, 1.03],  # golden hour
	[19.0, Color(0.9, 0.92, 1.1), Color(1.05, 0.9, 0.92), 0.82, 1.02, 0.98],    # dusk: cold, pink light
	[20.5, Color(0.92, 0.96, 1.1), Color(0.9, 0.95, 1.08), 0.72, 1.0, 1.0],
	[24.0, Color(0.92, 0.96, 1.1), Color(0.9, 0.95, 1.08), 0.72, 1.0, 1.0],
]
static var GRADE_MAT: ShaderMaterial
static func update_grade(gm) -> void:
	var l2 = gm.layers[2]
	var rc: ColorRect = l2.get_node_or_null("Grade")
	if rc == null:
		GRADE_MAT = ShaderMaterial.new()
		GRADE_MAT.shader = load("res://shaders/grade.gdshader")
		rc = ColorRect.new()
		rc.name = "Grade"
		rc.material = GRADE_MAT
		rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l2.add_child.call_deferred(rc)   # after the roof layers (20, 21), so it is drawn over them
	rc.visible = true
	rc.size = Vector2(gm.Wv, gm.Hv)
	var h := fmod(gm.G.time / 60.0, 24.0)
	var i := 0
	while i < GRADES.size() - 2 and h >= GRADES[i + 1][0]: i += 1
	var a: Array = GRADES[i]
	var b: Array = GRADES[i + 1]
	var t := smoothstep(0.0, 1.0, (h - a[0]) / (b[0] - a[0]))
	var wet := 0.0
	if gm.mode == "flight" and gm.F: wet = gm.F.storm
	elif gm.mode == "ground" and gm.S: wet = gm.S.rain
	GRADE_MAT.set_shader_parameter("shadow_tint", (a[1] as Color).lerp(b[1], t))
	GRADE_MAT.set_shader_parameter("high_tint", (a[2] as Color).lerp(b[2], t).lerp(Color(0.97, 0.99, 1.02), wet * 0.6))
	GRADE_MAT.set_shader_parameter("sat", lerpf(a[3], b[3], t) * (1.0 - wet * 0.3))
	GRADE_MAT.set_shader_parameter("con", lerpf(a[4], b[4], t))
	GRADE_MAT.set_shader_parameter("expo", lerpf(a[5], b[5], t))

static func draw_objective(gm, g: Pen, y: float) -> void:
	var txt: String = gm.menu.objective()
	var BW: float = gm.Wv - 24
	if gm.mode == "flight" and gm.F:
		var nt = gm.flight.nav_target()
		if nt:
			var F: Dictionary = gm.F
			var d := Vector2(nt.x - F.x, nt.y - F.y).length()
			var q := rad_to_deg(U.ang_diff(atan2(nt.y - F.y, nt.x - F.x), F.hdg))
			txt += " %d km, %s%s." % [U.km(d), "straight ahead" if absf(q) < 12 else ("turn right" if q > 0 else "turn left"), ", not enough fuel" if d > memo(gm, "range") else ""]
	var lines: Array = [txt]
	if Pen.measure(txt, 12) + 40 > BW:
		var ws := txt.split(" ")
		var a := ""
		for i in ws.size():
			var tr := (a + " " + ws[i]) if a != "" else ws[i]
			if Pen.measure(tr, 12) + 40 > BW and a != "":
				lines = [a, " ".join(ws.slice(i))]
				break
			a = tr
	var mw := 0.0
	for l in lines: mw = maxf(mw, Pen.measure(l, 12))
	var w := minf(BW, mw + 40)
	var hh := 40.0 if lines.size() > 1 else 24.0
	g.rr(10, y, w, hh, 5, rgba(60, 14, 40, 0.78))
	g.poly(PackedVector2Array([Vector2(21, y + 6), Vector2(26, y + 12), Vector2(21, y + 18), Vector2(16, y + 12)]), hc("#f0c4dd"))
	for i in lines.size():
		g.text(lines[i], 32, y + 12 + i * 16, 12, hc("#f6e8ef"), -1, "600", 0, Color.BLACK, w - 38)
	# mayday: its own bright red line under your destination, for as long as it lasts
	var mt = gm.flight.mayday_target() if (gm.mode == "flight" and gm.F) else null
	if mt:
		var F: Dictionary = gm.F
		var md := Vector2(mt.x - F.x, mt.y - F.y).length()
		var mq := rad_to_deg(U.ang_diff(atan2(mt.y - F.y, mt.x - F.x), F.hdg))
		var mtxt := "MAYDAY at %s, %d min left. %d km, %s%s." % [mt.name, maxi(0, int(round(gm.G.mayday.until - gm.G.time))), U.km(md),
			"straight ahead" if absf(mq) < 12 else ("turn right" if mq > 0 else "turn left"), ", not enough fuel" if md > memo(gm, "range") else ""]
		var my2 := y + hh + 6
		var mw2 := minf(BW, Pen.measure(mtxt, 12) + 40)
		var flash := 0.5 + 0.5 * sin(gm.T * 6)
		g.rr(10, my2, mw2, 24, 5, rgba(130, 10, 10, 0.82))
		g.poly(PackedVector2Array([Vector2(21, my2 + 6), Vector2(26, my2 + 12), Vector2(21, my2 + 18), Vector2(16, my2 + 12)]), rgba(255, 70 + 80 * flash, 60, 1))
		g.text(mtxt, 32, my2 + 12, 12, hc("#ffe3df"), -1, "700", 0, Color.BLACK, mw2 - 38)

# =====================================================================
# flight world
# =====================================================================
static func draw_world(gm, g: Pen, cx: float, cy: float, sc: float, t: float) -> Dictionary:
	var W: float = gm.Wv
	var H: float = gm.Hv
	var wd: World = gm.wd
	if gm.mode != "flight":   # the title screen's drifting map: no time-of-day grade
		var gr = gm.layers[2].get_node_or_null("Grade")
		if gr: gr.visible = false
	g.set_xf(Transform2D.IDENTITY)
	g.rect(0, 0, W, H, hc(SEA))
	var x0 := cx - W / 2 / sc
	var x1 := cx + W / 2 / sc
	var y0 := cy - H / 2 / sc
	var y1 := cy + H / 2 / sc
	g.set_view(sc, W / 2 - cx * sc, H / 2 - cy * sc)
	set_view3d(gm, cx, cy, sc)
	_tb_init()
	# terrain detail fades in near the ground (flight view only)
	var dt := clampf((sc - 0.85) / 0.5, 0, 1) if gm.mode == "flight" else 0.0
	if dt > 0.0:
		if g.ci.material != TREE_MAT: g.ci.material = TREE_MAT
		TREE_MAT.set_shader_parameter("detail", dt)
		TREE_MAT.set_shader_parameter("seed", wd.SEED)
		TREE_MAT.set_shader_parameter("sun_dir", SUN_DIR)
		TREE_MAT.set_shader_parameter("sun_a", SUN_A)
		TREE_MAT.set_shader_parameter("chunk_w", CH + 1)
	var ov: Texture2D = gm.baker.overview
	if ov:
		var opx := float(ov.get_width())
		var k := opx / D.WORLD
		var sx := clampf(x0 * k - 1, 0, opx - 1)
		var sy := clampf(y0 * k - 1, 0, opx - 1)
		var sw := clampf((x1 - x0) * k + 2, 1, opx - sx)
		var sh := clampf((y1 - y0) * k + 2, 1, opx - sy)
		g.tex_region(ov, Rect2(sx / k, sy / k, sw / k, sh / k), Rect2(sx, sy, sw, sh))
	# terrain chunks cover the land and the whole ocean margin around it
	var cmin := int(floor(-gm.OCEAN_PAD / CH)) - 2
	var cmax := int(floor((D.WORLD + gm.OCEAN_PAD) / CH)) + 2
	for gy in range(int(floor(y0 / CH)), int(floor(y1 / CH)) + 1):
		for gx in range(int(floor(x0 / CH)), int(floor(x1 / CH)) + 1):
			if gx < cmin or gy < cmin or gx > cmax or gy > cmax: continue
			var c: Texture2D = gm.baker.get_chunk(gx, gy)
			if c == null: continue
			if dt > 0.0: _detail_chunk(g, c, gx, gy)
			else: g.tex(c, gx * CH, gy * CH, CH + 1, CH + 1)
	var sf := clampf((sc - 0.5) / 0.22, 0, 1)
	if gm.mode == "flight" and gm.F:   # trees at every zoom, their alpha set by altitude
		draw_scatter(gm, g, x0, y0, x1, y1, sf, t, tree_fade(gm.F.alt))
	elif sc > 0.512:
		draw_scatter(gm, g, x0, y0, x1, y1, sf, t, sf)
	var tgt = gm.flight.nav_target() if (gm.mode == "flight" and gm.G and gm.F) else null
	var mdt = gm.flight.mayday_target() if (gm.mode == "flight" and gm.G and gm.F) else null
	for s in wd.strips:
		if s.x < x0 - 800 or s.x > x1 + 800 or s.y < y0 - 800 or s.y > y1 + 800: continue
		draw_strip(gm, g, s)
		if tgt != null and s.id == tgt.id:
			var pl := 0.5 + 0.5 * sin(t * 3)
			g.dashed_arc(s.x, s.y, s.len / 2 + 90 + pl * 20, 0, TAU, rgba(242, 182, 74, 0.45 + 0.4 * pl), 4 / sc, 18 / sc, 12 / sc)
		if mdt != null and s.id == mdt.id:
			var pm := 0.5 + 0.5 * sin(t * 6)
			g.dashed_arc(s.x, s.y, s.len / 2 + 150 + pm * 25, 0, TAU, rgba(255, 40, 30, 0.55 + 0.45 * pm), 5 / sc, 18 / sc, 12 / sc)
	draw_smoke(gm, g, x0, y0, x1, y1, t)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1}

static func draw_strip(gm, g: Pen, s: Dictionary) -> void:
	if s.type == "road": return
	var wd: World = gm.wd
	var F = gm.F
	g.save()
	g.translate(s.x, s.y)
	g.rotate(s.ang)
	var L: float = s.len
	var Wd: float = s.wid
	var sid: int = s.id
	var h0 := U.hash3(sid, 1, wd.SEED + 5)
	var cl := (Vector2(PV.x, PV.y) - Vector2(s.x, s.y)).rotated(-s.ang)
	var sl := SUN.rotated(-s.ang)
	g.rr(-L / 2 - 90, -Wd / 2 - 60, L + 180, Wd + 210, 40, rgba(150, 170, 100, 0.13))
	if F and F.alt < 70 and gm.known.has(sid):
		var pc := rgba(212, 90, 157, 0.45)
		g.dashed(-L / 2 - 900, 0, -L / 2 - 30, 0, pc, 3, 24, 18)
		g.dashed(L / 2 + 30, 0, L / 2 + 900, 0, pc, 3, 24, 18)
	if s.get("failsafe", false):
		Failsafe.draw_air(gm, g, s)
		g.restore()
		return
	if s.get("arch", "") == "family":
		FarmFolk.draw_air(gm, g, s, L, Wd)
		g.restore()
		return
	var dirt: bool = s.type == "dirt"
	var hav: bool = s.type == "haven"
	if not dirt:
		g.rect(-L / 4 - 10, Wd / 2, 34, 20, hc("#46443f"))
		g.rect(-L / 4 - 40, Wd / 2 + 18, 200, 56, hc("#46443f"))
	g.rect(-L / 2 - 6, -Wd / 2 - 6, L + 12, Wd + 12, rgba(20, 20, 16, 0.28))
	g.rect(-L / 2, -Wd / 2, L, Wd, hc("#3e4644") if hav else (hc("#8a7550") if dirt else hc("#3c3b38")))
	if dirt:
		g.rect(-L / 2, -6, L, 3, rgba(60, 45, 25, 0.3)); g.rect(-L / 2, 4, L, 3, rgba(60, 45, 25, 0.3))
		var x := -L / 2
		while x <= L / 2 + 0.01:
			g.rect(x - 3, -Wd / 2 - 6, 6, 4, rgba(240, 235, 220, 0.85)); g.rect(x - 3, Wd / 2 + 2, 6, 4, rgba(240, 235, 220, 0.85))
			x += L / 6
	else:
		var wc := hc("#e2dbc6")
		var x := -L / 2 + 50
		while x < L / 2 - 50:
			g.rect(x, -1.5, 24, 3, wc)
			x += 46
		for i in range(-3, 4):
			g.rect(-L / 2 + 8, i * Wd / 8 - 1.5, 26, 3, wc); g.rect(L / 2 - 34, i * Wd / 8 - 1.5, 26, 3, wc)
		for i in 8:
			g.rect(-L / 2 + 60 + U.hash3(sid, i, 3) * (L - 120), -Wd / 4 + U.hash3(i, sid, 4) * Wd / 2, 30, 4, Color(0, 0, 0, 0.25))
	var nh := 4 if hav else (3 if s.type == "airport" else (2 if s.type == "regional" else 1))
	for j in nh * 2:   # all shadows, then all hangars
		var ps := 0 if j < nh else 1
		var i := j % nh
		var hx := -L / 4 - 30 + i * 72
		var hy := Wd / 2 + (22.0 if dirt else 26.0)
		var hw := 60.0
		var hh := 38.0 if dirt else 46.0
		var rc: Array = ["#8a9a86", "#5d6b5a"] if hav else (["#8a8378", "#5a544b"] if U.hash3(sid, i, 9) < 0.5 else ["#8a5a44", "#5a3a2c"])
		var ho := draw_box3d(g, ps, hx, hy, hw, hh, HANGAR_H, cl, sl, U.shade(hc(rc[1]), 0.62))
		if ps == 0: continue
		hx += ho.x; hy += ho.y
		g.rect(hx, hy, hw, hh / 2, hc(rc[0])); g.rect(hx, hy + hh / 2, hw, hh / 2, hc(rc[1]))
		g.rect(hx, hy + hh / 2 - 1, hw, 2, Color(1, 1, 1, 0.15))
		if U.hash3(sid, i, 11) < 0.3 and not hav: g.circle(hx + hw * 0.6, hy + hh * 0.4, 10, rgba(20, 16, 12, 0.7))
	if s.fuel and not hav:
		for i in 2:
			var fx := L / 4 + 10 + i * 26
			var fy := Wd / 2 + 40
			draw_cyl3d(g, 0, fx, fy, 11, TANK_H, cl, sl, Color.BLACK)
		for i in 2:
			var fx := L / 4 + 10 + i * 26
			var fy := Wd / 2 + 40
			var to := draw_cyl3d(g, 1, fx, fy, 11, TANK_H, cl, sl, hc("#7c776d"))
			g.circle(fx + to.x, fy + to.y, 11, hc("#b4aea2")); g.circle(fx + to.x - 3, fy + to.y - 3, 5, hc("#e2dccf"))
		g.rect(L / 4 + 60, Wd / 2 + 30, 10, 14, hc("#a3301f"))
	if hav:
		var x := -L / 2
		while x <= L / 2:
			g.rect(x - 3, -Wd / 2 - 8, 6, 6, hc("#9cc063")); g.rect(x - 3, Wd / 2 + 2, 6, 6, hc("#9cc063"))
			x += 40
		g.rect(-40, -Wd / 2 - 120, 80, 80, hc("#6f7a6a"))
		g.stroke_rr(-L / 2 - 70, -Wd / 2 - 150, L + 140, Wd + 300, 30, rgba(200, 200, 190, 0.6), 3)
	if not hav:
		var tx := L / 2 + 200
		var ty := Wd / 2 + 160
		var rdc := hc("#46443f")
		g.rect(tx - 190, ty - 7, 380, 14, rdc); g.rect(tx - 7, ty - 130, 14, 260, rdc); g.rect(-L / 4 + 20, Wd / 2 + 62, tx - (-L / 4 + 20), 8, rdc)
		var hkey := Vector2i(sid, wd.SEED)
		var hl: Array = HOUSES.get(hkey, [])
		if hl.is_empty():
			# town houses, worked out once per airfield: [x, y, w, h, roof lit, roof shade]
			var hi := [0]
			var add := func(hx: float, hy: float, hw: float, hh: float) -> void:
				hi[0] += 1
				var i: int = hi[0]
				if U.hash3(sid, i, 46) < 0.18: return
				var rc := hc(D.HOUSEROOF[int(U.hash3(i, sid, 45) * D.HOUSEROOF.size())])
				hl.append([hx - hw / 2, hy - hh / 2, hw, hh, U.shade(rc, 1.15), U.shade(rc, 0.68)])
			for k in range(-5, 6):
				if k == 0: continue
				var hx := tx + k * 34
				var w1 := 24 + U.hash3(sid, k, 47) * 8
				add.call(hx, ty - 26, w1, 22.0); add.call(hx, ty + 26, w1, 22.0)
			for k in range(-3, 4):
				if k == 0: continue
				var hy := ty + k * 34
				add.call(tx - 26, hy, 22.0, 24.0); add.call(tx + 26, hy, 22.0, 24.0)
			HOUSES[hkey] = hl
		var wallc := hc("#6e6458")
		for hs in hl:   # all shadows first, then all houses
			draw_box3d(g, 0, hs[0], hs[1], hs[2], hs[3], HOUSE_H, cl, sl, wallc)
		for hs in hl:
			var o := draw_box3d(g, 1, hs[0], hs[1], hs[2], hs[3], HOUSE_H, cl, sl, wallc)
			var hx: float = hs[0] + o.x
			var hy: float = hs[1] + o.y
			var hw: float = hs[2]
			var hh: float = hs[3]
			if hw >= hh:
				g.rect(hx, hy, hw, hh / 2, hs[4]); g.rect(hx, hy + hh / 2, hw, hh / 2, hs[5])
			else:
				g.rect(hx, hy, hw / 2, hh, hs[4]); g.rect(hx + hw / 2, hy, hw / 2, hh, hs[5])
	if h0 < 0.35 and not hav:
		g.save(); g.translate(L / 2 + 50, -Wd / 2 - 40); g.rotate(h0 * 9)
		g.ga = 0.85
		draw_plane(g, D.PLANES[int(h0 * 10) % 2], 30, 0, false)
		g.circle(2, 4, 9, rgba(20, 14, 10, 0.6))
		g.restore()
	var wx := -L / 2 + 40
	var wy := -Wd / 2 - 26
	var wa: float = (atan2(F.wind.y, F.wind.x) - s.ang) if F else 0.6
	g.circle(wx, wy, 2.5, hc("#dddddd"))
	g.save(); g.translate(wx, wy); g.rotate(wa + sin(gm.T * 3) * 0.08)
	g.poly(PackedVector2Array([Vector2(0, -4), Vector2(22, -2), Vector2(22, 2), Vector2(0, 4)]), hc("#ff7a2a"))
	g.rect(8, -3, 4, 6, Color.WHITE)
	g.restore()
	g.restore()

static func draw_smoke(gm, g: Pen, x0: float, y0: float, x1: float, y1: float, t: float) -> void:
	var C := 2600.0
	var wd: World = gm.wd
	for cy in range(int(floor((y0 - 500) / C)), int(floor((y1 + 300) / C)) + 1):
		for cx in range(int(floor((x0 - 500) / C)), int(floor((x1 + 300) / C)) + 1):
			if U.hash3(cx, cy, wd.SEED + 77) > 0.24: continue
			var sx := (cx + 0.2 + U.hash3(cx, cy, wd.SEED + 78) * 0.6) * C
			var sy := (cy + 0.2 + U.hash3(cx, cy, wd.SEED + 79) * 0.6) * C
			var ck := -(cx * 100003 + cy) - 7
			var v = gm.TCACHE.get(ck)
			if v == null:
				v = wd.terr(sx, sy) > 2
				gm.TCACHE[ck] = v
			if not v: continue
			draw_wildfire(g, sx, sy, t, U.hash3(cx, cy, 5))
	# the same fires at disputed fields (fields.gd), 3-5 on and round the strip
	for s in wd.strips:
		if not s.get("cleared", false) or s.x < x0 - 800 or s.x > x1 + 800 or s.y < y0 - 800 or s.y > y1 + 800: continue
		var ci := 0
		for p in Fields.camps(s):
			draw_wildfire(g, p.x, p.y, t, U.hash3(int(s.id), ci, 5))
			ci += 1

## One of the fires burning out on the map: flame and its smoke plume (ph staggers the puffs).
static func draw_wildfire(g: Pen, sx: float, sy: float, t: float, ph: float) -> void:
	g.circle(sx, sy, 6 + randf() * 3, rgba(255, 120 + randf() * 60, 40, 0.8))
	for i in 8:
		var k := fmod(t * 0.07 + i / 8.0 + ph, 1.0)
		g.circle(sx + k * 300, sy - k * 170, 16 + k * 95, rgba(46, 44, 42, 0.38 * (1 - k)))

static func draw_clouds(gm, g: Pen, cx: float, cy: float, sc: float, alpha: float) -> void:
	var C := 1700.0
	var W: float = gm.Wv
	var H: float = gm.Hv
	var seed_v: int = gm.wd.SEED
	# every cloud's puffs (x, y, radius) are worked out once per cell and kept in CLOUD_CELLS
	if CLOUD_SEED != seed_v:
		CLOUD_CELLS.clear(); CLOUD_SEED = seed_v
	var clouds_in := func(s2: float, pad: float, tex: Texture2D, off: Vector2, col: Color) -> void:
		var x0 := cx - W / 2 / s2 - pad
		var x1 := cx + W / 2 / s2 + pad
		var y0 := cy - H / 2 / s2 - pad
		var y1 := cy + H / 2 / s2 + pad
		for gy in range(int(floor(y0 / C)), int(floor(y1 / C)) + 1):
			for gx in range(int(floor(x0 / C)), int(floor(x1 / C)) + 1):
				var key := Vector2i(gx, gy)
				var pf = CLOUD_CELLS.get(key)
				if pf == null:
					pf = PackedFloat32Array()
					if U.hash3(gx, gy, seed_v + 91) <= CLOUD_DENSITY:
						var bx := (gx + U.hash3(gx, gy, seed_v + 92)) * C
						var by := (gy + U.hash3(gx, gy, seed_v + 93)) * C
						for i in 6:
							var a := U.hash3(gx * 7 + i, gy, seed_v + 94) * TAU
							var r := U.hash3(gx, gy * 7 + i, seed_v + 95)
							pf.append(bx + cos(a) * r * 150); pf.append(by + sin(a) * r * 85); pf.append(90 + r * 110)
					if CLOUD_CELLS.size() > 400: CLOUD_CELLS.clear()
					CLOUD_CELLS[key] = pf
				for i in range(0, pf.size(), 3):
					var rad: float = pf[i + 2]
					g.ci.draw_texture_rect(tex, Rect2(pf[i] + off.x - rad, pf[i + 1] + off.y - rad, rad * 2, rad * 2), false, col)
	g.set_view(sc, W / 2 - cx * sc, H / 2 - cy * sc)
	var cs := SUN * CLOUD_SHADOW
	var sa := 0.13 * SUN_A
	if sa > 0.005: clouds_in.call(sc, 800.0 + cs.length(), Tx.SPUFF, cs, Color(1, 1, 1, sa))
	if alpha > 0.01:
		var s2 := sc * 1.3
		g.set_view(s2, W / 2 - cx * s2, H / 2 - cy * s2)
		clouds_in.call(s2, 400.0, Tx.PUFF, Vector2.ZERO, Color(1, 1, 1, minf(1, alpha * 2.6)))
	g.ga = 1.0

## Every storm's centre this frame (World.storm_pos keeps them all) and radius, as packed
## arrays, so the storm loops skip the far ones cheaply.
static var STORM_R := PackedFloat32Array()
static var STORM_L = null
static func storms_now(wd) -> PackedVector2Array:
	if wd.STORMS.is_empty(): return PackedVector2Array()
	wd.storm_pos(wd.STORMS[0])
	if not is_same(STORM_L, wd.STORMS) or STORM_R.size() != wd.STORMS.size():
		STORM_L = wd.STORMS
		STORM_R.resize(wd.STORMS.size())
		for i in wd.STORMS.size(): STORM_R[i] = wd.STORMS[i].r
	return wd._sp
static var CLOUD_CELLS := {}
static var CLOUD_SEED := -1
static var storm_imgs := {}
static var STORM_PUFFS := {}   # a storm's 11 puffs (angle, distance, radius) by its size and the seed
static func draw_storms(gm, g: Pen, cx: float, cy: float, sc: float) -> void:
	var s2 := sc * 1.3
	var W: float = gm.Wv
	var H: float = gm.Hv
	g.set_view(s2, W / 2 - cx * s2, H / 2 - cy * s2)
	var hw := W / 2 / s2
	var hh := H / 2 / s2
	var fade := 1 - clampf((gm.F.storm if gm.F else 0.0) * 1.6, 0, 0.85)
	var seed_v: int = gm.wd.SEED
	var sps := storms_now(gm.wd)
	for si in sps.size():
		var q: Vector2 = sps[si]
		var E: float = STORM_R[si] * 1.3
		if q.x + E < cx - hw or q.x - E > cx + hw or q.y + E < cy - hh or q.y - E > cy + hh: continue
		var s: Dictionary = gm.wd.STORMS[si]
		g.ga = fade * 0.6
		var ri := int(s.r)
		var pk := Vector2i(ri, seed_v)
		var pf = STORM_PUFFS.get(pk)
		if pf == null:
			pf = PackedFloat32Array()
			for i in 11:
				var a := U.hash3(i, ri, seed_v + 61) * TAU
				var d: float = U.hash3(i, 7, ri) * s.r * 0.6
				var rad: float = s.r * (0.34 + U.hash3(i, 3, ri) * 0.34)
				pf.append(cos(a) * d - rad); pf.append(sin(a) * d - rad); pf.append(rad * 2)
			STORM_PUFFS[pk] = pf
		var sc0 := Color(1, 1, 1, g.ga)
		for i in range(0, pf.size(), 3):
			g.ci.draw_texture_rect(Tx.DPUFF, Rect2(q.x + pf[i], q.y + pf[i + 1], pf[i + 2], pf[i + 2]), false, sc0)
		if randf() < 0.03:
			var a := randf() * TAU
			var d: float = randf() * s.r * 0.5
			var rad: float = s.r * 0.45
			g.ga = 0.35 * fade
			g.tex(Tx.LPUFF, q.x + cos(a) * d - rad, q.y + sin(a) * d - rad, rad * 2, rad * 2)
	g.ga = 1.0

# =====================================================================
# flight frame
# =====================================================================
static func prep_flight(gm) -> void:
	var F: Dictionary = gm.F
	var lx: float = F.x + cos(F.hdg) * F.spd * 0.9
	var ly: float = F.y + sin(F.hdg) * F.spd * 0.9
	if gm.cam_snap:
		gm.camX = lx; gm.camY = ly; gm.cam_snap = false
	else:
		var cf := 1.0 - pow(0.92, minf(gm.get_process_delta_time(), 0.2) * 60.0)
		gm.camX = lerpf(gm.camX, lx, cf); gm.camY = lerpf(gm.camY, ly, cf)
	# prefetch chunks ahead of the plane
	var ax: float = F.x + cos(F.hdg) * 1500
	var ay: float = F.y + sin(F.hdg) * 1500
	for o in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var gx = int(floor(ax / CH)) + o[0]
		var gy = int(floor(ay / CH)) + o[1]
		if gx < -1 or gy < -1 or gx > 30 or gy > 30: continue
		if not gm.baker.has_chunk(gx, gy):
			gm.baker.get_chunk(gx, gy)
			break
	prefetch_scatter(gm, gm.camX, gm.camY, flight_scale(gm, F.alt), F.hdg)

static func flight_layer(gm, idx: int, g: Pen) -> void:
	var F: Dictionary = gm.F
	var P: Dictionary = gm.PS()
	var sc := flight_scale(gm, F.alt)
	var alt := maxf(0.0, F.alt)
	var W: float = gm.Wv
	var H: float = gm.Hv
	match idx:
		0:
			var vb := draw_world(gm, g, gm.camX, gm.camY, sc, gm.T)
			gm.set_meta("vb", vb)
			draw_fog(gm, g, gm.camX, gm.camY, sc, alt)
			var grow := plane_grow(P, alt)
			var psd := Vector2.from_angle(SUN_ANG) * alt * 1.31
			var sh := plane_shadow(gm, F, psd, P.size * 1.7)
			g.save(); g.translate(sh.x, sh.y); g.rotate(F.hdg); draw_plane(g, P, P.size * 1.7 * sh.z, 0, true, F.bank, F.get("pitch", 0.0)); g.restore()
			g.save(); g.translate(F.x, F.y); g.rotate(F.hdg); draw_plane(g, P, P.size * 1.7 * grow, F.prop, false, F.bank, F.get("pitch", 0.0)); g.restore()
			if not F.onGround and not F.crashed and (F.vs < -0.5 or F.alt < 30):
				var pt = memo(gm, "touchdown")
				if pt and pt.t < 45:
					var s = gm.wd.strip_at(pt.x, pt.y, 1)
					var c := hc("#d9a441")
					if pt.vs <= -15: c = hc("#e3644c")
					else:
						var ok: bool = s != null and gm.flight.align_to(s.ang, F.trk)
						if not ok:
							var rd = gm.wd.road_at(pt.x, pt.y)
							ok = rd != null and gm.flight.align_to(rd.r.ang, F.trk)
						if ok: c = hc("#9cc063")
					var q := 11 / sc
					var cl := c
					cl.a = 0.55
					g.dashed(F.x + psd.x, F.y + psd.y, pt.x, pt.y, cl, 2 / sc, 6 / sc, 7 / sc)
					for k in 2:
						var lw := (2.5 if k else 3.5) / sc
						var col: Color = c if k else Color(0, 0, 0, 0.6)
						g.lines(PackedVector2Array([Vector2(pt.x - q, pt.y - q), Vector2(pt.x + q, pt.y + q), Vector2(pt.x + q, pt.y - q), Vector2(pt.x - q, pt.y + q)]), col, lw)
						g.ring(pt.x, pt.y, q * 1.7, col, lw)
			if F.crashed:
				for i in 14:
					var a := randf() * TAU
					var r: float = randf() * P.size * 0.8
					g.circle(F.x + cos(a) * r, F.y + sin(a) * r, P.size * (0.15 + randf() * 0.3), rgba(255, 120 + randf() * 90, 40, 0.7) if i % 3 else rgba(30, 26, 24, 0.6))
			var tlw := maxf(2, 2.5 / sc)
			for tr in F.tracers:
				var a: float = tr.life / 0.35
				g.line(tr.x + (tr.tx - tr.x) * (1 - a), tr.y + (tr.ty - tr.y) * (1 - a), tr.x + (tr.tx - tr.x) * minf(1, 1.3 - a), tr.y + (tr.ty - tr.y) * minf(1, 1.3 - a), rgba(255, 190, 90, a), tlw)
			var ai = memo(gm, "approach")
			if ai and ai.phase != "high" and ai.slack > -200:
				var pl := 0.5 + 0.5 * sin(gm.T * 5)
				var nx: float = -ai.cy
				var ny: float = ai.cx
				var now: bool = ai.phase == "now"
				var col := rgba(255, 224, 120, 0.6 + 0.3 * pl) if now else rgba(240, 160, 210, 0.55)
				var GW := maxf(70, 20 / sc)
				var tdx: float = ai.s.x + ai.cx * (-ai.s.len / 2 + ai.s.len * 0.22)
				var tdy: float = ai.s.y + ai.cy * (-ai.s.len / 2 + ai.s.len * 0.22)
				g.dashed(ai.px, ai.py, tdx, tdy, col, 1.5 / sc, 8 / sc, 10 / sc)
				g.line(ai.px - nx * GW, ai.py - ny * GW, ai.px + nx * GW, ai.py + ny * GW, col, 3 / sc)
				g.save(); g.translate(ai.px + nx * (GW + 12 / sc), ai.py + ny * (GW + 12 / sc)); g.scale(1 / sc, 1 / sc)
				g.text("Start down" if now else "Descend here", 0, 0, 12, hc("#ffe08a") if now else hc("#f0d0e2"), -1, "600", 3, Color(0, 0, 0, 0.6))
				g.restore()
			var dk: float = gm.dark()
			if dk >= 0.02:
				g.set_xf(Transform2D.IDENTITY)
				g.rect(0, 0, W, H, rgba(6, 10, 28, 0.7 * dk))
		1:
			night_glows(gm, g, sc, alt, P)
		2:
			draw_storms(gm, g, gm.camX, gm.camY, sc)
			draw_clouds(gm, g, gm.camX, gm.camY, sc, clampf((alt - 45) / 60.0, 0, 1) * (0.28 - 0.2 * gm.dark()))
			g.set_xf(Transform2D.IDENTITY)
			if F.storm > 0:
				var k: float = F.storm
				g.rect(0, 0, W, H, rgba(18, 22, 30, k * 0.45))
				var ln := PackedVector2Array()
				for i in int(90 * k):
					var x := randf() * W
					var y := randf() * H
					ln.append(Vector2(x, y)); ln.append(Vector2(x - 5, y + 16))
				g.lines(ln, rgba(200, 210, 225, 0.35), 1.2)
			if F.flash > 0: g.rect(0, 0, W, H, rgba(235, 240, 255, minf(1, F.flash * 2)))
			vignette(gm, g, 0.34)
			grade(gm, g)
		7:
			hud_flight(gm, g, P, sc)

static func night_glows(gm, g: Pen, sc: float, alt: float, P: Dictionary) -> void:
	var dk: float = gm.dark()
	if dk < 0.02: return
	var F: Dictionary = gm.F
	var W: float = gm.Wv
	var H: float = gm.Hv
	g.set_view(sc, W / 2 - gm.camX * sc, H / 2 - gm.camY * sc)
	var vb: Dictionary = gm.get_meta("vb", {"x0": 0, "y0": 0, "x1": 0, "y1": 0})
	var glow := func(x: float, y: float, r: float, key: String, a: float) -> void:
		g.ga = minf(1, a)
		g.tex(Tx.glow(key), x - r, y - r, r * 2, r * 2)
		g.ga = 1.0
	var lr := maxf(14, 9 / sc)
	for s in gm.wd.strips:
		if not s.fuel or s.x < vb.x0 - 800 or s.x > vb.x1 + 800 or s.y < vb.y0 - 800 or s.y > vb.y1 + 800: continue
		var c := cos(s.ang)
		var n := sin(s.ang)
		var hav: bool = s.type == "haven"
		for i in 7:
			var u: float = -s.len / 2 + s.len * i / 6.0
			for sd in [-1, 1]:
				var o: float = sd * (s.wid / 2 + 6)
				glow.call(s.x + c * u - n * o, s.y + n * u + c * o, lr, "140,230,120" if hav else "255,215,140", dk if hav else 0.85 * dk)
	# fires at disputed fields (fields.gd): the same glow as the fires out on the map
	for s in gm.wd.strips:
		if not s.get("cleared", false) or s.x < vb.x0 - 800 or s.x > vb.x1 + 800 or s.y < vb.y0 - 800 or s.y > vb.y1 + 800: continue
		for p in Fields.camps(s): glow.call(p.x, p.y, 170 + randf() * 20, "255,110,40", 0.45 * dk)
	var C := 2600.0
	var wd: World = gm.wd
	for cy in range(int(floor((vb.y0 - 500) / C)), int(floor((vb.y1 + 300) / C)) + 1):
		for cx in range(int(floor((vb.x0 - 500) / C)), int(floor((vb.x1 + 300) / C)) + 1):
			if U.hash3(cx, cy, wd.SEED + 77) > 0.24: continue
			var sx := (cx + 0.2 + U.hash3(cx, cy, wd.SEED + 78) * 0.6) * C
			var sy := (cy + 0.2 + U.hash3(cx, cy, wd.SEED + 79) * 0.6) * C
			var v = gm.TCACHE.get(-(cx * 100003 + cy) - 7)
			if v == null or not v: continue
			glow.call(sx, sy, 170 + randf() * 20, "255,110,40", 0.45 * dk)
	g.save()
	g.translate(F.x, F.y)
	g.rotate(F.hdg)
	var sz: float = P.size * 1.7 * plane_grow(P, alt)   # same size as the plane sprite (grow in flight_layer)
	if alt < 75:
		g.radial(0, 0, [[0.0, rgba(255, 240, 200, 0.28 * dk)], [520.0, Color(0, 0, 0, 0)]], 24)
	var blink := fmod(gm.T, 1.2) < 0.12
	# wingtip and tail lights sit on the rendered frame's tips, so they follow the bank and pitch
	var pb: float = F.bank
	var pp: float = F.get("pitch", 0.0)
	var tl = plane_pt(P, "tipL", pb, pp)
	var tr = plane_pt(P, "tipR", pb, pp)
	var ta = plane_pt(P, "tail", pb, pp)
	if tl == null: tl = Vector2(0.1, -0.6)
	if tr == null: tr = Vector2(0.1, 0.6)
	if ta == null: ta = Vector2(-0.45, 0)
	glow.call(sz * tl.x, sz * tl.y, 10, "255,60,50", dk)
	glow.call(sz * tr.x, sz * tr.y, 10, "60,255,120", dk)
	if blink: glow.call(sz * ta.x, sz * ta.y, 16, "255,255,255", dk)
	g.restore()

static var NEAR_V = null
static var NEAR_RD = null
static var NEAR_MS := -100000
static var NEAR_WD = null
static func hud_flight(gm, g: Pen, P: Dictionary, sc: float) -> void:
	var F: Dictionary = gm.F
	var G: Dictionary = gm.G
	var W: float = gm.Wv
	var H: float = gm.Hv
	var T: float = gm.T
	var wd: World = gm.wd
	g.set_xf(Transform2D.IDENTITY)
	var pw := minf(W - 150, 340)
	var px := 10.0
	var py := 10.0
	g.rr(px, py, pw, 70, 6, rgba(12, 16, 14, 0.74))
	var fr: float = G.fuel / P.fuelCap
	g.text("Fuel", px + 10, py + 17, 12, hc("#b9b09a"))
	g.rect(px + 44, py + 11, pw - 56, 12, Color(1, 1, 1, 0.12))
	g.rect(px + 44, py + 11, (pw - 56) * fr, 12, (hc("#e3644c") if fmod(T, 1.0) < 0.5 else hc("#8a2a1c")) if fr < 0.2 else hc("#d9a441"))
	var ink := hc("#efe6cf")
	g.text("%.1f of %d gal, %d km left, hull %d%%" % [G.fuel, int(P.fuelCap), U.km(memo(gm, "range")), int(ceil(G.hull))], px + 10, py + 38, 13, ink)
	var hdg := int(round(fmod(rad_to_deg(F.hdg) + 90 + 360 * 4, 360)))
	g.text("%d kt   %d ft   %s%d fpm   %s°" % [int(round(F.spd * 0.75)), int(round(maxf(0, F.alt) * 45)), "▲" if F.vs >= 0 else "▼", absi(int(round(F.vs * 27))) * 100, ("00" + str(hdg)).right(3)], px + 10, py + 57, 13, ink)
	# minimap
	var mr := minf(58, W * 0.15)
	var mx := W - mr - 12
	var my := mr + 12
	var R := 6000.0
	var k := mr / R
	# open sea beyond the map edge: same colour the main flight view uses there
	g.circle(mx, my, mr, hc(SEA))
	var ovw: Texture2D = gm.baker.overview_wide
	var ov: Texture2D = gm.baker.overview
	if ovw:
		# real terrain and sea all the way out (the wide overview covers the ocean margin)
		var o: float = gm.baker.wide_origin
		var span: float = gm.baker.wide_span
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			var sp := Vector2(mx + cos(a) * mr, my + sin(a) * mr)
			pts.append(sp)
			uvs.append(Vector2((F.x + (sp.x - mx) / k - o) / span, (F.y + (sp.y - my) / k - o) / span))
		g.ci.draw_colored_polygon(pts, Color.WHITE, uvs, ovw)
	elif ov:
		# Draw the overview inside the circle, but only where it actually covers the
		# world. Past the map edge the texture's UVs would run outside 0..1 and smear
		# its edge pixels into streaks, so clip the circle to the world's rectangle.
		var circ := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			circ.append(Vector2(mx + cos(a) * mr, my + sin(a) * mr))
		var wx0: float = mx + (0.0 - F.x) * k
		var wy0: float = my + (0.0 - F.y) * k
		var wx1: float = mx + (D.WORLD - F.x) * k
		var wy1: float = my + (D.WORLD - F.y) * k
		var wrect := PackedVector2Array([Vector2(wx0, wy0), Vector2(wx1, wy0), Vector2(wx1, wy1), Vector2(wx0, wy1)])
		for pts in Geometry2D.intersect_polygons(circ, wrect):
			var uvs := PackedVector2Array()
			for sp in pts:
				uvs.append(Vector2((F.x + (sp.x - mx) / k) / D.WORLD, (F.y + (sp.y - my) / k) / D.WORLD))
			g.ci.draw_colored_polygon(pts, Color.WHITE, uvs, ov)
	g.circle(mx, my, mr, rgba(10, 14, 12, 0.25))
	var sps := storms_now(wd)
	var scol := rgba(120, 140, 190, 0.35)
	for si in sps.size():
		var q: Vector2 = sps[si]
		var sxp: float = mx + (q.x - F.x) * k
		var syp: float = my + (q.y - F.y) * k
		var sr: float = STORM_R[si] * k
		if Vector2(sxp - mx, syp - my).length() - sr > mr: continue
		_clipped_disc(g, sxp, syp, sr, mx, my, mr, scol, si)
	var rn: float = memo(gm, "range") * k
	if rn < mr: g.dashed_arc(mx, my, rn, 0, TAU, rgba(212, 90, 157, 0.9), 1, 3, 3)
	var nt = gm.flight.nav_target()
	var mdt2 = gm.flight.mayday_target()
	for s in known_strips(gm):
		var dx: float = (s.x - F.x) * k
		var dy: float = (s.y - F.y) * k
		if dx * dx + dy * dy > mr * mr * 0.9: continue
		var isnt: bool = nt != null and nt.id == s.id
		g.ring(mx + dx, my + dy, 4.5 if isnt else 3.0, hc("#9cc063") if s.type == "haven" else (hc("#8fbf88") if Fields.friendly(s) else (hc("#f0802a") if s.get("cleared", false) else hc("#e07ab3"))), 2.5 if isnt else 1.5)
		if mdt2 != null and mdt2.id == s.id:
			g.ring(mx + dx, my + dy, 7.0, hc("#ff2a1e"), 2.5)
	g.save(); g.translate(mx, my); g.rotate(F.hdg)
	g.poly(PackedVector2Array([Vector2(6, 0), Vector2(-4, -4), Vector2(-4, 4)]), Color.WHITE)
	g.restore()
	g.ring(mx, my, mr, rgba(239, 230, 207, 0.5), 1.5)
	g.text("N", mx, my - mr + 9, 11, ink, 0, "700")
	draw_objective(gm, g, py + 120)
	var wv: float = F.wind.length()
	var wy := py + 92
	g.rr(px, wy - 13, 172, 26, 5, rgba(12, 16, 14, 0.74))
	if wv > 1:
		g.save(); g.translate(px + 18, wy); g.rotate(atan2(F.wind.y, F.wind.x))
		g.lines(PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(8, 0), Vector2(3, -4), Vector2(8, 0), Vector2(3, 4)]), ink, 2)
		g.restore()
	g.text("%s   Day %d, %s" % [("Wind %d kt" % int(round(wv * 0.75))) if wv > 1 else "Calm", gm.day(), gm.clock()], px + 34, wy, 12, ink)
	var psx: float = W / 2 + (F.x - gm.camX) * sc
	var psy: float = H / 2 + (F.y - gm.camY) * sc
	var ntp = null
	if nt:
		var a2 := atan2(nt.y - F.y, nt.x - F.x)
		var r2 := minf(W, H) * 0.2 + 24
		ntp = Vector2(psx + cos(a2) * r2, psy + sin(a2) * r2)
	for s in known_strips(gm):
		var sx: float = W / 2 + (s.x - gm.camX) * sc
		var sy: float = H / 2 + (s.y - gm.camY) * sc
		if sx < -60 or sx > W + 60 or sy < -30 or sy > H + 30: continue
		var t: String = "Haven" if s.type == "haven" else s.name
		var ly: float = sy - s.wid * sc - 18
		if ntp != null:
			var lw2 := Pen.measure(t, 12) / 2 + 26
			if absf(sx - ntp.x) < lw2 and absf(ly - ntp.y) < 26: continue
		g.text(t, sx, ly, 12, hc("#f0c4dd"), 0, "600", 3, Color(0, 0, 0, 0.65))
	if nt:
		var a := atan2(nt.y - F.y, nt.x - F.x)
		var d := Vector2(nt.x - F.x, nt.y - F.y).length()
		if d > 250:
			var rd := minf(W, H) * 0.2 + 24
			var pl := 0.5 + 0.5 * sin(T * 4)
			var ax := psx + cos(a) * rd
			var ay := psy + sin(a) * rd
			var short: bool = d > memo(gm, "range")
			var lbl := "%s %d km" % ["Haven" if nt.type == "haven" else String(nt.name).split(" ")[0], U.km(d)]
			var lw := Pen.measure(lbl, 14, "700") + 16
			var lh := 22.0
			var place := func(sgn: float) -> Vector2:
				var off := 26 + absf(cos(a)) * lw / 2 + absf(sin(a)) * lh / 2
				return Vector2(psx + cos(a) * (rd + sgn * off), psy + sin(a) * (rd + sgn * off))
			var fits := func(v: Vector2) -> bool: return v.x - lw / 2 >= 6 and v.x + lw / 2 <= W - 66 and v.y - lh / 2 >= 150 and v.y + lh / 2 <= H - 110
			var tp: Vector2 = place.call(1.0)
			if not fits.call(tp):
				var alt2: Vector2 = place.call(-1.0)
				if fits.call(alt2): tp = alt2
				else: tp = Vector2(clampf(tp.x, lw / 2 + 6, W - lw / 2 - 66), clampf(tp.y, 150 + lh / 2, H - 110 - lh / 2))
			if absf(tp.x - ax) < lw / 2 + 18 and absf(tp.y - ay) < lh / 2 + 18: tp.y = ay + (-1 if ay > H / 2 else 1) * (lh / 2 + 22)
			g.rr(tp.x - lw / 2, tp.y - lh / 2, lw, lh, 5, rgba(12, 16, 14, 0.72))
			g.text(lbl, tp.x, tp.y, 14, hc("#ff8a70") if short else hc("#f3d38c"), 0, "700")
			g.dashed_arc(psx, psy, rd, a - 0.5, a + 0.5, rgba(217, 164, 65, 0.25 + 0.2 * pl), 2, 4, 8)
			g.save(); g.translate(ax, ay); g.rotate(a); var kk := 1.25 + pl * 0.15; g.scale(kk, kk)
			var arrow := PackedVector2Array([Vector2(16, 0), Vector2(-9, -12), Vector2(-3, 0), Vector2(-9, 12)])
			g.poly(arrow, hc("#ff8a70") if short else hc("#f2b64a"))
			var ac := arrow.duplicate(); ac.append(arrow[0])
			g.polyline(ac, Color(0, 0, 0, 0.65), 2.5)
			g.restore()
	var mt = gm.flight.mayday_target()
	if mt:
		var ma := atan2(mt.y - F.y, mt.x - F.x)
		var md := Vector2(mt.x - F.x, mt.y - F.y).length()
		if md > 250:
			var mrd := minf(W, H) * 0.2 + 64
			var mpl := 0.5 + 0.5 * sin(T * 6)
			var max2 := psx + cos(ma) * mrd
			var may2 := psy + sin(ma) * mrd
			var mlbl := "MAYDAY %s %d km" % [String(mt.name).split(" ")[0], U.km(md)]
			var mlw := Pen.measure(mlbl, 14, "700") + 16
			var mlh := 22.0
			var mplace := func(sgn: float) -> Vector2:
				var off := 26 + absf(cos(ma)) * mlw / 2 + absf(sin(ma)) * mlh / 2
				return Vector2(psx + cos(ma) * (mrd + sgn * off), psy + sin(ma) * (mrd + sgn * off))
			var mfits := func(v: Vector2) -> bool: return v.x - mlw / 2 >= 6 and v.x + mlw / 2 <= W - 66 and v.y - mlh / 2 >= 150 and v.y + mlh / 2 <= H - 110
			var mtp: Vector2 = mplace.call(1.0)
			if not mfits.call(mtp):
				var malt: Vector2 = mplace.call(-1.0)
				if mfits.call(malt): mtp = malt
				else: mtp = Vector2(clampf(mtp.x, mlw / 2 + 6, W - mlw / 2 - 66), clampf(mtp.y, 150 + mlh / 2, H - 110 - mlh / 2))
			if absf(mtp.x - max2) < mlw / 2 + 18 and absf(mtp.y - may2) < mlh / 2 + 18: mtp.y = may2 + (-1 if may2 > H / 2 else 1) * (mlh / 2 + 22)
			g.rr(mtp.x - mlw / 2, mtp.y - mlh / 2, mlw, mlh, 5, rgba(12, 16, 14, 0.72))
			g.text(mlbl, mtp.x, mtp.y, 14, hc("#ff5a4a"), 0, "700")
			g.dashed_arc(psx, psy, mrd, ma - 0.5, ma + 0.5, rgba(255, 40, 30, 0.35 + 0.3 * mpl), 2, 4, 8)
			g.save(); g.translate(max2, may2); g.rotate(ma); var mk := 1.25 + mpl * 0.15; g.scale(mk, mk)
			var marrow := PackedVector2Array([Vector2(16, 0), Vector2(-9, -12), Vector2(-3, 0), Vector2(-9, 12)])
			g.poly(marrow, hc("#ff2a1e"))
			var mac := marrow.duplicate(); mac.append(marrow[0])
			g.polyline(mac, Color(0, 0, 0, 0.65), 2.5)
			g.restore()
	# throttle
	var tb: Dictionary = gm.thr_bar
	g.rr(tb.x - 4, tb.y - 24, tb.w + 8, tb.h + 32, 6, rgba(12, 16, 14, 0.74))
	g.rect(tb.x, tb.y, tb.w, tb.h, Color(1, 1, 1, 0.1))
	g.rect(tb.x, tb.y + tb.h * (1 - F.thr), tb.w, tb.h * F.thr, hc("#d9a441") if G.fuel > 0 else hc("#6b5a3a"))
	var ay2: float = tb.y + tb.h * 0.67
	g.line(tb.x - 4, ay2, tb.x + tb.w + 4, ay2, hc("#d45a9d"), 2)
	g.text("%d%%" % int(round(F.thr * 100)), tb.x + tb.w / 2, tb.y - 12, 12, ink, 0, "700")
	g.save(); g.translate(tb.x - 12, ay2); g.rotate(-PI / 2)
	g.text("Approach", 0, 0, 11, hc("#e07ab3"), 0)
	g.restore()
	# status
	var msg := ""
	var c := ink
	# the nearest strip and the road below only pick the status line: ten times a second will do
	var nowm := Time.get_ticks_msec()
	if nowm - NEAR_MS > 100 or nowm < NEAR_MS or not is_same(NEAR_WD, wd):
		NEAR_V = wd.nearest_strip(F.x, F.y, 1600)
		NEAR_RD = wd.road_at(F.x, F.y) if (not F.onGround and F.alt < 40) else null
		NEAR_MS = nowm; NEAR_WD = wd
	var near = NEAR_V
	var rdh = NEAR_RD if (not F.onGround and F.alt < 40) else null
	var blinkc := hc("#e3644c") if fmod(T, 0.5) < 0.25 else ink
	if G.fuel <= 0 and not F.onGround:
		msg = "Engine out. The road below will do." if rdh else "Engine out. Glide to a runway or a road."
		c = hc("#e3644c")
	elif not F.onGround and G.hull < 25:
		msg = "Airframe failing. Land now."; c = blinkc
	elif F.storm > 0.5:
		msg = "Severe turbulence."; c = hc("#e3644c")
	elif F.underFire > 0:
		msg = "Ground fire. Climb."; c = hc("#e3644c")
	elif F.onGround and F.departing:
		msg = "Push the throttle up to roll." if F.spd < 3 else "Rolling. Stay on the runway."
	elif F.onGround:
		msg = "Cut the throttle to stop." if F.thr > 0.1 else "Braking."
	elif F.vs < -15 and F.alt < 35:
		msg = "Sinking too fast. Add power."; c = blinkc
	elif G.fuel / P.fuelCap < 0.15:
		msg = "Low fuel."; c = hc("#e3644c")
	elif G.leak > 0 and not F.onGround:
		msg = "Fuel leak, %.1f gal a minute." % (G.leak * 60); c = hc("#e3644c")
	elif rdh and gm.flight.align_to(rdh.r.ang, F.trk):
		msg = "Over a straight stretch of road. You could put it down here."; c = hc("#f0c4dd")
	else:
		gm.AP = memo(gm, "approach")
		var AP = gm.AP
		if AP and (AP.phase != "early" or F.alt < 75):
			var nm: String = "Haven" if AP.s.type == "haven" else AP.s.name
			if AP.phase == "early":
				msg = "Hold your altitude. Start down for %s in %d km." % [nm, maxi(1, U.km(AP.slack))]; c = hc("#f0c4dd")
			elif AP.phase == "now":
				msg = "Start your descent now. Pull the throttle to the pink mark."; c = hc("#ffe08a") if fmod(T, 0.6) < 0.3 else hc("#f0c4dd")
			elif AP.phase == "late":
				msg = "You started down late. Cut the power further or you will overshoot."; c = hc("#ffb080")
			else:
				msg = "Too high and fast to land at %s. Circle back and start down earlier." % nm; c = hc("#e3644c")
		elif F.assist and near:
			var nn: String = "Haven" if near.type == "haven" else near.name
			msg = ("Approach assist is bringing you down at %s. Hands off." % nn) if F.thr <= 0.75 else "Approach assist is lining you up. Pull the throttle back to the mark."
			c = hc("#f0c4dd")
		elif near and F.alt < 70 and gm.known.has(near.id):
			var nn: String = "Haven" if near.type == "haven" else near.name
			msg = ("Lined up with %s. Ease down." % nn) if gm.flight.align_ok(near) else ("Line up with the runway at %s." % nn)
			c = hc("#f0c4dd")
	if msg != "":
		var w := minf(W - 20, Pen.measure(msg, 15) + 24)
		g.rr(W / 2 - w / 2, H - 100, w, 30, 5, rgba(12, 16, 14, 0.74))
		g.text(msg, W / 2, H - 85, 15, c, 0, "600", 0, Color.BLACK, w - 16)
	for p in gm.ptrs.values():
		if p.role == "steer":
			g.line(p.sx - 70, p.sy, p.sx + 70, p.sy, rgba(239, 230, 207, 0.35), 2)
			g.circle(clampf(p.x, p.sx - 70, p.sx + 70), p.sy, 14, rgba(239, 230, 207, 0.5))

## key: the clipped outline is kept under it and reused while the disc and circle move less
## than a quarter pixel (clipping polygons every frame is slow).
static var CLIP_CACHE := {}
static func _clipped_disc(g: Pen, x: float, y: float, r: float, cx: float, cy: float, cr: float, col: Color, key = null) -> void:
	if Vector2(x - cx, y - cy).length() + r <= cr:
		g.circle(x, y, r, col)   # wholly inside: nothing to clip
		return
	var sig := PackedFloat32Array([x, y, r, cx, cy, cr])
	var hit = CLIP_CACHE.get(key) if key != null else null
	if hit != null:
		var same := true
		for i in 6:
			if absf(hit[0][i] - sig[i]) > 0.25: same = false; break
		if same:
			for poly in hit[1]: g.poly(poly, col)
			return
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		a.append(Vector2(x + cos(t) * r, y + sin(t) * r))
		b.append(Vector2(cx + cos(t) * cr, cy + sin(t) * cr))
	var polys := []
	for poly in Geometry2D.intersect_polygons(a, b):
		if poly.size() >= 3: polys.append(poly)
	if key != null: CLIP_CACHE[key] = [sig, polys]
	for poly in polys: g.poly(poly, col)

# =====================================================================
# ground frame
# =====================================================================
static func prep_ground(gm) -> void:
	var S: Dictionary = gm.S
	var sh: float = S.shake
	S.rcx = S.cx + (randf() - 0.5) * sh
	S.rcy = S.cy + (randf() - 0.5) * sh
	var dk: float = gm.dark()
	var dr: ColorRect = gm.dark_rect
	if dk > 0.02:
		var gs: float = gm.ground_scale()
		var p: Dictionary = S.p
		var vx: float = gm.Wv / 2 + (p.x - S.rcx) * gs
		var vy: float = gm.Hv / 2 + (p.y - S.rcy) * gs
		var m: ShaderMaterial = gm.dark_mat
		m.set_shader_parameter("dk", dk)
		m.set_shader_parameter("screen", Vector2(gm.Wv, gm.Hv))
		m.set_shader_parameter("ppos", Vector2(vx, vy))
		m.set_shader_parameter("r0", (150.0 if gm.has("monocle") else 110.0) * 1.5 * gs)   # glow round you: 1.5x wider...
		m.set_shader_parameter("r0_a", 0.5)   # ...and half as bright (Greg, 2026-10-12)
		m.set_shader_parameter("cone_a", p.ang)
		m.set_shader_parameter("cone_l", ((620.0 if gm.has("monocle") else 430.0) * gs * (0.3 if S.flick > 0 else 1.0)) if gm.torch else 0.0)
		m.set_shader_parameter("flash_r", 340.0 * gs if S.flash > 0 else 0.0)
		var arr := PackedVector3Array()
		for b in S.get("blit", []):   # blasts light up BLAST_LIGHT_R blast radii around them, briefly
			if arr.size() >= 16: break
			var bx: float = gm.Wv / 2 + (b.x - S.rcx) * gs
			var by: float = gm.Hv / 2 + (b.y - S.rcy) * gs
			var rb: float = b.r * gs * clampf(b.life / (Blasts.BLAST_LIGHT_T * 0.5), 0.0, 1.0)
			if bx < -rb or bx > gm.Wv + rb or by < -rb or by > gm.Hv + rb: continue
			arr.append(Vector3(bx, by, rb))
		for f in S.get("mf", []):   # survivors' muzzle flashes light up the dark as far as yours (flash_r)
			if arr.size() >= 16: break
			var fx: float = gm.Wv / 2 + (f.x - S.rcx) * gs
			var fy: float = gm.Hv / 2 + (f.y - S.rcy) * gs
			var rf := 340 * gs
			if fx < -rf or fx > gm.Wv + rf or fy < -rf or fy > gm.Hv + rf: continue
			arr.append(Vector3(fx, fy, rf))
		for f in site_fires(S):   # fires light up the dark, breathing with their glow
			if arr.size() >= 16: break
			var fx: float = gm.Wv / 2 + (f[0] - S.rcx) * gs
			var fy: float = gm.Hv / 2 + (f[1] - S.rcy) * gs
			var rf: float = FIRE_LIGHT_R * f[2] * (0.4 + 0.6 * f[3]) * fire_pulse(gm.T, f[4]) * gs
			if fx < -rf or fx > gm.Wv + rf or fy < -rf or fy > gm.Hv + rf: continue
			arr.append(Vector3(fx, fy, rf))
		for l in S.lights:
			if not l.on: continue
			var sx: float = gm.Wv / 2 + (l.x + 12 - S.rcx) * gs
			var sy: float = gm.Hv / 2 + (l.y - S.rcy) * gs
			var rl := 140 * gs
			if sx < -rl or sx > gm.Wv + rl or sy < -rl or sy > gm.Hv + rl: continue
			if arr.size() < 16: arr.append(Vector3(sx, sy, rl))
		var nl := arr.size()
		for i in range(arr.size(), 16): arr.append(Vector3.ZERO)
		m.set_shader_parameter("lights", arr)
		m.set_shader_parameter("nlights", nl)
		dr.visible = true
	else:
		dr.visible = false

const FLOATER_BOTTOM := 44.0   # on foot: the newest pop-up message sits this far above the bottom edge
const FLOATER_LINE := 19.0     # and older ones stack upwards this far apart
const FLOATER_MAX := 5         # at most this many shown at once
const SMOKE_HIDE := 0.5        # how much of the player a smoke cloud hides at full density
const SV_FLASH_NIGHT := 2.0     # enemy muzzle flashes at night: this many times as bright as by day (drawn again over the dark)
const FIRE_LIGHT_R := 190.0    # at night a car fire lights up this far around it (burning wreckage pieces: x their size, ~0.45)
const FIRE_PULSE := 0.12       # how much fire glows and fire light swell and shrink as they pulse

## Slow warm pulse (with a faster flicker on top) for a fire's glow and light, 1 - FIRE_PULSE..1 + FIRE_PULSE.
## On foot: tree shadows from the sun (they used to be baked into the site at a fixed angle).
static func foot_tree_shadows(gm, g: Pen, vx0: float, vy0: float, vx1: float, vy1: float) -> void:
	if SUN_A < 0.01: return
	var S: Dictionary = gm.S
	var L := SUN.length() * FOOT_TREE_H * 0.5
	var pad := 40.0 + L * 3
	var c0 := maxi(0, int(floor((vx0 - pad) / TS)))
	var c1 := mini(S.cols - 1, int(floor((vx1 + pad) / TS)))
	var r0 := maxi(0, int(floor((vy0 - pad) / TS)))
	var r1 := mini(S.rows - 1, int(floor((vy1 + pad) / TS)))
	var col := Color(10 / 255.0, 18 / 255.0, 8 / 255.0, 0.36 * SUN_A)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if S.g[r * S.cols + c] != 5: continue
			var hf := foot_tree_hf(c, r)
			var o := SUN * FOOT_TREE_H * hf * 0.55
			g.ellipse((c + 0.5) * TS + o.x, (r + 0.5) * TS + o.y, 28 + L * hf, 25, SUN_ANG, col)

## On foot: this tree's height as a share of FOOT_TREE_H (0.65 to 1.45).
static func foot_tree_hf(c: int, r: int) -> float:
	return 0.65 + U.hash3(c, r, 29) * 0.8

static func fire_pulse(T: float, ph: float) -> float:
	return 1.0 + FIRE_PULSE * (0.75 * sin(T * 4.0 + ph) + 0.25 * sin(T * 11.0 + ph * 1.7))

## Every fire burning on the site, as [x, y, size (1 = a car), strength 0..1, pulse phase]: burning cars
## waiting to blow, wrecks still burning after the blast, and burning pieces of wreckage once they've landed.
static func site_fires(S: Dictionary) -> Array:
	var out := []
	for car in S.cars:
		if not car.dead and car.fuse >= 0: out.append([car.x, car.y, 1.0, minf(1.0, float(car.burnT) / 1.5), float(car.c)])
		elif car.dead and car.get("fireT", 0.0) > 0: out.append([car.x, car.y, 1.0, minf(1.0, car.fireT / (car.fireMax / 3.0)), float(car.c)])
	for d in S.get("debris", []):
		if d.fireT > 0 and d.t >= d.fly: out.append([d.x, d.y, 0.45, minf(1.0, d.fireT / 3.0), d.ph])
	return out

## A fire like the map campfires: a warm pulsing glow round a flickering hot core.
static func draw_fire(gm, g: Pen, x: float, y: float, sz: float, k: float, ph: float) -> void:
	var pu := fire_pulse(gm.T, ph)
	var r1 := 80.0 * sz * pu
	g.ga = 0.32 * k * pu
	g.tex(Tx.glow("255,150,60"), x - r1, y - r1, r1 * 2, r1 * 2)
	var r2 := 46.0 * sz * pu
	g.ga = 0.55 * k
	g.tex(Tx.glow("255,110,40"), x - r2, y - r2, r2 * 2, r2 * 2)
	g.ga = 1.0
	for q in 3:
		g.circle(x + (randf() - 0.5) * 8 * sz, y + (randf() - 0.5) * 6 * sz, (5 + randf() * 3) * sz * (0.5 + 0.5 * k), rgba(255, 120 + randf() * 60, 40, 0.8))
	g.circle(x, y, (2.5 + randf() * 1.5) * sz, rgba(255, 230, 170, 0.85 * k))

## On foot: the part of the site on screen this frame, in world units. Things wholly outside it
## (by their margin) aren't drawn; sites are much bigger than the screen.
static var VIEW := Rect2()
static func on_view(x: float, y: float, m: float) -> bool:
	return x > VIEW.position.x - m and x < VIEW.end.x + m and y > VIEW.position.y - m and y < VIEW.end.y + m

static func ground_layer(gm, idx: int, g: Pen) -> void:
	var S: Dictionary = gm.S
	var gs: float = gm.ground_scale()
	var cx: float = S.rcx
	var cy: float = S.rcy
	var W: float = gm.Wv
	var H: float = gm.Hv
	VIEW = Rect2(cx - W / 2 / gs, cy - H / 2 / gs, W / gs, H / gs)
	var T: float = gm.T
	var p: Dictionary = S.p
	var view := func(): g.set_view(gs, W / 2 - cx * gs, H / 2 - cy * gs)
	match idx:
		0:
			g.rect(0, 0, W, H, hc("#1c2216"))
			view.call()
			var vx0 := maxf(0, cx - W / 2 / gs - 40)
			var vy0 := maxf(0, cy - H / 2 / gs - 40)
			var vx1 := minf(S.cols * TS, cx + W / 2 / gs + 40)
			var vy1 := minf(S.rows * TS, cy + H / 2 / gs + 40)
			var BK := SiteGen.BK
			if vx1 > vx0 and vy1 > vy0 and S.bg.baked:
				g.tex_region(S.bg.get_texture(), Rect2(vx0, vy0, vx1 - vx0, vy1 - vy0), Rect2(vx0 * BK, vy0 * BK, (vx1 - vx0) * BK, (vy1 - vy0) * BK))
			set_view3d(gm, cx, cy, gs)
			if S.tanker:
				var tk: Dictionary = S.tanker
				g.save(); g.translate(tk.x, tk.y)
				g.rr(-58, -10, 124, 30, 6, Color(0, 0, 0, 0.35))
				g.rr(-64, -14, 28, 28, 4, hc("#8a2a1c"))
				g.rect(-60, -11, 8, 22, hc("#1c2226"))
				g.rr(-34, -15, 96, 30, 14, hc("#b8b4aa"))
				g.rect(-30, -13, 88, 6, Color(1, 1, 1, 0.18))
				for q in 5: g.circle(-20 + q * 18, 4, 3 + (q % 2) * 2, rgba(120, 60, 30, 0.35))
				g.rect(10, -3, 8, 6, hc("#3a3a3a"))
				g.restore()
				if tk.gal > 0 and tk.prog > 0: g.arc(p.x, p.y, 22, -PI / 2, -PI / 2 + tk.prog * TAU, hc("#d9a441"), 4)
			for k in S.crates:
				if on_view(k.x, k.y, 60): draw_container(gm, g, k)
			draw_pickups(gm, g)
			for b in S.thrown:
				var bz: float = b.get("z", 0.0)   # height while a survivor's lob is in the air
				g.ellipse(b.x + 3 + bz * 0.3, b.y + 4, 7, 5, 0, Color(0, 0, 0, 0.3 * (1.0 - minf(0.6, bz / 100.0))))
				g.save(); g.translate(b.x, b.y - bz)
				g.rotate(b.spin)
				g.rr(-7, -4, 14, 8, 2, hc("#5b5f63"))
				g.rect(-7, -4, 3, 8, hc("#3a3d40")); g.rect(4, -4, 3, 8, hc("#3a3d40"))
				g.restore()
				if fmod(T, 0.25) < 0.12: g.circle(b.x, b.y - bz - 6, 2.5, hc("#ff4a30"))
			for sg in S.get("smk", []):   # survivors' smoke grenades in the air: a pipe bomb in olive drab
				var cz: float = sg.z
				g.ellipse(sg.x + 3 + cz * 0.3, sg.y + 4, 7, 5, 0, Color(0, 0, 0, 0.3 * (1.0 - minf(0.6, cz / 100.0))))
				g.save(); g.translate(sg.x, sg.y - cz)
				g.rotate(sg.spin)
				g.rr(-7, -4, 14, 8, 2, hc("#66704a"))
				g.rect(-7, -4, 3, 8, hc("#3f4630")); g.rect(4, -4, 3, 8, hc("#3f4630"))
				g.restore()
			for d in S.drops:
				if not on_view(d.x, d.y, 40): continue
				var pl := 0.5 + 0.5 * sin(T * 5 + d.x)
				g.rect(d.x - 5, d.y - 3, 14, 10, Color(0, 0, 0, 0.3))
				if d.k == "gun":
					# a dropped gun: barrel and stock (short for the revolver), gold glow
					var lg: bool = int(d.get("w", 0)) != 0
					g.rect(d.x - (11.0 if lg else 6.0), d.y - 2, 22.0 if lg else 12.0, 4, hc("#161615"))
					if lg: g.rect(d.x - 13, d.y - 2.5, 8, 5, hc("#5a3e26"))
					else: g.rect(d.x - 7, d.y - 1, 4, 6, hc("#5a3e26"))
					g.ring(d.x, d.y, 15, rgba(255, 210, 122, 0.3 + 0.4 * pl), 1.5)
					continue
				if d.k == "ammo":
					g.rect(d.x - 7, d.y - 5, 14, 10, hc("#4f5530"))
					for q in 4: g.rect(d.x - 5 + q * 3, d.y - 3, 2, 6, hc("#d9b35a"))
				else:
					g.rect(d.x - 7, d.y - 4, 14, 8, hc("#5d7d3a")); g.rect(d.x - 2, d.y - 2, 4, 4, hc("#9cc063"))
				g.ring(d.x, d.y, 12, rgba(240, 220, 140, 0.25 + 0.35 * pl), 1.2)
			for br in S.barrels:
				if br.dead or not on_view(br.x, br.y, 40): continue
				g.ellipse(br.x + 4, br.y + 5, 12, 11, 0, Color(0, 0, 0, 0.32))
				var lit: bool = br.fuse >= 0 and fmod(T, 0.1) < 0.05
				g.circle(br.x, br.y, 11.5, hc("#ffc070") if lit else hc("#a8301f"))
				g.circle(br.x - 4, br.y - 4, 5, hc("#ffe8b0") if lit else rgba(255, 140, 110, 0.35))
				g.ring(br.x, br.y, 8, rgba(40, 8, 4, 0.6), 1.5)
				g.circle(br.x + 4, br.y - 3, 2.2, hc("#2a2a28"))
				g.poly(PackedVector2Array([Vector2(br.x - 3.5, br.y + 4), Vector2(br.x, br.y - 2), Vector2(br.x + 3.5, br.y + 4)]), hc("#e8c74a"))
			# wreckage thrown out by car blasts: charred chunks, tumbling out in an arc, then lying there
			for d in S.get("debris", []):
				var k: float = minf(1.0, d.t / d.fly)
				var hgt := sin(PI * k) * 26.0
				var dx: float = lerpf(d.sx, d.x, k)
				var dy: float = lerpf(d.sy, d.y, k)
				if not on_view(dx, dy, 60): continue
				var an: float = d.ang + d.spin * minf(d.t, d.fly)
				var sh := PackedVector2Array()
				var pc := PackedVector2Array()
				for v in d.pts:
					var w: Vector2 = v.rotated(an)
					sh.append(Vector2(dx + w.x + 2 + hgt * 0.3, dy + w.y + 3))
					pc.append(Vector2(dx + w.x, dy + w.y - hgt))
				g.poly(sh, Color(0, 0, 0, 0.3))
				g.poly(pc, hc("#15120f"))
				g.polyline(pc + PackedVector2Array([pc[0]]), hc("#2c2520"), 1.0)
			# fires: burning cars (out of hitpoints, waiting to blow), wrecks still burning after
			# the blast, burning wreckage; drawn like the campfires on the map (draw_smoke)
			for f in site_fires(S):
				draw_fire(gm, g, f[0], f[1], f[2], f[3], f[4])
			# blast-radius rings: burning cars and thrown bombs
			for car in S.cars:
				if not car.dead and car.fuse >= 0: blast_ring(gm, g, car.x, car.y, Blasts.CAR_BLAST_R, car.fuse)
			for b in S.thrown:
				if not b.dead: blast_ring(gm, g, b.x, b.y, Blasts.BOMB_BLAST_R, b.fuse)
			var P: Dictionary = gm.PS()
			var pk: float = P.get("foot_k", 1.0)   # per-plane size when parked, seen on foot
			g.save(); g.translate(S.plane.x + 10 * pk, S.plane.y + 14 * pk); draw_plane(g, P, 190 * pk, 0, true); g.restore()
			g.save(); g.translate(S.plane.x, S.plane.y); draw_plane(g, P, 190 * pk, 0, false); g.restore()
			if S.nearPlane: g.dashed_arc(S.plane.x, S.plane.y, 130, 0, TAU, rgba(212, 90, 157, 0.8), 2, 8, 6)
			for z in S.zs:
				if on_view(z.x, z.y, 60): draw_zombie(gm, g, z)
			for v in S.sv:
				if not on_view(v.x, v.y, 60): continue
				# startled hop on spotting you: up and down, drawn bigger like your jump
				var sj: float = sin(PI * (1 - float(v.jt) / Survivors.SV_STARTLE_T)) * 3.5 if v.has("jt") else 0.0
				if sj > 0:
					g.save(); g.translate(v.x, v.y - sj * 0.5); g.scale(1 + sj / 45, 1 + sj / 45); g.translate(-v.x, -v.y)
				draw_person(g, v.x, v.y, v.ang, {"body": v.shirt, "skin": v.skin, "hair": "#2b2118", "cap": v.cap, "gun": not v.get("unarmed", false), "bare": v.get("unarmed", false), "long": int(v.get("w", 1)) != 0, "vest": float(v.get("armor", 0.0)) > 0, "walk": v.wk, "hit": v.hit > 0, "lower": 1.0 - float(v.get("gup", 0.0))})
				if sj > 0: g.restore()
			gm.farm.draw(g)
			gm.fields.draw(g)
			for n in S.npcs:
				draw_person(g, n.x, n.y, n.ang, {"body": "#3f7a7a", "skin": "#e0b894", "hair": "#5a3a22", "gun": true, "long": int(n.get("w", 0)) != 0, "walk": n.wk, "hit": n.hit > 0})
				if not n.follow:
					var pl := 0.5 + 0.5 * sin(T * 5)
					g.ring(n.x, n.y, 22 + pl * 6, rgba(240, 160, 210, 0.3 + 0.5 * pl), 2)
				g.text(n.name, n.x, n.y - 22, 11, hc("#f0c4dd"), 0, "700", 3, Color(0, 0, 0, 0.7))
			for cl in S.get("clouds", []): draw_cloud(g, cl, T)
			var jz: float = sin(PI * (1 - p.jt / 0.46)) * 14 if p.jt > 0 else 0.0
			if jz > 0: g.ellipse(p.x + 3 + jz * 0.4, p.y + 5 + jz * 0.7, 10, 7, 0, Color(0, 0, 0, 0.25))
			g.save()
			if jz > 0:
				g.translate(p.x, p.y - jz * 0.5); g.scale(1 + jz / 45, 1 + jz / 45); g.translate(-p.x, -p.y)
			# inside a smoke cloud you're partly hidden: SMOKE_HIDE at full density, fading out
			# toward the thin edge of the cloud (g.restore() puts the alpha back)
			var hid := 0.0
			for cl in S.get("clouds", []):
				var dc := Vector2(p.x - cl.x, p.y - cl.y).length()
				if dc < cl.r: hid = maxf(hid, float(cl.den) * clampf((cl.r - dc) / (cl.r * 0.3), 0.0, 1.0))
			g.ga = 1.0 - SMOKE_HIDE * minf(1.0, hid)
			draw_person(g, p.x, p.y, p.ang, {"body": "#9a3a2a" if S.hurt > 0 else "#6b4a2e", "skin": "#d9b48f", "cap": "#34404c", "gun": gm.ammo_left() > 0 and not gm.unarmed_here(), "bare": gm.unarmed_here(), "long": gm.G.weapon > 0, "walk": p.wk, "swing": S.swing > 0})
			g.restore()
		1:
			view.call()
			if S.flash > 0:
				var mx: float = p.x + cos(p.ang) * 26
				var my: float = p.y + sin(p.ang) * 26
				g.radial(mx, my, [[0.0, rgba(255, 220, 150, 0.9)], [48 * 0.3, rgba(255, 160, 70, 0.4)], [48.0, rgba(255, 120, 40, 0)]], 24)
			for f in S.get("mf", []):
				g.radial(f.x, f.y, [[0.0, rgba(255, 220, 150, 0.9)], [48 * 0.3, rgba(255, 160, 70, 0.4)], [48.0, rgba(255, 120, 40, 0)]], 24)
			if S.boomFlash > 0 and S.scorch.size():
				var q: Dictionary = S.scorch[S.scorch.size() - 1]
				g.radial(q.x, q.y, [[0.0, rgba(255, 190, 90, minf(1, S.boomFlash * 3))], [200.0, rgba(255, 90, 30, 0)]], 32)
			for b in S.bul:
				if b.bolt:
					g.line(b.x, b.y, b.x - b.vx * 0.02, b.y - b.vy * 0.02, hc("#6a4a2a"), 1)
					continue
				var tx: float = b.x - b.vx * 0.025
				var ty: float = b.y - b.vy * 0.025
				g.line(b.x, b.y, tx, ty, rgba(255, 200, 110, 0.35) if b.pl else rgba(255, 110, 80, 0.35), 2.5)
				g.line(b.x, b.y, tx, ty, rgba(255, 245, 210, 0.95) if b.pl else rgba(255, 190, 170, 0.95), 0.9)
		2:
			view.call()
			for f in S.fx:
				var z: float = f.sz
				g.rect(f.x - z / 2, f.y - z / 2, z, z, hc(f.c))
			for m in S.smoke:
				g.ga = clampf(m.life / m.max, 0, 1) * 0.6
				g.tex(Tx.GPUFF if m.g else Tx.DPUFF, m.x - m.r, m.y - m.r, m.r * 2, m.r * 2)
			g.ga = 1.0
			for car in S.cars:
				# smoke plume like the map campfires' (draw_smoke) at ground scale: while burning,
				# and bigger over the wreck after it blows, thinning out over CAR_SMOLDER seconds
				if car.dead:
					if car.burnT <= 0: continue
					var fade: float = minf(1.0, car.burnT / car.burnMax * 1.5)
					for i in 10:
						var k := fmod(T * 0.22 + i / 10.0 + float(car.c) * 0.13, 1.0)
						g.circle(car.x + k * 200, car.y - k * 120, 12 + k * 70, rgba(40, 38, 36, 0.55 * (1 - k) * fade))
					continue
				if car.fuse < 0: continue
				var grow := minf(1.0, float(car.burnT) / 1.5)
				for i in 8:
					var k := fmod(T * 0.35 + i / 8.0 + float(car.c) * 0.13, 1.0)
					g.circle(car.x + k * 90, car.y - k * 55, (5 + k * 30) * grow, rgba(46, 44, 42, 0.45 * (1 - k)))
		20:   # roofs, on their own layer so roof.gdshader can cut peek circles out of them
			view.call()
			draw_roofs(gm, g)
		21:   # everything drawn over the roofs (crows, haze, trees, ...)
			view.call()
			for cw in S.crows:
				if cw.gone: continue
				g.save(); g.translate(cw.x, cw.y)
				if cw.fly:
					g.ellipse(10 + cw.h * 0.6, 14 + cw.h, 5, 3, 0, Color(0, 0, 0, 0.2))
					g.rotate(atan2(cw.vy, cw.vx))
					var f := sin(T * 22 + cw.ph) * 6
					g.polyline(PackedVector2Array([Vector2(-8, -f), Vector2(0, 0), Vector2(-8, f)]), hc("#141416"), 2.4)
					g.ellipse(0, 0, 5, 2.5, 0, hc("#141416"))
				else:
					g.rotate(cw.a)
					g.ellipse(1, 2, 5, 3, 0, Color(0, 0, 0, 0.25))
					g.ellipse(0, 0, 5, 3, 0, hc("#18181a"))
					var pk := 2.0 if sin(T * 6 + cw.ph) > 0.7 else 0.0
					g.circle(4 + pk, 0, 2.2, hc("#18181a"))
					g.rect(6 + pk, -0.6, 2, 1.2, hc("#8a7a40"))
				g.restore()
			var mw: float = S.cols * TS
			var mh: float = S.rows * TS
			g.ga = 0.1
			for i in 5:
				var sx := fmod(T * 14 + i * 977, mw + 900) - 450
				var sy := fmod(i * 613 + T * 5, mh)
				var sz := 380 + i * 60
				g.tex(Tx.SPUFF, sx - sz / 2, sy - sz / 2, sz, sz * 0.7)
			g.ga = 1.0
			var c0 := maxi(0, int(floor((cx - W / 2 / gs - 40) / TS)))
			var c1 := mini(S.cols - 1, int(floor((cx + W / 2 / gs + 40) / TS)))
			var r0 := maxi(0, int(floor((cy - H / 2 / gs - 40) / TS)))
			var r1 := mini(S.rows - 1, int(floor((cy + H / 2 / gs + 40) / TS)))
			if Tx.FOOT_TREES.size():
				# the original flat on-foot trees (Greg, 2026-10-15), with their baked shadow in site.gd
				for r in range(r0, r1 + 1):
					for c in range(c0, c1 + 1):
						if S.g[r * S.cols + c] != 5: continue
						var x := (c + 0.5) * TS
						var y := (r + 0.5) * TS
						var j := U.hash3(c, r, 3)
						var sz := 70 + j * 14
						g.ga = 0.45 if Vector2(p.x - x, p.y - y).length() < 34 else 1.0
						g.tex(Tx.FOOT_TREES[int(j * 3)], x - sz / 2, y - sz / 2, sz, sz, FarmFolk.tree_tint(S, c, r))
				g.ga = 1.0
			gm.farm.draw_top(g)   # family farm windmill sails, above roofs and trees
			g.set_xf(Transform2D.IDENTITY)
			var dk: float = gm.dark()
			vignette(gm, g, 0.8 + dk * 0.15)
			grade(gm, g)
			if S.rain > 0:
				g.rect(0, 0, W, H, rgba(20, 26, 34, S.rain * 0.3))
				var ln := PackedVector2Array()
				for i in int(100 * S.rain):
					var x := randf() * W
					var y := randf() * H
					ln.append(Vector2(x, y)); ln.append(Vector2(x - 4, y + 14))
				g.lines(ln, rgba(200, 210, 225, 0.3), 1.2)
			if S.nd < 150:
				var k: float = (1 - S.nd / 150.0) * (0.55 + 0.45 * sin(T * 8))
				vignette_red(gm, g, 0.3 * k)
		4:
			var dk: float = gm.dark()
			if dk <= 0.02: return
			g.set_xf(Transform2D.IDENTITY)
			if dk > 0.2:
				for z in S.zs:
					if z.dormant or z.rise > 0: continue
					var sx: float = W / 2 + (z.x - cx) * gs
					var sy: float = H / 2 + (z.y - cy) * gs
					if sx < -20 or sx > W + 20 or sy < -20 or sy > H + 20: continue
					var a: float = z.ang
					var hx := (7.0 if z.kind == "crawler" else 3.2) + 3
					var s := (1.4 if z.kind == "bloat" else 1.0) * gs
					for e in [-2.1, 2.1]:
						var ex = sx + (cos(a) * hx - sin(a) * e) * s
						var ey = sy + (sin(a) * hx + cos(a) * e) * s
						g.ga = dk * 0.85
						g.tex(Tx.glow("255,60,30"), ex - 4.5, ey - 4.5, 9, 9)
						g.ga = 1.0
						g.rect(ex - 0.8, ey - 0.8, 1.6, 1.6, rgba(255, 150, 110, dk))
			for f in S.get("mf", []):   # enemy muzzle flashes: the flash again over the dark, so at night it's SV_FLASH_NIGHT x as bright
				var fx: float = W / 2 + (f.x - cx) * gs
				var fy: float = H / 2 + (f.y - cy) * gs
				var rf: float = 48.0 * gs
				if fx < -rf or fx > W + rf or fy < -rf or fy > H + rf: continue
				var fa: float = minf(1.0, dk) * (SV_FLASH_NIGHT - 1.0)
				g.radial(fx, fy, [[0.0, rgba(255, 220, 150, 0.9 * fa)], [rf * 0.3, rgba(255, 160, 70, 0.4 * fa)], [rf, rgba(255, 120, 40, 0)]], 24)
			for f in site_fires(S):   # warm glow over the dark round every fire, pulsing
				var fx: float = W / 2 + (f[0] - cx) * gs
				var fy: float = H / 2 + (f[1] - cy) * gs
				var rf: float = FIRE_LIGHT_R * 0.8 * f[2] * fire_pulse(gm.T, f[4]) * gs
				if fx < -rf or fx > W + rf or fy < -rf or fy > H + rf: continue
				g.ga = 0.3 * dk * f[3]
				g.tex(Tx.glow("255,140,60"), fx - rf, fy - rf, rf * 2, rf * 2)
			g.ga = 1.0
			for l in S.lights:
				if not l.on: continue
				var sx: float = W / 2 + (l.x + 12 - cx) * gs
				var sy: float = H / 2 + (l.y - cy) * gs
				var rl := 130 * gs
				if sx < -rl or sx > W + rl or sy < -rl or sy > H + rl: continue
				g.ga = 0.28 * dk
				g.tex(Tx.glow("255,210,140"), sx - rl, sy - rl, rl * 2, rl * 2)
			g.ga = 1.0
		5:
			g.set_xf(Transform2D.IDENTITY)
			if S.hurt > 0: g.rect(0, 0, W, H, rgba(160, 20, 10, S.hurt * 0.6))
			for sp in S.splat:
				var a := minf(1, sp.life / 1.2) * 0.7
				var col := rgba(105, 8, 5, a)
				var si := int(sp.s)
				for q in 7:
					var an := U.hash3(q, si, 5) * TAU
					var dd: float = U.hash3(si, q, 6) * sp.r * 0.7
					var rr2: float = sp.r * (0.18 + U.hash3(q, q, si) * 0.3)
					g.circle(sp.x + cos(an) * dd, sp.y + sin(an) * dd, rr2, col)
				g.rect(sp.x - 2, sp.y, 4, sp.r * 0.6 + (1.8 - sp.life) * 40, col)
				g.rect(sp.x + sp.r * 0.3, sp.y, 3, sp.r * 0.4 + (1.8 - sp.life) * 25, col)
			if S.boomFlash > 0: g.rect(0, 0, W, H, rgba(255, 190, 110, minf(1, S.boomFlash * 1.2)))
		7:
			# speech over people's heads ("Hey!", names, "Smoke!", ...): drawn here, above the night
			# darkness, smoke and screen effects, so it's always fully readable
			view.call()
			for f in S.fl:
				if not f.get("w", false): continue   # the rest are stacked near the bottom of the screen, below
				g.ga = clampf(f.life, 0, 1)
				g.text(f.txt, f.x, f.y, 14, hc(f.c), 0, "700", 3, Color(0, 0, 0, 0.7))
			g.ga = 1.0
			g.set_xf(Transform2D.IDENTITY)
			# pop-up messages on foot: stacked near the bottom of the screen, newest lowest,
			# so they don't cover the action around the player
			var fy: float = H - FLOATER_BOTTOM
			for k in range(S.fl.size() - 1, -1, -1):
				var f: Dictionary = S.fl[k]
				if f.get("w", false): continue
				g.ga = clampf(f.life, 0, 1)
				g.text(f.txt, W / 2, fy, 15, hc(f.c), 0, "700", 3, Color(0, 0, 0, 0.7))
				fy -= FLOATER_LINE
				if fy < H - FLOATER_BOTTOM - FLOATER_LINE * (FLOATER_MAX - 1): break
			g.ga = 1.0
			hud_ground(gm, g)
			if gm.uist == "" and not gm.cursor_on_btn: draw_ads_reticle(gm, g)

## The exploration-mode cursor (replaces the Windows pointer). Follows the mouse
## normally; while aiming down sights it follows the slowed virtual cursor and
## tightens up as the camera settles in.
## Blinking red dashed ring showing how far a blast will reach from (x, y); blinks
## faster once the fuse is nearly out.
static func blast_ring(gm, g: Pen, x: float, y: float, rad: float, fuse: float) -> void:
	var rate: float = Blasts.BLAST_RING_BLINK * (2.0 if fuse < Blasts.BLAST_RING_HURRY else 1.0)
	if fmod(gm.T * rate, 1.0) >= 0.5: return   # off half the time
	g.dashed_arc(x, y, rad, 0, TAU, rgba(255, 40, 30, 0.75), 2.5, Blasts.BLAST_RING_DASH, Blasts.BLAST_RING_GAP)

static func draw_ads_reticle(gm, g: Pen) -> void:
	var c: Vector2 = gm.reticle_pos()
	var k: float = gm.ads_ease()
	var a := 0.8 + 0.15 * k
	var r := 14.0 - 5.0 * k   # tightens as you settle in
	var shade := Color(0, 0, 0, 0.45 * a)
	var ink := rgba(239, 230, 207, a)
	g.ring(c.x, c.y, r, shade, 3.0)
	g.ring(c.x, c.y, r, ink, 1.5)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		g.line(c.x + d.x * (r + 3), c.y + d.y * (r + 3), c.x + d.x * (r + 9), c.y + d.y * (r + 9), ink, 1.5)
	# red dot only while a shot would actually get there (range, walls, cars, barrels)
	var wp: Vector2 = gm.s2w_g(c.x, c.y)
	if gm.shot_reaches(wp.x, wp.y): g.circle(c.x, c.y, 1.6, rgba(227, 100, 76, a))

# =====================================================================
# ground sprites
# =====================================================================
const ROOF_H := 16.0     # on foot: roof height for the wall slivers and sun shadows, world units
const FOOT_TREE_H := 46.0   # on foot: average canopy top height (each tree varies)
const WALL_FOOT := Color(0.5, 0.46, 0.4)
## A lintel over each door and window, sticking out past the outside of the wall and the
## roof edge so openings show from outside. rm.lt caches [x, y, w, h, window?] per opening.
const LINTEL := Color(0.6, 0.53, 0.42)
const LINTEL_WIN := Color(0.5, 0.46, 0.4)
static func draw_lintels(g: Pen, S: Dictionary, rm: Dictionary) -> void:
	if not rm.has("lt"):
		var lt := []
		var at := func(c: int, r: int) -> int: return S.g[r * S.cols + c]
		for side in 4:   # top, bottom, left, right walls
			var horiz := side < 2
			var n: int = rm.w if horiz else rm.h
			var k := 1
			while k < n - 1:
				var c: int = rm.c + k if horiz else (rm.c if side == 2 else rm.c + rm.w - 1)
				var r: int = (rm.r if side == 0 else rm.r + rm.h - 1) if horiz else rm.r + k
				var v: int = at.call(c, r)
				if v != 2 and v != 15:
					k += 1
					continue
				var k1 := k
				while k1 + 1 < n - 1 and at.call(c + (k1 + 1 - k) if horiz else c, r if horiz else r + (k1 + 1 - k)) == v: k1 += 1
				var a0 := k * TS - 4.0
				var a1 := (k1 + 1) * TS + 4.0
				match side:
					0: lt.append([rm.c * TS + a0, rm.r * TS + 2.0, a1 - a0, 9.0, v == 15])
					1: lt.append([rm.c * TS + a0, (rm.r + rm.h) * TS - 11.0, a1 - a0, 9.0, v == 15])
					2: lt.append([rm.c * TS + 2.0, rm.r * TS + a0, 9.0, a1 - a0, v == 15])
					3: lt.append([(rm.c + rm.w) * TS - 11.0, rm.r * TS + a0, 9.0, a1 - a0, v == 15])
				k = k1 + 1
		rm.lt = lt
	for l in rm.lt:
		g.rect(l[0] + 3, l[1] + 4, l[2], l[3], Color(0, 0, 0, 0.35))
	for l in rm.lt:
		var col: Color = LINTEL_WIN if l[4] else LINTEL
		g.rect(l[0], l[1], l[2], l[3], col)
		g.rect(l[0], l[1], l[2], 2, col.lightened(0.25))
		g.rect(l[0], l[1], 2, l[3], col.lightened(0.15))
		g.rect(l[0], l[1] + l[3] - 2, l[2], 2, col.darkened(0.35))
		g.rect(l[0] + l[2] - 2, l[1], 2, l[3], col.darkened(0.3))

static func draw_roofs(gm, g: Pen) -> void:
	var S: Dictionary = gm.S
	var p: Dictionary = S.p
	var sid: int = S.s.id
	var sighted := ads_sighted(gm, S, p)
	var gs: float = gm.ground_scale()
	var ox: float = gm.Wv / 2 - S.rcx * gs
	var oy: float = gm.Hv / 2 - S.rcy * gs
	var rects := PackedVector4Array()
	var fades := PackedVector2Array()
	var centres := PackedVector2Array()
	var rf := 1.0 - pow(0.82, minf(gm.get_process_delta_time(), 0.05) * 60.0)   # roof fade, 0.18 per frame at 60 fps
	var cam := Vector2(PV.x, PV.y)
	var shown := []
	for ri in S.rooms.size():
		var rm: Dictionary = S.rooms[ri]
		var inside: bool = p.x > rm.c * TS and p.x < (rm.c + rm.w) * TS and p.y > rm.r * TS and p.y < (rm.r + rm.h) * TS
		rm.ra = lerpf(rm.ra, 0.05 if inside else 1.0, rf)
		# aiming in through an opening fades a soft circle around where the sightline crosses
		# it; peeking in at a door fades one around the player
		if not inside and sighted.has(ri): rm.apt = sighted[ri]
		rm.ak = lerpf(rm.get("ak", 0.0), 1.0 if not inside and sighted.has(ri) else 0.0, rf)
		rm.pk = lerpf(rm.get("pk", 0.0), 1.0 if not inside and peeking(S, p, rm) else 0.0, rf)
		if (rm.ak > 0.01 or rm.pk > 0.01) and rects.size() < 16:
			rects.append(Vector4(rm.c * TS * gs + ox, rm.r * TS * gs + oy, ((rm.c + rm.w) * TS + 10) * gs + ox, ((rm.r + rm.h) * TS + 10) * gs + oy))
			fades.append(Vector2(rm.ak, rm.pk))
			var apt: Vector2 = rm.get("apt", Vector2.ZERO)
			centres.append(Vector2(apt.x * gs + ox, apt.y * gs + oy))
		if rm.ra < 0.02: continue
		if not Rect2(rm.c * TS, rm.r * TS, rm.w * TS, rm.h * TS).grow(80).intersects(VIEW): continue
		g.ga = rm.ra
		draw_box3d(g, 0, rm.c * TS + 10, rm.r * TS + 10, rm.w * TS - 20, rm.h * TS - 20, ROOF_H, cam, SUN, Color.BLACK)
		shown.append(rm)
	g.ga = 1.0
	# then the walls you can see between the ground and each roof (on the sides facing the
	# middle of the screen), then the roof itself, which stays where it always was
	for rm in shown:
		var x: float = rm.c * TS + 10
		var y: float = rm.r * TS + 10
		var w: float = rm.w * TS - 20
		var h: float = rm.h * TS - 20
		g.ga = rm.ra
		var k := ROOF_H / maxf(PV.z - ROOF_H, PV.z * 0.25)
		var b := (cam - Vector2(x + w / 2, y + h / 2)) * (k / (1.0 + k))
		draw_box3d(g, 1, x + b.x, y + b.y, w, h, ROOF_H, cam, SUN, U.shade(hc(rm.roof if rm.roof else "#6b5a4a"), 0.5).lerp(WALL_FOOT, 0.5))
		g.save(); g.translate(x, y)
		draw_roof(g, rm, sid, w, h)
		g.restore()
		g.ga = 1.0
	for rm in S.rooms:
		if Rect2(rm.c * TS, rm.r * TS, rm.w * TS, rm.h * TS).grow(40).intersects(VIEW): draw_lintels(g, S, rm)
	var m: ShaderMaterial = gm.roof_mat
	m.set_shader_parameter("screen", Vector2(gm.Wv, gm.Hv))
	m.set_shader_parameter("ppos", Vector2(p.x * gs + ox, p.y * gs + oy))
	m.set_shader_parameter("circ_r", PEEK_RADIUS * TS * gs)
	m.set_shader_parameter("ads_r", ADS_RADIUS * TS * gs)
	m.set_shader_parameter("peek_a", PEEK_ALPHA)
	m.set_shader_parameter("nrooms", rects.size())
	for i in range(rects.size(), 16):
		rects.append(Vector4.ZERO)
		fades.append(Vector2.ZERO)
		centres.append(Vector2.ZERO)
	m.set_shader_parameter("rooms", rects)
	m.set_shader_parameter("centres", centres)
	m.set_shader_parameter("fades", fades)
	for rm in S.rooms:
		if rm.sign == null or not on_view((rm.door[0] + 1) * TS, rm.door[1] * TS, 120): continue
		var dc: int = rm.door[0]
		var dr: int = rm.door[1]
		var top: bool = rm.door[2]
		var x := (dc + 1) * TS
		var y := (dr + 1) * TS + 4 if top else dr * TS - 4
		var tw := Pen.measure(rm.sign, 8, "700") + 12
		g.rect(x - tw / 2 + 2, y - 6, tw, 14, Color(0, 0, 0, 0.35))
		g.rect(x - tw / 2, y - 8, tw, 14, hc("#e8dcc0"))
		g.stroke_rect(x - tw / 2 + 1.5, y - 6.5, tw - 3, 11, hc("#3a3028"), 1)
		g.text(rm.sign, x, y - 0.5, 8, hc("#2a221a"), 0, "700")

## Looking in through a doorway: standing directly in front of one of the building's
## door openings (outside, or in the doorway, within PEEK_DIST of the wall) with your facing
## line passing in through that opening makes the roof see-through in a soft circle around
## the player (PEEK_RADIUS).
const PEEK_RADIUS := 6.0  # tiles: peeking cuts a soft circle this big around the player out of the roof
const PEEK_DIST := PEEK_RADIUS   # tiles out from the wall (same as the see-through circle)
const PEEK_ALPHA := 0.3   # roof opacity where it's cut while peeking or aiming in (inside the building the whole roof is 0.05)

static func peeking(S: Dictionary, p: Dictionary, rm: Dictionary) -> bool:
	var c0: int = rm.c
	var r0: int = rm.r
	var c1: int = rm.c + rm.w - 1
	var r1: int = rm.r + rm.h - 1
	var reach := PEEK_DIST * TS
	# quick reject: player nowhere near this building
	if p.x < c0 * TS - reach or p.x > (c1 + 1) * TS + reach or p.y < r0 * TS - reach or p.y > (r1 + 1) * TS + reach: return false
	var fx := cos(p.ang)
	var fy := sin(p.ang)
	var cols: int = S.cols
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var edge_c := c == c0 or c == c1
			var edge_r := r == r0 or r == r1
			if not (edge_c or edge_r) or (edge_c and edge_r): continue   # perimeter only, skip corners
			var gv: int = S.g[r * cols + c]
			if gv != 2 and gv != 15: continue   # not an opening (doorway or window)
			var ix := 0.0
			var iy := 0.0
			if r == r0: iy = 1.0
			elif r == r1: iy = -1.0
			elif c == c0: ix = 1.0
			else: ix = -1.0
			var dx: float = p.x - (c + 0.5) * TS
			var dy: float = p.y - (r + 0.5) * TS
			var out := -(dx * ix + dy * iy)   # how far outside the wall line (negative = in the doorway)
			var side := dx * -iy + dy * ix   # sideways from this opening tile's centre
			if out > reach or out < -0.5 * TS: continue   # too far out, or already past the doorway
			if absf(side) > 0.5 * TS: continue   # not directly in front of this tile of the opening
			# looking in: the facing line must cross the wall through an opening tile
			var fin := fx * ix + fy * iy
			if fin < 0.2: continue
			var hx: float = p.x + fx * (out / fin)
			var hy: float = p.y + fy * (out / fin)
			var hc_: int = clampi(int(floor(hx / TS)), c0, c1) if iy != 0.0 else c
			var hr_: int = clampi(int(floor(hy / TS)), r0, r1) if ix != 0.0 else r
			var hv: int = S.g[hr_ * cols + hc_]
			if hv == 2 or hv == 15: return true
	return false

## Aiming in through an opening: while aiming down sights, follow the sightline from the
## player towards the reticle (and on past it) until it hits a wall. Any building it
## enters through a door opening gets a see-through circle (ADS_RADIUS), centred where the
## sightline crosses that opening. Returns {room index (into S.rooms): crossing point}.
const ADS_PEEK_RANGE := 20.0   # tiles the sightline is followed
const ADS_RADIUS := 3.0        # tiles: radius of the soft circle cut out of the roof (half the peek circle)

static func ads_sighted(gm, S: Dictionary, p: Dictionary) -> Dictionary:
	var hit := {}
	if not gm.ads: return hit
	var wp: Vector2 = gm.s2w_g(gm.reticle_pos().x, gm.reticle_pos().y)
	var dir := Vector2(wp.x - p.x, wp.y - p.y)
	if dir.length() < 1.0: return hit
	dir = dir.normalized()
	var cols: int = S.cols
	var through := {}   # rooms whose door opening the sightline has crossed: where it crossed
	var lc := -999
	var lr := -999
	var n := int(ADS_PEEK_RANGE * TS / 4.0)
	for i in range(1, n + 1):
		var q := Vector2(p.x, p.y) + dir * (4.0 * i)
		var c := int(floor(q.x / TS))
		var r := int(floor(q.y / TS))
		if c == lc and r == lr: continue
		lc = c; lr = r
		if gm.solid_b(q.x, q.y): break
		for ri in S.rooms.size():
			var rm: Dictionary = S.rooms[ri]
			if c < rm.c or r < rm.r or c >= rm.c + rm.w or r >= rm.r + rm.h: continue
			var edge: bool = c == rm.c or r == rm.r or c == rm.c + rm.w - 1 or r == rm.r + rm.h - 1
			if edge:
				var gv: int = S.g[r * cols + c]
				if (gv == 2 or gv == 15) and not through.has(ri): through[ri] = q
			elif through.has(ri) and not hit.has(ri):
				hit[ri] = through[ri]
	return hit

static func draw_roof(g: Pen, rm: Dictionary, sid: int, w: float, h: float) -> void:
	var col := hc(rm.roof if rm.roof else "#6b5a4a")
	var H1 := func(a: int, b: int) -> float: return U.hash3(a, b, sid * 13 + rm.c * 7 + rm.r)
	if rm.flat:
		g.rect(0, 0, w, h, col)
		var x := 6.0
		while x < w:
			g.rect(x, 4, 1, h - 8, Color(1, 1, 1, 0.05))
			x += 12
		g.stroke_rect(2, 2, w - 4, h - 4, U.shade(col, 0.62), 4)
		g.stroke_rect(4.5, 4.5, w - 9, h - 9, Color(1, 1, 1, 0.12), 1)
		var nac := 3 if w > 200 else 2
		for k in nac:
			var ax: float = 8 + (k + H1.call(k, 1) * 0.6) * (w - 40) / nac
			var ay: float = 8 + H1.call(1, k) * (h - 34)
			g.rect(ax + 4, ay + 5, 24, 18, Color(0, 0, 0, 0.35))
			g.rect(ax, ay, 24, 18, hc("#9ea2a4"))
			g.circle(ax + 12, ay + 9, 6, hc("#6c7072"))
			g.lines(PackedVector2Array([Vector2(ax + 6, ay + 9), Vector2(ax + 18, ay + 9), Vector2(ax + 12, ay + 3), Vector2(ax + 12, ay + 15)]), hc("#4a4e50"), 1)
		for k in 4:
			g.ellipse(H1.call(k, 5) * w, H1.call(5, k) * h, 8 + H1.call(k, k) * 14, 5 + H1.call(k, 7) * 8, 0, rgba(30, 25, 20, 0.12))
	else:
		var hz := w >= h
		var L := h if hz else w
		var c1 := U.shade(col, 1.28)
		var c2 := U.shade(col, 1.05)
		var c3 := U.shade(col, 0.72)
		var c4 := U.shade(col, 0.58)
		if hz:
			g.poly_grad(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h / 2), Vector2(0, h / 2)]), PackedColorArray([c1, c1, c2, c2]))
			g.poly_grad(PackedVector2Array([Vector2(0, h / 2), Vector2(w, h / 2), Vector2(w, h), Vector2(0, h)]), PackedColorArray([c3, c3, c4, c4]))
		else:
			g.poly_grad(PackedVector2Array([Vector2(0, 0), Vector2(w / 2, 0), Vector2(w / 2, h), Vector2(0, h)]), PackedColorArray([c1, c2, c2, c1]))
			g.poly_grad(PackedVector2Array([Vector2(w / 2, 0), Vector2(w, 0), Vector2(w, h), Vector2(w / 2, h)]), PackedColorArray([c3, c4, c4, c3]))
		var ln := PackedVector2Array()
		var q := 5.0
		while q < L:
			if hz: ln.append_array([Vector2(0, q), Vector2(w, q)])
			else: ln.append_array([Vector2(q, 0), Vector2(q, h)])
			q += 6
		g.lines(ln, Color(0, 0, 0, 0.16), 1)
		var tk := PackedVector2Array()
		q = 5.0
		var row := 0
		var span := w if hz else h
		while q < L:
			var s2 := float((row % 2) * 5)
			while s2 < span:
				if hz: tk.append_array([Vector2(s2, q - 6), Vector2(s2, q)])
				else: tk.append_array([Vector2(q - 6, s2), Vector2(q, s2)])
				s2 += 10
			q += 6
			row += 1
		g.lines(tk, Color(0, 0, 0, 0.08), 1)
		if hz: g.rect(0, h / 2 - 1.5, w, 3, U.shade(col, 1.4))
		else: g.rect(w / 2 - 1.5, 0, 3, h, U.shade(col, 1.4))
		g.stroke_rect(1, 1, w - 2, h - 2, Color(0, 0, 0, 0.3), 2)
		if rm.kind == "house" or H1.call(3, 3) < 0.4:
			var cx2: float = w * (0.25 + H1.call(2, 2) * 0.5) if hz else w * 0.3
			var cy2: float = h * 0.28 if hz else h * (0.25 + H1.call(2, 2) * 0.5)
			g.rect(cx2 + 3, cy2 + 4, 10, 10, Color(0, 0, 0, 0.35))
			g.rect(cx2, cy2, 10, 10, hc("#6a4a3a"))
			g.rect(cx2 + 2, cy2 + 2, 6, 6, hc("#2a2220"))
		if H1.call(9, 9) < 0.18:
			var hx: float = w * (0.3 + H1.call(4, 4) * 0.4)
			var hy: float = h * (0.3 + H1.call(6, 6) * 0.4)
			g.ellipse(hx, hy, 12, 9, 0, rgba(15, 10, 8, 0.85))
			g.stroke_ellipse(hx, hy, 12, 9, 0, hc("#3a2a1e"), 2)
	var ga0 := g.ga
	for k in 7:
		var s2: float = 18 + H1.call(k, 20) * 50
		g.ga = ga0 * (0.1 + H1.call(k, 21) * 0.08)
		g.tex(Tx.SPUFF, H1.call(k, 22) * w - s2 / 2, H1.call(k, 23) * h - s2 / 2, s2, s2)
	if not rm.flat:
		for k in 4:
			var s2: float = 10 + H1.call(k, 24) * 22
			g.ga = ga0 * 0.25
			g.tex(Tx.GPUFF, H1.call(k, 25) * w - s2 / 2, H1.call(k, 26) * h - s2 / 2, s2, s2 * 0.7)
		g.ga = ga0
		for k in 6: g.rect(H1.call(k, 27) * w, H1.call(k, 28) * h, 5, 4, rgba(20, 16, 12, 0.45))
		if H1.call(8, 8) < 0.2:
			g.save(); g.translate(w * (0.3 + H1.call(5, 5) * 0.4), h * (0.3 + H1.call(6, 5) * 0.4)); g.rotate(H1.call(7, 7) - 0.5)
			g.rect(-16, -12, 32, 24, hc("#3a5f8a"))
			g.rect(-16, -12, 32, 3, Color(1, 1, 1, 0.15))
			for c in [[-14, -10], [14, -10], [-14, 10], [14, 10]]: g.rect(c[0] - 1, c[1] - 1, 2, 2, hc("#dddddd"))
			g.restore()
	else:
		g.ga = ga0
		var ln := PackedVector2Array()
		for k in 5:
			var x2: float = H1.call(k, 29) * w
			ln.append_array([Vector2(x2, 2), Vector2(x2 + (H1.call(k, 30) - 0.5) * 6, 8 + H1.call(k, 31) * h * 0.5)])
		g.lines(ln, rgba(120, 60, 30, 0.22), 2)
		g.ellipse(w * H1.call(1, 32), h * H1.call(2, 32), 14, 8, 0, rgba(30, 40, 50, 0.25))
	g.ga = ga0

static var zseeds := {}
static func _zkey_seed(key: String) -> int:
	if zseeds.has(key): return zseeds[key]
	var sd := 0
	for ch in key:
		sd = (sd * 31 + ch.unicode_at(0)) & 0xFFFFFFFF
		if sd >= 0x80000000: sd -= 0x100000000
	zseeds[key] = sd
	return sd

static func z_sprite(g: Pen, z: Dictionary) -> void:
	var kind: String = z.kind
	var shirt: String = "#5d6b3e" if kind == "bloat" else ("#2e2e30" if kind == "scream" else z.shirt)
	var skin: String = "#9fb07a" if kind == "bloat" else ("#d4d2c4" if kind == "scream" else z.skin)
	var v: int = z["var"]
	var key := (kind if kind != "" else "n") + shirt + skin + str(v) + ("a" if z.arm else "")
	var Rn := U.Mulberry.new(_zkey_seed(key))
	var sc := hc(skin)
	var tw := 9.5 if kind == "bloat" else (7.0 if kind == "crawler" else 7.5)
	var th := 13.0 if kind == "bloat" else (10.0 if kind == "crawler" else 11.5)
	var body := PackedVector2Array()
	for i in 22:
		var a := float(i) / 22 * TAU
		var rj := 1 + (Rn.next() - 0.5) * 0.2
		body.append(Vector2(cos(a) * tw * rj, sin(a) * th * rj))
	Rn.next()
	g.poly(body, hc(shirt))
	var bc := body.duplicate(); bc.append(body[0])
	g.polyline(bc, Color(0, 0, 0, 0.5), 0.8)
	for i in 3: g.ellipse((Rn.next() - 0.5) * 8, (Rn.next() - 0.5) * 14, 1.2 + Rn.next() * 1.8, 0.8 + Rn.next() * 1.3, Rn.next() * 3, sc)
	if v == 2:
		g.ellipse(-1, 0, 4, 6, 0, U.shade(sc, 0.85))
		var ln := PackedVector2Array()
		for i in range(-2, 3):
			ln.append(Vector2(-4, i * 2.2)); ln.append(Vector2(2, i * 2.2))
		g.lines(ln, rgba(70, 15, 12, 0.8), 0.8)
	for i in 5:
		var r := 70 + int(Rn.next() * 45)
		var a := 0.5 + Rn.next() * 0.4
		g.ellipse((Rn.next() - 0.3) * 9, (Rn.next() - 0.5) * 16, 1.4 + Rn.next() * 3, 1 + Rn.next() * 2.3, Rn.next() * 3, rgba(r, 6, 4, a))
	if kind == "bloat":
		for i in 7: g.circle((Rn.next() - 0.5) * 14, (Rn.next() - 0.5) * 20, 0.8 + Rn.next() * 1.5, rgba(205, 200, 90, 0.75))
	g.ellipse(-3.5, 0, 4, tw * 1.15, 0, Color(0, 0, 0, 0.2))
	var hx := 7.0 if kind == "crawler" else 3.2
	g.circle(hx, 0, 5.6, sc)
	g.ring(hx, 0, 5.6, Color(0, 0, 0, 0.45), 0.6)
	g.pie(hx - 1.5, 0, 4.6, PI * 0.5, PI * 1.5, Color(0, 0, 0, 0.15))
	var vl := PackedVector2Array()
	for i in 4:
		vl.append(Vector2(hx - 3 + Rn.next() * 2, (Rn.next() - 0.5) * 6))
		vl.append(Vector2(hx - 1 + Rn.next() * 3, (Rn.next() - 0.5) * 8))
	g.lines(vl, rgba(50, 60, 90, 0.45), 0.4)
	if z.arm:
		g.pie(hx - 0.5, 0, 6.7, PI * 0.4, PI * 1.6, hc("#50584a"))
	elif kind != "scream":
		for i in 6:
			var a := PI * (0.55 + Rn.next() * 0.9)
			g.ellipse(hx + cos(a) * 3.9, sin(a) * 3.9, 1.9, 1, a, hc("#211d19"))
	g.ellipse(hx + 3, -2.1, 1.4, 1.05, 0, rgba(15, 4, 4, 0.95))
	g.ellipse(hx + 3, 2.1, 1.4, 1.05, 0, rgba(15, 4, 4, 0.95))
	g.ellipse(hx + 5, 0, 1.15, 2.9 if kind == "scream" else 1.9, 0, hc("#3a0806"))
	g.ellipse(hx + 4.4, 1.6, 1, 2, 0.3, rgba(130, 10, 8, 0.65))
	g.rect(hx + 5.3, -1, 0.6, 0.7, rgba(230, 225, 200, 0.7))
	g.rect(hx + 5.3, 0.4, 0.6, 0.7, rgba(230, 225, 200, 0.7))

static func draw_zombie(gm, g: Pen, z: Dictionary) -> void:
	var kind: String = z.kind
	var sc := 1.4 if kind == "bloat" else (0.95 if kind == "crawler" else 1.0)
	g.save()
	g.translate(z.x, z.y)
	if z.dormant:
		g.rotate(z.da)
		var sk := hc(z.skin)
		g.ellipse(0, 0, 13, 8, 0, U.shade(hc(z.shirt), 0.6))
		g.lines(PackedVector2Array([Vector2(4, -7), Vector2(10, -14), Vector2(-8, 6), Vector2(-16, 10)]), U.shade(sk, 0.6), 4)
		g.circle(14, 1, 5.5, U.shade(sk, 0.7))
		g.restore()
		return
	g.ellipse(3 * sc, 5 * sc, 12 * sc, 9 * sc, 0, Color(0, 0, 0, 0.34))
	var wk: float = z.wk
	var a: float = z.ang + (0.0 if kind == "crawler" else sin(wk * 0.45) * 0.14)
	if z.wind > 0: a += (randf() - 0.5) * 0.25
	g.rotate(a)
	g.scale(sc, sc)
	if z.rise > 0:
		var k: float = 1 - z.rise / 0.7
		g.rotate((1 - k) * 1.3)
		g.scale(0.65 + 0.35 * k, 0.65 + 0.35 * k)
	if z.wind > 0: g.translate(-3, 0)
	var hit: bool = z.hit > 0
	var skin := Color.WHITE if hit else hc("#9fb07a" if kind == "bloat" else ("#d4d2c4" if kind == "scream" else z.skin))
	if kind != "crawler":
		var w := sin(wk)
		g.ellipse(w * 6, -4.5, 4.5, 3, 0, hc("#1c1a17"))
		g.ellipse(-w * 6, 4.5, 4.5, 3, 0, hc("#1c1a17"))
	else:
		g.line(-5, 0, -15, sin(wk) * 2, rgba(70, 10, 8, 0.75), 6)
	var reach := 25.0 if z.lng > 0 else (12.0 if z.wind > 0 else (21.0 if kind == "crawler" else 18.0))
	var sw := sin(wk * 0.7) * 2.5
	var sleeve := Color.WHITE if hit else U.shade(hc("#5d6b3e" if kind == "bloat" else ("#2e2e30" if kind == "scream" else z.shirt)), 0.8)
	var arm := func(sy: float, ph: float) -> void:
		g.line(1, sy, 10, sy + ph * 0.5, sleeve, 5)
		g.line(10, sy + ph * 0.5, reach, sy * 0.8 + ph, skin, 3.6)
		var fl := PackedVector2Array()
		for f in range(-1, 2):
			fl.append(Vector2(reach, sy * 0.8 + ph)); fl.append(Vector2(reach + 3.8, sy * 0.8 + ph + f * 2.2))
		g.lines(fl, skin, 1.1)
	arm.call(-8.0, sw)
	if z["var"] != 3: arm.call(8.0, -sw)
	else: g.circle(2, 9, 2.6, hc("#5a0e0a"))
	z_sprite(g, z)
	if hit: g.ellipse(0, 0, 8, 12, 0, Color(1, 1, 1, 0.55))
	g.restore()

## A smoke grenade's cloud: overlapping grey puffs drifting slowly, thick enough in the middle
## to hide anyone in it, thinning and spreading as it dies away.
static func draw_cloud(g: Pen, cl: Dictionary, T: float) -> void:
	var den: float = cl.den
	if den <= 0.01: return
	var R: float = cl.r
	var sd: int = int(cl.seed)
	for q in 12:
		var a := float(sd + q * 137) * 0.618 * TAU + T * 0.15 * (1.0 if q % 2 == 0 else -1.0)
		var rr := R * (0.15 + 0.45 * fmod(float(sd * 7 + q * 53) * 0.0137, 1.0))
		var pr := R * (0.42 + 0.12 * sin(T * 0.7 + q))
		var shade := 0.68 + 0.08 * float(q % 3)
		g.circle(cl.x + cos(a) * rr, cl.y + sin(a) * rr, pr, Color(shade, shade, shade * 0.98, 0.42 * den))
	g.circle(cl.x, cl.y, R * 0.55, Color(0.74, 0.74, 0.72, 0.5 * den))

static func draw_person(g: Pen, x: float, y: float, a: float, o: Dictionary) -> void:
	g.save()
	g.translate(x, y)
	g.ellipse(3, 5, 12, 9, 0, Color(0, 0, 0, 0.3))
	g.rotate(a)
	var w := sin(o.get("walk", 0.0))
	var hit: bool = o.get("hit", false)
	var skin := Color.WHITE if hit else hc(o.skin)
	var body := Color.WHITE if hit else hc(o.body)
	g.ellipse(w * 6, -4.5, 4.5, 3, 0, hc("#211d19"))
	g.ellipse(-w * 6, 4.5, 4.5, 3, 0, hc("#211d19"))
	var swing: bool = o.get("swing", false)
	if o.get("gun", false):
		var lng: bool = o.get("long", false)
		# "lower" 0..1: gun swung down across the body (relaxed carry) instead of aimed ahead
		var rot: float = float(o.get("lower", 0.0)) * 0.85
		var pv := Vector2(4, 3)
		if rot != 0:
			g.save(); g.translate(pv.x, pv.y); g.rotate(rot); g.translate(-pv.x, -pv.y)
		g.rect(7, 0.5, 23.0 if lng else 15.0, 3.5, hc("#161615"))
		if lng: g.rect(3, 0, 8, 4.5, hc("#5a3e26"))
		if rot != 0: g.restore()
		var e1 := pv + (Vector2(8, -2) - pv).rotated(rot)
		var e2 := pv + (Vector2(10, 4) - pv).rotated(rot)
		var h1 := pv + (Vector2(9, -1.5) - pv).rotated(rot)
		var h2 := pv + (Vector2(11, 3.5) - pv).rotated(rot)
		g.lines(PackedVector2Array([Vector2(0, -8), e1, Vector2(0, 8), e2]), body, 4.5)
		g.circle(h1.x, h1.y, 2.6, skin)
		g.circle(h2.x, h2.y, 2.6, skin)
	elif o.get("bare", false):   # empty-handed: arms in, nothing in them
		g.lines(PackedVector2Array([Vector2(0, -8), Vector2(5, -7), Vector2(0, 8), Vector2(5, 7)]), body, 4.5)
		g.circle(6, -6.5, 2.4, skin)
		g.circle(6, 6.5, 2.4, skin)
	else:
		g.lines(PackedVector2Array([Vector2(0, -8), Vector2(6, -9), Vector2(0, 8), Vector2(9, 5)]), body, 4.5)
		g.line(10, 5, 30.0 if swing else 22.0, -8.0 if swing else 9.0, hc("#9a9a92"), 2.5)
	if swing: g.arc(0, 0, 30, -1, 1, rgba(230, 230, 220, 0.35), 10)
	var capc: String = o.get("cap", "")
	var pack: String = o.get("pack", "")   # a backpack without the cap (settlers)
	if capc != "" or pack != "":
		g.rect(-12, -6, 6, 12, hc(pack if pack != "" else "#4a4232"))
		g.rect(-12, -6, 2, 12, Color(0, 0, 0, 0.25))
	g.ellipse(0, 0, 7.5, 11.5, 0, body)
	if o.get("vest", false) and not hit:
		# body armour: grey plate vest over the shirt
		g.ellipse(0, 0, 6.2, 9.6, 0, hc("#4b5259"))
		g.rect(-3.2, -6, 6.4, 12, hc("#5f676f"))
	g.stroke_ellipse(0, 0, 7.5, 11.5, 0, Color(0, 0, 0, 0.35), 1)
	g.ellipse(-2, -3.5, 4, 6, 0, Color(1, 1, 1, 0.13))
	var fem: bool = o.get("fem", false)
	if fem:
		# women: a fuller bust out front, and long hair falling down the back
		for sy in [-3.0, 3.0]:
			g.circle(6.6, sy + signf(sy) * 0.3, 2.6, U.shade(body, 0.62))
			g.circle(6.4, sy, 2.4, body)
			g.circle(6.7, sy - 0.8, 1.0, Color(1, 1, 1, 0.18))
		var hcol := hc(o.get("hair", "#2a2620"))
		g.ellipse(-5.0, 0, 5.6, 7.4, 0, hcol)                     # hair over the shoulders
		g.ellipse(-8.6, 0, 3.4, 4.6, 0, U.shade(hcol, 0.85))      # and down the back
	g.circle(1, 0, 5.8, skin)
	if capc != "":
		g.circle(0, 0, 5.9, hc(capc))
		g.rect(3, -3.6, 4.5, 7.2, hc(capc))
	else:
		g.pie(-0.5, 0, 5.6, PI * 0.55, PI * 1.45, hc(o.get("hair", "#2a2620")))
	g.restore()

static func draw_container(gm, g: Pen, k: Dictionary) -> void:
	var S: Dictionary = gm.S
	var x: float = k.x
	var y: float = k.y
	var o: bool = k.open
	var pl := 0.5 + 0.5 * sin(gm.T * 4 + k.id)
	var near_d := Vector2(S.p.x - x, S.p.y - y).length()
	g.save()
	g.translate(x, y)
	var shadow := func(w: float, h: float): g.rect(-w / 2 + 4, -h / 2 + 5, w, h, Color(0, 0, 0, 0.32))
	match k.ty:
		"locker":
			shadow.call(30, 16)
			g.rect(-15, -8, 30, 16, hc("#3c4228") if o else hc("#5a6236"))
			g.rect(-15, -8, 30, 3, Color(1, 1, 1, 0.12))
			if o: g.rect(-12, -5, 24, 10, hc("#2b2e1c"))
			else:
				g.rect(-11, -2, 3, 5, hc("#2b2e1c")); g.rect(8, -2, 3, 5, hc("#2b2e1c"))
				g.text_base("U.S.", 0, 3, 6, hc("#c8b070"), 0, "700")
		"register":
			shadow.call(20, 18)
			g.rr(-10, -9, 20, 18, 3, hc("#4a4c4e") if o else hc("#6d7174"))
			g.rect(-7, -7, 14, 5, hc("#1d2a22"))
			g.rect(-8, 2, 16, 6, hc("#23180e") if o else hc("#b8bcbf"))
			if not o: g.rect(-5, -6, 6, 2, hc("#8ee07a"))
		"toolbox":
			shadow.call(24, 12)
			g.rr(-12, -6, 24, 12, 2, hc("#6e2016") if o else hc("#b8321f"))
			g.rect(-12, -6, 24, 2, Color(1, 1, 1, 0.18))
			g.polyline(PackedVector2Array([Vector2(-5, -6), Vector2(-5, -9), Vector2(5, -9), Vector2(5, -6)]), hc("#2a2a2a"), 2)
			if o: g.rect(-10, -3, 20, 7, hc("#2a1a12"))
		"cabinet":
			shadow.call(20, 20)
			g.rect(-10, -10, 20, 20, hc("#9c9a92") if o else hc("#e4e1d6"))
			g.stroke_rect(-10, -10, 20, 20, Color(0, 0, 0, 0.25), 1)
			if o: g.rect(-8, -8, 16, 16, hc("#4a4842"))
			else:
				g.rect(-2, -7, 4, 14, hc("#c0392b")); g.rect(-7, -2, 14, 4, hc("#c0392b"))
		"jerry":
			for cn in [[-7, -3, "#8a2a1c"], [5, 2, "#4b5a2f"], [-2, 8, "#8a2a1c"]]:
				var ccx: float = cn[0]
				var ccy: float = cn[1]
				g.rect(ccx - 5, ccy - 5, 14, 12, Color(0, 0, 0, 0.3))
				g.rr(ccx - 7, ccy - 6, 13, 11, 2, U.shade(hc(cn[2]), 0.5) if o else hc(cn[2]))
				g.rect(ccx - 6, ccy - 5, 11, 2, Color(1, 1, 1, 0.15))
				g.rect(ccx + 2, ccy - 7, 3, 2, hc("#222222"))
		"dresser":
			shadow.call(26, 14)
			g.rect(-13, -7, 26, 14, hc("#3a2818") if o else hc("#5e3f26"))
			g.lines(PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(0, -7), Vector2(0, 7)]), Color(0, 0, 0, 0.35), 1)
			for d in [[-6, -3.5], [6, -3.5], [-6, 3.5], [6, 3.5]]: g.rect(d[0] - 1, d[1] - 1, 2, 2, hc("#c8a860"))
			if o: g.rect(1, 1, 11, 5, hc("#1c130b"))
		"desk":
			shadow.call(34, 18)
			g.rect(-17, -9, 34, 18, hc("#4a3522") if o else hc("#6e4e30"))
			g.rect(-17, -9, 34, 3, Color(1, 1, 1, 0.08))
			if not o:
				g.save(); g.rotate(0.2); g.rect(-10, -5, 10, 8, hc("#e8e2d0")); g.restore()
				g.rect(4, -4, 8, 6, hc("#e8e2d0"))
			else: g.rect(-14, 0, 12, 7, hc("#2a1c10"))
		"safe":
			shadow.call(20, 20)
			g.rect(-10, -10, 20, 20, hc("#4a4f54"))
			g.rect(-10, -10, 20, 3, Color(1, 1, 1, 0.12))
			g.stroke_rect(-8, -8, 16, 16, hc("#2a2e32"), 1.5)
			if o:
				g.rect(-7, -7, 14, 14, hc("#15181a"))
				g.save(); g.translate(8, -8); g.rotate(-0.9); g.rect(0, 0, 16, 3, hc("#5a6066")); g.restore()
			else:
				g.circle(0, 0, 4, hc("#b8bcc0"))
				g.rect(-0.7, -4, 1.4, 3, hc("#2a2e32"))
				g.rect(5, -1, 3, 6, hc("#8a8e92"))
		"stash":
			if o:
				g.rect(-9, -4, 18, 8, hc("#15100a"))
				g.save(); g.rotate(0.4); g.rect(4, -10, 18, 5, hc("#6a5236")); g.restore()
			elif near_d < 110:
				g.save(); g.rotate(0.06); g.rect(-10, -3.5, 20, 7, hc("#7a5c3a")); g.rect(-10, 3.5, 20, 1.5, Color(0, 0, 0, 0.4)); g.restore()
				var tw := 0.5 + 0.5 * sin(gm.T * 9)
				g.poly(PackedVector2Array([Vector2(3, -8), Vector2(4, -5), Vector2(7, -4), Vector2(4, -3), Vector2(3, 0), Vector2(2, -3), Vector2(-1, -4), Vector2(2, -5)]), rgba(255, 235, 170, tw))
		_:
			shadow.call(22, 22)
			if o:
				g.rect(-11, -11, 22, 22, hc("#5e4629"))
				g.rect(-8, -8, 16, 16, hc("#231a11"))
				g.save(); g.translate(12, -4); g.rotate(0.5); g.rect(-10, -3, 20, 6, hc("#7a5c36")); g.restore()
			else:
				g.rect(-11, -11, 22, 22, hc("#8c6c40"))
				g.rect(-11, -11, 11, 11, rgba(255, 230, 180, 0.14))
				g.stroke_rect(-10, -10, 20, 20, hc("#4d3920"), 1.5)
				g.lines(PackedVector2Array([Vector2(-10, -3.5), Vector2(10, -3.5), Vector2(-10, 3.5), Vector2(10, 3.5)]), hc("#4d3920"), 1.5)
				g.rect(-10, -10, 20, 2, rgba(255, 240, 200, 0.2))
	if not o and (k.ty != "stash" or near_d < 110):
		g.ring(0, 0, 21, rgba(240, 200, 120, 0.2 + 0.35 * pl), 1.5)
	g.restore()

static func draw_item(g: Pen, k: String, x: float, y: float) -> void:
	g.save()
	g.translate(x, y)
	match k:
		"fuel":
			g.rr(-5, -6, 10, 12, 2, hc("#a8301f")); g.rect(1, -8, 3, 2, hc("#222222")); g.rect(-4, -5, 8, 2, Color(1, 1, 1, 0.2))
		"ammo":
			for q in range(-1, 2):
				g.rect(q * 4 - 1.5, -4, 3, 8, hc("#d9b35a")); g.rect(q * 4 - 1.5, -6, 3, 3, hc("#8a5a2a"))
		"cash":
			g.rect(-7, -4, 14, 8, hc("#4f7a3a")); g.rect(-6, -3, 12, 6, hc("#8fc06a")); g.ellipse(0, 0, 2.5, 2, 0, hc("#4f7a3a"))
		"band":
			g.rect(-6, -3, 12, 6, hc("#e8e4d8")); g.rect(-1, -2.5, 2, 5, hc("#c0392b")); g.rect(-3, -1, 6, 2, hc("#c0392b"))
		"med":
			g.rect(-6, -6, 12, 12, hc("#e8e4d8")); g.rect(-1.5, -4.5, 3, 9, hc("#c0392b")); g.rect(-4.5, -1.5, 9, 3, hc("#c0392b"))
		"parts":
			var pts := PackedVector2Array()
			for q in 8:
				var a := q / 8.0 * TAU
				pts.append(Vector2(cos(a) * 6.5, sin(a) * 6.5)); pts.append(Vector2(cos(a + 0.2) * 4.5, sin(a + 0.2) * 4.5))
			g.poly(pts, hc("#9aa0a4")); g.circle(0, 0, 2, hc("#3a3e40"))
		"goods":
			g.rect(-6, -5, 12, 10, hc("#7a4a7a")); g.rect(-1, -5, 2, 10, hc("#c9a0c9")); g.rect(-6, -1, 12, 2, hc("#c9a0c9"))
		"bomb":
			g.rr(-6, -3, 12, 6, 2, hc("#55595c")); g.rect(5, -1, 2, 2, hc("#ff4a30"))
		"armor":
			g.poly(PackedVector2Array([Vector2(-6, -6), Vector2(-2, -6), Vector2(0, -3), Vector2(2, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)]), hc("#4a5a70"))
		"chart":
			g.rect(-7, -5, 14, 10, hc("#e0d6b8")); g.polyline(PackedVector2Array([Vector2(-5, 2), Vector2(-1, -2), Vector2(4, 1)]), hc("#9b2a68"), 1)
		"weapon":
			g.rect(-8, -2, 16, 3, hc("#1c1c1c")); g.rect(-8, -2, 5, 6, hc("#5a3e26"))
		_:
			var pts := PackedVector2Array()
			for q in 10:
				var a := q / 10.0 * TAU - PI / 2
				var r2 := 3.0 if q % 2 else 7.0
				pts.append(Vector2(cos(a) * r2, sin(a) * r2))
			g.poly(pts, hc("#ffd27a"))
			var pc := pts.duplicate(); pc.append(pts[0])
			g.polyline(pc, hc("#8a6a20"), 1)
	g.restore()

const RCRGB := ["232,226,208", "156,192,99", "127,178,240", "255,210,122"]
static func draw_pickups(gm, g: Pen) -> void:
	var T: float = gm.T
	for q in gm.S.pk:
		var rar: int = D.RAR[q.k]
		var bob := sin(T * 6 + q.x) * 1.5
		if rar >= 2:
			var pl := 0.6 + 0.4 * sin(T * 5 + q.y)
			g.ga = 0.55 * pl
			g.tex(Tx.glow(RCRGB[rar]), q.x - 9, q.y - 80, 18, 86)
			g.ga = 0.7
			g.tex(Tx.glow(RCRGB[rar]), q.x - 22, q.y - 22, 44, 44)
			g.ga = 1.0
		g.ellipse(q.x + 2, q.y + 3, 7, 4, 0, Color(0, 0, 0, 0.3))
		var rc := hc(D.RCOL[rar]); rc.a = 0.6
		g.ring(q.x, q.y - q.z + bob, 10, rc, 1.2)
		draw_item(g, q.k, q.x, q.y - q.z + bob)

## Bottom right: the rounds in the gun in hand as icons (bullets, shells or bolts), spent
## ones as dim slots, and a bar while reloading. Hidden when you're down to the machete.
static func draw_mag(gm, g: Pen) -> void:
	var G: Dictionary = gm.G
	if gm.ammo_left() <= 0: return
	var w: Dictionary = D.WEAPONS[G.weapon]
	var cap: int = int(w.mag)
	var n: int = gm.mag_of()
	var k: String = String(w.ammo)
	var per := 20   # icons per row (the SMG's 40 take two)
	var iw := 4.0
	var ih := 12.0
	match k:
		"shell": iw = 7.0; ih = 14.0
		"rifle": iw = 5.0; ih = 17.0
		"bolt": iw = 6.0; ih = 24.0
		"smg", "ar": iw = 3.5; ih = 11.0
	var gap := 3.0
	var cols := mini(cap, per)
	var rows := int(ceil(float(cap) / per))
	var bw := cols * (iw + gap) - gap
	var pw := maxf(bw, 110.0) + 20.0
	var ph := 30.0 + rows * (ih + 5.0) + 8.0
	var x0: float = gm.Wv - pw - 12.0
	var y0: float = gm.Hv - ph - 12.0
	g.rr(x0, y0, pw, ph, 6, rgba(12, 16, 14, 0.74))
	var rl: bool = gm.reloading()
	g.text("Reloading" if rl else String(w.name), x0 + 10, y0 + 13, 12, hc("#e8c860") if rl else hc("#b9b09a"))
	for i in cap:
		var ix := x0 + 10.0 + (i % per) * (iw + gap)
		var iy := y0 + 24.0 + floorf(float(i) / per) * (ih + 5.0)
		if i >= n:
			g.rect(ix, iy, iw, ih, Color(1, 1, 1, 0.12))   # spent
			continue
		match k:
			"shell":   # red hull, brass base
				g.rect(ix, iy, iw, ih, hc("#b8402e"))
				g.rect(ix, iy + ih * 0.68, iw, ih * 0.32, hc("#d9b35a"))
			"bolt":    # steel head, wooden shaft, red fletching
				g.poly(PackedVector2Array([Vector2(ix + iw / 2, iy), Vector2(ix + iw, iy + 5), Vector2(ix, iy + 5)]), hc("#c9ccd0"))
				g.rect(ix + iw / 2 - 1, iy + 5, 2, ih - 5, hc("#8a6a44"))
				g.rect(ix, iy + ih - 6, iw, 5, hc("#b8402e"))
			_:         # brass case, copper tip
				g.rect(ix, iy + ih * 0.3, iw, ih * 0.7, hc("#d9b35a"))
				g.rect(ix + 0.5, iy, iw - 1, ih * 0.32, hc("#b87333"))
	if rl:
		var f := 1.0 - float(gm.S.p.rl) / float(w.rl)
		g.rect(x0 + 10, y0 + ph - 7, (pw - 20), 3, Color(1, 1, 1, 0.12))
		g.rect(x0 + 10, y0 + ph - 7, (pw - 20) * f, 3, hc("#e8c860"))

static func hud_ground(gm, g: Pen) -> void:
	var S: Dictionary = gm.S
	var G: Dictionary = gm.G
	var W: float = gm.Wv
	var H: float = gm.Hv
	var T: float = gm.T
	var pw := minf(W - 24, 330)
	var px := 10.0
	var py := 10.0
	var ink := hc("#efe6cf")
	g.rr(px, py, pw, 106, 6, rgba(12, 16, 14, 0.74))
	if G.armor > 0: g.rect(px + 54, py + 24, (pw - 66) * G.armor / 100, 3, hc("#9fb6e0"))
	if S.p.stam < 100: g.rect(px + 54, py + 28, (pw - 66) * S.p.stam / 100, 2, hc("#e3644c") if S.p.stam < 15 else hc("#e8c860"))
	g.text("Health", px + 10, py + 17, 12, hc("#b9b09a"))
	g.rect(px + 54, py + 11, pw - 66, 12, Color(1, 1, 1, 0.12))
	g.rect(px + 54, py + 11, (pw - 66) * G.hp / 100, 12, hc("#e3644c") if G.hp < 30 else hc("#9cc063"))
	var aunit: String = D.AMMO[gm.ammo_key()].unit
	var aleft: int = gm.ammo_left()
	var atxt: String = ("unlimited " + aunit) if gm.unl_ammo else ("%d %s spare" % [gm.reserve_left(), aunit])
	g.text("%s   %d bomb%s" % [(D.WEAPONS[G.weapon].name + ", " + atxt) if aleft > 0 else ("Machete, no " + aunit), G.bombs, "" if G.bombs == 1 else "s"], px + 10, py + 40, 13, ink)
	g.text("%d bandage%s   %d medkit%s   %d part%s%s" % [G.band, "" if G.band == 1 else "s", G.med, "" if G.med == 1 else "s", G.parts, "" if G.parts == 1 else "s", ("   armor " + str(int(ceil(G.armor)))) if G.armor > 0 else ""], px + 10, py + 58, 13, ink)
	var awake := 0
	for z in S.zs:
		if not z.dormant: awake += 1
	g.text("$%d   %d gal in cans   %d dead in sight" % [G.cash, int(floor(G.carried)), awake], px + 10, py + 76, 13, ink)
	var dk: float = gm.dark()
	g.text("Day %d, %s%s" % [gm.day(), gm.clock(), ". Night, they move faster" if dk > 0.5 else ""], px + 10, py + 94, 13, hc("#9fb6e0") if dk > 0.5 else hc("#b9b09a"))
	if gm.ASH.is_empty():
		for i in 22: gm.ASH.append({"x": randf(), "y": randf(), "s": 0.4 + randf(), "o": randf() * 9})
	for a in gm.ASH:
		var x := fposmod(a.x + T * 0.012 * a.s + sin(T * 0.7 + a.o) * 0.01, 1.0) * W
		var y := fmod(a.y + T * 0.02 * a.s, 1.0) * H
		g.circle(x, y, 0.8 + a.s * 0.7, rgba(200, 196, 188, 0.2))
	draw_objective(gm, g, py + 112)
	draw_mag(gm, g)
	var nx := 10.0
	var ny := py + 162
	var nw := minf(W - 24, 220)
	var f: float = S.noise / 100.0
	g.rr(nx, ny, nw, 20, 5, rgba(12, 16, 14, 0.74))
	g.rect(nx + 56, ny + 7, nw - 64, 6, Color(1, 1, 1, 0.1))
	var nc: Color
	if f >= 1: nc = hc("#ff5a3a") if fmod(T, 0.4) < 0.2 else hc("#a3301f")
	elif f > 0.65: nc = hc("#e3644c")
	elif f > 0.35: nc = hc("#e0a040")
	else: nc = hc("#b9b09a")
	g.rect(nx + 56, ny + 7, (nw - 64) * f, 6, nc)
	for q in [0.35, 0.65]: g.rect(nx + 56 + (nw - 64) * q - 1, ny + 5, 2, 10, Color(0, 0, 0, 0.5))
	g.text("HORDE" if f >= 1 else "Noise", nx + 8, ny + 10, 11, hc("#ff8a70") if f >= 1 else ink)
	# clearing and settling (fields.gd): enemies left to kill, or the settlers' count, under the meter
	var fl: String = gm.fields.hud_line()
	if fl != "":
		g.rr(nx, ny + 24, minf(W - 24, Pen.measure(fl, 12) + 16), 20, 5, rgba(12, 16, 14, 0.74))
		g.text(fl, nx + 8, ny + 34, 12, hc("#9cc063") if S.get("calm", false) else hc("#f2b64a"), -1, "600")
	var gs: float = gm.ground_scale()
	if S.npcs.is_empty() and G.contracts.size():
		var sx: float = W / 2 + (S.plane.x - S.cx) * gs
		var sy: float = H / 2 + (S.plane.y - S.cy) * gs
		if sx < 20 or sx > W - 20 or sy < 150 or sy > H - 20:
			var a := atan2(sy - H / 2, sx - W / 2)
			var ex := clampf(sx, 34, W - 34)
			var ey := clampf(sy, 170, H - 40)
			g.save(); g.translate(ex, ey); g.rotate(a)
			var tri := PackedVector2Array([Vector2(14, 0), Vector2(-8, -10), Vector2(-8, 10)])
			g.poly(tri, hc("#f2b64a"))
			var tc := tri.duplicate(); tc.append(tri[0])
			g.polyline(tc, Color(0, 0, 0, 0.6), 2)
			g.restore()
			g.text("Plane", ex - cos(a) * 24, ey - sin(a) * 18, 11, hc("#f3d38c"), 0, "700")
	for n in S.npcs:
		var sx: float = W / 2 + (n.x - S.cx) * gs
		var sy: float = H / 2 + (n.y - S.cy) * gs
		if sx < 20 or sx > W - 20 or sy < 150 or sy > H - 20:
			var a := atan2(sy - H / 2, sx - W / 2)
			g.save(); g.translate(clampf(sx, 30, W - 30), clampf(sy, 170, H - 40)); g.rotate(a)
			g.poly(PackedVector2Array([Vector2(12, 0), Vector2(-7, -8), Vector2(-7, 8)]), hc("#e07ab3"))
			g.restore()
	if W > 480:
		g.text(S.s.name, W - 14, py + 17, 13, hc("#f0c4dd"), 1, "700")
		# danger level under the name: five dots, filled up to the danger level
		var dg: int = clampi(int(S.danger), 0, 5)
		for i in 5:
			var cxp: float = W - 18 - (4 - i) * 12
			if i < dg: g.circle(cxp, py + 31, 4.2, hc("#f0c4dd"))
			else: g.ring(cxp, py + 31, 3.8, rgba(240, 196, 221, 0.6), 1.3)
