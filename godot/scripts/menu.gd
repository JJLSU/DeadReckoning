class_name Menu
## Everything around the game rather than in it: menu actions (trade, repairs, jobs,
## upgrades), contracts, saving and loading, the title screen and starting or resuming
## a run, display settings, and the testing buttons. Split out of game.gd.

const SAVE_PATH := "user://deadreckoning_v1.json"

# display settings — camera zoom, interface size, window
const SETTINGS_PATH := "user://settings.cfg"
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15
const UI_MIN := 0.6
const UI_MAX := 2.5
const UI_STEP := 0.1
const WIN_SIZES := [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]

var gm: Game   # the game: run state, site, shared helpers

func _init(game: Game) -> void:
	gm = game

# ======================================================================
# saving and loading
# ======================================================================
func save_game() -> bool:
	if gm.G == null: return true
	gm.G.known = gm.known.keys()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(gm.G))
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	return ok

func quit_to_desktop(save_progress: bool) -> void:
	if save_progress and not save_game():
		gm.toast("Could not save your game. Please try again.", "bad")
		return
	gm.get_tree().quit()

func load_save():
	if not FileAccess.file_exists(SAVE_PATH): return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary): return null
	if not save_fits(d): return null
	return d

## Saves record the land size they were made with (older saves have none = 30,000).
## A save from a different land size describes a different map, so it can't be resumed.
func save_fits(d: Dictionary) -> bool:
	return absf(float(d.get("world", 30000.0)) - gm.WORLD) < 1.0

## True when there's a save file that can't be used with the current land size.
func old_save_exists() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return false
	var d = JSON.parse_string(f.get_as_text())
	return d is Dictionary and not save_fits(d)

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func checkpoint() -> void:
	gm.G.known = gm.known.keys()
	gm.CP = JSON.stringify(gm.G)
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
	# older saves may have more tank upgrades than the plane now allows
	if st.has("plane") and st.has("tanks"):
		var pi := clampi(int(st.plane), 0, D.PLANES.size() - 1)
		st.tanks = mini(int(st.tanks), int(D.PLANES[pi].tankMax))
		if st.has("fuel"):
			var fcap: float = D.PLANES[pi].fuel + st.tanks * D.PLANES[pi].tankStep
			st.fuel = minf(float(st.fuel), fcap)
	return st

# ======================================================================
# contracts
# ======================================================================
func gen_offers(s: Dictionary) -> Array:
	if s.get("hostile", false): return []
	var R := gm.range_full()
	var n := 2 if s.type == "dirt" else (3 if s.type == "regional" else 4)
	var c: Array = []
	if s.type != "road":
		c = gm.wd.strips.filter(func(o):
			if o.id == s.id or o.type == "haven" or o.type == "road" or o.get("hostile", false): return false
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
			"reward": int(round((120 + d * 2 / 100 * 6) * (1 + 0.15 * o.danger) * (1.25 if gm.has("radio") else 1.0) / 5.0)) * 5})
	return out

func contract_target(c: Dictionary) -> int:
	return int(c.pickup) if (c.get("type", "") == "rescue" and c.get("stage", "") == "pickup") else int(c.dest)

func objective() -> String:
	if gm.S and gm.S.npc == null:
		if gm.G.contracts.size(): return "Board the plane and fly to %s." % gm.strip(contract_target(gm.G.contracts[0])).name
		return "No job yet. Board the plane to see the job board."
	if gm.S and gm.S.npc:
		return ("Lead %s back to the plane." % gm.S.npc.name) if gm.S.npc.follow else ("Find %s in %s." % [gm.S.npc.name, D.WHERE[gm.S.npc.where]])
	for k in gm.G.contracts:
		if k.get("type", "") == "rescue":
			return ("Rescue %s at %s." % [k.who, gm.strip(int(k.pickup)).name]) if k.stage == "pickup" else ("Fly %s to %s." % [k.who, gm.strip(int(k.dest)).name])
	if gm.G.contracts.size():
		var c: Dictionary = gm.G.contracts[0]
		return "Deliver %s to %s." % [c.what, gm.strip(int(c.dest)).name]
	if gm.G.plane == 0:
		return "You can afford a Heron. Find an airport with a dealer." if gm.G.cash >= D.PLANES[1].price else "Take jobs and sell goods. A Heron costs $%d." % D.PLANES[1].price
	if not gm.known.has(0):
		if gm.G.rings.is_empty(): return "Find Haven. Old charts may tell you where to look."
		return "Haven is in one of the four rings on your chart. Old charts narrow them down."
	return "Fly to Haven."

