class_name Game
extends Node2D
## Dead Reckoning — main game controller. A close port of the HTML game's logic.

const WORLD := 30000.0
const TS := 32.0
const SAVE_PATH := "user://deadreckoning_v1.json"

# aim down sights — on foot, hold right mouse
const ADS_MOVE := 0.5     # walk speed multiplier while aiming
const ADS_SENS := 0.5     # mouse sensitivity multiplier while aiming
const ADS_ZOOM := 0.25    # extra zoom at full aim (0.25 = 25% closer)
const ADS_LEAD := 90.0    # how far (world px) the camera leans toward where you face
const ADS_RATE := 6.0     # ease speed in/out (higher = snappier)

var wd := World.new()
var baker: Baker
var synth: Synth
var ui: UI
var layers: Array = []
var dark_rect: ColorRect
var dark_mat: ShaderMaterial
var post_mat: ShaderMaterial

var G = null            # run state (Dictionary) or null
var F = null            # flight state or null
var S = null            # ground site or null
var mode := "title"
var uist := "title"     # current overlay: "" (none), title, menu, pause, map, dead, win
var menu_tab := "contracts"
var known := {}
var CP := ""
var T := 0.0
var camX := 0.0
var camY := 0.0
var cam_snap := true
var ads := false               # aiming down sights right now
var ads_cur := Vector2.ZERO    # virtual cursor (screen px) used while aiming
var discT := 0.0
var Wv := 1280.0
var Hv := 720.0
var thr_bar := {"x": 0.0, "y": 0.0, "w": 38.0, "h": 120.0}
var mouse := {"x": 0.0, "y": 0.0, "down": false, "active": false}
var ptrs := {}           # mouse-drag roles in flight: 0 -> {role,sx,sy,x,y}
var demo := {"x": 0.0, "y": 0.0, "h": -0.5}
var TCACHE := {}
var ASH: Array = []
var AP = null
var sat := 0.84
var con := 1.07
var ready_done := false

# ======================================================================
# setup
# ======================================================================
func _ready() -> void:
	randomize()
	wd.game = self
	Tx.init_basic()
	baker = Baker.new()
	add_child(baker)
	synth = Synth.new()
	add_child(synth)
	for i in 7:
		if i == 3:
			dark_rect = ColorRect.new()
			dark_mat = ShaderMaterial.new()
			dark_mat.shader = load("res://shaders/darkness.gdshader")
			dark_rect.material = dark_mat
			dark_rect.visible = false
			dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(dark_rect)
			layers.append(null)
			continue
		var l := DrawLayer.new()
		l.idx = i
		l.game = self
		if i == 1 or i == 4:
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = m
		add_child(l)
		layers.append(l)
	var hud := DrawLayer.new()
	hud.idx = 7
	hud.game = self
	add_child(hud)
	layers.append(hud)
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bb)
	var post := ColorRect.new()
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post.material = post_mat
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.name = "Post"
	add_child(post)
	ui = UI.new()
	ui.game = self
	add_child(ui)
	get_viewport().size_changed.connect(_resize)
	_resize()
	# world + textures
	var sv = load_save()
	wd.gen_world(int(sv.seed) if sv else randi() % 1000000000)
	baker.set_world(wd)
	await baker.build_overview()
	await Tx.bake_all(baker)
	var st: Dictionary = wd.strips[wd.START]
	demo = {"x": st.x, "y": st.y, "h": -0.6}
	ready_done = true
	show_title()
	synth.warm()

func _resize() -> void:
	var s := get_viewport().get_visible_rect().size
	Wv = s.x
	Hv = s.y
	thr_bar.w = 38.0
	thr_bar.x = Wv - thr_bar.w - 12
	thr_bar.h = clampf(Hv * 0.34, 120, 250)
	thr_bar.y = maxf(150, Hv - thr_bar.h - 120)
	if dark_rect: dark_rect.size = s
	var post := get_node_or_null("Post")
	if post: post.size = s

# ======================================================================
# state helpers
# ======================================================================
func new_state(seed_v: int) -> Dictionary:
	return {"v": 1, "seed": seed_v, "cash": 150, "plane": 0, "tanks": 0, "engine": 0, "fuel": 18.0, "time": 420.0, "hull": 100.0, "leak": 0.0, "roadStrips": [],
		"band": 3, "parts": 1, "bombs": 1, "diff": 1, "armor": 0.0, "goods": {}, "rumor": 2600.0, "trinkets": [], "carried": 0.0, "ammo": 70, "med": 2, "hp": 100.0,
		"weapons": [0], "weapon": 0, "contracts": [], "known": [], "strip": wd.START, "looted": {}, "offers": [], "nav": -1, "visits": {}, "mayday": null,
		"stats": {"flights": 0, "deliv": 0, "kills": 0, "dist": 0.0}}

func save_game() -> void:
	if G == null: return
	G.known = known.keys()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(G))

func load_save():
	if not FileAccess.file_exists(SAVE_PATH): return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else null

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func checkpoint() -> void:
	G.known = known.keys()
	CP = JSON.stringify(G)
	save_game()

## JSON turns ints into floats; put integer fields back.
func normalize(st: Dictionary) -> Dictionary:
	for k in ["seed", "cash", "plane", "tanks", "engine", "band", "parts", "bombs", "diff", "ammo", "med", "weapon", "strip", "nav"]:
		if st.has(k) and st[k] != null: st[k] = int(st[k])
	var ws: Array = []
	for w in st.get("weapons", [0]): ws.append(int(w))
	st.weapons = ws
	for arr in [st.get("contracts", []), st.get("offers", [])]:
		for c in arr:
			for k in ["dest", "pickup", "reward"]:
				if c.has(k): c[k] = int(c[k])
	for k in st.get("goods", {}).keys(): st.goods[k] = int(st.goods[k])
	if st.get("mayday") is Dictionary:
		st.mayday.id = int(st.mayday.id); st.mayday.reward = int(st.mayday.reward)
	var stt: Dictionary = st.get("stats", {})
	for k in ["flights", "deliv", "kills"]: stt[k] = int(stt.get(k, 0))
	stt["dist"] = float(stt.get("dist", 0))
	st.stats = stt
	return st

func PS() -> Dictionary:
	var b: Dictionary = D.PLANES[G.plane]
	var p := b.duplicate()
	p.burn = b.burn * (0.9 if has("wings") else 1.0)
	p.fuelCap = b.fuel + G.tanks * b.tankStep
	p.max = b.max * (1 + 0.08 * G.engine)
	p.cruise = b.cruise * (1 + 0.08 * G.engine)
	return p

func range_for(gal: float) -> float:
	var P := PS()
	return gal / (P.burn * (0.15 + 0.85 * 0.8)) * 0.8 * P.max
func range_now() -> float: return range_for(G.fuel)
func range_full() -> float: return range_for(PS().fuelCap)
func has(id: String) -> bool: return G != null and G.trinkets.has(id)
func DF() -> Dictionary: return D.DIFFS[G.diff if G != null else 1]
func strips() -> Array: return wd.strips
func strip(i: int) -> Dictionary: return wd.strips[i]
func toast(msg: String, cls: String = "") -> void: ui.toast(msg, cls)
func toast_later(t: float, msg: String, cls: String = "") -> void:
	get_tree().create_timer(t).timeout.connect(func(): toast(msg, cls))
func sfx(k: String, v: float = -1.0) -> void: synth.sfx(k, v)
func cap(s: String) -> String: return s.substr(0, 1).to_upper() + s.substr(1)

func dark() -> float:
	if G == null: return 0.0
	var h := fmod(G.time / 60.0, 24.0)
	if h >= 7 and h < 18: return 0.0
	if h >= 18 and h < 20: return (h - 18) / 2.0
	if h >= 5 and h < 7: return 1.0 - (h - 5) / 2.0
	return 1.0
func clock() -> String:
	var m := int(floor(G.time)) % 1440
	return U.pad2(m / 60) + ":" + U.pad2(m % 60)
func day() -> int: return int(floor(G.time / 1440.0)) + 1

# ======================================================================
# input
# ======================================================================
func key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)

func _unhandled_input(e: InputEvent) -> void:
	if not ready_done: return
	if e is InputEventKey and e.pressed and not e.echo:
		var c: int = e.physical_keycode
		if c == KEY_C and mode == "flight" and F and uist == "" and cruise_ok(): F.cruise = not F.cruise
		if c == KEY_M and (mode == "flight" or mode == "ground") and (uist == "" or uist == "map"): ui.toggle_map()
		if (c == KEY_ESCAPE or c == KEY_P) and (mode == "flight" or mode == "ground"):
			if uist == "": ui.open_pause()
			elif uist == "pause" or uist == "map": ui.close_ui()
		if uist == "" and mode == "ground":
			if c == KEY_E and S and S.nearPlane: ui.open_menu()
			if c == KEY_SPACE: jump()
			if c == KEY_Q: swap_weapon()
			if c == KEY_H: heal()
			if c == KEY_G: throw_bomb()
	elif e is InputEventMouseButton:
		var x: float = e.position.x
		var y: float = e.position.y
		if e.button_index != MOUSE_BUTTON_LEFT: return
		if e.pressed:
			if not ads:
				mouse.x = x; mouse.y = y
			mouse.active = true
			if mode == "ground":
				mouse.down = true
				return
			if uist != "": return
			if mode == "flight":
				var role := "thr" if (x > Wv - 100 and y > thr_bar.y - 50 and y < thr_bar.y + thr_bar.h + 50) else "steer"
				ptrs[0] = {"role": role, "sx": x, "sy": y, "x": x, "y": y}
				if role == "thr": set_thr(y)
		else:
			ptrs.erase(0)
			mouse.down = false
	elif e is InputEventMouseMotion:
		if ads:
			# cursor is captured: steer a virtual cursor at reduced sensitivity
			ads_cur = (ads_cur + e.relative * ADS_SENS).clamp(Vector2.ZERO, Vector2(Wv, Hv))
			mouse.x = ads_cur.x; mouse.y = ads_cur.y
		else:
			mouse.x = e.position.x; mouse.y = e.position.y
		mouse.active = true
		if ptrs.has(0):
			var p: Dictionary = ptrs[0]
			p.x = e.position.x; p.y = e.position.y
			if p.role == "thr": set_thr(p.y)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		ptrs.clear()
		mouse.down = false
		set_ads(false)

func set_thr(y: float) -> void:
	if F: F.thr = clampf(1.0 - (y - thr_bar.y) / thr_bar.h, 0.0, 1.0)

func clear_input() -> void:
	ptrs.clear()
	mouse.down = false
	set_ads(false)

## Enter/leave aim-down-sights. While aiming the OS cursor is captured and
## hidden; a virtual cursor (ads_cur) moves at ADS_SENS and a reticle is drawn.
## On release the real cursor is put back where the reticle was.
func set_ads(on: bool) -> void:
	if on == ads: return
	ads = on
	if on:
		ads_cur = Vector2(mouse.x, mouse.y) if mouse.active else get_viewport().get_mouse_position()
		mouse.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(ads_cur)
		mouse.x = ads_cur.x; mouse.y = ads_cur.y

## 0..1 eased aim amount, drives camera zoom and lean.
func ads_ease() -> float:
	return smoothstep(0.0, 1.0, S.get("adsK", 0.0)) if S else 0.0

