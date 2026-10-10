class_name Game
extends Node2D
## Dead Reckoning — main game controller. A close port of the HTML game's logic.
## Owns the run state (G, F, S) and the frame loop, the player on foot, zombies, bullets and
## the ground helpers. Bigger systems live in their own scripts, reached through the vars
## below: survivors.gd (armed survivors), blasts.gd (explosions and cars), flight.gd
## (flying and landing) and menu.gd (menus, saves, title screen, settings).

const WORLD := D.WORLD   # land size: set in data.gd
# Open ocean all the way around the landmass (which spans 0..WORLD). It is made wide
# enough that the longest-ranged plane - best tanks, best engine, wings trinket, full
# throttle and the strongest tailwind - can't reach the edge on one full tank, then
# multiplied by OCEAN_SAFETY. Worked out from the plane data at start-up (ocean_pad()).
const OCEAN_SAFETY := 1.2
const MAX_ENGINE := 2       # engine upgrades available (see the "engine" purchase)
const MAX_WIND := 22.0      # strongest wind rolled at takeoff
var OCEAN_PAD := 0.0
var old_save_warned := false
const TS := 32.0
# Slow health regen: after REGEN_DELAY s of standing still (within one tile of where you
# stopped), not sprinting, not shooting and not hurt, health creeps back up to REGEN_CAP.
const REGEN_DELAY := 3.0
const REGEN_CAP := 50.0   # % of max health (max is 100)
const REGEN_RATE := 3.0   # health per second

# aim down sights — on foot, hold right mouse
const ADS_MOVE := 0.5     # walk speed multiplier while aiming
const ADS_SENS := 0.45     # mouse sensitivity multiplier while aiming
const ADS_ZOOM := 0.25    # extra zoom at full aim (0.25 = 25% closer)
const ADS_LEAD := 90.0    # how far (world px) the camera leans toward where you face

# Screamers: must see you (clear line of sight) within SCREAM_RANGE px, roughly facing you
# (within SCREAM_CONE degrees), for SCREAM_WINDUP seconds straight before they scream.
# They stop and snarl while winding up; break line of sight or kill them to stop it.
const SCREAM_RANGE := 300.0
const SCREAM_CONE := 70.0
const SCREAM_WINDUP := 1.0
const ADS_AUTO_SPREAD := 0.5  # automatic weapons' bullet spread multiplier while aiming
# When a person (you, an armed survivor, the rescue survivor) is hurt but not killed, a
# short spray of blood flies off away from whatever hit them, like the sparks off a wall,
# in the same dark red as the blood left on the ground.
const HIT_SPRAY_N := 3.5         # particles per hit, on average (2 or 3)
const HIT_SPRAY_SZ := 3.0        # particle size (wall sparks are 3)
const HIT_SPRAY_SPREAD := 0.45   # half-width of the spray cone, radians
const HIT_SPRAY_MIN := 60.0      # particle speed range, px/s
const HIT_SPRAY_MAX := 170.0
const ADS_RATE := 2.0     # ease speed in/out (higher = snappier); 2.0 = half a second each way
const BOLT_SNEAK_MULT := 2.0   # aimed crossbow damage multiplier on a hostile survivor who isn't alerted yet
const CAM_EDGE := 60.0    # player always stays at least this many screen px from the view's edge
const CAM_TOP := 140.0    # ...and this far from the top (clears the status panel)

# bodies — closest a zombie's or survivor's centre can get to the player's (r10 + r10).
# Keep below the 24px bite range so they can still reach you.
const Z_BODY := 20.0

var zoom := 1.0          # world camera zoom multiplier (1 = default framing)
var ui_scale := 1.0      # interface size multiplier on top of automatic window scaling
var fullscreen := false
var win_idx := 0

var wd := World.new()
var baker: Baker
var synth: Synth
var ui: UI
# Systems split out of this script; each keeps a reference back to the game (gm).
var survivors := Survivors.new(self)
var blasts := Blasts.new(self)
var flight := Flight.new(self)
var menu := Menu.new(self)
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
var ads_off := Vector2.ZERO    # reticle offset from the player in WORLD units (kept steady while the camera zooms/leans)
var ads_virtual := false       # circle is on the virtual cursor: while aiming AND while the camera eases back
var ads_skip := false          # ignore the motion event caused by re-centring the hidden cursor
var cursor_on_btn := false     # exploration: pointer is over an on-screen button, show the Windows cursor
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
	OCEAN_PAD = ocean_pad()
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
	menu.load_settings()
	_resize()
	# world + textures
	var sv = menu.load_save()
	wd.PAD = OCEAN_PAD
	wd.gen_world(int(sv.seed) if sv else randi() % 1000000000)
	baker.set_world(wd)
	await baker.build_overview(OCEAN_PAD)
	await Tx.bake_all(baker)
	var st: Dictionary = wd.strips[wd.START]
	demo = {"x": st.x, "y": st.y, "h": -0.6}
	ready_done = true
	menu.show_title()
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
	return {"v": 1, "world": WORLD, "seed": seed_v, "cash": 150, "plane": 0, "tanks": 0, "engine": 0, "fuel": 18.0, "time": 420.0, "hull": 100.0, "leak": 0.0, "roadStrips": [],
		"band": 3, "parts": 1, "bombs": 1, "diff": 1, "armor": 0.0, "goods": {}, "rings": [], "trinkets": [], "carried": 0.0, "ammo": 70, "med": 2, "hp": 100.0,
		"weapons": [0], "weapon": 0, "contracts": [], "known": [], "strip": wd.START, "looted": {}, "offers": [], "nav": -1, "visits": {}, "mayday": null,
		"stats": {"flights": 0, "deliv": 0, "kills": 0, "dist": 0.0}}

func PS() -> Dictionary:
	var b: Dictionary = D.PLANES[G.plane]
	var p := b.duplicate()
	p.burn = b.burn * (0.9 if has("wings") else 1.0)
	p.fuelCap = b.fuel + G.tanks * b.tankStep
	p.max = b.max * (1 + 0.08 * G.engine)
	p.cruise = b.cruise * (1 + 0.08 * G.engine)
	return p