func bearing(a: Dictionary, b: Dictionary) -> String:
	var deg := fmod(rad_to_deg(atan2(b.y - a.y, b.x - a.x)) + 90 + 360, 360)
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(deg / 45.0)) % 8]

# ======================================================================
# testing helpers (HUD buttons, see UI.DEBUG_BUTTONS)
# ======================================================================
func dbg_all_weapons() -> void:
	if gm.G == null: return
	for i in D.WEAPONS.size():
		if not gm.G.weapons.has(i): gm.G.weapons.append(i)
	gm.sfx("click")
	gm.toast("Testing: all weapons added. Press 1-%d to equip." % D.WEAPONS.size(), "good")

func dbg_ammo() -> void:
	if gm.G == null: return
	gm.G.ammo += 1000
	gm.sfx("click")
	gm.toast("Testing: +1,000 rounds (%d total)." % gm.G.ammo, "good")

func dbg_all_trinkets() -> void:
	if gm.G == null: return
	for t in D.TRINKETS:
		if not gm.G.trinkets.has(t[0]): gm.G.trinkets.append(t[0])
	gm.sfx("click")
	gm.toast("Testing: all %d trinkets added." % D.TRINKETS.size(), "good")

func dbg_best_plane() -> void:
	if gm.G == null: return
	gm.G.plane = D.PLANES.size() - 1
	gm.G.tanks = int(D.PLANES[gm.G.plane].tankMax)
	gm.G.engine = gm.MAX_ENGINE
	gm.G.fuel = gm.PS().fuelCap
	gm.G.hull = 100.0
	gm.sfx("click")
	gm.toast("Testing: %s with full tanks and engine upgrades." % D.PLANES[gm.G.plane].name, "good")

func dbg_reveal_map() -> void:
	if gm.G == null: return
	var n := 0
	for s in gm.wd.strips:
		if s.type == "haven": continue   # Haven stays hidden so the rumour rings can be tested
		if not gm.known.has(s.id):
			gm.known[s.id] = true
			n += 1
	gm.G.known = gm.known.keys()
	gm.sfx("click")
	gm.toast("Testing: map revealed, %d new fields charted. Haven is still hidden." % n, "good")

func dbg_cash() -> void:
	if gm.G == null: return
	gm.G.cash += 1000
	gm.sfx("click")
	gm.toast("Testing: +$1,000 ($%d total)." % gm.G.cash, "good")

func dbg_fuel() -> void:
	if gm.G == null: return
	gm.G.carried += 1000.0
	gm.sfx("click")
	gm.toast("Testing: +1,000 gal in cans (%d total)." % int(floor(gm.G.carried)), "good")

# ======================================================================
# menu actions
# ======================================================================
func good_price(s: Dictionary, g: String) -> int:
	return int(round(D.GOODS[g][1] * (0.6 + U.hash3(s.id, D.GKEYS.find(g), gm.wd.SEED + 71)) * (1.2 if gm.has("ledger") else 1.0)))

func repair_cost() -> int:
	return int(ceil(100 - gm.G.hull)) * 4 + (60 if gm.G.leak > 0 else 0)