# ======================================================================
# frame loop
# ======================================================================
func _process(delta: float) -> void:
	if not ready_done: return
	var dt := minf(0.05, delta)
	T += dt
	if ads and not (mode == "ground" and S): set_ads(false)
	if mode == "flight" and F:
		if uist == "":
			var n := 3 if (F.cruise and cruise_ok()) else 1
			var k := 0
			while k < n and F and uist == "" and mode == "flight":
				upd_flight(dt)
				k += 1
	elif mode == "ground" and S:
		set_ads(uist == "" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		if uist == "": upd_ground(dt)
	else:
		demo.x += cos(demo.h) * 60 * dt
		demo.y += sin(demo.h) * 60 * dt
		demo.h += sin(T * 0.1) * 0.02 * dt
	var fl: bool = mode == "flight" and F != null and uist == "" and not F.crashed
	synth.engine((F.thr if G.fuel > 0 else 0.0) if fl else 0.0, F.alt if F else 0.0, fl)
	var rk := 0.0
	if uist == "":
		if mode == "flight" and F: rk = F.storm
		elif mode == "ground" and S: rk = S.rain
	synth.rain(rk)
	if mode == "flight" and F: Render.prep_flight(self)
	if mode == "ground" and S: Render.prep_ground(self)
	else: dark_rect.visible = false
	post_mat.set_shader_parameter("sat", sat)
	post_mat.set_shader_parameter("con", con)
	for l in layers:
		if l: l.queue_redraw()
	ui.update_buttons()

func draw_layer(idx: int, p: Pen) -> void:
	if not ready_done:
		if idx == 0: p.rect(0, 0, Wv, Hv, U.hx("#10150f"))
		return
	if mode == "flight" and F:
		Render.flight_layer(self, idx, p)
	elif mode == "ground" and S:
		Render.ground_layer(self, idx, p)
	elif idx == 0 and baker.overview:
		Render.draw_world(self, p, demo.x, demo.y, Render.flight_scale(self, 90), T)
	elif idx == 0:
		p.rect(0, 0, Wv, Hv, U.hx("#2c4c58"))

# ======================================================================
# flight
# ======================================================================
func cruise_ok() -> bool:
	return F != null and not F.onGround and not F.crashed and F.alt > 45 and F.storm < 0.05 and F.underFire <= 0 and G.fuel > 0

func takeoff() -> void:
	sat = 0.84; con = 1.07
	var s := strip(G.strip)
	var a: float = s.ang + (0.0 if randf() < 0.5 else PI)
	var wa := randf() * TAU
	var ws := randf() * 22
	F = {"x": s.x - cos(a) * (s.len / 2 - 30), "y": s.y - sin(a) * (s.len / 2 - 30), "hdg": a, "spd": 0.0, "alt": 0.0, "vs": 0.0, "thr": 0.0, "onGround": true, "departing": true,
		"rollStrip": s, "bank": 0.0, "prop": 0.0, "storm": 0.0, "tb": 0.0, "tracers": [], "underFire": 0.0, "flash": 0.0, "gx": 0.0, "gy": 0.0, "gfT": 0.0,
		"wind": Vector2(cos(wa) * ws, sin(wa) * ws), "trk": a, "cruise": false, "crashed": false, "assist": false, "inStorm": false, "warnedFire": false, "evT": 60 + randf() * 50, "autothr": false}
	mode = "flight"
	_free_site()
	ui.close_ui()
	cam_snap = true
	clear_input()
	checkpoint()
	toast("Throttle up to take off. Keep it on the runway.")

func _thr_touch() -> bool:
	return key(KEY_W) or key(KEY_S) or key(KEY_UP) or key(KEY_DOWN) or (ptrs.has(0) and ptrs[0].role == "thr")

func upd_flight(dt: float) -> void:
	G.time += dt
	var P := PS()
	var steer := 0.0
	if key(KEY_A) or key(KEY_LEFT): steer -= 1
	if key(KEY_D) or key(KEY_RIGHT): steer += 1
	for p in ptrs.values():
		if p.role == "steer": steer += clampf((p.x - p.sx) / 70.0, -1, 1)
	steer = clampf(steer, -1, 1)
	F.assist = false
	if F.onGround and F.rollStrip and absf(steer) < 0.05 and F.spd > 3:
		var rs: Dictionary = F.rollStrip
		var dir: float = rs.ang if absf(U.ang_diff(rs.ang, F.hdg)) < PI / 2 else rs.ang + PI
		var lat: float = -(F.x - rs.x) * sin(dir) + (F.y - rs.y) * cos(dir)
		steer = clampf(U.ang_diff(dir, F.hdg) * 3 - lat * 0.02, -1, 1)
	if not F.onGround and F.alt < 70 and absf(steer) < 0.05:
		var best = null
		var bd := 2600.0
		for s in wd.strips:
			if not known.has(s.id) or s.type == "road": continue
			var d := Vector2(s.x - F.x, s.y - F.y).length()
			if d < bd:
				bd = d
				best = s
		if best:
			var dir: float = best.ang if absf(U.ang_diff(best.ang, F.hdg)) < PI / 2 else best.ang + PI
			var cx := cos(dir)
			var cy := sin(dir)
			var rx: float = F.x - best.x
			var ry2: float = F.y - best.y
			var along := rx * cx + ry2 * cy
			var lat0 := -rx * cy + ry2 * cx
			if along < best.len / 2 - 40 and along > -2600 and absf(lat0) < 450:
				var la := clampf(-along * 0.35, 260, 700)
				var tx: float = best.x + cx * (along + la)
				var ty: float = best.y + cy * (along + la)
				var des := atan2(ty - F.y, tx - F.x)
				var df := U.ang_diff(des, F.trk)
				if absf(U.ang_diff(des, F.hdg)) < 0.9:
					steer = clampf(df * 2.6, -0.9, 0.9)
					F.assist = true
					if not _thr_touch() and F.thr <= 0.75 and along > -2200:
						var pt = predict_touchdown()
						var pa: float = ((pt.x - best.x) * cx + (pt.y - best.y) * cy) if pt else 1e9
						var tgt: float = -best.len / 2 + best.len * 0.22
						if pa < tgt - 50: F.thr = minf(0.72, F.thr + 0.9 * dt)
						elif pa > tgt + 50: F.thr = maxf(0.08, F.thr - 0.6 * dt)
						F.autothr = true
	if key(KEY_W) or key(KEY_UP): F.thr = minf(1, F.thr + 0.55 * dt)
	if key(KEY_S) or key(KEY_DOWN): F.thr = maxf(0, F.thr - 0.55 * dt)
	var eff: float = F.thr if G.fuel > 0 else 0.0
	if G.fuel > 0: G.fuel = maxf(0, G.fuel - P.burn * (0.15 + 0.85 * F.thr) * dt)
	var target: float = eff * P.max
	if F.onGround:
		if target > F.spd: F.spd += (target - F.spd) * 0.25 * dt
		else: F.spd = maxf(target, F.spd - (38.0 if eff < 0.08 else 14.0) * dt)
	else:
		F.spd += (target - F.spd) * (0.28 if target > F.spd else 0.3) * dt
	var turnK: float = clampf(F.spd / 30.0, 0, 1) * 0.7 if F.onGround else 1.0
	F.bank = lerpf(F.bank, 0.0 if F.onGround else steer, minf(1, dt * 4))
	F.hdg += steer * P.turn * turnK * dt
	F.prop += dt * (eff * 40 + 2)
	var altT := clampf((F.spd - P.stall) / (P.cruise - P.stall) * 100, -80, 120)
	if F.onGround:
		F.alt = 0.0; F.vs = 0.0
		if altT > 3:
			F.onGround = false; F.alt = 0.3; F.rollStrip = null; F.departing = false
			G.stats.flights += 1
			toast("Airborne.")
	else:
		F.vs = maxf(clampf((altT - F.alt) * 1.3, -48, 22), -(5 + F.alt * 0.55))
		F.alt += F.vs * dt
		if F.alt <= 0:
			touchdown(P)
			if uist != "" or F == null or mode != "flight": return
	if G.leak > 0 and G.fuel > 0: G.fuel = maxf(0, G.fuel - G.leak * dt)
	var st := wd.storm_at(F.x, F.y)
	F.storm = 0.0 if F.onGround else st.k
	F.gx = 0.0; F.gy = 0.0
	if F.storm > 0:
		var k: float = F.storm
		if not F.inStorm and k > 0.03: toast("Flying into weather. Hold on.", "bad")
		F.inStorm = true
		F.tb = lerpf(F.tb, (randf() - 0.5) * 2, minf(1, dt * 3))
		F.hdg += F.tb * k * 0.9 * dt
		F.alt += (randf() - 0.5) * k * 70 * dt
		F.spd = maxf(0, F.spd + (randf() - 0.5) * k * 30 * dt)
		var bp: Vector2 = st.best.p
		var ta := atan2(F.y - bp.y, F.x - bp.x) + PI / 2
		var gu := 48 * k * (0.6 + 0.4 * sin(T * 1.7))
		F.gx = cos(ta) * gu; F.gy = sin(ta) * gu
		if k > 0.55: G.hull -= (k - 0.55) * 14 * dt
		if randf() < k * dt * 0.5:
			F.flash = 0.25
			sfx("thunder")
			if k > 0.4 and randf() < 0.18:
				G.hull -= 10
				toast("Lightning strike.", "bad")
	elif F.storm <= 0:
		F.inStorm = false
	F.flash -= dt
	F.underFire -= dt
	F.gfT -= dt
	if F.gfT <= 0 and not F.onGround:
		F.gfT = 0.45
		var tt := wd.terr(F.x, F.y)
		if F.alt < 45 and (tt == 9 or tt == 10) and randf() < 0.5:
			var a := randf() * TAU
			var rr2 := 150 + randf() * 250
			var hit: bool = randf() < 0.35 * (1 - F.alt / 60.0)
			F.tracers.append({"x": F.x + cos(a) * rr2, "y": F.y + sin(a) * rr2, "tx": F.x + (0.0 if hit else (randf() - 0.5) * 140), "ty": F.y + (0.0 if hit else (randf() - 0.5) * 140), "life": 0.35})
			sfx("enemy")
			F.underFire = 1.5
			if not F.warnedFire:
				F.warnedFire = true
				toast("Ground fire. Climb out of range.", "bad")
			if hit:
				G.hull -= 4 + randf() * 5
				if randf() < 0.3:
					G.leak += 0.03
					toast("Fuel leak.", "bad")
	var i: int = F.tracers.size() - 1
	while i >= 0:
		F.tracers[i].life -= dt
		if F.tracers[i].life <= 0: F.tracers.remove_at(i)
		i -= 1
	if G.hull <= 0:
		G.hull = 0.0
		die("breakup")
		return
	var dx: float = cos(F.hdg) * F.spd * dt
	var dy: float = sin(F.hdg) * F.spd * dt
	if not F.onGround:
		dx += (F.wind.x + F.gx) * dt
		dy += (F.wind.y + F.gy) * dt
	if dx != 0 or dy != 0: F.trk = atan2(dy, dx)
	F.x += dx; F.y += dy
	G.stats.dist += Vector2(dx, dy).length()
	if F.x < 0 or F.y < 0 or F.x > WORLD or F.y > WORLD:
		F.x = clampf(F.x, 0, WORLD); F.y = clampf(F.y, 0, WORLD)
		var toC := atan2(WORLD / 2 - F.y, WORLD / 2 - F.x)
		F.hdg += U.ang_diff(toC, F.hdg) * dt * 2
	if F.onGround:
		var s = F.rollStrip if F.rollStrip else wd.strip_at(F.x, F.y, 0)
		var on: bool = s != null and wd.on_runway(s, F.x, F.y, 1.5)
		if not on and F.spd > 24:
			die("loop")
			return
		if not F.departing and F.spd < 2.5 and eff < 0.1:
			var near = s if s else wd.nearest_strip(F.x, F.y, 500)
			if near:
				arrive(near)
				return
	if not F.onGround:
		F.evT -= dt
		if F.evT <= 0 and G.mayday == null:
			F.evT = 100 + randf() * 80
			var rn := range_now()
			var cand := wd.strips.filter(func(s):
				var d := Vector2(s.x - F.x, s.y - F.y).length()
				return s.type != "haven" and s.type != "road" and s.id != G.strip and d > 1200 and d < minf(5500, rn * 0.9))
			if cand.size():
				var s: Dictionary = cand[randi() % cand.size()]
				known[s.id] = true
				var d := Vector2(s.x - F.x, s.y - F.y).length()
				G.mayday = {"id": s.id, "until": G.time + d / 100 * 2.2 + 40, "reward": int(round((150 + d / 100 * 6) / 5.0)) * 5}
				sfx("rare")
				toast("Radio: \"Mayday, mayday. We are pinned down at %s. Anyone out there?\" Land within %d minutes for $%d." % [s.name, int(round(G.mayday.until - G.time)), G.mayday.reward], "mag")
	if G.mayday and G.time > G.mayday.until:
		toast("The mayday has gone silent.", "bad")
		G.mayday = null
	discT -= dt
	if discT <= 0:
		discT = 0.5
		for s in wd.strips:
			if not known.has(s.id) and Vector2(s.x - F.x, s.y - F.y).length() < 2200:
				known[s.id] = true
				toast("Runway lights on the coast. Haven is real." if s.type == "haven" else "Spotted a field: " + s.name, "mag")

func align_to(sang: float, a: float) -> bool:
	var d := fmod(fmod(a - sang, PI) + PI, PI)
	d = minf(d, PI - d)
	return d < 0.6
func align_ok(s: Dictionary) -> bool:
	return align_to(s.ang, F.hdg if F.onGround else F.trk)

func approach_info():
	if F == null or F.onGround or F.alt < 4: return null
	var best = null
	var nt = nav_target()
	# GDScript lambdas cannot reassign captured locals, so collect via a holder
	var holder := [null]
	var cand2 := func(s):
		if s == null or not known.has(s.id) or s.type == "road": return
		var d := Vector2(s.x - F.x, s.y - F.y).length()
		if d > 7000: return
		var dir: float = s.ang if absf(U.ang_diff(s.ang, F.hdg)) < PI / 2 else s.ang + PI
		var cx := cos(dir)
		var cy := sin(dir)
		var rx: float = F.x - s.x
		var ry: float = F.y - s.y
		var along := rx * cx + ry * cy
		var lat := -rx * cy + ry * cx
		if along > s.len / 2 or absf(lat) > 700 or absf(U.ang_diff(atan2(s.y - F.y, s.x - F.x), F.hdg)) > 1.1: return
		var td: float = -s.len / 2 + s.len * 0.22 - along
		if holder[0] == null or td < holder[0].td:
			holder[0] = {"s": s, "dir": dir, "cx": cx, "cy": cy, "along": along, "lat": lat, "td": td}
	cand2.call(nt)
	if holder[0] == null:
		for s in wd.strips: cand2.call(s)
	best = holder[0]
	if best == null: return null
	var p1 = predict_touchdown(0.33)
	var p0 = predict_touchdown(0.0)
	if p1 == null: return null
	var Dd := Vector2(p1.x - F.x, p1.y - F.y).length()
	var D0 := Vector2(p0.x - F.x, p0.y - F.y).length() if p0 else Dd
	var slack: float = best.td - Dd
	best.D = Dd
	best.slack = slack
	best.canMake = D0 < best.td + best.s.len * 0.7
	best.px = best.s.x + best.cx * (-best.s.len / 2 + best.s.len * 0.22) - best.cx * Dd
	best.py = best.s.y + best.cy * (-best.s.len / 2 + best.s.len * 0.22) - best.cy * Dd
	best.phase = "early" if slack > 220 else ("now" if slack >= -220 else ("late" if best.canMake else "high"))
	return best

func predict_touchdown(thrO: float = -1.0):
	var P := PS()
	var x: float = F.x
	var y: float = F.y
	var spd: float = F.spd
	var alt: float = F.alt
	var vs := 0.0
	var tg: float = ((F.thr if thrO < 0 else thrO) if G.fuel > 0 else 0.0) * P.max
	var c := cos(F.hdg)
	var n := sin(F.hdg)
	var wx: float = F.wind.x
	var wy: float = F.wind.y
	var st: float = P.stall
	var cr: float = P.cruise
	for i in 450:
		var dt := 0.1
		spd += (tg - spd) * (0.28 if tg > spd else 0.3) * dt
		var altT := clampf((spd - st) / (cr - st) * 100, -80, 120)
		vs = maxf(clampf((altT - alt) * 1.3, -48, 22), -(5 + alt * 0.55))
		alt += vs * dt
		x += c * spd * dt + wx * dt
		y += n * spd * dt + wy * dt
		if alt <= 0: return {"x": x, "y": y, "vs": vs, "t": i * dt}
	return null

func touchdown(P: Dictionary) -> void:
	var vs: float = F.vs
	F.alt = 0.0
	var s = wd.strip_at(F.x, F.y, 1.7)
	var firm := func():
		if vs < -6:
			G.hull = maxf(1, G.hull - round((-vs - 6) * 2.5))
			toast("Firm touchdown. The airframe felt that.", "bad")
	if s and vs > -19 and align_ok(s):
		F.onGround = true; F.rollStrip = s; F.departing = false; F.vs = 0.0; F.thr = 0.0
		sfx("thump")
		if vs > -6: toast("Smooth touchdown.")
		firm.call()
		return
	if s == null and vs > -15:
		var rd = wd.road_at(F.x, F.y) if wd.terr(F.x, F.y) > 1 else null
		if rd and align_to(rd.r.ang, F.trk):
			var rs := make_road_strip(rd)
			F.onGround = true; F.rollStrip = rs; F.departing = false; F.vs = 0.0; F.thr = 0.0
			sfx("thump")
			toast("Emergency landing on the road.", "mag")
			firm.call()
			return
	var t := wd.terr(F.x, F.y)
	if t <= 1:
		die("ditch")
		return
	if s and vs > -15:
		die("misalign")
		return
	if vs <= -15 or F.spd > P.stall * 1.1:
		die("crash")
		return
	die("overrun")

func make_road_strip(rd: Dictionary) -> Dictionary:
	var r: Dictionary = rd.r
	var cx: float = r.x1 + r.dx * rd.t
	var cy: float = r.y1 + r.dy * rd.t
	for s in wd.strips:
		if s.type == "road" and Vector2(s.x - cx, s.y - cy).length() < 900: return s
	var nb = wd.nearest_strip(cx, cy, 1e9)
	var s := {"id": wd.strips.size(), "type": "road", "arch": "road", "name": "%s, mile %d" % [r.name, maxi(1, int(round(rd.t * r.len / 160.0)))], "x": cx, "y": cy, "ang": r.ang, "len": 640.0, "wid": 40.0,
		"fuel": false, "shop": false, "dealer": false, "danger": clampi((nb.danger if nb else 2) + 1, 1, 5), "fuelPrice": 0, "seed": randi() % 1000000000, "home": false}
	wd.strips.append(s)
	G.roadStrips.append(s.duplicate())
	known[s.id] = true
	return s

func arrive(s: Dictionary) -> void:
	G.strip = s.id
	known[s.id] = true
	if s.type == "haven":
		win()
		return
	var paid := 0
	var n := 0
	var keep: Array = []
	for c in G.contracts:
		if c.dest == s.id and (c.get("type", "") != "rescue" or c.get("stage", "") == "aboard"):
			paid += int(c.reward)
			n += 1
		else:
			keep.append(c)
	G.contracts = keep
	if s.type == "road" and int(G.visits.get(str(s.id), 0)) == 0:
		toast_later(0.9, "No pump and no mechanic out here. Find fuel and get off this road.", "bad")
	if G.mayday and int(G.mayday.id) == s.id:
		var mr: int = G.mayday.reward
		G.cash += mr; G.band += 2; G.ammo += 20; G.mayday = null
		toast_later(0.05, "You made it in time. The survivors pay $%d and press bandages and rounds into your hands." % mr, "good")
	if paid:
		G.cash += paid
		G.stats.deliv += n
		toast("Delivered %s. Paid $%d." % [(str(n) + " loads") if n > 1 else "the load", paid], "good")
	if G.nav == s.id: G.nav = -1
	G.visits[str(s.id)] = int(G.visits.get(str(s.id), 0)) + 1
	G.offers = gen_offers(s)
	enter_ground(s)
	checkpoint()

func nav_target():
	if G.mayday: return strip(int(G.mayday.id))
	if G.nav >= 0: return strip(G.nav)
	if G.contracts.size(): return strip(contract_target(G.contracts[0]))
	return null

# ======================================================================
# contracts
# ======================================================================
func gen_offers(s: Dictionary) -> Array:
	var R := range_full()
	var n := 2 if s.type == "dirt" else (3 if s.type == "regional" else 4)
	var c: Array = []
	if s.type != "road":
		c = wd.strips.filter(func(o):
			if o.id == s.id or o.type == "haven" or o.type == "road": return false
			var d := Vector2(o.x - s.x, o.y - s.y).length()
			return d > 1400 and d < R * 0.95)
	c.shuffle()
	var out: Array = []
	for o in c.slice(0, n):
		var d := Vector2(o.x - s.x, o.y - s.y).length()
		var cg: Array = D.CARGO[randi() % D.CARGO.size()]
		out.append({"id": U.rid(), "type": "", "dest": o.id, "icon": cg[0], "what": cg[1], "reward": int(round((70 + d / 100 * 8) * (1 + 0.15 * o.danger) * (0.85 + randf() * 0.3) / 5.0)) * 5})
	if c.size() > n and randf() < 0.6:
		var o: Dictionary = c[n]
		var d := Vector2(o.x - s.x, o.y - s.y).length()
		var who: String = D.RNAMES[randi() % D.RNAMES.size()]
		var wk: Array = D.WHERE.keys()
		var where: String = wk[randi() % wk.size()]
		out.append({"id": U.rid(), "type": "rescue", "stage": "pickup", "pickup": o.id, "dest": s.id, "who": who, "where": where, "icon": "🆘", "what": who,
			"reward": int(round((120 + d * 2 / 100 * 6) * (1 + 0.15 * o.danger) * (1.25 if has("radio") else 1.0) / 5.0)) * 5})
	return out

func contract_target(c: Dictionary) -> int:
	return int(c.pickup) if (c.get("type", "") == "rescue" and c.get("stage", "") == "pickup") else int(c.dest)

func objective() -> String:
	if S and S.npc == null:
		if G.contracts.size(): return "Board the plane and fly to %s." % strip(contract_target(G.contracts[0])).name
		return "No job yet. Board the plane to see the job board."
	if S and S.npc:
		return ("Lead %s back to the plane." % S.npc.name) if S.npc.follow else ("Find %s in %s." % [S.npc.name, D.WHERE[S.npc.where]])
	if G.mayday and mode == "flight":
		var s := strip(int(G.mayday.id))
		return "Mayday at %s. %d minutes left." % [s.name, maxi(0, int(round(G.mayday.until - G.time)))]
	for k in G.contracts:
		if k.get("type", "") == "rescue":
			return ("Rescue %s at %s." % [k.who, strip(int(k.pickup)).name]) if k.stage == "pickup" else ("Fly %s to %s." % [k.who, strip(int(k.dest)).name])
	if G.contracts.size():
		var c: Dictionary = G.contracts[0]
		return "Deliver %s to %s." % [c.what, strip(int(c.dest)).name]
	if G.plane == 0:
		return "You can afford a Heron. Find an airport with a dealer." if G.cash >= D.PLANES[1].price else "Take jobs and sell goods. A Heron costs $%d." % D.PLANES[1].price
	if not known.has(0): return "Find Haven in the far northeast. Old charts narrow the search."
	return "Fly to Haven."

func bearing(a: Dictionary, b: Dictionary) -> String:
	var deg := fmod(rad_to_deg(atan2(b.y - a.y, b.x - a.x)) + 90 + 360, 360)
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(deg / 45.0)) % 8]