## Farthest any plane could fly on one full tank, with every upgrade, x OCEAN_SAFETY.
## Full throttle gives the most distance per gallon, so that's the worst case.
func ocean_pad() -> float:
	var best := 0.0
	for b in D.PLANES:
		var gal: float = b.fuel + b.tankMax * b.tankStep
		var burn: float = b.burn * 0.9                       # wings trinket
		var spd: float = b.max * (1 + 0.08 * MAX_ENGINE) + MAX_WIND
		best = maxf(best, gal / burn * spd)
	return best * OCEAN_SAFETY

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

func sfx(k: String, v: float = -1.0, pitch: float = 1.0) -> void: synth.sfx(k, v, pitch)
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

func _input(e: InputEvent) -> void:
	# Escape leaves fullscreen before any menu or gameplay handles the key.
	if fullscreen and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		menu.set_fullscreen(false)
		if ui: ui.refresh_settings()
		get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if not ready_done: return
	if menu.display_input(e): return
	if e is InputEventKey and e.pressed and not e.echo:
		var c: int = e.physical_keycode
		if c == KEY_C and mode == "flight" and F and uist == "" and flight.cruise_ok(): F.cruise = not F.cruise
		if c == KEY_M and (mode == "flight" or mode == "ground") and (uist == "" or uist == "map"): ui.toggle_map()
		if (c == KEY_ESCAPE or c == KEY_P) and (mode == "flight" or mode == "ground"):
			if uist == "": ui.open_pause()
			elif uist == "pause" or uist == "map": ui.close_ui()
			elif uist == "settings":
				ui.close_ui()
				ui.open_pause()
		if uist == "" and mode == "ground":
			if c == KEY_E and S and S.nearPlane: ui.open_menu()
			if c == KEY_SPACE: jump()
			if c == KEY_Q: swap_weapon()
			var weapon_slot := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7].find(c)
			if weapon_slot < 0: weapon_slot = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7].find(c)
			if weapon_slot >= 0: select_weapon(weapon_slot)
			if c == KEY_H: heal()
			if c == KEY_G: throw_bomb()
	elif e is InputEventMouseButton:
		var x: float = e.position.x
		var y: float = e.position.y
		if e.button_index != MOUSE_BUTTON_LEFT: return
		if e.pressed:
			if not ads_virtual:
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
		if ads_virtual:
			# The real cursor is hidden; steer a virtual cursor (reduced sensitivity while
			# aiming, full speed while the camera eases back after release).
			# e.relative comes from the normal (accelerated, stretch-scaled) pointer, so
			# ADS_SENS is always relative to how the visible cursor normally moves.
			var rel: Vector2 = e.relative
			if ads_skip:
				ads_skip = false
				if rel.length() > minf(Wv, Hv) * 0.2: rel = Vector2.ZERO
			ads_cur = (ads_cur + rel * (ADS_SENS if ads else 1.0)).clamp(Vector2.ZERO, Vector2(Wv, Hv))
			ads_off = (ads_cur - player_screen()) / ground_scale()
			mouse.x = ads_cur.x; mouse.y = ads_cur.y
			# keep the hidden cursor away from the window edges so it never stops short
			var mid := Vector2(Wv, Hv) * 0.5
			if e.position.distance_to(mid) > minf(Wv, Hv) * 0.25:
				get_viewport().warp_mouse(mid)
				ads_skip = true
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
		if S: S.adsK = 0.0   # skip the ease-back so the pointer is released right away

func set_thr(y: float) -> void:
	if F: F.thr = clampf(1.0 - (y - thr_bar.y) / thr_bar.h, 0.0, 1.0)

func clear_input() -> void:
	ptrs.clear()
	mouse.down = false
	set_ads(false)

## Enter/leave aim-down-sights. While aiming the OS cursor is hidden and kept in
## the window; a virtual cursor (ads_cur) moves at ADS_SENS and a reticle is drawn.
## (Not MOUSE_MODE_CAPTURED: on Windows that switches to raw mouse input, which
## ignores the Windows pointer speed/acceleration, so "half speed" could end up
## feeling no slower than the normal cursor.)
## On release the virtual cursor stays pinned to the world until the camera has
## finished easing back, then the real cursor is put back where the circle is.
func set_ads(on: bool) -> void:
	if on == ads: return
	ads = on
	if on and not ads_virtual:
		ads_cur = Vector2(mouse.x, mouse.y) if mouse.active else get_viewport().get_mouse_position()
		ads_off = (ads_cur - player_screen()) / ground_scale()
		mouse.active = true
		ads_skip = false
		ads_virtual = true

## Hand control back to the real (hidden) pointer, placed where the circle is.
func end_virtual_cursor() -> void:
	ads_virtual = false
	get_viewport().warp_mouse(ads_cur)
	mouse.x = ads_cur.x; mouse.y = ads_cur.y

## Where the exploration-mode circle cursor is drawn.
func reticle_pos() -> Vector2:
	return ads_cur if ads_virtual else get_viewport().get_mouse_position()

## Exploration mode hides the Windows pointer (the circle is drawn instead) while
## playing; menus, flight mode and hovering an on-screen button get the normal
## pointer back.
func update_cursor() -> void:
	var want := Input.MOUSE_MODE_VISIBLE
	cursor_on_btn = false
	var playing: bool = mode == "ground" and S and uist == ""
	if ads_virtual and not (ads or (playing and S.get("adsK", 0.0) > 0.0)):
		end_virtual_cursor()
	if playing:
		if ads_virtual:
			want = Input.MOUSE_MODE_CONFINED_HIDDEN
		elif over_hud_button():
			cursor_on_btn = true
		else:
			want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want: Input.mouse_mode = want

## True when the mouse is over one of the visible on-screen buttons (heal, map, board...).
func over_hud_button() -> bool:
	if ui == null: return false
	for k in ui.btns:
		var b: Control = ui.btns[k]
		if b.is_visible_in_tree() and b.get_global_rect().has_point(b.get_global_mouse_position()): return true
	return false

## Player's position on screen (unshaken camera), in viewport pixels.
func player_screen() -> Vector2:
	if not S: return Vector2(Wv, Hv) * 0.5
	var gs := ground_scale()
	return Vector2(Wv / 2 + (S.p.x - S.cx) * gs, Hv / 2 + (S.p.y - S.cy) * gs)