func act(a: String, v = null) -> void:
	var s = gm.strip(gm.G.strip) if gm.G else null
	var P = gm.PS() if gm.G else null
	match a:
		"tab":
			gm.menu_tab = v
			gm.ui.render_menu()
		"close", "resume": gm.ui.close_ui()
		"band":
			if gm.G.cash >= 25:
				gm.G.cash -= 25; gm.G.band += 1
			gm.ui.render_menu()
		"bomb":
			if gm.G.cash >= 60:
				gm.G.cash -= 60; gm.G.bombs += 1
			gm.ui.render_menu()
		"sell":
			var n := int(gm.G.goods.get(v, 0))
			var pr := good_price(s, v)
			if n:
				gm.G.cash += n * pr
				gm.G.goods[v] = 0
				gm.toast("Sold %d %s for $%d." % [n, D.GOODS[v][0], n * pr], "good")
				gm.sfx("cash")
			gm.ui.render_menu()
		"sellparts":
			if gm.G.parts > 0:
				gm.G.parts -= 1; gm.G.cash += 15
			gm.ui.render_menu()
		"fieldfix":
			if gm.G.parts > 0 and gm.G.hull < 100:
				gm.G.parts -= 1
				gm.G.hull = minf(100, gm.G.hull + (25 if gm.has("gloves") else 15))
				gm.toast("Patched a section of the airframe.", "good")
			gm.ui.render_menu()
		"fieldleak":
			if gm.G.parts >= 2 and gm.G.leak > 0:
				gm.G.parts -= 2; gm.G.leak = 0.0
				gm.toast("Fuel line sealed.", "good")
			gm.ui.render_menu()
		"repair":
			var c := repair_cost()
			if c > 0 and gm.G.cash >= c:
				gm.G.cash -= c; gm.G.hull = 100.0; gm.G.leak = 0.0
				gm.toast("The mechanic patches her up.", "good")
			gm.ui.render_menu()
		"sleep":
			var m := fmod(gm.G.time, 1440.0)
			gm.G.time += fmod(390 - m + 1440, 1440.0)
			gm.G.hp = minf(100, gm.G.hp + 40)
			gm.G.offers = gen_offers(s)
			gm.enter_ground(s)
			checkpoint()
			gm.toast("Day %d. You wake at first light." % gm.day(), "good")
		"sound":
			gm.synth.set_on(not gm.synth.on)
			gm.ui.close_ui()
			gm.ui.open_pause()
		"zoom":
			set_zoom(1.0 if v == 0 else gm.zoom * (ZOOM_STEP if v > 0 else 1.0 / ZOOM_STEP), false)
			gm.ui.refresh_settings()
		"uiscale":
			set_ui_scale(1.0 if v == 0 else gm.ui_scale + UI_STEP * signf(v), false)
			gm.ui.refresh_settings()
		"fullscreen":
			set_fullscreen(not gm.fullscreen)
			gm.ui.refresh_settings()
		"winsize":
			set_window_size((gm.win_idx + 1) % WIN_SIZES.size())
			gm.ui.refresh_settings()
		"settings":
			gm.ui.show_settings(v)
		"diff":
			gm.G.diff = int(v)
			save_game()
			gm.ui.close_ui()
			gm.ui.open_pause()
			gm.toast("Difficulty: %s. It takes full effect at the next airfield." % D.DIFFS[gm.G.diff].name, "mag")
		"takeoff": gm.flight.takeoff()
		"pour":
			var n := minf(gm.G.carried, P.fuelCap - gm.G.fuel)
			gm.G.fuel += n
			gm.G.carried -= n
			gm.toast("Poured %.1f gal." % n)
			gm.ui.render_menu()
		"buy5":
			var n := minf(5, P.fuelCap - gm.G.fuel)
			var c := int(ceil(n * s.fuelPrice))
			if gm.G.cash >= c:
				gm.G.cash -= c; gm.G.fuel += n
			gm.ui.render_menu()
		"fill":
			var n: float = P.fuelCap - gm.G.fuel
			n = minf(n, floor(gm.G.cash / float(s.fuelPrice)))
			gm.G.cash -= int(ceil(n * s.fuelPrice))
			gm.G.fuel += n
			gm.ui.render_menu()
		"accept":
			var idx := int(v)
			if idx < gm.G.offers.size():
				var c: Dictionary = gm.G.offers[idx]
				gm.G.offers.remove_at(idx)
				gm.G.contracts.append(c)
				var tg := contract_target(c)
				gm.known[tg] = true
				gm.known[int(c.dest)] = true
				if gm.G.nav < 0: gm.G.nav = tg
				gm.toast(("Rescue job taken. Course set to %s." % gm.strip(tg).name) if c.get("type", "") == "rescue" else ("Loaded %s. Course set to %s." % [c.what, gm.strip(tg).name]), "mag")
			gm.ui.render_menu()
		"dump":
			gm.G.contracts.remove_at(int(v))
			gm.ui.render_menu()
		"nav":
			gm.G.nav = int(v)
			gm.ui.render_menu()
		"tank":
			var c: int = 450 * (gm.G.tanks + 1) + gm.G.plane * 200
			if gm.G.cash >= c and gm.G.tanks < P.tankMax:
				gm.G.cash -= c; gm.G.tanks += 1
				gm.toast("Auxiliary tank fitted.", "good")
			gm.ui.render_menu()
		"engine":
			var c: int = 600 * (gm.G.engine + 1)
			if gm.G.cash >= c and gm.G.engine < 2:
				gm.G.cash -= c; gm.G.engine += 1
				gm.toast("Engine overhauled.", "good")
			gm.ui.render_menu()
		"weapon":
			var i := int(v)
			var w: Dictionary = D.WEAPONS[i]
			if gm.G.weapons.has(i): gm.select_weapon(i)
			elif gm.G.cash >= w.price:
				gm.G.cash -= w.price
				gm.G.weapons.append(i)
				gm.toast("Bought %s. Press %d to equip." % [w.name, i + 1], "good")
			gm.ui.render_menu()
		"ammo":
			if gm.G.cash >= 35:
				gm.G.cash -= 35; gm.G.ammo += 30
			gm.ui.render_menu()
		"ammo100":
			if gm.G.cash >= 100:
				gm.G.cash -= 100; gm.G.ammo += 100
			gm.ui.render_menu()
		"med":
			if gm.G.cash >= 60:
				gm.G.cash -= 60; gm.G.med += 1
			gm.ui.render_menu()
		"plane":
			var i := int(v)
			var cost: int = D.PLANES[i].price - int(floor(D.PLANES[gm.G.plane].price * 0.5))
			if gm.G.cash >= cost:
				gm.G.cash -= cost
				gm.G.plane = i
				gm.G.tanks = 0
				gm.G.engine = 0
				gm.G.fuel = minf(gm.G.fuel, gm.PS().fuelCap)
				gm.G.contracts = gm.G.contracts.slice(0, gm.PS().slots)
				gm.toast("The %s is yours." % D.PLANES[i].name, "good")
			gm.ui.render_menu()
		"newgame": start_new()
		"continue":
			var sv = load_save()
			if sv: resume_from(sv)
		"retry":
			var st = JSON.parse_string(gm.CP)
			st = normalize(st)
			st.cash = int(floor(st.cash * (0.8 if st.diff == 2 else 0.9)))
			st.hp = 100.0
			resume_from(st)
			gm.toast("You wake up in the hangar with a headache and a lighter wallet.", "bad")
		"save_quit_desktop": quit_to_desktop(true)
		"quit_desktop": quit_to_desktop(false)
		"quit":
			save_game()
			show_title()
		"help": gm.ui.show_help()
		"backtitle": show_title()
		"settingsback":
			if gm.mode == "flight" or gm.mode == "ground":
				gm.ui.close_ui()
				gm.ui.open_pause()
			else:
				show_title()

