class_name Failsafe
extends RefCounted
## Failsafe: an airfield near the middle of the map with a paved runway, built beside the
## farm from Greg's low-poly model (Models/test farm, LowPoly_FarmReady.blend; animals left out).
## In flight the farm is one quad that shaders/trees.gdshader draws from three images rendered
## from the model (sprites/failsafe, made by farm_render.py): the farm seen from straight above
## under an even sky, its height map, and its walls seen from eight sides. The shader traces
## each pixel's line of sight through the height map, so roofs lean like the rest of the
## world's buildings and walls show, and it casts the sun's shadows from the clock.
## On foot Failsafe is a family farm (FarmFolk). Added for every world (old saves too) after
## the rest of the map is made, so nothing else about a seed changes.

const NAME := "Failsafe"
const S := 8.0                          # world units per metre of the model (doubled from 4, Greg 2026-10-18)
const SIZE_M := Vector2(89.0, 69.0)     # area rendered by farm_render.py, metres
const HMAX_M := 16.0                    # height map range, metres
const WALL_SHEAR := 0.7                 # farm_render.py M0: sideways shift per unit of height in the wall views
const RUN_LEN := 520.0
const RUN_WID := 52.0
const GAP := 16.0                       # runway edge to the farm's road
const SPACING := 1800.0                 # at least this far from every other airfield
const GAIN := 1.15                     # farm colour brightness in flight
const SAT := 0.85                        # and saturation, so it sits with the terrain

static var COL: Texture2D
static var HGT: Texture2D
static var WALLS: Texture2D
static var MM: MultiMesh
static var HIMG: Image   # the height map, for Render.plane_shadow()
# sun shadows, made once per sun position by shaders/farm_shadow.gdshader (_bake_shadow)
const SHD_RES := 1024                   # texels across the shadow texture
const SHD_REDO := 0.5                   # remake it when the tallest shadow's tip has moved this far
static var SHD_VP: SubViewport
static var SHD_MAT: ShaderMaterial
static var SHD_SUN := Vector2(INF, INF) # the sun it was made for, farm frame
static var SHD_AREA := Vector4(0, 0, 1, 1)
static var SHD_OK := false
static var _tried := false

static func farm_size() -> Vector2:
	return SIZE_M * S

## Farm centre in the strip's own frame (runway along x, the farm on the +y side).
static func farm_off(s: Dictionary) -> Vector2:
	return Vector2(0.0, float(s.wid) / 2.0 + GAP + farm_size().y / 2.0)

# =====================================================================
# World
# =====================================================================
## Finds open grass nearest the middle of the map, with room for the runway and the farm,
## and adds the airfield as the last strip.
static func place(wd) -> void:
	wd.remove_meta("failsafe")
	var W: float = World.WORLD
	var fs := farm_size()
	var step := 250.0
	var r := 0.0
	while r < W * 0.3:
		var n := maxi(1, int(TAU * r / step))
		for i in n:
			var a := TAU * i / n
			var x := W / 2 + cos(a) * r
			var y := W / 2 + sin(a) * r
			for k in 4:
				var ang := k * PI / 4
				if _fits(wd, x, y, ang, fs):
					var s := {"id": wd.strips.size(), "name": NAME, "type": "regional", "x": x, "y": y, "ang": ang,
						"len": RUN_LEN, "wid": RUN_WID, "fuel": true, "shop": false, "dealer": false, "fuelPrice": 4,
						"seed": int(U.hash3(int(x), int(y), wd.SEED) * 1e9), "danger": 1, "arch": "family",
						"home": false, "hostile": false, "failsafe": true}
					wd.strips.append(s)
					wd.set_meta("failsafe", s)
					return
		r += step

static func _fits(wd, x: float, y: float, ang: float, fs: Vector2) -> bool:
	for s in wd.strips:
		if Vector2(s.x - x, s.y - y).length() < SPACING: return false
	var x1 := maxf(RUN_LEN, fs.x) / 2 + 40
	var x0 := -x1
	var y0 := -RUN_WID / 2 - 40
	var y1 := RUN_WID / 2 + GAP + fs.y + 30
	var c := cos(ang)
	var n := sin(ang)
	var rad := Vector2(x1, y1).length() + 60
	for rd in wd.ROADS:
		var t := clampf(((x - rd.x1) * rd.dx + (y - rd.y1) * rd.dy) / rd.len2, 0.0, 1.0)
		if Vector2(rd.x1 + rd.dx * t - x, rd.y1 + rd.dy * t - y).length() < rad: return false
	var ly := y0
	while ly <= y1:
		var lx := x0
		while lx <= x1:
			# the farm is narrower than the runway: skip ground beside it
			if (ly > RUN_WID / 2 + 40 and absf(lx) > fs.x / 2 + 30) or (ly < RUN_WID / 2 + 40 and absf(lx) > RUN_LEN / 2 + 40):
				lx += 50
				continue
			var t: int = wd.terr(x + lx * c - ly * n, y + lx * n + ly * c)
			if t != 3 and t != 4: return false
			lx += 50
		ly += 50
	return true

