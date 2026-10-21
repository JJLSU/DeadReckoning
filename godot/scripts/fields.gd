class_name Fields
extends RefCounted
## Clearing and settling hostile airfields (Greg, 2026-10-20). Kill every enemy at a zombie
## or survivor-held field and it stays clear for CLEAR_TIME of game time. Ring Failsafe's bell
## and as many settlers as the plane seats come out of the houses, gather at the bell and
## board. Fly them in: they get off and patrol, and once the field's NEED have arrived before
## the time is up it is settled for good: friendly, green on the map, with fuel, the farm
## store and a job board. If time runs out first the enemy takes it back.
## Run state: G.fields {str(strip id): {"st": "cleared"/"settled", "until", "have", "need"}}
## and G.crew (settlers aboard). apply() lays it over the freshly generated strips.

const CLEAR_TIME := 2880.0   # game minutes a cleared field stays clear (2 days; in flight 1 s = 1 min, on foot 1 s = 0.5 min)
const NEED := {"dirt": 6, "regional": 8, "airport": 10}   # settlers it takes to hold a field
const POOL_Z := 10           # dead still to come at a zombie field after the ones already there:
const POOL_Z_STEP := 4       # DF().count * (POOL_Z + POOL_Z_STEP * danger)
const POOL_SV := 4           # survivor-held: reinforcements still to come, POOL_SV + danger
const SETTLERS_SHOWN := 12   # most settlers walking about a field at once
const GATHER_R := Vector2(48.0, 78.0)   # px from the bell where settlers gather
const GATHER_T := 2.5        # s at the bell, all together, before they head for the plane
const GATHER_MAX := 20.0     # s: stragglers don't hold the rest up longer than this
const EMERGE := Vector2(0.2, 2.5)   # s before each one sets off out of their house
const WALK := 1.0            # walking to the bell and the plane, fraction of the usual 85 px/s
const BOARD_R := 48.0        # px from the plane where they climb in
const PATROL_R := Vector2(4.0, 8.0)   # tiles they wander round their post
const GREET_R := 110.0
const GREET_GAP := 6.0
const SHIRTS := ["#4f5a3a", "#5a4a32", "#3f5468", "#6a3f32", "#4a5f58", "#5d5a4a", "#3a4a3a", "#6a5a3a"]
const PACKS := ["#4a4232", "#3d4a35", "#5a4632", "#3a3e44"]
const HAIR := ["#2b2118", "#5a3a22", "#8a6a3a", "#c8b07a", "#3a2a20"]
const GREETINGS := ["We've got it from here.", "Quiet so far.", "All clear on this side.", "Good to see you, pilot.", "Holding the line.", "Nice field you found us."]

var gm: Game

func _init(game: Game) -> void:
	gm = game

# =====================================================================
# Which fields, and their state
# =====================================================================
## Fields that can be fought over: everything but Haven, road landings, farms and Failsafe.
static func clearable(s: Dictionary) -> bool:
	return s.type != "haven" and s.type != "road" and s.get("arch", "") != "family"

## Friendly fields: family farms, Failsafe, and fields your settlers hold.
static func friendly(s: Dictionary) -> bool:
	return s.get("arch", "") == "family" or s.get("settled", false)

## Nothing hostile left there (cleared or settled): no dead, no garrison.
static func calm(s: Dictionary) -> bool:
	return s.get("cleared", false) or s.get("settled", false)

## Remembers what world gen made of each strip, so apply() can undo a field's state.
## Called at the end of World.gen_world.
static func record_base(wd) -> void:
	for s in wd.strips:
		s.base = [s.get("hostile", false), s.fuel, s.fuelPrice]

func entry(s: Dictionary) -> Variant:
	if gm.G == null: return null
	return gm.G.get("fields", {}).get(str(s.id))

func need_of(s: Dictionary) -> int:
	return int(NEED.get(s.type, 8))