# ======================================================================
# ground: site setup
# ======================================================================
func _free_site() -> void:
	if S and S.has("bg") and is_instance_valid(S.bg):
		S.bg.queue_free()
	S = null

func gen_site(s: Dictionary) -> Dictionary:
	var gen := SiteGen.new()
	var site: Dictionary = gen.build(self, s)
	var plane: Vector2 = site.plane
	var ry: int = site.ry
	site.merge({"noise": 0.0, "waves": [], "splat": [], "flick": 0.0, "hbT": 0.0, "nd": 1e9, "band": -1, "smoke": [], "swing": 0.0, "thrown": [], "crows": [], "pk": [],
		"s": s, "pump": Vector2(plane.x + 260, (ry - 1) * TS + 14) if s.fuel else null,
		"p": {"x": plane.x + 150, "y": plane.y - 8, "ang": 0.0, "cd": 0.0, "stam": 100.0, "jt": 0.0, "jcd": 0.0, "safe": Vector2(plane.x + 150, plane.y - 8), "jx": 0, "wk": 0.0, "sprint": false},
		"zs": [], "sv": [], "bul": [], "drops": [], "fx": [], "fl": [], "t": 0.0, "spawnT": 5.0, "danger": s.danger,
		"cx": plane.x + 150, "cy": plane.y, "shake": 0.0, "flash": 0.0, "hurt": 0.0, "nearPlane": false, "scorch": [], "flow": PackedInt32Array(), "flowT": 0.0,
		"boomFlash": 0.0, "rain": minf(1.0, wd.storm_at(s.x, s.y).k * 1.6), "npc": null, "air": false, "tSprint": false, "noAmmoT": -9.0, "flN": 0, "cawT": -9.0, "sipT": -9.0, "tkHint": false,
		"rcx": 0.0, "rcy": 0.0, "adsK": 0.0, "cap": 0, "rooms_ra": []})
	var bg := SiteBg.new()
	add_child(bg)
	bg.setup(site)
	site.bg = bg
	var cols: int = site.cols
	var g: PackedByteArray = site.g
	for f in 4:
		for q in 30:
			var c := 2 + int(randf() * (cols - 4))
			var r := 2 + int(randf() * (ry - 3))
			if g[r * cols + c] != 0: continue
			var n := 3 + int(randf() * 5)
			for k in n:
				site.crows.append({"x": (c + 0.5) * TS + (randf() - 0.5) * 50, "y": (r + 0.5) * TS + (randf() - 0.5) * 40, "a": randf() * TAU, "ph": randf() * 9, "fly": false, "h": 0.0, "life": 5.0, "vx": 0.0, "vy": 0.0, "gone": false})
			break
	var first: bool = s.get("home", false) and int(G.visits.get(str(s.id), 0)) <= 1
	S = site
	var nz := int(round(DF().count * (3 if first else 2 + s.danger * 3 + (3 if site.arch == "town" else 0) + (4 if site.arch == "road" else 0) + 4) + round(dark() * 3)))
	for i in nz: spawn_z(true)
	if not first:
		var nd2 := int(round((1 + s.danger * 0.8) * DF().count))
		for i in nd2:
			var n0: int = S.zs.size()
			spawn_z(true)
			if S.zs.size() > n0:
				var z: Dictionary = S.zs[S.zs.size() - 1]
				z.dormant = true; z.kind = ""; z.arm = false; z.da = randf() * TAU; z.hp = 45.0 + s.danger * 8
	site.cap = int(round((8 if first else 10 + s.danger * 4) * DF().count))
	site.noise = 0.0 if first else (6 + s.danger * 2) * DF().noise
	for i in 4 + int(randf() * 5):
		for q in 30:
			var c := 1 + int(randf() * (cols - 2))
			var r := 1 + int(randf() * (ry - 2))
			var v := g[r * cols + c]
			if v != 0 and v != 2 and v != 11 and v != 14: continue
			var x := (c + 0.5) * TS
			var y := (r + 0.5) * TS
			blood(x, y, 5)
			stamp_corpse({"x": x, "y": y, "a": randf() * TAU, "shirt": D.ZSHIRT[randi() % D.ZSHIRT.size()], "skin": ["#c69c74", "#8a5f40", "#e0b894", "#8c9a78"][randi() % 4]})
			break
	if not first and randf() < 0.2 + 0.08 * s.danger + (0.25 if site.arch == "military" else 0.0) and site.rooms.size():
		var n := 1 + int(randf() * mini(3, s.danger))
		for i in n:
			var o: Dictionary = site.rooms[randi() % site.rooms.size()]
			var x: float = (o.c + 1.5 + randf() * (o.w - 3)) * TS
			var y: float = (o.r + 1.5 + randf() * (o.h - 3)) * TS
			if Vector2(x - site.p.x, y - site.p.y).length() > 320 and not solid(x, y):
				site.sv.append({"x": x, "y": y, "shirt": ["#5a5f3a", "#4a3a2a", "#3f4f5f"][randi() % 3], "skin": ["#c69c74", "#8a5f40", "#e0b894"][randi() % 3],
					"cap": "#3a3226" if randf() < 0.5 else "", "wk": 0.0, "hp": 70.0, "cd": 1 + randf(), "ang": 0.0, "alert": false, "hit": 0.0, "sw": 0.0, "sd": 1.0, "dead": false})
	return site