## The Failsafe strip of this world, if it has one. (Not always the last strip: road
## landings add strips while you play.)
static func strip_of(wd):
	return wd.get_meta("failsafe", null)

## True over the farm (plus margin m), so the scatter keeps trees off it.
static func on_farm(wd, x: float, y: float, m: float) -> bool:
	var s = strip_of(wd)
	if s == null: return false
	var p := Vector2(x - s.x, y - s.y).rotated(-s.ang) - farm_off(s)
	var h := farm_size() / 2 + Vector2(m, m)
	return absf(p.x) < h.x and absf(p.y) < h.y

## Height of the farm at (x, y), world units (0 off the farm, or before its images load).
static func height_at(wd, x: float, y: float) -> float:
	var s = strip_of(wd)
	if s == null or HIMG == null: return 0.0
	var p := -(Vector2(x - s.x, y - s.y).rotated(-s.ang) - farm_off(s))   # the farm is turned half round
	var fs := farm_size()
	var u := p.x / fs.x + 0.5
	var v := p.y / fs.y + 0.5
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0: return 0.0
	return HIMG.get_pixel(int(u * HIMG.get_width()), int(v * HIMG.get_height())).r * HMAX_M * S

# =====================================================================
# Flight view
# =====================================================================
static func _load() -> bool:
	if COL: return true
	if _tried: return false
	_tried = true
	var c := Tx._png("res://sprites/failsafe/color.png")
	var h := Tx._png("res://sprites/failsafe/height.png")
	var w := Tx._png("res://sprites/failsafe/walls.png")
	if c == null or h == null or w == null: return false
	COL = _mipped(c)
	HGT = h
	HIMG = h.get_image()
	if HIMG and HIMG.is_compressed(): HIMG.decompress()
	WALLS = _mipped(w)
	return true