## Puts G.fields onto the strips (after world gen, a load, or a change).
func apply() -> void:
	if gm.G == null: return
	if not gm.G.has("fields") or not (gm.G.fields is Dictionary): gm.G.fields = {}
	gm.G.crew = int(gm.G.get("crew", 0))
	for s in gm.wd.strips:
		if s.has("base"):
			s.hostile = s.base[0]; s.fuel = s.base[1]; s.fuelPrice = s.base[2]
		s.erase("cleared"); s.erase("settled")
	for k in gm.G.fields.keys():
		var id := int(k)
		if id < 0 or id >= gm.wd.strips.size(): continue
		var s: Dictionary = gm.wd.strips[id]
		var e: Dictionary = gm.G.fields[k]
		s.hostile = false
		if e.st == "settled":
			s.settled = true
			s.fuel = true
			s.fuelPrice = 5
		else:
			s.cleared = true

## Cleared fields whose time is up go back to the enemy. The field you're standing on waits
## until you leave (here = true checks it too: called as you arrive).
func tick(here: bool = false) -> void:
	if gm.G == null or not gm.G.has("fields"): return
	var changed := false
	for k in gm.G.fields.keys():
		var e: Dictionary = gm.G.fields[k]
		if e.st != "cleared" or gm.G.time < float(e.until): continue
		if not here and gm.mode == "ground" and gm.S and int(gm.S.s.id) == int(k): continue
		gm.G.fields.erase(k)
		changed = true
		var s: Dictionary = gm.strip(int(k))
		var lost := int(e.have)
		gm.toast_later(0.3, "%s has been overrun%s." % [s.name, (". The %d settler%s there didn't make it" % [lost, "" if lost == 1 else "s"]) if lost > 0 else ""], "bad")
	if changed: apply()

func time_left(e: Dictionary) -> String:
	var m := maxf(0.0, float(e.until) - gm.G.time)
	var d := int(m / 1440.0)
	var h := int(fmod(m, 1440.0) / 60.0)
	if d > 0: return "%dd %dh" % [d, h]
	if h > 0: return "%dh %dm" % [h, int(fmod(m, 60.0))]
	return "%dm" % int(m)

## Seats left for settlers: the plane's seats less mayday passengers and settlers aboard.
func seats_free() -> int:
	return int(gm.PS().get("seats", 1)) - gm.G.pax.size() - int(gm.G.get("crew", 0))

## The nearest cleared field to strip s (somewhere to take settlers), or null.
func nearest_cleared(s: Dictionary):
	var best = null
	var bd := 1e18
	for o in gm.wd.strips:
		if not o.get("cleared", false): continue
		var d := Vector2(o.x - s.x, o.y - s.y).length()
		if d < bd:
			bd = d
			best = o
	return best

# =====================================================================
# On foot: arriving, clearing, settlers
# =====================================================================
## After the site is built (Game.enter_ground): how many enemies are still to come, settlers
## walking about, and settlers you brought getting off the plane.
func on_enter(site: Dictionary) -> void:
	var s: Dictionary = site.s
	site.setl = []
	site.greetT2 = 0.0
	if not clearable(s): return
	var e = entry(s)
	if e == null:
		if s.get("hostile", false): site.pool = POOL_SV + int(s.danger)
		else: site.pool = int(round(gm.DF().count * (POOL_Z + POOL_Z_STEP * int(s.danger))))
		return
	site.calm = true
	var have: int = int(e.need) if e.st == "settled" else int(e.have)
	_place_patrols(site, mini(SETTLERS_SHOWN, have))
	if e.st == "settled":
		gm.toast_later(0.4, "Your settlers hold %s. Fuel and medicine for sale." % s.name, "good")
		return
	var crew := int(gm.G.get("crew", 0))
	if crew > 0:
		gm.G.crew = 0
		e.have = int(e.have) + crew
		for i in mini(crew, maxi(0, SETTLERS_SHOWN - site.setl.size())): _disembark(site, i)
		if int(e.have) >= int(e.need):
			settle(s)
			gm.G.offers = gm.menu.gen_offers(s)   # a job board now (arrive() made the offers before they landed)
			gm.toast_later(0.4, "%d settlers climb out. %s is settled: %d/%d. It's ours now, with fuel and medicine for sale." % [crew, s.name, int(e.have), int(e.need)], "good")
			gm.sfx("rare")
		else:
			gm.toast_later(0.4, "%d settler%s climb%s out and start patrolling. Settlers %d/%d. %s before they come back." % [crew, "" if crew == 1 else "s", "s" if crew == 1 else "", int(e.have), int(e.need), time_left(e)], "good")
	else:
		gm.toast_later(0.4, "Cleared field. Settlers %d/%d, %s before they come back. Ring the bell at Failsafe to bring more." % [int(e.have), int(e.need), time_left(e)], "mag")