func enter_ground(s: Dictionary) -> void:
	_free_site()
	gen_site(s)
	spawn_npc(s)
	mode = "ground"
	ui.close_ui()
	clear_input()
	F = null
	if dark() > 0.5: toast("It is dark. The dead move faster at night.", "bad")

func spawn_npc(s: Dictionary) -> void:
	var c = null
	for k in G.contracts:
		if k.get("type", "") == "rescue" and k.stage == "pickup" and int(k.pickup) == s.id:
			c = k
			break
	if c == null or S == null: return
	var rm = null
	for r in S.rooms:
		if r.kind == c.where:
			rm = r
			break
	if rm == null:
		for r in S.rooms:
			if r.kind == "house":
				rm = r
				break
	if rm == null and S.rooms.size(): rm = S.rooms[S.rooms.size() - 1]
	if rm == null: return
	var x: float = (rm.c + rm.w / 2.0) * TS
	var y: float = (rm.r + rm.h / 2.0) * TS
	var q := 0
	while q < 30 and solid(x, y):
		x = (rm.c + 1.5 + randf() * (rm.w - 3)) * TS
		y = (rm.r + 1.5 + randf() * (rm.h - 3)) * TS
		q += 1
	var where: String = c.where if rm.kind == c.where else "house"
	S.npc = {"x": x, "y": y, "ang": PI / 2, "hp": 60.0, "name": c.who, "where": where, "cid": c.id, "follow": false, "wk": 0.0, "hit": 0.0}
	toast_later(0.7, "%s is hiding in %s." % [c.who, D.WHERE[where]], "mag")

func npc_hurt(d: float) -> void:
	var n = S.npc
	if n == null: return
	n.hp -= d
	n.hit = 0.15
	blood(n.x, n.y, 2)
	if n.hp <= 0:
		blood(n.x, n.y, 8)
		stamp_corpse({"x": n.x, "y": n.y, "a": randf() * TAU, "shirt": "#3f7a7a", "skin": "#e0b894"})
		G.contracts = G.contracts.filter(func(k): return k.id != n.cid)
		toast("%s did not make it. The job is gone." % cap(n.name), "bad")
		S.npc = null

func upd_npc(dt: float) -> void:
	var n = S.npc
	if n == null: return
	var p: Dictionary = S.p
	var dx: float = p.x - n.x
	var dy: float = p.y - n.y
	var d := Vector2(dx, dy).length()
	if d == 0: d = 1
	n.hit -= dt
	if not n.follow and d < 70:
		n.follow = true
		toast("%s: \"%s\"" % [cap(n.name), D.FOUND[randi() % D.FOUND.size()]], "mag")
		sfx("loot")
	if n.follow and d > 44:
		var vx := dx / d
		var vy := dy / d
		if d > 120 and not los(n.x, n.y, p.x, p.y):
			var fd = flow_dir(n.x, n.y)
			if fd:
				vx = fd.x; vy = fd.y
		var ox: float = n.x
		var oy: float = n.y
		var sp := 175.0 if d > 160 else 140.0
		move_c(n, vx * sp * dt, vy * sp * dt, 9)
		n.wk += Vector2(n.x - ox, n.y - oy).length() * 0.22
		n.ang = atan2(vy, vx)
	if n.follow and (Vector2(n.x - S.plane.x, n.y - S.plane.y).length() < 160 or (S.nearPlane and d < 120)):
		for c in G.contracts:
			if c.id == n.cid:
				c.stage = "aboard"
				G.nav = int(c.dest)
				toast("%s climbs into the back. Fly them to %s." % [cap(n.name), strip(int(c.dest)).name], "good")
				sfx("cash")
				break
		S.npc = null

# ======================================================================
# ground: helpers
# ======================================================================
const MOVE := [0, 1, 0, 0, 0, 1, 1, 1, 1, 0, 1, 0, 0, 1, 0, 0]
const BLOCK := [0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0]

func solid(x: float, y: float) -> bool:
	var c := int(floor(x / TS))
	var r := int(floor(y / TS))
	if c < 0 or r < 0 or c >= S.cols or r >= S.rows: return true
	var v: int = S.g[r * S.cols + c]
	if S.air and (v == 6 or v == 7 or v == 10): return false
	return MOVE[v] == 1
func solid_b(x: float, y: float) -> bool:
	var c := int(floor(x / TS))
	var r := int(floor(y / TS))
	if c < 0 or r < 0 or c >= S.cols or r >= S.rows: return true
	return BLOCK[S.g[r * S.cols + c]] == 1
func hit_box(x: float, y: float, r: float) -> bool:
	return solid(x - r, y - r) or solid(x + r, y - r) or solid(x - r, y + r) or solid(x + r, y + r)
func move_c(e: Dictionary, dx: float, dy: float, r: float) -> void:
	var nx: float = e.x + dx
	if not hit_box(nx, e.y, r): e.x = nx
	var ny: float = e.y + dy
	if not hit_box(e.x, ny, r): e.y = ny