# ======================================================================
# title & lifecycle
# ======================================================================
func show_title() -> void:
	gm.mode = "title"
	gm.F = null
	gm._free_site()
	gm.sat = 0.84; gm.con = 1.07
	gm.ui.show_title(load_save() != null)
	if old_save_exists() and not gm.old_save_warned:
		gm.old_save_warned = true
		gm.toast_later(0.6, "Your saved run is from the old, smaller map and can't be continued. Start a new run to play on the new map.", "bad")

func _regen_world(seed_v: int) -> void:
	gm.wd.PAD = gm.OCEAN_PAD
	gm.wd.gen_world(seed_v)
	gm.baker.set_world(gm.wd)
	gm.TCACHE.clear()
	gm.baker.build_overview(gm.OCEAN_PAD)

func start_new() -> void:
	var seed_v := randi() % 1000000000
	_regen_world(seed_v)
	gm.G = gm.new_state(seed_v)
	gm.known = {gm.wd.START: true}
	var st := gm.strip(gm.wd.START)
	var others := gm.wd.strips.filter(func(s): return s.type != "haven" and s.id != gm.wd.START)
	others.sort_custom(func(a, b): return Vector2(a.x - st.x, a.y - st.y).length() < Vector2(b.x - st.x, b.y - st.y).length())
	for s in others.slice(0, 2): gm.known[s.id] = true
	gm.G.visits[str(gm.wd.START)] = 1
	gm.G.offers = gen_offers(st)
	gm.enter_ground(st)
	checkpoint()
	gm.toast("%s. Home, for now." % st.name)
	gm.toast_later(1.6, "Loot the hangars, then board the plane.", "mag")