func settle(s: Dictionary) -> void:
	var e = entry(s)
	if e == null: return
	e.st = "settled"
	e.have = int(e.need)
	apply()
	if gm.S and int(gm.S.s.id) == int(s.id) and gm.S.get("pump") == null:
		gm.S.pump = Vector2(gm.S.plane.x + 260, (gm.S.ry - 1) * gm.TS + 14)

## Enemies still to deal with here (on the map plus those still to come), or -1 where nothing is hostile.
func hostiles_left() -> int:
	var S = gm.S
	if S == null or not S.has("pool") or S.get("calm", false): return -1
	var n: int = maxi(0, int(S.pool))   # (queued reinforcements come out of the pool)
	for z in S.zs:
		if not z.dead: n += 1
	for v in S.sv:
		if not v.dead: n += 1
	return n

## Every frame on foot (after the farm folk).
func update(p: Dictionary, dt: float) -> void:
	var S: Dictionary = gm.S
	if S.has("pool") and not S.get("calm", false) and S.t > 1.0: _check_clear(S)
	if not S.has("setl"): return
	S.greetT2 -= dt
	var gather: Array = S.setl.filter(func(v): return v.st == "out" or v.st == "gather")
	if gather.size():
		var all_in := gather.all(func(v): return v.st == "gather")
		S.gathT = float(S.get("gathT", 0.0)) + dt
		if all_in: S.gathAll = float(S.get("gathAll", 0.0)) + dt
		if (all_in and S.gathAll >= GATHER_T) or S.gathT >= GATHER_MAX:
			var first := true
			for v in gather:
				v.st = "board"
				v.path = PackedVector2Array()
				if first:
					gm.survivors.sv_say(v, "Let's go!")
					first = false
	for v in S.setl.duplicate():
		_upd_settler(S, v, p, dt)
		if S.setl.has(v) and v.st != "gather": gm.survivors.fr_jostle(v, dt)   # (everyone at the bell stands together)

func _check_clear(S: Dictionary) -> void:
	if not S.get("rq", []).is_empty(): return   # a reinforcement wave is still on its way in
	var held: bool = S.get("hostile", false)
	if held:
		var alive := 0
		for v in S.sv:
			if not v.dead: alive += 1
		if alive > 0: return
		if int(S.pool) > 0:
			# the garrison is gone: whoever they have left comes for you
			if int(S.get("svq", 0)) == 0:
				S.svq = int(S.pool)
				S.svqT = 2.0
				gm.toast("Engines on the road. They're sending everyone they have left.", "bad")
			return
		S.svq = 0
	else:
		var awake := 0
		var dormant := 0
		for z in S.zs:
			if z.dead: continue
			if z.dormant: dormant += 1
			else: awake += 1
		if awake > 0 or int(S.pool) > 0: return
		if dormant > 0:
			# the last of the dead: the bodies that weren't dead get up
			for z in S.zs:
				if z.dormant and not z.dead:
					z.dormant = false; z.rise = 0.7; z.alert = true
			gm.toast("Some of the bodies on the ground are getting up.", "bad")
			return
	_cleared(S)