## The farm is drawn far smaller than its images near the top of a climb: give them mipmaps.
static func _mipped(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null: return t
	if img.is_compressed(): img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The strip in its own frame (draw_strip has translated and rotated g).
static func draw_air(gm, g: Pen, s: Dictionary) -> void:
	var L: float = s.len
	var Wd: float = s.wid
	var asph := Render.hc("#3c3b38")
	var fo := farm_off(s)
	var fs := farm_size()
	# taxiway from the runway to the farm gate, then the runway
	g.rect(-16, Wd / 2 - 2, 32, GAP + 6, asph)
	g.rect(-L / 2 - 6, -Wd / 2 - 6, L + 12, Wd + 12, Render.rgba(20, 20, 16, 0.28))
	g.rect(-L / 2, -Wd / 2, L, Wd, asph)
	var wc := Render.hc("#e2dbc6")
	var x := -L / 2 + 50
	while x < L / 2 - 50:
		g.rect(x, -1.5, 24, 3, wc)
		x += 46
	for i in range(-3, 4):
		g.rect(-L / 2 + 8, i * Wd / 8 - 1.5, 26, 3, wc); g.rect(L / 2 - 34, i * Wd / 8 - 1.5, 26, 3, wc)
	g.rect(-L / 2 + 2, -Wd / 2 + 2, L - 4, 2, Color(wc, 0.7)); g.rect(-L / 2 + 2, Wd / 2 - 4, L - 4, 2, Color(wc, 0.7))
	for i in 8:
		g.rect(-L / 2 + 60 + U.hash3(s.id, i, 3) * (L - 120), -Wd / 4 + U.hash3(i, s.id, 4) * Wd / 2, 30, 4, Color(0, 0, 0, 0.25))
	if _load():
		_draw_farm(gm, g, s, fo, fs)
	# windsock on the open side of the runway
	var F = gm.F
	var wx := -L / 2 + 40
	var wy := -Wd / 2 - 26
	var wa: float = (atan2(F.wind.y, F.wind.x) - s.ang) if F else 0.6
	g.circle(wx, wy, 2.5, Render.hc("#dddddd"))
	g.save(); g.translate(wx, wy); g.rotate(wa + sin(gm.T * 3) * 0.08)
	g.poly(PackedVector2Array([Vector2(0, -4), Vector2(22, -2), Vector2(22, 2), Vector2(0, 4)]), Render.hc("#ff7a2a"))
	g.rect(8, -3, 4, 6, Color.WHITE)
	g.restore()

## The farm quad. Its frame: centre of the images, x along the image, y down the image;
## turned half round from the strip so the farm gate (bottom of the images) faces the runway.
static func _draw_farm(gm, g: Pen, s: Dictionary, fo: Vector2, fs: Vector2) -> void:
	Render._tb_init()
	var xf := Transform2D(float(s.ang), Vector2(s.x, s.y)) * Transform2D(0.0, fo) * Transform2D(PI, Vector2.ZERO)
	var inv := xf.affine_inverse()
	var cam: Vector2 = inv * Vector2(Render.PV.x, Render.PV.y)
	var eye: float = Render.PV.z
	var hu := HMAX_M * S
	# room around the farm for roofs leaning out and shadows falling past its edge
	var k := hu / maxf(eye - hu, eye * 0.25)
	var lean := (cam.length() + fs.length() / 2) * k
	var m := clampf(maxf(lean, Render.SUN_LEN * hu * Render.SUN_A) + 6.0, 6.0, 900.0)
	var q := fs + Vector2(m, m) * 2.0
	if MM == null:
		MM = MultiMesh.new()
		MM.transform_format = MultiMesh.TRANSFORM_2D
		MM.use_colors = true
		MM.use_custom_data = true
		MM.mesh = Render.TQUAD
		MM.instance_count = 1
		MM.set_instance_color(0, Color.WHITE)
		MM.set_instance_custom_data(0, Color(0.0, 0.0, -3.0, 0.0))
	MM.set_instance_transform_2d(0, Transform2D(Vector2(q.x, 0), Vector2(0, q.y), Vector2.ZERO))
	var mat: ShaderMaterial = Render.TREE_MAT
	if g.ci.material != mat: g.ci.material = mat
	mat.set_shader_parameter("eye", eye)
	mat.set_shader_parameter("sun_a", Render.SUN_A)
	mat.set_shader_parameter("farm_col", COL)
	mat.set_shader_parameter("farm_hgt", HGT)
	mat.set_shader_parameter("farm_wall", WALLS)
	mat.set_shader_parameter("farm_size", fs)
	mat.set_shader_parameter("farm_q", q)
	mat.set_shader_parameter("farm_cam", cam)
	mat.set_shader_parameter("farm_sun", inv.basis_xform(Render.SUN))
	mat.set_shader_parameter("farm_h", hu)
	mat.set_shader_parameter("farm_shear", WALL_SHEAR)
	mat.set_shader_parameter("farm_gain", GAIN)
	mat.set_shader_parameter("farm_sat", SAT)
	_bake_shadow(gm, inv.basis_xform(Render.SUN), fs, hu)
	mat.set_shader_parameter("farm_shd_ok", 1.0 if SHD_OK else 0.0)
	mat.set_shader_parameter("farm_shd_area", SHD_AREA)
	if SHD_VP: mat.set_shader_parameter("farm_shd", SHD_VP.get_texture())
	g.save()
	g.translate(fo.x, fo.y)
	g.rotate(PI)
	g.ci.draw_multimesh(MM, COL)
	g.restore()

## The farm's sun shadows change only as the clock moves the sun, so they are worked out into
## a texture by a one-off render, not on every pixel every frame. The texture covers the farm and
## the ground its shadows fall on; it is redone once the sun has moved a little.
static func _bake_shadow(gm, sun: Vector2, fs: Vector2, hu: float) -> void:
	if SHD_VP == null or not is_instance_valid(SHD_VP):
		SHD_VP = SubViewport.new()
		SHD_VP.size = Vector2i(SHD_RES, SHD_RES)
		SHD_VP.disable_3d = true
		SHD_VP.transparent_bg = false
		SHD_VP.render_target_update_mode = SubViewport.UPDATE_DISABLED
		SHD_MAT = ShaderMaterial.new()
		SHD_MAT.shader = load("res://shaders/farm_shadow.gdshader")
		var r := ColorRect.new()
		r.size = Vector2(SHD_RES, SHD_RES)
		r.material = SHD_MAT
		SHD_VP.add_child(r)
		gm.add_child.call_deferred(SHD_VP)
		SHD_SUN = Vector2(INF, INF)
		SHD_OK = false
		return
	if not SHD_VP.is_inside_tree(): return
	if SHD_SUN.x != INF and (sun - SHD_SUN).length() * hu < SHD_REDO:
		SHD_OK = true   # made on an earlier frame
		return
	# the farm, plus the ground its shadows reach (they fall along +sun from what casts them)
	var lo := -fs / 2
	var hi := fs / 2
	var reach := sun * hu
	lo = lo.min(lo + reach) - Vector2(4, 4)
	hi = hi.max(hi + reach) + Vector2(4, 4)
	SHD_AREA = Vector4(lo.x, lo.y, hi.x - lo.x, hi.y - lo.y)
	SHD_MAT.set_shader_parameter("farm_hgt", HGT)
	SHD_MAT.set_shader_parameter("farm_size", fs)
	SHD_MAT.set_shader_parameter("farm_h", hu)
	SHD_MAT.set_shader_parameter("farm_sun", sun)
	SHD_MAT.set_shader_parameter("area", SHD_AREA)
	SHD_VP.render_target_update_mode = SubViewport.UPDATE_ONCE
	SHD_OK = SHD_SUN.x != INF   # the first one is drawn this frame: until then farm_at marches
	SHD_SUN = sun