func resume_from(st: Dictionary) -> void:
	st = normalize(st)
	if gm.baker.overview == null or int(st.seed) != gm.wd.SEED: _regen_world(int(st.seed))
	gm.G = st
	for kv in [["time", 420.0], ["hull", 100.0], ["leak", 0.0], ["roadStrips", []], ["trinkets", []], ["diff", 1], ["band", 0], ["parts", 0], ["bombs", 0], ["armor", 0.0], ["rings", []], ["goods", {}], ["looted", {}], ["visits", {}], ["mayday", null], ["offers", []]]:
		if not gm.G.has(kv[0]) or (gm.G[kv[0]] == null and kv[1] != null): gm.G[kv[0]] = kv[1]
	gm.wd.strips = gm.wd.strips.filter(func(s): return s.type != "road")
	for r in gm.G.roadStrips:
		var rr: Dictionary = r.duplicate()
		rr.id = gm.wd.strips.size()
		for k in ["x", "y", "ang", "len", "wid"]: rr[k] = float(rr[k])
		rr.danger = int(rr.danger)
		rr.seed = int(rr.seed)
		gm.wd.strips.append(rr)
	if gm.G.strip >= gm.wd.strips.size(): gm.G.strip = gm.wd.START
	if gm.G.nav >= gm.wd.strips.size(): gm.G.nav = -1
	gm.G.contracts = gm.G.contracts.filter(func(c): return int(c.dest) < gm.wd.strips.size())
	gm.known = {}
	for k in gm.G.get("known", []): gm.known[int(k)] = true
	gm.known[gm.G.strip] = true
	gm.enter_ground(gm.strip(gm.G.strip))
	checkpoint()