func _cleared(S: Dictionary) -> void:
	var s: Dictionary = S.s
	gm.G.fields[str(s.id)] = {"st": "cleared", "until": gm.G.time + CLEAR_TIME, "have": 0, "need": need_of(s)}
	apply()
	S.calm = true
	S.hostile = false
	S.svq = 0
	gm.sfx("rare")
	gm.toast("%s is clear. It stays ours for 2 days. Ring the bell at Failsafe and fly in %d settlers to hold it." % [s.name, need_of(s)], "good")

## Settlers already at a field, spread over it at their posts.
func _place_patrols(site: Dictionary, n: int) -> void:
	var posts: Array = []
	for i in n:
		var pt = _post(site, posts)
		if pt == null: return
		posts.append(pt)
		var v := _new_settler(pt.x, pt.y)
		_to_patrol(v, pt)
		site.setl.append(v)

## A settler getting off the plane, walking to a post of their own.
func _disembark(site: Dictionary, i: int) -> void:
	var pl: Vector2 = site.plane
	var x := pl.x
	var y := pl.y
	for q in 20:
		x = pl.x + 40 + randf() * 60
		y = pl.y - 20 - randf() * 40
		if not gm.hit_box(x, y, 9): break
	var v := _new_settler(x, y)
	var posts: Array = site.setl.map(func(o): return Vector2(o.get("hx", o.tx), o.get("hy", o.ty)))
	var pt = _post(site, posts)
	if pt == null: pt = Vector2(x, y - 80)
	v.st = "post"
	v.tx = pt.x; v.ty = pt.y
	v.t = 0.3 + i * 0.5
	site.setl.append(v)

## An open spot outside the buildings, far from the other posts and off the strip.
func _post(site: Dictionary, posts: Array) -> Variant:
	var ts: float = gm.TS
	var best = null
	var best_d := -1.0
	for t in 24:
		var x: float = (2.0 + randf() * (site.cols - 4)) * ts
		var y: float = (2.0 + randf() * (site.ry - 3)) * ts
		if gm.hit_box(x, y, 10) or gm.survivors._in_room(site, x, y): continue
		var md := INF
		for q in posts: md = minf(md, Vector2(x - q.x, y - q.y).length())
		if md > best_d:
			best_d = md
			best = Vector2(x, y)
	return best

func _new_settler(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y, "ang": randf() * TAU, "wk": 0.0, "st": "patrol", "t": 0.0, "tx": x, "ty": y,
		"shirt": SHIRTS[randi() % SHIRTS.size()], "pack": PACKS[randi() % PACKS.size()], "skin": D.sv_skin(), "hair": HAIR[randi() % HAIR.size()],
		"fem": randf() < 0.4, "long": randf() < 0.5, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y), "spm": randf_range(0.9, 1.1), "greetT": -99.0}

func _to_patrol(v: Dictionary, pt: Vector2) -> void:
	v.st = "patrol"
	v.hx = pt.x; v.hy = pt.y
	v.erase("pr")
	gm.survivors.sv_patrol_init(v)
	v.pr = randf_range(PATROL_R.x, PATROL_R.y) * gm.TS

## Walks a settler toward (tx, ty) round walls; true once within `near` px.
func _walk(v: Dictionary, tx: float, ty: float, near: float, dt: float) -> bool:
	var d := Vector2(tx - v.x, ty - v.y).length()
	if d <= near: return true
	var dir: Vector2 = gm.survivors.sv_nav(v, tx, ty)
	dir = gm.survivors.sv_avoid(v, dir.x, dir.y, gm.survivors.people())   # round people in the way
	var st := minf(d, 85.0 * WALK * float(v.spm) * dt)
	var ox: float = v.x
	var oy: float = v.y
	gm.move_c(v, dir.x * st, dir.y * st, 8)
	v.wk += Vector2(v.x - ox, v.y - oy).length() * 0.22
	if dir != Vector2.ZERO: v.ang = lerp_angle(float(v.ang), dir.angle(), minf(1.0, dt * 10))
	return false