## While aiming, pin the reticle to the player in world space: it stays over the
## same spot relative to the player while the camera zooms and leans, so neither
## its distance from the player nor the aim direction drifts during the transition.
## (On screen it spreads outward with the zoom, staying on whatever it was over.)
func ads_follow() -> void:
	ads_cur = (player_screen() + ads_off * ground_scale()).clamp(Vector2.ZERO, Vector2(Wv, Hv))
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
			var n := 3 if (F.cruise and flight.cruise_ok()) else 1
			var k := 0
			while k < n and F and uist == "" and mode == "flight":
				flight.upd_flight(dt)
				k += 1
	elif mode == "ground" and S:
		set_ads(uist == "" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		if uist == "": upd_ground(dt)
		if ads_virtual and S: ads_follow()
	else:
		demo.x += cos(demo.h) * 60 * dt
		demo.y += sin(demo.h) * 60 * dt
		demo.h += sin(T * 0.1) * 0.02 * dt
	update_cursor()
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
		"zs": [], "sv": [], "bul": [], "drops": [], "fx": [], "fl": [], "mf": [], "t": 0.0, "spawnT": 5.0, "danger": s.danger, "scrN": 0,
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
	blasts.init_cars()
	var hostile: bool = s.get("hostile", false)
	site.hostile = hostile
	site.svh = []        # garrison members still inside buildings
	site.alarm = false   # set once the garrison is alerted
	var nz := int(round(DF().count * (3 if first else 2 + s.danger * 3 + (3 if site.arch == "town" else 0) + (4 if site.arch == "road" else 0) + 4) + round(dark() * 3)))
	if hostile: nz = 0
	for i in nz: spawn_z(true)
	if not first and not hostile:
		var nd2 := int(round((1 + s.danger * 0.8) * DF().count))
		for i in nd2:
			var n0: int = S.zs.size()
			spawn_z(true)
			if S.zs.size() > n0:
				var z: Dictionary = S.zs[S.zs.size() - 1]
				if z.kind == "scream": S.scrN -= 1
				z.dormant = true; z.kind = ""; z.arm = false; z.da = randf() * TAU; z.hp = 45.0 + s.danger * 8
	site.cap = 0 if hostile else int(round((8 if first else 10 + s.danger * 4) * DF().count))
	# First visit to any site starts silent; return visits start with some noise.
	var first_visit: bool = int(G.visits.get(str(s.id), 0)) <= 1
	site.noise = 0.0 if first_visit else (6 + s.danger * 2) * DF().noise
	for i in 4 + int(randf() * 5):
		for q in 30:
			var c := 1 + int(randf() * (cols - 2))
			var r := 1 + int(randf() * (ry - 2))
			var v := g[r * cols + c]
			if v != 0 and v != 2 and v != 11 and v != 14: continue
			var x := (c + 0.5) * TS
			var y := (r + 0.5) * TS
			blood(x, y, 5)
			stamp_corpse({"x": x, "y": y, "a": randf() * TAU, "shirt": D.ZSHIRT[randi() % D.ZSHIRT.size()], "skin": "#8c9a78" if randf() < 1.0 / 6.0 else D.sv_skin()})
			break
	if hostile:
		survivors.spawn_garrison(site)
	elif not first and randf() < 0.2 + 0.08 * s.danger + (0.25 if site.arch == "military" else 0.0) and site.rooms.size():
		var n := 1 + int(randf() * mini(3, s.danger))
		for i in n:
			var o: Dictionary = site.rooms[randi() % site.rooms.size()]
			var x: float = (o.c + 1.5 + randf() * (o.w - 3)) * TS
			var y: float = (o.r + 1.5 + randf() * (o.h - 3)) * TS
			if Vector2(x - site.p.x, y - site.p.y).length() > 320 and not solid(x, y):
				site.sv.append(survivors.new_sv(x, y))
	return site

func enter_ground(s: Dictionary) -> void:
	_free_site()
	gen_site(s)
	survivors.spawn_npc(s)
	mode = "ground"
	ui.close_ui()
	clear_input()
	F = null
	if s.get("hostile", false):
		toast("Armed survivors hold this strip. No fuel, no trade, no jobs. Keep your head down.", "bad")
	elif dark() > 0.5: toast("It is dark. The dead move faster at night.", "bad")

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
	if S.air:
		# Jumping clears sandbags (10) and inner fences (6), but not the fence
		# ringing the edge of the site, and not cars or the tanker (7).
		if v == 10: return false
		if v == 6 and c > 0 and r > 0 and c < S.cols - 1 and r < S.rows - 1: return false
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

## Keeps a zombie or armed survivor from walking through the player. If its centre ends up closer
## than Z_BODY, it is pushed back out to the edge of the player's body (or back to
## where it started if a wall is in the way). Applies mid-jump too, so the player
## can't hop over enemies. Returns true if the enemy was held back.
func body_block(z: Dictionary, p: Dictionary, zx: float, zy: float, vx: float, vy: float) -> bool:
	var ex: float = z.x - p.x
	var ey: float = z.y - p.y
	var ed := sqrt(ex * ex + ey * ey)
	if ed >= Z_BODY: return false
	if ed < 0.01:
		# dead centre: back out the way it came
		var back := Vector2(-vx, -vy)
		if back.length() < 0.01: back = Vector2(1, 0)
		back = back.normalized()
		ex = back.x; ey = back.y; ed = 1.0
	var tx: float = p.x + ex / ed * Z_BODY
	var ty: float = p.y + ey / ed * Z_BODY
	if not hit_box(tx, ty, 10):
		z.x = tx; z.y = ty
	else:
		z.x = zx; z.y = zy
	return true

func los(x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Vector2(x1 - x0, y1 - y0).length()
	var n := int(ceil(d / 14.0))
	for i in range(1, n):
		var t := float(i) / n
		if solid_b(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t): return false
	return true

## Could a 10px-radius body walk in a straight line from (x0, y0) to (x1, y1)? Unlike
## los() this uses the body's width and what blocks walking, not sight: a line that only
## grazes a wall corner fails, and so does one across a fence you can see over.
func walk_clear(x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Vector2(x1 - x0, y1 - y0).length()
	var n := int(ceil(d / 8.0))
	for i in range(1, n + 1):
		var t := float(i) / n
		if hit_box(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 10): return false
	return true

## Inside the rescue survivor's hiding place (while that mission is running here)?
func in_safe(x: float, y: float) -> bool:
	return S != null and S.get("safe") != null and (S.safe as Rect2).has_point(Vector2(x, y))

## Would a shot fired now reach world point (tx, ty)? Drives the red dot in the
## exploration cursor. Mirrors shoot() and the bullet loop: same muzzle point
## (16px out from the player), same range (spd x life), same walls/cars (solid_b)
## and red barrels. Spread is ignored. Pointing straight at a wall or barrel counts
## as reaching it. Out of ammo it uses the machete's 44px reach instead.
func shot_reaches(tx: float, ty: float) -> bool:
	var p: Dictionary = S.p
	var to := Vector2(tx - p.x, ty - p.y)
	var d := to.length()
	if G.ammo <= 0: return d < 44.0
	var w: Dictionary = D.WEAPONS[G.weapon]
	var travel := d - 16.0   # distance from the muzzle to the cursor
	if travel <= 0.0: return true
	if travel > float(w.spd) * float(w.life): return false
	var dir := to / d
	var o := Vector2(p.x, p.y) + dir * 16.0
	var tc := int(floor(tx / TS))
	var tr := int(floor(ty / TS))
	var n := int(ceil(travel / 4.0))   # about the bullet's own sub-step
	for i in range(1, n + 1):
		var q := o + dir * (travel * float(i) / n)
		if solid_b(q.x, q.y):
			return int(floor(q.x / TS)) == tc and int(floor(q.y / TS)) == tr
		for br in S.barrels:
			if not br.dead and pow(br.x - q.x, 2) + pow(br.y - q.y, 2) < 150:
				return pow(br.x - tx, 2) + pow(br.y - ty, 2) < 150
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

## Blood spray off a person hit at (x, y), flying along dir (away from what hit them).
func blood_spray(x: float, y: float, dir: Vector2) -> void:
	if S == null: return
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(randf() * TAU)
	for n in int(HIT_SPRAY_N) + (1 if randf() < fmod(HIT_SPRAY_N, 1.0) else 0):
		var a := dir.angle() + (randf() - 0.5) * 2.0 * HIT_SPRAY_SPREAD
		var v := randf_range(HIT_SPRAY_MIN, HIT_SPRAY_MAX)
		S.fx.append({"x": x + dir.x * 6, "y": y + dir.y * 6, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.22 + randf() * 0.12,
			"c": "#5a0c08" if randf() < 0.75 else "#6e120c", "sz": HIT_SPRAY_SZ, "drag": false})

## Would amt of damage leave them standing? (armour soaks half of a hit while it lasts)
func survives(hp: float, armor: float, amt: float) -> bool:
	return hp - (amt - minf(armor, amt * 0.5)) > 0

func stamp_corpse(k: Dictionary) -> void:
	S.bg.stamp(["corpse", k])

func stamp_scorch(x: float, y: float) -> void:
	S.bg.stamp(["scorch", x, y])

## Muzzle flash from someone other than the player (survivors, your rescue): a short glow
## at the gun drawn by render.gd, which also lights the dark at night. The player's own
## flash is S.flash.
func muzzle_flash(x: float, y: float, ang: float) -> void:
	if not S.has("mf"): S.mf = []
	S.mf.append({"x": x + cos(ang) * 22, "y": y + sin(ang) * 22, "life": 0.06})

func floater(x: float, y: float, txt: String, c: String = "#efe6cf") -> void:
	S.fl.append({"x": x, "y": y, "txt": txt, "c": c, "life": 1.4})

func ground_scale() -> float:
	var gs := clampf(sqrt(Wv * Hv) / 600.0, 0.72, 1.6)
	return gs * zoom * (1.0 + ADS_ZOOM * ads_ease())

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
		if in_safe(x, y): continue
		var arm: bool = S.arch == "military" and randf() < 0.5
		var run: bool = not arm and randf() < 0.07 * S.danger
		var kind := ""
		if not arm and not run:
			var q := randf()
			if S.danger >= 2 and q < 0.08: kind = "bloat"
			elif initial and S.scrN < S.danger - 1 and q < 0.13: kind = "scream"   # at most danger-1 per visit, none spawned later
			elif q < 0.16: kind = "crawler"
		if kind == "scream": S.scrN += 1
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
		if d < 95: survivors.npc_hurt(18, Vector2(S.npc.x - e.x, S.npc.y - e.y))
	if S == null: return
	var pd := Vector2(S.p.x - e.x, S.p.y - e.y).length()
	if pd < 95:
		hurt(22 * (1 - pd / 95) + 6, "gas")
		if S and uist == "": blood_spray(S.p.x, S.p.y, Vector2(S.p.x - e.x, S.p.y - e.y))

## Damage to a zombie or survivor; armoured survivors soak up half of each hit
## until their armour runs out (same rule as the player's armour).
func dmg_enemy(e: Dictionary, d: float) -> void:
	var ar: float = e.get("armor", 0.0)
	if ar > 0:
		var a := minf(ar, d * 0.5)
		e.armor = ar - a
		d -= a
	e.hp -= d

## A survivor (hostile or your rescue) hurt by a bullet, melee or gas sometimes cries out:
## the same "Aagh!" as when a blast throws them, quieter the further away they are. Called
## after the damage is taken; a hit that kills makes no cry. Blasts play their own cries
## (Blasts.BLAST_CRY_MAX), so blast damage doesn't call this.
const HURT_CRY_CHANCE := 0.6
func hurt_cry(e: Dictionary) -> void:
	if e.hp <= 0 or randf() >= HURT_CRY_CHANCE: return
	var d := Vector2(e.x - S.p.x, e.y - S.p.y).length()
	sfx("cry", 0.14 * (1.0 - 0.6 * minf(1.0, d / 900.0)), e.get("voice", 1.0))

## A survivor killed before they knew you were there (not alerted) lets out a short "Ugh!".
func death_ugh(e: Dictionary) -> void:
	var d := Vector2(e.x - S.p.x, e.y - S.p.y).length()
	sfx("ugh", 0.14 * (1.0 - 0.6 * minf(1.0, d / 900.0)), e.get("voice", 1.0))

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

func shoot() -> void:
	var w: Dictionary = D.WEAPONS[G.weapon]
	var p: Dictionary = S.p
	p.cd = w.rate
	regen_reset()
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
				var was_alert: bool = e.get("alert", false)
				dmg_enemy(e, 67.0 if has("boots") else 42.0)
				if S.sv.has(e): hurt_cry(e)
				if e.hp > 0 and S.sv.has(e): blood_spray(e.x, e.y, Vector2(e.x - p.x, e.y - p.y))
				e.hit = 0.12
				e.alert = true
				move_c(e, cos(p.ang) * 18, sin(p.ang) * 18, 10)
				blood(e.x, e.y, 2)
				hit = true
				if e.hp <= 0 and not e.dead:
					e.dead = true
					G.stats.kills += 1
					blood(e.x, e.y, 6)
					if S.sv.has(e) and not was_alert: death_ugh(e)
		if hit: sfx("hit")
		if S.t - S.noAmmoT > 4:
			S.noAmmoT = S.t
			floater(p.x, p.y - 24, "Out of ammo. Using the machete.", "#e3644c")
		return
	G.ammo -= 1
	sfx(w.snd)
	if S.npc and S.npc.follow and not w.silent:
		S.npc.fire_t = S.t + Survivors.NPC_FIRE_WINDOW   # your rescue joins in
	var spr: float = w.spr * (ADS_AUTO_SPREAD if ads and w.get("auto", false) else 1.0)
	# some weapons hit harder when aimed down sights ("ads_dmg" in D.WEAPONS, e.g. the crossbow).
	# Only counts once the aim has fully settled in (adsK reaches 1), not the moment you press.
	var aimed: bool = ads and S.get("adsK", 0.0) >= 1.0
	var base_dmg: float = float(w.get("ads_dmg", w.dmg)) if aimed else float(w.dmg)
	var scope_k := 1.2 if has("scope") else 1.0
	# "hip_zdmg": damage to the dead when NOT aimed in (crossbow); survivors still take base_dmg
	var zdmg: float = (float(w.hip_zdmg) if w.has("hip_zdmg") and not aimed else base_dmg) * scope_k
	for i in w.pel:
		var a: float = p.ang + (randf() - 0.5) * spr * 2
		S.bul.append({"x": p.x + cos(p.ang) * 16, "y": p.y + sin(p.ang) * 16, "vx": cos(a) * w.spd, "vy": sin(a) * w.spd, "life": w.life, "dmg": base_dmg * scope_k, "zdmg": zdmg, "aim": aimed, "pl": true, "kb": w.kb, "bolt": w.bolt})
	if not w.bolt:   # spent casing — guns only, the crossbow has none
		S.fx.append({"x": p.x + cos(p.ang) * 8, "y": p.y + sin(p.ang) * 8, "vx": cos(p.ang + 1.6) * 110 + (randf() - 0.5) * 40, "vy": sin(p.ang + 1.6) * 110 + (randf() - 0.5) * 40, "life": 0.7, "c": "#d9b35a", "sz": 2.2, "drag": true})
	add_noise(w.noise)
	if not w.silent:
		S.flash = 0.06
		S.shake = minf(8, S.shake + (7.0 if w.pel > 6 else (5.0 if w.pel > 1 else (1.2 if w.rate < 0.15 else 2.0))))
		for z in S.zs:
			if not z.dormant and Vector2(z.x - p.x, z.y - p.y).length() < 520: z.alert = true
		for v in S.sv:
			if Vector2(v.x - p.x, v.y - p.y).length() < 700: survivors.sv_hear(v, p.x, p.y)

## fx = false: just the damage (and death), no splatter, sound or shake (used for blast
## damage spread over a few frames, whose effects play once when it goes off).
func hurt(d: float, cause: String, fx: bool = true) -> void:
	if uist != "": return
	regen_reset()
	if not fx:
		if G.armor > 0:
			var a2 := minf(G.armor, d * 0.5)
			G.armor -= a2
			d -= a2
		G.hp -= d
		if G.hp <= 0:
			G.hp = 0.0
			die(cause)
		return
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
			toast("Picked up %s. Press %d to equip." % [D.WEAPONS[w].name, w + 1], "good")
			return ["Found a %s!" % String(D.WEAPONS[w].name).to_lower(), "#ffd27a"]
	return null

func read_chart() -> Array:
	var s := strip(G.strip)
	var un := wd.strips.filter(func(o): return not known.has(o.id) and o.type != "haven" and o.type != "road")
	un.sort_custom(func(a, b): return Vector2(a.x - s.x, a.y - s.y).length() < Vector2(b.x - s.x, b.y - s.y).length())
	un = un.slice(0, 3)
	for o in un: known[o.id] = true
	var tail := ""
	if not known.has(0):
		if G.rings.is_empty():
			# first chart: the four rumour rings appear at full size
			G.rings = wd.RING0.duplicate()
			tail = ", four places Haven might be"
		else:
			# later charts: one ring that can still shrink, picked at random
			var can: Array = []
			for i in G.rings.size():
				if float(G.rings[i]) > World.RING_MIN + 0.5: can.append(i)
			if can.size():
				var pick: int = can[randi() % can.size()]
				G.rings[pick] = maxf(World.RING_MIN, float(G.rings[pick]) * World.RING_SHRINK)
				tail = ", a Haven rumour narrowed"
	return ["Old chart: %d field%s marked%s" % [un.size(), "" if un.size() == 1 else "s", tail], "#f0c4dd"]

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
	if S.get("hostile", false): rolls += 1   # survivor-held strips are well stocked
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

func select_weapon(index: int) -> void:
	if G == null or index < 0 or index >= D.WEAPONS.size(): return
	if not G.weapons.has(index):
		toast("You don't own %s yet." % D.WEAPONS[index].name)
		return
	var changed: bool = G.weapon != index
	G.weapon = index
	toast("Equipped: %s [%d]" % [D.WEAPONS[index].name, index + 1], "good")
	if changed:
		sfx("click")
		if S != null:
			floater(S.p.x, S.p.y - 26, D.WEAPONS[index].name, "#efe6cf")
			S.p.cd = maxf(S.p.cd, 0.25)

func swap_weapon() -> void:
	if mode != "ground" or S == null or uist != "" or G.weapons.size() < 2: return
	var own: Array = G.weapons.duplicate()
	own.sort()
	select_weapon(own[(own.find(G.weapon) + 1) % own.size()])

func jump() -> void:
	if mode != "ground" or S == null or uist != "": return
	var p: Dictionary = S.p
	if ads: return   # no jumping while aiming down sights
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
	blasts.blast_dmg_tick(p, dt)
	if S == null or uist == "dead": return
	S.flowT -= dt
	if S.flowT <= 0:
		S.flowT = 0.3
		build_flow()
	var ml := upd_player(p, dt)
	if upd_bullets(p, dt): return
	for z in S.zs:
		if z.dead: killed(z, true)
	if S == null: return
	for v in S.sv:
		if v.dead: killed(v, false)
	if S == null or uist == "dead": return
	S.zs = S.zs.filter(func(z): return not z.dead)
	S.sv = S.sv.filter(func(v): return not v.dead)
	if upd_zombies(p, nk, dt): return
	survivors.upd_survivors(p, dt)
	upd_drops(p)
	upd_spawns(dt)
	for br in S.barrels:
		if br.fuse >= 0 and not br.dead:
			br.fuse -= dt
			if br.fuse <= 0: blasts.explode(br)
			if S == null or uist == "dead": return
	blasts.update_cars(dt)
	if S == null or uist == "dead": return
	if randf() < dt * 0.4:
		var nd := 1e9
		for z in S.zs:
			if z.alert:
				var d2 := Vector2(z.x - p.x, z.y - p.y).length()
				if d2 < nd: nd = d2
		if nd < 450: sfx("groan", 0.09 * (1 - nd / 450))
	if upd_effects(dt): return
	survivors.upd_npc(dt)
	if S == null: return
	upd_pickups(dt)
	upd_crows(p, dt)
	upd_tanker(p, ml, dt)
	S.nearPlane = Vector2(p.x - S.plane.x, p.y - S.plane.y).length() < 130
	upd_camera(p, dt)
	upd_mood(dt)

## Slow regen up to REGEN_CAP while you keep still. Wandering more than a tile from where
## you stopped, or sprinting, restarts the wait (shoot() and hurt() restart it too).
func upd_regen(p: Dictionary, sprint: bool, dt: float) -> void:
	if sprint or Vector2(p.x, p.y).distance_to(p.get("rgA", Vector2(p.x, p.y))) > TS:
		regen_reset()
	if not p.has("rgA"): p.rgA = Vector2(p.x, p.y)
	p.rgT = p.get("rgT", 0.0) + dt
	if p.rgT >= REGEN_DELAY and G.hp > 0 and G.hp < REGEN_CAP:
		G.hp = minf(REGEN_CAP, G.hp + REGEN_RATE * dt)

func regen_reset() -> void:
	if not S or not S.has("p"): return
	S.p.rgT = 0.0
	S.p.rgA = Vector2(S.p.x, S.p.y)

## You on foot: walking and sprinting (stamina), being thrown by blasts, jumping,
## aiming and firing. Returns how hard you're pushing to move (0 = standing still).
func upd_player(p: Dictionary, dt: float) -> float:
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
	var pown := blasts.knock_tick(p, dt)   # thrown by a blast? (you can't run against it)
	S.air = p.jt > 0
	move_c(p, mx * ps * dt * pown, my * ps * dt * pown, 10)
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
	upd_regen(p, sprint, dt)
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
	return ml

## Bullets in flight: walls, cars, red barrels, zombies, survivors and you.
## Returns true when the site is gone or you died (stop the frame there).
func upd_bullets(p: Dictionary, dt: float) -> bool:
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
				var car = blasts.car_at(b.x, b.y)
				if car and not b.bolt: blasts.car_hit(car, b.dmg)   # crossbow bolts just stick in
				dead = true
				break
			var hb := false
			for br in S.barrels:
				if not br.dead and pow(br.x - b.x, 2) + pow(br.y - b.y, 2) < 150:
					if not b.bolt:   # crossbow bolts stop in the barrel without setting it off
						br.hp -= b.dmg
						if br.hp <= 0: blasts.explode(br)
					hb = true
					break
			if hb:
				dead = true
				break
			if S == null: return true
			if b.pl:
				for z in S.zs:
					if not z.dead and pow(z.x - b.x, 2) + pow(z.y - b.y, 2) < 144:
						z.hp -= float(b.get("zdmg", b.dmg))   # the crossbow hip-fires weaker at the dead
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
							var was_alert: bool = v.alert
							# an aimed (ADS) crossbow bolt into a survivor who hasn't spotted you yet hits harder
							dmg_enemy(v, b.dmg * (BOLT_SNEAK_MULT if b.bolt and b.get("aim", false) and not v.alert else 1.0))
							hurt_cry(v)
							v.hit = 0.1
							survivors.sv_hear(v, p.x, p.y)
							blood(v.x, v.y, 1)
							if v.hp > 0: blood_spray(v.x, v.y, Vector2(b.vx, b.vy))
							if v.hp <= 0:
								v.dead = true
								G.stats.kills += 1
								blood(v.x, v.y, 6)
								if not was_alert: death_ugh(v)
								var am := randf() < 0.6
								S.drops.append({"x": v.x, "y": v.y, "k": "ammo" if randf() < 0.6 else "cash", "n": (10 + randi() % 10) if am else (30 + randi() % 60)})
								if randf() < Survivors.SV_GUN_DROP and not v.get("unarmed", false):
									S.drops.append({"x": v.x + 14, "y": v.y + 6, "k": "gun", "w": int(v.get("w", 0)), "n": 0})
							dead = true
							break
			elif pow(p.x - b.x, 2) + pow(p.y - b.y, 2) < 110:
				hurt(b.dmg, "shot")
				if S and uist == "": blood_spray(p.x, p.y, Vector2(b.vx, b.vy))
				dead = true
		if S == null or uist == "dead": return true
		b.life -= dt
		if dead or b.life <= 0: S.bul.remove_at(i)
		i -= 1
	return false

## Zombies: waking, chasing (flow field), lunging, screamers, biting you and the
## rescue survivor. nk is the night speed-up. Returns true when the frame should stop.
func upd_zombies(p: Dictionary, nk: float, dt: float) -> bool:
	S.nd = 1e9
	var zs: Array = S.zs
	for z in zs:
		var dx: float = p.x - z.x
		var dy: float = p.y - z.y
		var d := Vector2(dx, dy).length()
		if d == 0: d = 1
		blasts.blast_dmg_tick(z, dt)
		if z.dead: continue
		var own := blasts.knock_tick(z, dt)   # thrown by a blast?
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
		if d < 250 and not z.alert and los(z.x, z.y, p.x, p.y): z.alert = true   # sight only; sound alerts are separate
		var vx: float
		var vy: float
		var sp: float
		if z.alert:
			vx = dx / d; vy = dy / d; sp = z.spd
			# straight at you only if the body fits along the line too (walk_clear()); the thin
			# sight line that grazes a corner made them flick between this and the flow field
			if d > 150 and not (d < 420 and los(z.x, z.y, p.x, p.y) and walk_clear(z.x, z.y, p.x, p.y)):
				var fd = flow_dir(z.x, z.y)
				if fd:
					vx = fd.x; vy = fd.y
			if S.npc and not in_safe(S.npc.x, S.npc.y):   # don't mob the hiding place
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
		if z.get("scr", 0.0) > 0: sp = 0   # screamer winding up: stands still
		sp *= nk * own
		var zx: float = z.x
		var zy: float = z.y
		move_c(z, vx * sp * dt, vy * sp * dt, 10)
		if in_safe(z.x, z.y) and not in_safe(zx, zy):
			z.x = zx; z.y = zy   # can't walk into the rescue survivor's hiding place
		var blocked := body_block(z, p, zx, zy, vx, vy)
		var moved := Vector2(z.x - zx, z.y - zy).length()
		z.wk += moved * 0.22
		if z.alert and moved < sp * dt * 0.3 and not blocked:
			z.st += dt
			if z.st > 0.25:
				z.det = 0.7
				z.ds = 1.0 if randf() < 0.5 else -1.0
				z.st = 0.0
		else:
			z.st = 0.0
		if z.get("scr", 0.0) <= 0: z.ang = atan2(vy, vx)   # (a winding-up screamer keeps staring at you)
		z.cd -= dt
		z.hit -= dt
		var sees: bool = z.kind == "scream" and not z.screamed and d < SCREAM_RANGE \
			and absf(U.ang_diff(atan2(dy, dx), z.ang)) < deg_to_rad(SCREAM_CONE) and los(z.x, z.y, p.x, p.y)
		if not sees: z["scr"] = 0.0
		else:
			if z.get("scr", 0.0) <= 0: sfx("snarl", 0.2)   # the tell: it's about to scream
			z["scr"] = z.get("scr", 0.0) + dt
			z.ang = atan2(dy, dx)
		if sees and z.scr >= SCREAM_WINDUP:
			z["scr"] = 0.0
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
			if nd < 250 and not z.alert and los(z.x, z.y, S.npc.x, S.npc.y): z.alert = true
			if nd < 22 and z.cd <= 0 and not in_safe(S.npc.x, S.npc.y):
				z.cd = 0.85
				survivors.npc_hurt(z.dmg, Vector2(S.npc.x - z.x, S.npc.y - z.y))
				if S == null: return true
		if d < 24 and z.cd <= 0 and not (p.jt > 0):
			z.cd = 0.85
			hurt(z.dmg, "bitten")
			if uist != "": return true
			blood_spray(p.x, p.y, Vector2(p.x - z.x, p.y - z.y))
	return false

## Walking over crates opens them; walking over drops (ammo, guns, cash) picks them up.
func upd_drops(p: Dictionary) -> void:
	for c in S.crates:
		if not c.open and Vector2(c.x - p.x, c.y - p.y).length() < 24: loot_crate(c)
	var i: int = S.drops.size() - 1
	while i >= 0:
		var d: Dictionary = S.drops[i]
		if Vector2(d.x - p.x, d.y - p.y).length() < 22:
			if d.k == "ammo":
				d.n = int(round(d.n * (1.3 if has("bandolier") else 1.0)))
				G.ammo += d.n
				floater(d.x, d.y - 16, "+%d rounds" % d.n)
			elif d.k == "gun":
				var wi: int = int(d.w)
				var wn: String = D.WEAPONS[wi].name
				if not G.weapons.has(wi):
					G.weapons.append(wi)
					floater(d.x, d.y - 16, wn + "!", "#ffd27a")
					toast("Picked up %s. Press %d to equip." % [wn, wi + 1], "good")
					sfx("jackpot")
				else:
					# already have one: strip it for its rounds
					var n := int(round(12 * (1.3 if has("bandolier") else 1.0)))
					G.ammo += n
					floater(d.x, d.y - 16, "+%d rounds (spare %s)" % [n, String(wn).to_lower()])
			else:
				G.cash += d.n
				floater(d.x, d.y - 16, "+$%d" % d.n, "#9cc063")
			S.drops.remove_at(i)
		i -= 1

## Noise waves (the dead, or armed reinforcements at survivor-held strips) and the
## steady trickle of new arrivals.
func upd_spawns(dt: float) -> void:
	# (no background noise: the meter only rises from what the player does)
	var held: bool = S.get("hostile", false)
	# At survivor-held strips the noise waves are armed reinforcements, not the dead.
	var waves := [[35, 0, "Doors bang open. Everyone inside is coming out to look for you."], [65, 3, "Engines on the road. They are bringing friends."], [100, 4, "Everyone they have is coming. Get to the plane."]] if held \
		else [[35, 5, "They know you are here."], [65, 9, "A crowd is gathering at the fence line."], [100, 14, "The horde is here. Get to the plane."]]
	for wv in waves:
		if S.noise >= wv[0] and not S.waves.has(wv[0]):
			S.waves.append(wv[0])
			toast(wv[2], "bad")
			sfx("horde")
			S.shake = maxf(S.shake, 5)
			if held and wv[1] == 0:   # first mark at a held strip: everyone indoors comes out looking for you
				survivors.call_out(S.p.x, S.p.y)
				continue
			for k in maxi(1, int(round(wv[1] * DF().count))):
				if held: S.svq = S.get("svq", 0) + 1   # they arrive one by one (Survivors.upd_garrison())
				else: spawn_edge(wv[0] >= 100 and G.diff != 0)
	S.spawnT -= dt
	if held and S.spawnT <= 0:
		# no dead here; once the meter is full, a reinforcement every 10-16 s
		S.spawnT = 10.0 + randf() * 6.0
		if S.noise >= 100 and S.sv.size() < 20: survivors.spawn_edge_sv()
	elif S.spawnT <= 0:
		var nf: float = S.noise / 100.0
		S.spawnT = maxf(0.7, (8 - S.danger * 1.1) * (1 - nf * 0.8)) * (0.7 + randf() * 0.6)
		var capn := mini(60, S.cap + int(floor(S.noise / 8.0)))
		if S.zs.size() < capn:
			if nf >= 1:
				spawn_edge(true)
				spawn_edge(randf() < 0.5)
			else:
				spawn_z(false)

## Particles, thrown bombs (bouncing, fuse), smoke and floating text.
## Returns true when a bomb going off ended the frame (site gone or you died).
func upd_effects(dt: float) -> bool:
	S.boomFlash -= dt
	var i: int = S.fx.size() - 1
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
		b.spin += dt * 12
		if b.get("air", 0.0) > 0:
			# lobbed by a survivor: arcing through the air over walls and cover (height z)
			b.air -= dt
			b.x += b.vx * dt; b.y += b.vy * dt
			var k: float = 1.0 - maxf(0.0, b.air) / b.air0
			b.z = 4.0 * b.h * k * (1.0 - k)
			if b.air <= 0:   # landed: rolls on a little
				b.z = 0.0
				b.vx *= 0.15; b.vy *= 0.15
		else:
			var f := pow(0.18, dt)
			b.vx *= f; b.vy *= f
			var nx: float = b.x + b.vx * dt
			if solid(nx, b.y): b.vx *= -0.5
			else: b.x = nx
			var ny: float = b.y + b.vy * dt
			if solid(b.x, ny): b.vy *= -0.5
			else: b.y = ny
		b.fuse -= dt
		if b.fuse <= 0:
			blasts.explode(b)
			if S == null or uist == "dead": return true
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
	return false

## The stash glint and the crows that scatter when you come near or fire.
func upd_crows(p: Dictionary, dt: float) -> void:
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

## Siphoning fuel from a tanker: stand still next to it (ml is your movement input).
func upd_tanker(p: Dictionary, ml: float, dt: float) -> void:
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

## Camera: aim-down-sights ease, smoothed follow and lean, kept inside the map and the player in view.
func upd_camera(p: Dictionary, dt: float) -> void:
	S.adsK = move_toward(S.get("adsK", 0.0), 1.0 if ads else 0.0, dt * ADS_RATE)
	# Camera = smoothed follow of the player (bcx/bcy) + ADS lean. The lean's size
	# uses the same eased amount as the zoom (not the follow smoothing), so zoom
	# and lean start, run and finish together, in and out. Only the lean's
	# direction is smoothed, so sweeping your aim doesn't jerk the camera.
	var ae := ads_ease()
	if ae <= 0.0: S.leanA = p.ang
	else: S.leanA = lerp_angle(S.get("leanA", p.ang), p.ang, minf(1, dt * 10))
	var lead := ADS_LEAD * ae
	var gs := ground_scale()
	var hw := Wv / 2 / gs
	var hh := Hv / 2 / gs
	var mw: float = S.cols * TS
	var mh: float = S.rows * TS
	var bx := lerpf(S.get("bcx", S.cx), p.x, minf(1, dt * 6))
	var by := lerpf(S.get("bcy", S.cy), p.y, minf(1, dt * 6))
	S.bcx = clampf(bx, hw, mw - hw) if mw > 2 * hw else mw / 2
	S.bcy = clampf(by, hh - 110 / gs, mh - hh) if mh > 2 * hh else mh / 2
	S.cx = S.bcx + cos(S.leanA) * lead
	S.cy = S.bcy + sin(S.leanA) * lead
	S.cx = clampf(S.cx, hw, mw - hw) if mw > 2 * hw else mw / 2
	S.cy = clampf(S.cy, hh - 110 / gs, mh - hh) if mh > 2 * hh else mh / 2
	# Never let the player leave the view (matters near the map edge, where the
	# map clamp plus the ADS zoom/lean could push them off screen). Margins are in
	# screen pixels; the top one clears the status panel. Applied last, so keeping
	# the player visible wins over keeping the camera inside the map.
	var edge := CAM_EDGE / gs
	S.cx = clampf(S.cx, p.x - hw + edge, p.x + hw - edge)
	S.cy = clampf(S.cy, p.y - hh + CAM_EDGE / gs, p.y + hh - CAM_TOP / gs)

## Screen shake, flashes, blood splats, lamp flicker, the heartbeat and the low-health colour grade.
func upd_mood(dt: float) -> void:
	S.shake = maxf(0, S.shake - dt * 20)
	S.flash -= dt
	S.hurt -= dt
	var mf: Array = S.get("mf", [])
	for k in range(mf.size() - 1, -1, -1):
		mf[k].life -= dt
		if mf[k].life <= 0: mf.remove_at(k)
	var i: int = S.splat.size() - 1
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
	synth.undeafen()
	if mode == "flight" and F:
		F.crashed = true
		sfx("thump" if kind == "overrun" else "crash")
	clear_input()
	ui.show_dead(kind)

func win() -> void:
	menu.clear_save()
	CP = ""
	ui.show_win()
	mode = "title"
	F = null
	_free_site()

# ======================================================================
# draw layers (one Node2D per layer, all drawn by draw_layer())
# ======================================================================
class DrawLayer extends Node2D:
	var idx := 0
	var game
	func _draw() -> void:
		game.draw_layer(idx, Pen.new(self))