func los(x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Vector2(x1 - x0, y1 - y0).length()
	var n := int(ceil(d / 14.0))
	for i in range(1, n):
		var t := float(i) / n
		if solid_b(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t): return false
	return true
func passable(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= S.cols or r >= S.rows: return false
	return MOVE[S.g[r * S.cols + c]] == 0
func build_flow() -> void:
	var cols: int = S.cols
	var n: int = cols * S.rows
	var fl: PackedInt32Array = S.flow
	if fl.size() != n: fl.resize(n)
	fl.fill(-1)
	var pc := int(floor(S.p.x / TS))
	var pr := int(floor(S.p.y / TS))
	if pc < 0 or pr < 0 or pc >= cols or pr >= S.rows:
		S.flow = fl
		return
	var q := PackedInt32Array()
	q.resize(n)
	var h := 0
	var tl := 0
	var i0 := pr * cols + pc
	fl[i0] = 0
	q[tl] = i0; tl += 1
	var g: PackedByteArray = S.g
	var rows: int = S.rows
	while h < tl:
		var i := q[h]; h += 1
		var c := i % cols
		var r := i / cols
		var d := fl[i] + 1
		for k in 4:
			var nc := c + (1 if k == 0 else (-1 if k == 1 else 0))
			var nr := r + (1 if k == 2 else (-1 if k == 3 else 0))
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows: continue
			var j := nr * cols + nc
			if MOVE[g[j]] == 1 or fl[j] >= 0: continue
			fl[j] = d
			q[tl] = j; tl += 1
	S.flow = fl
const N8 := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]
func flow_dir(x: float, y: float):
	var fl: PackedInt32Array = S.flow
	if fl.is_empty(): return null
	var c := int(floor(x / TS))
	var r := int(floor(y / TS))
	if c < 0 or r < 0 or c >= S.cols or r >= S.rows: return null
	var cur := fl[r * S.cols + c]
	var best := 1000000000 if cur < 0 else cur
	var bx := 0.0
	var by := 0.0
	var found := false
	for d in N8:
		var nc: int = c + d[0]
		var nr: int = r + d[1]
		if not passable(nc, nr): continue
		if d[0] != 0 and d[1] != 0 and (not passable(c + d[0], r) or not passable(c, r + d[1])): continue
		var v := fl[nr * S.cols + nc]
		if v >= 0 and v < best:
			best = v
			bx = (nc + 0.5) * TS - x
			by = (nr + 0.5) * TS - y
			found = true
	if not found: return null
	var m := Vector2(bx, by).length()
	if m == 0: m = 1
	return Vector2(bx / m, by / m)

func add_noise(v: float) -> void:
	if S: S.noise = minf(100.0, S.noise + v * DF().noise)

func blood(x: float, y: float, n: int) -> void:
	var recs: Array = []
	for i in n:
		recs.append([x + (randf() - 0.5) * 18, y + (randf() - 0.5) * 18, 3 + randf() * 6])
	S.bg.stamp(["blood", recs])
func stamp_corpse(k: Dictionary) -> void:
	S.bg.stamp(["corpse", k])
func stamp_scorch(x: float, y: float) -> void:
	S.bg.stamp(["scorch", x, y])
func floater(x: float, y: float, txt: String, c: String = "#efe6cf") -> void:
	S.fl.append({"x": x, "y": y, "txt": txt, "c": c, "life": 1.4})

func ground_scale() -> float:
	var gs := clampf(sqrt(Wv * Hv) / 600.0, 0.72, 1.6)
	return gs * (1.0 + ADS_ZOOM * ads_ease())
func s2w_g(x: float, y: float) -> Vector2:
	var gs := ground_scale()
	return Vector2((x - Wv / 2) / gs + S.cx, (y - Hv / 2) / gs + S.cy)

func enemies() -> Array:
	return S.zs + S.sv

func assist(a: float) -> float:
	var p: Dictionary = S.p
	var best = null
	var bd := 0.35
	for e in enemies():
		if e.get("dormant", false): continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d > 520: continue
		var q := absf(U.ang_diff(atan2(e.y - p.y, e.x - p.x), a))
		if q < bd and los(p.x, p.y, e.x, e.y):
			bd = q
			best = e
	return atan2(best.y - p.y, best.x - p.x) if best else a

func spawn_edge(run: bool) -> void:
	for t2 in 40:
		var side := randi() % 4
		var c: int = 1 if side == 0 else (S.cols - 2 if side == 1 else 1 + int(randf() * (S.cols - 2)))
		var r: int = 1 if side == 2 else (S.ry - 2 if side == 3 else 1 + int(randf() * (S.rows - 2)))
		var x: float = (c + 0.5) * TS
		var y: float = (r + 0.5) * TS
		if solid(x, y) or Vector2(x - S.p.x, y - S.p.y).length() < 380: continue
		var n0: int = S.zs.size()
		spawn_z(false)
		if S.zs.size() > n0:
			var z: Dictionary = S.zs[S.zs.size() - 1]
			z.x = x; z.y = y; z.alert = true
			if run and z.kind == "":
				z.run = true
				z.spd = maxf(z.spd, 112)
		return

func spawn_z(initial: bool) -> void:
	for t in 40:
		var c := 1 + int(randf() * (S.cols - 2))
		var r := 1 + int(randf() * (S.rows - 2))
		var v: int = S.g[r * S.cols + c]
		if MOVE[v] == 1 or v == 12: continue
		var x := (c + 0.5) * TS
		var y := (r + 0.5) * TS
		if Vector2(x - S.p.x, y - S.p.y).length() < (380 if initial else 460): continue
		var arm: bool = S.arch == "military" and randf() < 0.5
		var run: bool = not arm and randf() < 0.07 * S.danger
		var kind := ""
		if not arm and not run:
			var q := randf()
			if S.danger >= 2 and q < 0.08: kind = "bloat"
			elif S.danger >= 2 and q < 0.13: kind = "scream"
			elif q < 0.16: kind = "crawler"
		var km2: Array = [2.0, 0.7] if kind == "bloat" else ([0.8, 1.1] if kind == "scream" else ([0.6, 0.72] if kind == "crawler" else [1.0, 1.0]))
		S.zs.append({"x": x, "y": y, "arm": arm, "kind": kind, "var": randi() % 4, "lcd": randf() * 2, "wind": 0.0, "lng": 0.0, "rise": 0.0,
			"shirt": D.ZSHIRT[randi() % D.ZSHIRT.size()], "skin": D.ZSKIN[randi() % 3], "wk": randf() * 6,
			"hp": (45.0 + S.danger * 8) * (2.2 if arm else 1.0) * km2[0], "spd": (118.0 if run else (48 + randf() * 22 + S.danger * 4) * (0.85 if arm else 1.0)) * km2[1],
			"run": run, "dmg": (9 + S.danger * 1.5) * DF().dmg, "cd": 0.0, "alert": false, "wa": randf() * TAU, "wt": 0.0, "st": 0.0, "det": 0.0, "ds": 1.0, "hit": 0.0, "ang": 0.0,
			"dormant": false, "da": 0.0, "wake": false, "screamed": false, "dead": false})
		return

# ======================================================================
# ground: combat
# ======================================================================
func toxic(e: Dictionary) -> void:
	sfx("pop")
	for i in 7:
		S.smoke.append({"x": e.x + (randf() - 0.5) * 60, "y": e.y + (randf() - 0.5) * 60, "r": 26 + randf() * 26, "life": 2 + randf() * 1.5, "max": 3.5, "g": true})
	for z in S.zs:
		if z == e or z.dead: continue
		var d := Vector2(z.x - e.x, z.y - e.y).length()
		if d < 95:
			z.hp -= 60; z.hit = 0.15
			if z.hp <= 0:
				z.dead = true
				G.stats.kills += 1
	if S.npc:
		var d := Vector2(S.npc.x - e.x, S.npc.y - e.y).length()
		if d < 95: npc_hurt(18)
	if S == null: return
	var pd := Vector2(S.p.x - e.x, S.p.y - e.y).length()
	if pd < 95: hurt(22 * (1 - pd / 95) + 6, "gas")

func killed(e: Dictionary, isZ: bool) -> void:
	if e.get("kind", "") == "bloat": toxic(e)
	if S == null: return
	var st: Array = []
	for q in 5:
		var a := randf() * TAU
		var l := 10 + randf() * 26
		st.append([e.x, e.y, e.x + cos(a) * l, e.y + sin(a) * l, 2 + randf() * 3])
	S.bg.stamp(["streaks", st])
	var k: String = e.get("kind", "")
	stamp_corpse({"x": e.x, "y": e.y, "a": randf() * TAU, "shirt": "#5d6b3e" if k == "bloat" else ("#2e2e30" if k == "scream" else e.shirt), "skin": e.skin})
	for n in 10:
		var a := randf() * TAU
		var v := 40 + randf() * 120
		S.fx.append({"x": e.x, "y": e.y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.4, "c": "#6e120d", "sz": 3.0, "drag": true})
	if isZ and randf() < 0.25: S.drops.append({"x": e.x, "y": e.y, "k": "ammo", "n": 3 + randi() % 6})

func explode(br: Dictionary) -> void:
	if br.dead: return
	br.dead = true
	add_noise(18)
	for c in S.crates:
		if not c.open and c.ty == "safe" and Vector2(c.x - br.x, c.y - br.y).length() < 120:
			c.forced = true
			loot_crate(c)
	var R := 130.0
	sfx("boom")
	S.shake = 16.0
	S.boomFlash = 0.3
	S.scorch.append({"x": br.x, "y": br.y})
	stamp_scorch(br.x, br.y)
	for i in 9:
		S.smoke.append({"x": br.x + (randf() - 0.5) * 60, "y": br.y + (randf() - 0.5) * 60, "r": 30 + randf() * 30, "life": 2 + randf() * 2, "max": 4.0, "g": false})
	for i in 40:
		var a := randf() * TAU
		var v := 60 + randf() * 260
		S.fx.append({"x": br.x, "y": br.y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.3 + randf() * 0.5, "c": "#ffb347" if randf() < 0.5 else "#e3644c", "sz": 3.0, "drag": false})
	for z in S.zs:
		var d := Vector2(z.x - br.x, z.y - br.y).length()
		if d < R:
			z.hp -= 160 * (1 - d / R / 1.3)
			z.hit = 0.15
			if z.hp <= 0 and not z.dead:
				z.dead = true
				G.stats.kills += 1
				blood(z.x, z.y, 6)
		if d < 700: z.alert = true
	for v in S.sv:
		var d := Vector2(v.x - br.x, v.y - br.y).length()
		if d < R:
			v.hp -= 160 * (1 - d / R / 1.3)
			if v.hp <= 0 and not v.dead:
				v.dead = true
				G.stats.kills += 1
				blood(v.x, v.y, 6)
		v.alert = true
	for o in S.barrels:
		if not o.dead and o.fuse < 0 and Vector2(o.x - br.x, o.y - br.y).length() < 110: o.fuse = 0.15
	var pd := Vector2(S.p.x - br.x, S.p.y - br.y).length()
	if pd < R: hurt(40 * (1 - pd / R) + 8, "blast")

func shoot() -> void:
	var w: Dictionary = D.WEAPONS[G.weapon]
	var p: Dictionary = S.p
	p.cd = w.rate
	if G.ammo <= 0:
		p.cd = 0.42
		S.swing = 0.18
		sfx("swing")
		var hit := false
		var nb = null
		var nd := 56.0
		for e in enemies():
			var d := Vector2(e.x - p.x, e.y - p.y).length()
			if d < nd:
				nd = d
				nb = e
		if nb: p.ang = atan2(nb.y - p.y, nb.x - p.x)
		for e in enemies():
			var d := Vector2(e.x - p.x, e.y - p.y).length()
			if d < 44 and absf(U.ang_diff(atan2(e.y - p.y, e.x - p.x), p.ang)) < 1.1:
				e.hp -= 67 if has("boots") else 42
				e.hit = 0.12
				e.alert = true
				move_c(e, cos(p.ang) * 18, sin(p.ang) * 18, 10)
				blood(e.x, e.y, 2)
				hit = true
				if e.hp <= 0 and not e.dead:
					e.dead = true
					G.stats.kills += 1
					blood(e.x, e.y, 6)
		if hit: sfx("hit")
		if S.t - S.noAmmoT > 4:
			S.noAmmoT = S.t
			floater(p.x, p.y - 24, "Out of ammo. Using the machete.", "#e3644c")
		return
	G.ammo -= 1
	sfx(w.snd)
	for i in w.pel:
		var a: float = p.ang + (randf() - 0.5) * w.spr * 2
		S.bul.append({"x": p.x + cos(p.ang) * 16, "y": p.y + sin(p.ang) * 16, "vx": cos(a) * w.spd, "vy": sin(a) * w.spd, "life": w.life, "dmg": w.dmg * (1.2 if has("scope") else 1.0), "pl": true, "kb": w.kb, "bolt": w.bolt})
	S.fx.append({"x": p.x + cos(p.ang) * 8, "y": p.y + sin(p.ang) * 8, "vx": cos(p.ang + 1.6) * 110 + (randf() - 0.5) * 40, "vy": sin(p.ang + 1.6) * 110 + (randf() - 0.5) * 40, "life": 0.7, "c": "#d9b35a", "sz": 2.2, "drag": true})
	add_noise(w.noise)
	if not w.silent:
		S.flash = 0.06
		S.shake = minf(8, S.shake + (7.0 if w.pel > 6 else (5.0 if w.pel > 1 else (1.2 if w.rate < 0.15 else 2.0))))
		for z in S.zs:
			if not z.dormant and Vector2(z.x - p.x, z.y - p.y).length() < 520: z.alert = true
	for v in S.sv:
		if Vector2(v.x - p.x, v.y - p.y).length() < 700: v.alert = true

func hurt(d: float, cause: String) -> void:
	if uist != "": return
	if S:
		for q in 1 + (1 if d > 10 else 0):
			S.splat.append({"x": randf() * Wv, "y": Hv * 0.15 + randf() * Hv * 0.7, "r": 28 + randf() * 50, "life": 1.8, "s": randf() * 999})
	if G.armor > 0:
		var a := minf(G.armor, d * 0.5)
		G.armor -= a
		d -= a
	G.hp -= d
	sfx("hurt")
	S.hurt = 0.3
	S.shake = minf(8, S.shake + 4)
	blood(S.p.x, S.p.y, 2)
	if G.hp <= 0:
		G.hp = 0.0
		die(cause)

func heal() -> void:
	if mode != "ground" or G.hp >= 100 or (G.med <= 0 and G.band <= 0): return
	if G.band > 0 and (G.hp >= 55 or G.med <= 0):
		G.band -= 1
		G.hp = minf(100, G.hp + 20)
		floater(S.p.x, S.p.y - 24, "+20 health", "#9cc063")
	else:
		G.med -= 1
		G.hp = minf(100, G.hp + 45)
		floater(S.p.x, S.p.y - 24, "+45 health", "#9cc063")
	sfx("loot")

func roll_loot(k: String, ty: String) -> Variant:
	var mil: bool = S.arch == "military"
	match k:
		"fuel":
			var n := (4 + int(round(randf() * 4))) if ty == "jerry" else (2 + int(round(randf() * 3)))
			G.carried += n
			return ["+%d gal fuel" % n, "#d9a441"]
		"ammo":
			var n := int(round(((22 if mil else 12) + randi() % 14) * (1 + 0.1 * (S.danger - 1)) * (1.3 if has("bandolier") else 1.0)))
			G.ammo += n
			return ["+%d rounds" % n, "#efe6cf"]
		"cash":
			var n := int(round(((40 + randi() % 100) if (ty == "register" or ty == "safe") else (15 + randi() % 56)) * (1 + 0.12 * (S.danger - 1))))
			G.cash += n
			return ["+$%d" % n, "#9cc063"]
		"band":
			var n := 1 + (1 if randf() < 0.4 else 0)
			G.band += n
			return ["+%d bandage%s" % [n, "s" if n > 1 else ""], "#e38aa6"]
		"med":
			G.med += 1
			return ["+1 medkit", "#e38aa6"]
		"parts":
			var n := 1 + randi() % 3
			G.parts += n
			return ["+%d spare part%s" % [n, "s" if n > 1 else ""], "#9fb6e0"]
		"bomb":
			G.bombs += 1
			return ["+1 pipe bomb", "#ff9a70"]
		"armor":
			if G.armor >= 100:
				G.med += 1
				return ["+1 medkit", "#e38aa6"]
			G.armor = 100.0
			return ["Body armor", "#9fb6e0"]
		"goods":
			var pool: Array = ["jewelry", "whiskey"] if ty == "dresser" else (["jewelry", "cigarettes"] if ty == "register" else (["cigarettes", "whiskey", "batteries"] if ty == "locker" else (["antibiotics"] if ty == "cabinet" else D.GKEYS)))
			var g: String = pool[randi() % pool.size()]
			var n := 1 + (1 if randf() < 0.3 else 0)
			G.goods[g] = int(G.goods.get(g, 0)) + n
			return ["+%d %s" % [n, D.GOODS[g][0]], "#f0c4dd"]
		"chart":
			return read_chart()
		"trinket":
			var un: Array = D.TRINKETS.filter(func(x): return not G.trinkets.has(x[0]))
			if un.is_empty():
				G.cash += 150
				return ["+$150", "#9cc063"]
			var tr: Array = un[randi() % un.size()]
			G.trinkets.append(tr[0])
			toast("Found: %s. %s" % [tr[1], tr[2]], "good")
			sfx("jackpot")
			return [tr[1] + "!", "#ffd27a"]
		"weapon":
			var un: Array = []
			for i in range(1, D.WEAPONS.size()):
				if not G.weapons.has(i): un.append(i)
			if un.is_empty():
				G.ammo += 30
				return ["+30 rounds", "#efe6cf"]
			var w: int = un[randi() % un.size()]
			G.weapons.append(w)
			G.weapon = w
			return ["Found a %s!" % String(D.WEAPONS[w].name).to_lower(), "#ffd27a"]
	return null

func read_chart() -> Array:
	var s := strip(G.strip)
	var un := wd.strips.filter(func(o): return not known.has(o.id) and o.type != "haven" and o.type != "road")
	un.sort_custom(func(a, b): return Vector2(a.x - s.x, a.y - s.y).length() < Vector2(b.x - s.x, b.y - s.y).length())
	un = un.slice(0, 3)
	for o in un: known[o.id] = true
	G.rumor = maxf(500.0, G.rumor * 0.72)
	return ["Old chart: %d field%s marked%s" % [un.size(), "" if un.size() == 1 else "s", "" if known.has(0) else ", Haven rumor sharpened"], "#f0c4dd"]

func loot_crate(c: Dictionary) -> void:
	if c.ty == "safe" and not c.forced:
		if G.parts <= 0:
			if S.t - c.warnT > 3:
				c.warnT = S.t
				floater(c.x, c.y - 20, "Locked safe. Needs a spare part or a bomb.", "#ffb080")
			return
		G.parts -= 1
		floater(c.x, c.y - 34, "Pried open with a spare part", "#9fb6e0")
	c.open = true
	var key_s := str(S.s.id)
	if not G.looted.has(key_s): G.looted[key_s] = []
	G.looted[key_s].append(c.id)
	var tab: Dictionary = D.CONT.get(c.ty, D.CONT.crate)
	var rolls: int
	if c.ty == "safe": rolls = 2 + (1 if randf() < 0.5 else 0)
	else: rolls = 1 + (1 if randf() < (0.6 if (c.ty == "locker" or c.ty == "desk") else 0.35) + 0.06 * (S.danger - 1) + (0.25 if has("rabbit") else 0.0) else 0)
	if c.ty != "jerry" and randf() < 0.04 * S.danger: rolls += 1
	var n := 0
	for i in rolls:
		var k := D.wpick(tab, func(): return randf())
		if k == "empty": continue
		var a := randf() * TAU
		var v := 70 + randf() * 90
		S.pk.append({"x": c.x, "y": c.y, "vx": cos(a) * v, "vy": sin(a) * v, "k": k, "ty": c.ty, "t": 0.0, "z": 0.0, "vz": 130 + randf() * 80})
		n += 1
	if n == 0: floater(c.x, c.y - 16, "Empty", "#9a9a92")
	sfx("safe" if c.ty == "safe" else "open")
	S.shake = minf(5, S.shake + 1.5)
	for q in 9:
		S.fx.append({"x": c.x, "y": c.y, "vx": (randf() - 0.5) * 170, "vy": (randf() - 0.5) * 170, "life": 0.45, "c": "#9a9ea0" if c.ty == "safe" else "#8a6a40", "sz": 2.5, "drag": true})

func upd_pickups(dt: float) -> void:
	var p: Dictionary = S.p
	var i: int = S.pk.size() - 1
	while i >= 0:
		var q: Dictionary = S.pk[i]
		q.t += dt
		if q.t < 0.5:
			var f := pow(0.04, dt)
			q.vx *= f; q.vy *= f
			var nx: float = q.x + q.vx * dt
			var ny: float = q.y + q.vy * dt
			if not solid(nx, ny):
				q.x = nx; q.y = ny
			q.vz -= 560 * dt
			q.z = maxf(0, q.z + q.vz * dt)
			if q.z == 0 and q.vz < 0: q.vz *= -0.35
		else:
			var dx: float = p.x - q.x
			var dy: float = p.y - q.y
			var d := Vector2(dx, dy).length()
			if d == 0: d = 1
			q.z = maxf(0, q.z - dt * 60)
			if d < 110:
				var sp := 240 + (110 - d) * 6
				q.x += dx / d * sp * dt
				q.y += dy / d * sp * dt
			if d < 18:
				var r = roll_loot(q.k, q.ty)
				if r:
					S.flN = (S.flN + 1) % 3
					floater(p.x, p.y - 26 - S.flN * 15, r[0], D.RCOL[D.RAR[q.k]])
					sfx("rare" if D.RAR[q.k] >= 2 else ("cash" if q.k == "cash" else "loot"))
				S.pk.remove_at(i)
		i -= 1

func swap_weapon() -> void:
	if mode != "ground" or S == null or G.weapons.size() < 2: return
	var own: Array = G.weapons.duplicate()
	own.sort()
	G.weapon = own[(own.find(G.weapon) + 1) % own.size()]
	floater(S.p.x, S.p.y - 26, D.WEAPONS[G.weapon].name, "#efe6cf")
	sfx("click")
	S.p.cd = 0.25

func jump() -> void:
	if mode != "ground" or S == null or uist != "": return
	var p: Dictionary = S.p
	if p.jt > 0 or p.jcd > 0 or p.stam < 12: return
	p.jt = 0.46
	p.jcd = 0.75
	p.stam -= 12
	sfx("jump")

func throw_bomb() -> void:
	if mode != "ground" or S == null or uist != "" or G.bombs <= 0: return
	G.bombs -= 1
	var p: Dictionary = S.p
	var a: float = p.ang
	var bd := 0.6
	for e in enemies():
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d > 420: continue
		var q := absf(U.ang_diff(atan2(e.y - p.y, e.x - p.x), p.ang))
		if q < bd:
			bd = q
			a = atan2(e.y - p.y, e.x - p.x)
	S.thrown.append({"x": p.x + cos(a) * 14, "y": p.y + sin(a) * 14, "vx": cos(a) * 440, "vy": sin(a) * 440, "fuse": 1.1, "dead": false, "spin": 0.0})
	sfx("swing")

# ======================================================================
# ground: update
# ======================================================================
func upd_ground(dt: float) -> void:
	S.t += dt
	G.time += dt * 0.5
	var nk := 1 + (0.12 if G.diff == 0 else (0.3 if G.diff == 2 else 0.2)) * dark()
	var p: Dictionary = S.p
	S.flowT -= dt
	if S.flowT <= 0:
		S.flowT = 0.3
		build_flow()
	var mx := 0.0
	var my := 0.0
	if key(KEY_W) or key(KEY_UP): my -= 1
	if key(KEY_S) or key(KEY_DOWN): my += 1
	if key(KEY_A) or key(KEY_LEFT): mx -= 1
	if key(KEY_D) or key(KEY_RIGHT): mx += 1
	var aim = null
	var fire := false
	var ml := Vector2(mx, my).length()
	if ml > 1:
		mx /= ml; my /= ml
	var sprint: bool = (key(KEY_SHIFT)) and not ads and p.stam > 4 and ml > 0.1
	p.sprint = sprint
	var ox: float = p.x
	var oy: float = p.y
	var ps := (168.0 if has("shoes") else 150.0) * (1.55 if sprint else 1.0) * (1.1 if p.jt > 0 else 1.0) * (ADS_MOVE if ads else 1.0)
	S.air = p.jt > 0
	move_c(p, mx * ps * dt, my * ps * dt, 10)
	S.air = false
	p.wk += Vector2(p.x - ox, p.y - oy).length() * (0.3 if sprint else 0.22)
	if sprint:
		add_noise(2.2 * dt)
		p.stam = maxf(0, p.stam - 30 * dt)
		if randf() < dt * 2.5:
			for z in S.zs:
				if not z.dormant and Vector2(z.x - p.x, z.y - p.y).length() < 230: z.alert = true
	elif p.jt <= 0:
		p.stam = minf(100, p.stam + 20 * dt)
	p.jcd -= dt
	if p.jt > 0:
		p.jt -= dt
		if p.jt <= 0:
			if hit_box(p.x, p.y, 10):
				p.jt = 0.04
				p.jx += 1
				if p.jx > 8:
					p.x = p.safe.x; p.y = p.safe.y; p.jt = 0.0; p.jx = 0
			else:
				p.jx = 0
				sfx("land")
				for q in 8: S.fx.append({"x": p.x, "y": p.y + 6, "vx": (randf() - 0.5) * 120, "vy": (randf() - 0.5) * 60, "life": 0.35, "c": "#8a7a5a", "sz": 3.0, "drag": true})
	elif not hit_box(p.x, p.y, 10):
		p.safe = Vector2(p.x, p.y)
	S.swing -= dt
	if mouse.active:
		var w := s2w_g(mouse.x, mouse.y)
		aim = atan2(w.y - p.y, w.x - p.x)
		fire = mouse.down
	if aim != null: p.ang = aim
	elif Vector2(mx, my).length() > 0.1: p.ang = atan2(my, mx)
	p.cd -= dt
	if fire and p.cd <= 0: shoot()
	# bullets
	var i: int = S.bul.size() - 1
	while i >= 0:
		var b: Dictionary = S.bul[i]
		var dead := false
		for k in 3:
			if dead: break
			b.x += b.vx * dt / 3
			b.y += b.vy * dt / 3
			if solid_b(b.x, b.y):
				for n in 3: S.fx.append({"x": b.x, "y": b.y, "vx": (randf() - 0.5) * 120, "vy": (randf() - 0.5) * 120, "life": 0.25, "c": "#e8c77a", "sz": 3.0, "drag": false})
				dead = true
				break
			var hb := false
			for br in S.barrels:
				if not br.dead and pow(br.x - b.x, 2) + pow(br.y - b.y, 2) < 150:
					br.hp -= b.dmg
					if br.hp <= 0: explode(br)
					hb = true
					break
			if hb:
				dead = true
				break
			if S == null: return
			if b.pl:
				for z in S.zs:
					if not z.dead and pow(z.x - b.x, 2) + pow(z.y - b.y, 2) < 144:
						z.hp -= b.dmg
						z.hit = 0.1
						sfx("hit")
						if z.dormant:
							z.dormant = false; z.rise = 0.35; z.alert = true
						for n in 4: S.fx.append({"x": b.x, "y": b.y, "vx": b.vx * 0.12 + (randf() - 0.5) * 90, "vy": b.vy * 0.12 + (randf() - 0.5) * 90, "life": 0.35, "c": "#7a1510", "sz": 2.5, "drag": true})
						z.alert = true
						var vl := Vector2(b.vx, b.vy).length()
						move_c(z, b.vx / vl * b.kb, b.vy / vl * b.kb, 10)
						blood(z.x, z.y, 1)
						if z.hp <= 0:
							z.dead = true
							G.stats.kills += 1
							blood(z.x, z.y, 6)
						dead = true
						break
				if not dead:
					for v in S.sv:
						if not v.dead and pow(v.x - b.x, 2) + pow(v.y - b.y, 2) < 144:
							v.hp -= b.dmg
							v.hit = 0.1
							v.alert = true
							blood(v.x, v.y, 1)
							if v.hp <= 0:
								v.dead = true
								G.stats.kills += 1
								blood(v.x, v.y, 6)
								var am := randf() < 0.6
								S.drops.append({"x": v.x, "y": v.y, "k": "ammo" if randf() < 0.6 else "cash", "n": (10 + randi() % 10) if am else (30 + randi() % 60)})
							dead = true
							break
			elif pow(p.x - b.x, 2) + pow(p.y - b.y, 2) < 110:
				hurt(b.dmg, "shot")
				dead = true
		if S == null or uist == "dead": return
		b.life -= dt
		if dead or b.life <= 0: S.bul.remove_at(i)
		i -= 1
	for z in S.zs:
		if z.dead: killed(z, true)
	if S == null: return
	for v in S.sv:
		if v.dead: killed(v, false)
	if S == null or uist == "dead": return
	S.zs = S.zs.filter(func(z): return not z.dead)
	S.sv = S.sv.filter(func(v): return not v.dead)
	# zombies
	S.nd = 1e9
	var zs: Array = S.zs
	for z in zs:
		var dx: float = p.x - z.x
		var dy: float = p.y - z.y
		var d := Vector2(dx, dy).length()
		if d == 0: d = 1
		if z.dormant:
			if d < 75 or z.wake:
				z.dormant = false; z.rise = 0.7; z.alert = true
				sfx("snarl", 0.16)
				S.shake = maxf(S.shake, 4)
			continue
		if z.rise > 0:
			z.rise -= dt
			continue
		if z.alert and d < S.nd: S.nd = d
		if d < 250: z.alert = true
		var vx: float
		var vy: float
		var sp: float
		if z.alert:
			vx = dx / d; vy = dy / d; sp = z.spd
			if d > 150 and not (d < 420 and los(z.x, z.y, p.x, p.y)):
				var fd = flow_dir(z.x, z.y)
				if fd:
					vx = fd.x; vy = fd.y
			if S.npc:
				var nx: float = S.npc.x - z.x
				var ny: float = S.npc.y - z.y
				var nd := Vector2(nx, ny).length()
				if nd == 0: nd = 1
				if nd < d * 0.7 and nd < 300:
					vx = nx / nd; vy = ny / nd
			if z.det > 0:
				z.det -= dt
				var px: float = -vy * z.ds
				var py: float = vx * z.ds
				vx = vx * 0.3 + px
				vy = vy * 0.3 + py
		else:
			z.wt -= dt
			if z.wt <= 0:
				z.wt = 1.5 + randf() * 3
				z.wa = randf() * TAU
			vx = cos(z.wa); vy = sin(z.wa); sp = z.spd * 0.3
		for o in zs:
			if o == z: continue
			var ox2: float = z.x - o.x
			var oy2: float = z.y - o.y
			var dd := ox2 * ox2 + oy2 * oy2
			if dd < 400 and dd > 0.01:
				var q := sqrt(dd)
				vx += ox2 / q * 0.8
				vy += oy2 / q * 0.8
		z.lcd -= dt
		if z.alert and z.kind == "" and d < 100 and z.lcd <= 0 and not (z.wind > 0) and not (z.lng > 0):
			z.wind = 0.28
			z.lcd = 2.4
			if randf() < 0.6: sfx("snarl", 0.1)
		if z.wind > 0:
			z.wind -= dt
			sp = 0
			if z.wind <= 0: z.lng = 0.32
		elif z.lng > 0:
			z.lng -= dt
			sp *= DF().lunge
			vx = dx / d; vy = dy / d
		sp *= nk
		var zx: float = z.x
		var zy: float = z.y
		move_c(z, vx * sp * dt, vy * sp * dt, 10)
		var moved := Vector2(z.x - zx, z.y - zy).length()
		z.wk += moved * 0.22
		if z.alert and moved < sp * dt * 0.3:
			z.st += dt
			if z.st > 0.25:
				z.det = 0.7
				z.ds = 1.0 if randf() < 0.5 else -1.0
				z.st = 0.0
		else:
			z.st = 0.0
		z.ang = atan2(vy, vx)
		z.cd -= dt
		z.hit -= dt
		if z.kind == "scream" and not z.screamed and d < 420 and los(z.x, z.y, p.x, p.y):
			z.screamed = true
			sfx("scream")
			S.shake = 6.0
			add_noise(22)
			toast("A screamer. More of them are coming.", "bad")
			for o in S.zs:
				o.alert = true
				if o.dormant: o.wake = true
			for k in 4: spawn_z(false)
		if S.npc:
			var nd := Vector2(S.npc.x - z.x, S.npc.y - z.y).length()
			if nd < 250: z.alert = true
			if nd < 22 and z.cd <= 0:
				z.cd = 0.85
				npc_hurt(z.dmg)
				if S == null: return
		if d < 24 and z.cd <= 0 and not (p.jt > 0):
			z.cd = 0.85
			hurt(z.dmg, "bitten")
			if uist != "": return
	# survivors
	for v in S.sv:
		var dx: float = p.x - v.x
		var dy: float = p.y - v.y
		var d := Vector2(dx, dy).length()
		if d == 0: d = 1
		var see := d < 520 and los(v.x, v.y, p.x, p.y)
		if see and d < 420: v.alert = true
		v.cd -= dt
		v.hit -= dt
		var vx := 0.0
		var vy := 0.0
		if v.alert:
			v.ang = atan2(dy, dx)
			if see:
				if d > 300:
					vx = dx / d; vy = dy / d
				elif d < 180:
					vx = -dx / d; vy = -dy / d
				v.sw -= dt
				if v.sw <= 0:
					v.sw = 1 + randf() * 1.5
					v.sd = 1.0 if randf() < 0.5 else -1.0
				vx += -dy / d * v.sd * 0.7
				vy += dx / d * v.sd * 0.7
				if v.cd <= 0:
					v.cd = 1.1 + randf() * 0.7
					var a: float = v.ang + (randf() - 0.5) * 0.22
					S.bul.append({"x": v.x + cos(a) * 14, "y": v.y + sin(a) * 14, "vx": cos(a) * 620, "vy": sin(a) * 620, "life": 0.9, "dmg": (8 + S.danger) * DF().dmg, "pl": false, "kb": 0.0, "bolt": false})
					sfx("enemy")
			else:
				vx = dx / d; vy = dy / d
		var vx0: float = v.x
		var vy0: float = v.y
		move_c(v, vx * 85 * dt, vy * 85 * dt, 10)
		v.wk += Vector2(v.x - vx0, v.y - vy0).length() * 0.22
	for c in S.crates:
		if not c.open and Vector2(c.x - p.x, c.y - p.y).length() < 24: loot_crate(c)
	i = S.drops.size() - 1
	while i >= 0:
		var d: Dictionary = S.drops[i]
		if Vector2(d.x - p.x, d.y - p.y).length() < 22:
			if d.k == "ammo":
				d.n = int(round(d.n * (1.3 if has("bandolier") else 1.0)))
				G.ammo += d.n
				floater(d.x, d.y - 16, "+%d rounds" % d.n)
			else:
				G.cash += d.n
				floater(d.x, d.y - 16, "+$%d" % d.n, "#9cc063")
			S.drops.remove_at(i)
		i -= 1
	add_noise((0.35 + 0.05 * S.danger) * dt)
	for wv in [[35, 5, "They heard the engine. More are coming."], [65, 9, "A crowd is gathering at the fence line."], [100, 14, "The horde is here. Get to the plane."]]:
		if S.noise >= wv[0] and not S.waves.has(wv[0]):
			S.waves.append(wv[0])
			toast(wv[2], "bad")
			sfx("horde")
			S.shake = maxf(S.shake, 5)
			for k in int(round(wv[1] * DF().count)): spawn_edge(wv[0] >= 100 and G.diff != 0)
	S.spawnT -= dt
	if S.spawnT <= 0:
		var nf: float = S.noise / 100.0
		S.spawnT = maxf(0.7, (8 - S.danger * 1.1) * (1 - nf * 0.8)) * (0.7 + randf() * 0.6)
		var capn := mini(60, S.cap + int(floor(S.noise / 8.0)))
		if S.zs.size() < capn:
			if nf >= 1:
				spawn_edge(true)
				spawn_edge(randf() < 0.5)
			else:
				spawn_z(false)
	for br in S.barrels:
		if br.fuse >= 0 and not br.dead:
			br.fuse -= dt
			if br.fuse <= 0: explode(br)
			if S == null or uist == "dead": return
	if randf() < dt * 0.4:
		var nd := 1e9
		for z in S.zs:
			if z.alert:
				var d2 := Vector2(z.x - p.x, z.y - p.y).length()
				if d2 < nd: nd = d2
		if nd < 450: sfx("groan", 0.09 * (1 - nd / 450))
	S.boomFlash -= dt
	i = S.fx.size() - 1
	while i >= 0:
		var f: Dictionary = S.fx[i]
		f.x += f.vx * dt
		f.y += f.vy * dt
		if f.drag:
			var dr := pow(0.02, dt)
			f.vx *= dr; f.vy *= dr
		f.life -= dt
		if f.life <= 0: S.fx.remove_at(i)
		i -= 1
	i = S.thrown.size() - 1
	while i >= 0:
		var b: Dictionary = S.thrown[i]
		var f := pow(0.18, dt)
		b.vx *= f; b.vy *= f
		b.spin += dt * 12
		var nx: float = b.x + b.vx * dt
		if solid(nx, b.y): b.vx *= -0.5
		else: b.x = nx
		var ny: float = b.y + b.vy * dt
		if solid(b.x, ny): b.vy *= -0.5
		else: b.y = ny
		b.fuse -= dt
		if b.fuse <= 0:
			explode(b)
			if S == null or uist == "dead": return
			S.thrown.remove_at(i)
		i -= 1
	i = S.smoke.size() - 1
	while i >= 0:
		var m: Dictionary = S.smoke[i]
		m.life -= dt; m.r += dt * 24; m.y -= dt * 10; m.x += dt * 6
		if m.life <= 0: S.smoke.remove_at(i)
		i -= 1
	i = S.fl.size() - 1
	while i >= 0:
		var f: Dictionary = S.fl[i]
		f.y -= 26 * dt
		f.life -= dt
		if f.life <= 0: S.fl.remove_at(i)
		i -= 1
	upd_npc(dt)
	if S == null: return
	upd_pickups(dt)
	for c in S.crates:
		if not c.open and c.ty == "stash" and not c.seen and Vector2(c.x - p.x, c.y - p.y).length() < 110:
			c.seen = true
			floater(c.x, c.y - 18, "Something glints under the floorboards", "#ffd27a")
	for cw in S.crows:
		if cw.gone: continue
		if not cw.fly:
			var dcw := Vector2(cw.x - p.x, cw.y - p.y).length()
			if dcw < 170 or (S.flash > 0 and dcw < 500):
				cw.fly = true
				var a := atan2(cw.y - p.y, cw.x - p.x) + (randf() - 0.5) * 0.8
				var v := 170 + randf() * 80
				cw.vx = cos(a) * v
				cw.vy = sin(a) * v
				if S.t - S.cawT > 1:
					S.cawT = S.t
					sfx("caw")
		else:
			cw.x += cw.vx * dt
			cw.y += cw.vy * dt
			cw.h = minf(40, cw.h + dt * 30)
			cw.life -= dt
			if cw.life <= 0: cw.gone = true
	if S.tanker and S.tanker.gal > 0:
		var tk: Dictionary = S.tanker
		var d := Vector2(p.x - tk.x, p.y - tk.y).length()
		if d < 70 and ml < 0.1:
			tk.prog += dt / 4.0
			add_noise(5 * dt)
			if S.t - S.sipT > 0.5:
				S.sipT = S.t
				sfx("siphon")
			if tk.prog >= 1:
				G.carried += tk.gal
				floater(p.x, p.y - 26, "+%d gal siphoned" % int(tk.gal), "#d9a441")
				sfx("loot")
				tk.gal = 0
		elif d < 70 and not S.tkHint:
			S.tkHint = true
			floater(tk.x, tk.y - 30, "Stand still to siphon fuel. It is noisy.", "#d9a441")
	S.nearPlane = Vector2(p.x - S.plane.x, p.y - S.plane.y).length() < 130
	S.adsK = move_toward(S.get("adsK", 0.0), 1.0 if ads else 0.0, dt * ADS_RATE)
	var lead := ADS_LEAD * ads_ease()
	S.cx = lerpf(S.cx, p.x + cos(p.ang) * lead, minf(1, dt * 6))
	S.cy = lerpf(S.cy, p.y + sin(p.ang) * lead, minf(1, dt * 6))
	var gs := ground_scale()
	var hw := Wv / 2 / gs
	var hh := Hv / 2 / gs
	var mw: float = S.cols * TS
	var mh: float = S.rows * TS
	S.cx = clampf(S.cx, hw, mw - hw) if mw > 2 * hw else mw / 2
	S.cy = clampf(S.cy, hh - 110 / gs, mh - hh) if mh > 2 * hh else mh / 2
	S.shake = maxf(0, S.shake - dt * 20)
	S.flash -= dt
	S.hurt -= dt
	i = S.splat.size() - 1
	while i >= 0:
		S.splat[i].life -= dt
		if S.splat[i].life <= 0: S.splat.remove_at(i)
		i -= 1
	if dark() > 0.3 and randf() < dt * 0.22: S.flick = 0.05 + randf() * 0.14
	S.flick -= dt
	if S.nd < 150 or G.hp < 35:
		S.hbT -= dt
		if S.hbT <= 0:
			S.hbT = 0.6 if G.hp < 35 else 0.8
			sfx("heart", (0.3 * (1 - S.nd / 150) + 0.08) if S.nd < 150 else 0.15)
	var band := 2 if G.hp < 35 else (1 if G.hp < 60 else 0)
	if band != S.band:
		S.band = band
		if band == 2:
			sat = 0.45; con = 1.16
		elif band == 1:
			sat = 0.7; con = 1.1
		else:
			sat = 0.84; con = 1.07

# ======================================================================
# death / win
# ======================================================================
func die(kind: String) -> void:
	if uist == "dead": return
	if mode == "flight" and F:
		F.crashed = true
		sfx("thump" if kind == "overrun" else "crash")
	clear_input()
	ui.show_dead(kind)

func win() -> void:
	clear_save()
	CP = ""
	ui.show_win()
	mode = "title"
	F = null
	_free_site()

# ======================================================================
# menu actions
# ======================================================================
func good_price(s: Dictionary, g: String) -> int:
	return int(round(D.GOODS[g][1] * (0.6 + U.hash3(s.id, D.GKEYS.find(g), wd.SEED + 71)) * (1.2 if has("ledger") else 1.0)))
func repair_cost() -> int:
	return int(ceil(100 - G.hull)) * 4 + (60 if G.leak > 0 else 0)

func act(a: String, v = null) -> void:
	var s = strip(G.strip) if G else null
	var P = PS() if G else null
	match a:
		"tab":
			menu_tab = v
			ui.render_menu()
		"close", "resume": ui.close_ui()
		"band":
			if G.cash >= 25:
				G.cash -= 25; G.band += 1
			ui.render_menu()
		"bomb":
			if G.cash >= 60:
				G.cash -= 60; G.bombs += 1
			ui.render_menu()
		"sell":
			var n := int(G.goods.get(v, 0))
			var pr := good_price(s, v)
			if n:
				G.cash += n * pr
				G.goods[v] = 0
				toast("Sold %d %s for $%d." % [n, D.GOODS[v][0], n * pr], "good")
				sfx("cash")
			ui.render_menu()
		"sellparts":
			if G.parts > 0:
				G.parts -= 1; G.cash += 15
			ui.render_menu()
		"fieldfix":
			if G.parts > 0 and G.hull < 100:
				G.parts -= 1
				G.hull = minf(100, G.hull + (25 if has("gloves") else 15))
				toast("Patched a section of the airframe.", "good")
			ui.render_menu()
		"fieldleak":
			if G.parts >= 2 and G.leak > 0:
				G.parts -= 2; G.leak = 0.0
				toast("Fuel line sealed.", "good")
			ui.render_menu()
		"repair":
			var c := repair_cost()
			if c > 0 and G.cash >= c:
				G.cash -= c; G.hull = 100.0; G.leak = 0.0
				toast("The mechanic patches her up.", "good")
			ui.render_menu()
		"sleep":
			var m := fmod(G.time, 1440.0)
			G.time += fmod(390 - m + 1440, 1440.0)
			G.hp = minf(100, G.hp + 40)
			G.offers = gen_offers(s)
			enter_ground(s)
			checkpoint()
			toast("Day %d. You wake at first light." % day(), "good")
		"sound":
			synth.set_on(not synth.on)
			ui.close_ui()
			ui.open_pause()
		"diff":
			G.diff = int(v)
			save_game()
			ui.close_ui()
			ui.open_pause()
			toast("Difficulty: %s. It takes full effect at the next airfield." % D.DIFFS[G.diff].name, "mag")
		"takeoff": takeoff()
		"pour":
			var n := minf(G.carried, P.fuelCap - G.fuel)
			G.fuel += n
			G.carried -= n
			toast("Poured %.1f gal." % n)
			ui.render_menu()
		"buy5":
			var n := minf(5, P.fuelCap - G.fuel)
			var c := int(ceil(n * s.fuelPrice))
			if G.cash >= c:
				G.cash -= c; G.fuel += n
			ui.render_menu()
		"fill":
			var n: float = P.fuelCap - G.fuel
			n = minf(n, floor(G.cash / float(s.fuelPrice)))
			G.cash -= int(ceil(n * s.fuelPrice))
			G.fuel += n
			ui.render_menu()
		"accept":
			var idx := int(v)
			if idx < G.offers.size():
				var c: Dictionary = G.offers[idx]
				G.offers.remove_at(idx)
				G.contracts.append(c)
				var tg := contract_target(c)
				known[tg] = true
				known[int(c.dest)] = true
				if G.nav < 0: G.nav = tg
				toast(("Rescue job taken. Course set to %s." % strip(tg).name) if c.get("type", "") == "rescue" else ("Loaded %s. Course set to %s." % [c.what, strip(tg).name]), "mag")
			ui.render_menu()
		"dump":
			G.contracts.remove_at(int(v))
			ui.render_menu()
		"nav":
			G.nav = int(v)
			ui.render_menu()
		"tank":
			var c: int = 450 * (G.tanks + 1) + G.plane * 200
			if G.cash >= c and G.tanks < P.tankMax:
				G.cash -= c; G.tanks += 1
				toast("Auxiliary tank fitted.", "good")
			ui.render_menu()
		"engine":
			var c: int = 600 * (G.engine + 1)
			if G.cash >= c and G.engine < 2:
				G.cash -= c; G.engine += 1
				toast("Engine overhauled.", "good")
			ui.render_menu()
		"weapon":
			var i := int(v)
			var w: Dictionary = D.WEAPONS[i]
			if G.weapons.has(i): G.weapon = i
			elif G.cash >= w.price:
				G.cash -= w.price
				G.weapons.append(i)
				G.weapon = i
				toast("Bought the %s." % String(w.name).to_lower(), "good")
			ui.render_menu()
		"ammo":
			if G.cash >= 35:
				G.cash -= 35; G.ammo += 30
			ui.render_menu()
		"ammo100":
			if G.cash >= 100:
				G.cash -= 100; G.ammo += 100
			ui.render_menu()
		"med":
			if G.cash >= 60:
				G.cash -= 60; G.med += 1
			ui.render_menu()
		"plane":
			var i := int(v)
			var cost: int = D.PLANES[i].price - int(floor(D.PLANES[G.plane].price * 0.5))
			if G.cash >= cost:
				G.cash -= cost
				G.plane = i
				G.tanks = 0
				G.engine = 0
				G.fuel = minf(G.fuel, PS().fuelCap)
				G.contracts = G.contracts.slice(0, PS().slots)
				toast("The %s is yours." % D.PLANES[i].name, "good")
			ui.render_menu()
		"newgame": start_new()
		"continue":
			var sv = load_save()
			if sv: resume_from(sv)
		"retry":
			var st = JSON.parse_string(CP)
			st = normalize(st)
			st.cash = int(floor(st.cash * (0.8 if st.diff == 2 else 0.9)))
			st.hp = 100.0
			resume_from(st)
			toast("You wake up in the hangar with a headache and a lighter wallet.", "bad")
		"quit":
			save_game()
			show_title()
		"help": ui.show_help()
		"backtitle": show_title()

# ======================================================================
# title & lifecycle
# ======================================================================
func show_title() -> void:
	mode = "title"
	F = null
	_free_site()
	sat = 0.84; con = 1.07
	ui.show_title(load_save() != null)

func _regen_world(seed_v: int) -> void:
	wd.gen_world(seed_v)
	baker.set_world(wd)
	TCACHE.clear()
	baker.build_overview()

func start_new() -> void:
	var seed_v := randi() % 1000000000
	_regen_world(seed_v)
	G = new_state(seed_v)
	known = {wd.START: true}
	var st := strip(wd.START)
	var others := wd.strips.filter(func(s): return s.type != "haven" and s.id != wd.START)
	others.sort_custom(func(a, b): return Vector2(a.x - st.x, a.y - st.y).length() < Vector2(b.x - st.x, b.y - st.y).length())
	for s in others.slice(0, 2): known[s.id] = true
	G.visits[str(wd.START)] = 1
	G.offers = gen_offers(st)
	enter_ground(st)
	checkpoint()
	toast("%s. Home, for now." % st.name)
	toast_later(1.6, "Loot the hangars, then board the plane.", "mag")

func resume_from(st: Dictionary) -> void:
	st = normalize(st)
	if baker.overview == null or int(st.seed) != wd.SEED: _regen_world(int(st.seed))
	G = st
	for kv in [["time", 420.0], ["hull", 100.0], ["leak", 0.0], ["roadStrips", []], ["trinkets", []], ["diff", 1], ["band", 0], ["parts", 0], ["bombs", 0], ["armor", 0.0], ["rumor", 2600.0], ["goods", {}], ["looted", {}], ["visits", {}], ["mayday", null], ["offers", []]]:
		if not G.has(kv[0]) or (G[kv[0]] == null and kv[1] != null): G[kv[0]] = kv[1]
	wd.strips = wd.strips.filter(func(s): return s.type != "road")
	for r in G.roadStrips:
		var rr: Dictionary = r.duplicate()
		rr.id = wd.strips.size()
		for k in ["x", "y", "ang", "len", "wid"]: rr[k] = float(rr[k])
		rr.danger = int(rr.danger)
		rr.seed = int(rr.seed)
		wd.strips.append(rr)
	if G.strip >= wd.strips.size(): G.strip = wd.START
	if G.nav >= wd.strips.size(): G.nav = -1
	G.contracts = G.contracts.filter(func(c): return int(c.dest) < wd.strips.size())
	known = {}
	for k in G.get("known", []): known[int(k)] = true
	known[G.strip] = true
	enter_ground(strip(G.strip))
	checkpoint()


class DrawLayer extends Node2D:
	var idx := 0
	var game
	func _draw() -> void:
		game.draw_layer(idx, Pen.new(self))