func _upd_settler(S: Dictionary, v: Dictionary, p: Dictionary, dt: float) -> void:
	v.t = float(v.t) - dt
	match v.st:
		"out":   # leaving their house for the bell
			if v.t > 0: return
			if _walk(v, v.tx, v.ty, 6.0, dt):
				v.st = "gather"
		"gather":
			var b: Vector2 = S.get("bell", Vector2.ZERO)
			v.ang = lerp_angle(float(v.ang), atan2(b.y - v.y, b.x - v.x), minf(1.0, dt * 6))
		"board":
			if _walk(v, S.plane.x, S.plane.y, BOARD_R, dt):
				S.setl.erase(v)
				gm.G.crew = int(gm.G.get("crew", 0)) + 1
				if not S.setl.any(func(o): return o.st == "board"): _all_aboard()
		"post":   # off the plane, walking to their post
			if v.t > 0: return
			if _walk(v, v.tx, v.ty, 10.0, dt): _to_patrol(v, Vector2(v.tx, v.ty))
		"patrol":
			var o := Vector2(v.x, v.y)
			var stv: Vector2 = gm.survivors.sv_patrol(v, dt)
			stv = gm.survivors.sv_avoid(v, stv.x, stv.y, gm.survivors.people())
			if stv != Vector2.ZERO: gm.move_c(v, stv.x * 85.0 * float(v.spm) * dt, stv.y * 85.0 * float(v.spm) * dt, 8)
			v.wk += o.distance_to(Vector2(v.x, v.y)) * 0.22
			var dp := Vector2(p.x - v.x, p.y - v.y)
			if dp.length() < 90 and not v.go: v.ang = lerp_angle(float(v.ang), dp.angle(), minf(1.0, dt * 6))
			if dp.length() < GREET_R and S.greetT2 <= 0 and S.t - float(v.greetT) > 45.0 and gm.los(v.x, v.y, p.x, p.y):
				v.greetT = S.t
				S.greetT2 = GREET_GAP
				gm.survivors.sv_say(v, GREETINGS[randi() % GREETINGS.size()])

func _all_aboard() -> void:
	var n := int(gm.G.get("crew", 0))
	var dest = nearest_cleared(gm.S.s)
	if dest and gm.G.nav < 0: gm.G.nav = int(dest.id)
	gm.toast("%d settler%s aboard. Fly them to %s." % [n, "" if n == 1 else "s", dest.name if dest else "a cleared field"], "good")
	gm.sfx("cash")

## Failsafe's bell was rung: settlers come out of the houses to fill the plane's free seats.
func on_bell() -> void:
	var S: Dictionary = gm.S
	if S.get("setl", []).any(func(o): return o.st != "patrol"):
		return   # already on their way
	if nearest_cleared(S.s) == null:
		gm.toast_later(0.8, "Faces at the windows, but nobody comes out. There's nowhere to send settlers yet: clear a hostile field first.")
		return
	var n := seats_free()
	if n <= 0:
		gm.toast_later(0.8, "The settlers wave from their doors. There's no room left in the %s." % gm.PS().name)
		return
	var homes: Array = S.rooms.filter(func(rm): return rm.kind == "house" or rm.kind == "shed" or rm.kind == "barn")
	if homes.is_empty(): homes = S.rooms
	var b: Vector2 = S.bell
	S.gathT = 0.0
	S.gathAll = 0.0
	var placed := 0
	for i in n:
		var rm = homes[i % homes.size()] if homes.size() else null
		var x: float = b.x
		var y: float = b.y + 120
		if rm:
			for q in 30:
				x = (rm.c + 1.5 + randf() * (rm.w - 3)) * gm.TS
				y = (rm.r + 1.5 + randf() * (rm.h - 3)) * gm.TS
				if not gm.hit_box(x, y, 9): break
		var v := _new_settler(x, y)
		v.st = "out"
		v.t = randf_range(EMERGE.x, EMERGE.y)
		var a := TAU * i / n + randf() * 0.3
		var r := randf_range(GATHER_R.x, GATHER_R.y)
		v.tx = b.x + cos(a) * r; v.ty = b.y + sin(a) * r
		for q in 10:
			if not gm.hit_box(v.tx, v.ty, 9): break
			r += 8
			v.tx = b.x + cos(a) * r; v.ty = b.y + sin(a) * r
		S.setl.append(v)
		placed += 1
	gm.toast_later(0.8, "Doors open across Failsafe. %d settler%s grab%s their packs and head for the bell." % [placed, "" if placed == 1 else "s", "s" if placed == 1 else ""], "good")