# ======================================================================
# display settings: zoom, interface size, window size, fullscreen
# ======================================================================
## Hotkeys that work anywhere. Returns true when the event was consumed.
func display_input(e: InputEvent) -> bool:
	if e is InputEventKey and e.pressed:
		var c: int = e.physical_keycode
		var ctrl: bool = e.ctrl_pressed or e.meta_pressed
		var zin: bool = c == KEY_EQUAL or c == KEY_KP_ADD
		var zout: bool = c == KEY_MINUS or c == KEY_KP_SUBTRACT
		var zreset: bool = c == KEY_0 or c == KEY_KP_0
		if zin or zout or zreset:
			if ctrl:
				set_ui_scale(1.0 if zreset else gm.ui_scale + (UI_STEP if zin else -UI_STEP))
			else:
				set_zoom(1.0 if zreset else gm.zoom * (ZOOM_STEP if zin else 1.0 / ZOOM_STEP))
			gm.ui.refresh_settings()
			return true
		if e.echo: return false
		if c == KEY_F11 or (c == KEY_ENTER and e.alt_pressed):
			set_fullscreen(not gm.fullscreen)
			gm.ui.refresh_settings()
			return true
	elif e is InputEventMouseButton and e.pressed and gm.uist == "":
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
			if e.ctrl_pressed: set_ui_scale(gm.ui_scale + (UI_STEP if up else -UI_STEP))
			else: set_zoom(gm.zoom * (1.07 if up else 1.0 / 1.07), false)
			return true
	return false

func set_zoom(z: float, announce: bool = true) -> void:
	gm.zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	if absf(gm.zoom - 1.0) < 0.02: gm.zoom = 1.0
	if announce and gm.ready_done and gm.uist == "": gm.toast("Zoom %d%%" % roundi(gm.zoom * 100))
	save_settings()

func set_ui_scale(s: float, announce: bool = true) -> void:
	gm.ui_scale = clampf(snappedf(s, 0.05), UI_MIN, UI_MAX)
	gm.get_window().content_scale_factor = gm.ui_scale
	if announce and gm.ready_done and gm.uist == "": gm.toast("Interface size %d%%" % roundi(gm.ui_scale * 100))
	save_settings()

func set_fullscreen(on: bool) -> void:
	gm.fullscreen = on
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_window_size()
	save_settings()

func set_window_size(i: int) -> void:
	gm.win_idx = clampi(i, 0, WIN_SIZES.size() - 1)
	if gm.fullscreen:
		gm.fullscreen = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_window_size()
	save_settings()

func _apply_window_size() -> void:
	var want: Vector2i = WIN_SIZES[gm.win_idx]
	var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var sz := Vector2i(mini(want.x, scr.size.x), mini(want.y, scr.size.y))
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(scr.position + (scr.size - sz) / 2)

func window_label() -> String:
	var w: Vector2i = WIN_SIZES[gm.win_idx]
	return "%d × %d" % [w.x, w.y]

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "zoom", gm.zoom)
	cf.set_value("display", "ui_scale", gm.ui_scale)
	cf.set_value("display", "fullscreen", gm.fullscreen)
	cf.set_value("display", "window", gm.win_idx)
	cf.save(SETTINGS_PATH)

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		# first launch: pick the largest preset that fits comfortably on this screen
		var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		gm.win_idx = 0
		for i in WIN_SIZES.size():
			if WIN_SIZES[i].x <= scr.size.x * 0.85 and WIN_SIZES[i].y <= scr.size.y * 0.85: gm.win_idx = i
		if DisplayServer.get_name() != "headless": _apply_window_size()
		save_settings()
		return
	gm.zoom = clampf(float(cf.get_value("display", "zoom", 1.0)), ZOOM_MIN, ZOOM_MAX)
	gm.ui_scale = clampf(float(cf.get_value("display", "ui_scale", 1.0)), UI_MIN, UI_MAX)
	gm.win_idx = clampi(int(cf.get_value("display", "window", 0)), 0, WIN_SIZES.size() - 1)
	gm.fullscreen = bool(cf.get_value("display", "fullscreen", false))
	gm.get_window().content_scale_factor = gm.ui_scale
	if DisplayServer.get_name() == "headless": return
	if gm.fullscreen: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else: _apply_window_size()