func draw(g: Pen) -> void:
	var S: Dictionary = gm.S
	for v in S.get("setl", []):
		if not Render.on_view(v.x, v.y, 60): continue
		Render.draw_person(g, v.x, v.y, v.ang, {"body": v.shirt, "skin": v.skin, "hair": v.hair, "cap": "", "pack": v.pack, "gun": true, "long": v.long, "fem": v.fem, "walk": v.wk, "lower": 1.0})

# =====================================================================
# Text for the HUD, the hangar and the chart
# =====================================================================
## Line under the field's name on foot: what's left to kill, or the settlers' count.
func hud_line() -> String:
	var S = gm.S
	if S == null: return ""
	var s: Dictionary = S.s
	var e = entry(s)
	if e:
		if e.st == "settled": return "Settled"
		return "Settlers %d/%d, %s left" % [int(e.have), int(e.need), time_left(e)]
	var n := hostiles_left()
	if n < 0: return ""
	return "%d %s left to clear" % [n, "hostile" if n == 1 else "hostiles"]

## Tag for the hangar menu, or [] when there's nothing to say.
func tag(s: Dictionary) -> Array:
	var e = entry(s)
	if e == null: return []
	if e.st == "settled": return ["Held by your settlers", true]
	return ["Cleared: settlers %d/%d, %s left" % [int(e.have), int(e.need), time_left(e)], true]

## Short label after a cleared field's name on the chart ("3/8").
func map_count(s: Dictionary) -> String:
	var e = entry(s)
	if e == null or e.st != "cleared": return ""
	return " %d/%d" % [int(e.have), int(e.need)]

# =====================================================================
# From the air: campfires at a disputed field (Greg, 2026-10-20)
# =====================================================================
## A cleared field still waiting for settlers shows 3-5 fires on and round the strip, drawn
## exactly like the fires out on the map (Render.draw_wildfire). They go when it's settled or retaken.
const CAMPS := Vector2i(3, 5)

## The campfires of a disputed field, in world units (none at other fields). Fixed per strip.
static func camps(s: Dictionary) -> Array:
	if not s.get("cleared", false): return []
	var sid: int = s.id
	var n: int = CAMPS.x + int(U.hash3(sid, 31, 7) * (CAMPS.y - CAMPS.x + 1))
	var L: float = s.len
	var Wd: float = s.wid
	var c := cos(float(s.ang))
	var sn := sin(float(s.ang))
	var out: Array = []
	for i in n:
		var u: float
		var v: float
		if i < 2:   # in the field: beside the runway, off the hangar side
			u = (U.hash3(sid, i, 41) - 0.5) * L * 0.8
			v = -(Wd / 2 + 18 + U.hash3(sid, i, 42) * 30)
		else:       # round it, out past the ends and sides
			var a: float = TAU * (i - 2) / maxf(1, n - 2) + U.hash3(sid, i, 43) * 1.2
			var r: float = 1.0 + U.hash3(sid, i, 44) * 0.6
			u = cos(a) * (L / 2 + 40) * r
			v = sin(a) * (Wd / 2 + 120) * r
		out.append(Vector2(s.x + c * u - sn * v, s.y + sn * u + c * v))
	return out
