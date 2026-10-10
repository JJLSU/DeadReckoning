class_name Flight
## Flying: takeoff, the flight model, approach and landing, touchdown and arriving at a
## strip, plus the course markers. Split out of game.gd.

# Flight: automatic help on the runway (keeps you on the centreline during the takeoff and
# landing roll) and on approach (steers you onto the runway and works the throttle).
# Off for now; the approach guides on screen are still drawn. Set true to turn it back on.
const LANDING_ASSIST := false

var gm: Game   # the game: run state, site, shared helpers

func _init(game: Game) -> void:
	gm = game

func cruise_ok() -> bool:
	return gm.F != null and not gm.F.onGround and not gm.F.crashed and gm.F.alt > 45 and gm.F.storm < 0.05 and gm.F.underFire <= 0 and gm.G.fuel > 0

func takeoff() -> void:
	gm.sat = 0.84; gm.con = 1.07
	var s := gm.strip(gm.G.strip)
	var a: float = s.ang + (0.0 if randf() < 0.5 else PI)
	var wa := randf() * TAU
	var ws := randf() * 22
	gm.F = {"x": s.x - cos(a) * (s.len / 2 - 30), "y": s.y - sin(a) * (s.len / 2 - 30), "hdg": a, "spd": 0.0, "alt": 0.0, "vs": 0.0, "thr": 0.0, "onGround": true, "departing": true,
		"rollStrip": s, "bank": 0.0, "prop": 0.0, "storm": 0.0, "tb": 0.0, "tracers": [], "underFire": 0.0, "flash": 0.0, "gx": 0.0, "gy": 0.0, "gfT": 0.0,
		"wind": Vector2(cos(wa) * ws, sin(wa) * ws), "trk": a, "cruise": false, "crashed": false, "assist": false, "inStorm": false, "warnedFire": false, "evT": 60 + randf() * 50, "autothr": false}
	gm.mode = "flight"
	gm._free_site()
	gm.ui.close_ui()
	gm.cam_snap = true
	gm.clear_input()
	gm.menu.checkpoint()
	gm.toast("Throttle up to take off. Keep it on the runway.")

func _thr_touch() -> bool:
	return gm.key(KEY_W) or gm.key(KEY_S) or gm.key(KEY_UP) or gm.key(KEY_DOWN) or (gm.ptrs.has(0) and gm.ptrs[0].role == "thr")

func upd_flight(dt: float) -> void:
	gm.G.time += dt
	var P := gm.PS()
	var steer := 0.0
	if gm.key(KEY_A) or gm.key(KEY_LEFT): steer -= 1
	if gm.key(KEY_D) or gm.key(KEY_RIGHT): steer += 1
	for p in gm.ptrs.values():
		if p.role == "steer": steer += clampf((p.x - p.sx) / 70.0, -1, 1)
	steer = clampf(steer, -1, 1)
	gm.F.assist = false
	if LANDING_ASSIST and gm.F.onGround and gm.F.rollStrip and absf(steer) < 0.05 and gm.F.spd > 3:
		var rs: Dictionary = gm.F.rollStrip
		var dir: float = rs.ang if absf(U.ang_diff(rs.ang, gm.F.hdg)) < PI / 2 else rs.ang + PI
		var lat: float = -(gm.F.x - rs.x) * sin(dir) + (gm.F.y - rs.y) * cos(dir)
		steer = clampf(U.ang_diff(dir, gm.F.hdg) * 3 - lat * 0.02, -1, 1)
	if LANDING_ASSIST and not gm.F.onGround and gm.F.alt < 70 and absf(steer) < 0.05:
		var best = null
		var bd := 2600.0
		for s in gm.wd.strips:
			if not gm.known.has(s.id) or s.type == "road": continue
			var d := Vector2(s.x - gm.F.x, s.y - gm.F.y).length()
			if d < bd:
				bd = d
				best = s
		if best:
			var dir: float = best.ang if absf(U.ang_diff(best.ang, gm.F.hdg)) < PI / 2 else best.ang + PI
			var cx := cos(dir)
			var cy := sin(dir)
			var rx: float = gm.F.x - best.x
			var ry2: float = gm.F.y - best.y
			var along := rx * cx + ry2 * cy
			var lat0 := -rx * cy + ry2 * cx
			if along < best.len / 2 - 40 and along > -2600 and absf(lat0) < 450:
				var la := clampf(-along * 0.35, 260, 700)
				var tx: float = best.x + cx * (along + la)
				var ty: float = best.y + cy * (along + la)
				var des := atan2(ty - gm.F.y, tx - gm.F.x)
				var df := U.ang_diff(des, gm.F.trk)
				if absf(U.ang_diff(des, gm.F.hdg)) < 0.9:
					steer = clampf(df * 2.6, -0.9, 0.9)
					gm.F.assist = true
					if not _thr_touch() and gm.F.thr <= 0.75 and along > -2200:
						var pt = predict_touchdown()
						var pa: float = ((pt.x - best.x) * cx + (pt.y - best.y) * cy) if pt else 1e9
						var tgt: float = -best.len / 2 + best.len * 0.22
						if pa < tgt - 50: gm.F.thr = minf(0.72, gm.F.thr + 0.9 * dt)
						elif pa > tgt + 50: gm.F.thr = maxf(0.08, gm.F.thr - 0.6 * dt)
						gm.F.autothr = true
	if gm.key(KEY_W) or gm.key(KEY_UP): gm.F.thr = minf(1, gm.F.thr + 0.55 * dt)
	if gm.key(KEY_S) or gm.key(KEY_DOWN): gm.F.thr = maxf(0, gm.F.thr - 0.55 * dt)
	var eff: float = gm.F.thr if gm.G.fuel > 0 else 0.0
	if gm.G.fuel > 0: gm.G.fuel = maxf(0, gm.G.fuel - P.burn * (0.15 + 0.85 * gm.F.thr) * dt)
	var target: float = eff * P.max
	if gm.F.onGround:
		if target > gm.F.spd: gm.F.spd += (target - gm.F.spd) * 0.25 * dt
		else: gm.F.spd = maxf(target, gm.F.spd - (38.0 if eff < 0.08 else 14.0) * dt)
	else:
		gm.F.spd += (target - gm.F.spd) * (0.28 if target > gm.F.spd else 0.3) * dt
	var turnK: float = clampf(gm.F.spd / 30.0, 0, 1) * 0.7 if gm.F.onGround else 1.0
	gm.F.bank = lerpf(gm.F.bank, 0.0 if gm.F.onGround else steer, minf(1, dt * 4))
	gm.F.hdg += steer * P.turn * turnK * dt
	gm.F.prop += dt * (eff * 40 + 2)
	var altT := clampf((gm.F.spd - P.stall) / (P.cruise - P.stall) * 100, -80, 120)
	if gm.F.onGround:
		gm.F.alt = 0.0; gm.F.vs = 0.0
		if altT > 3:
			gm.F.onGround = false; gm.F.alt = 0.3; gm.F.rollStrip = null; gm.F.departing = false
			gm.G.stats.flights += 1
			gm.toast("Airborne.")
	else:
		gm.F.vs = maxf(clampf((altT - gm.F.alt) * 1.3, -48, 22), -(5 + gm.F.alt * 0.55))
		gm.F.alt += gm.F.vs * dt
		if gm.F.alt <= 0:
			touchdown(P)
			if gm.uist != "" or gm.F == null or gm.mode != "flight": return
	if gm.G.leak > 0 and gm.G.fuel > 0: gm.G.fuel = maxf(0, gm.G.fuel - gm.G.leak * dt)
	var st := gm.wd.storm_at(gm.F.x, gm.F.y)
	gm.F.storm = 0.0 if gm.F.onGround else st.k
	gm.F.gx = 0.0; gm.F.gy = 0.0
	if gm.F.storm > 0:
		var k: float = gm.F.storm
		if not gm.F.inStorm and k > 0.03: gm.toast("Flying into weather. Hold on.", "bad")
		gm.F.inStorm = true
		gm.F.tb = lerpf(gm.F.tb, (randf() - 0.5) * 2, minf(1, dt * 3))
		gm.F.hdg += gm.F.tb * k * 0.9 * dt
		gm.F.alt += (randf() - 0.5) * k * 70 * dt
		gm.F.spd = maxf(0, gm.F.spd + (randf() - 0.5) * k * 30 * dt)
		var bp: Vector2 = st.best.p
		var ta := atan2(gm.F.y - bp.y, gm.F.x - bp.x) + PI / 2
		var gu := 48 * k * (0.6 + 0.4 * sin(gm.T * 1.7))
		gm.F.gx = cos(ta) * gu; gm.F.gy = sin(ta) * gu
		if k > 0.55: gm.G.hull -= (k - 0.55) * 14 * dt
		if randf() < k * dt * 0.5:
			gm.F.flash = 0.25
			gm.sfx("thunder")
			if k > 0.4 and randf() < 0.18:
				gm.G.hull -= 10
				gm.toast("Lightning strike.", "bad")
	elif gm.F.storm <= 0:
		gm.F.inStorm = false
	gm.F.flash -= dt
	gm.F.underFire -= dt
	gm.F.gfT -= dt
	if gm.F.gfT <= 0 and not gm.F.onGround:
		gm.F.gfT = 0.45
		var tt := gm.wd.terr(gm.F.x, gm.F.y)
		if gm.F.alt < 45 and (tt == 9 or tt == 10) and randf() < 0.5:
			var a := randf() * TAU
			var rr2 := 150 + randf() * 250
			var hit: bool = randf() < 0.35 * (1 - gm.F.alt / 60.0)
			gm.F.tracers.append({"x": gm.F.x + cos(a) * rr2, "y": gm.F.y + sin(a) * rr2, "tx": gm.F.x + (0.0 if hit else (randf() - 0.5) * 140), "ty": gm.F.y + (0.0 if hit else (randf() - 0.5) * 140), "life": 0.35})
			gm.sfx("enemy")
			gm.F.underFire = 1.5
			if not gm.F.warnedFire:
				gm.F.warnedFire = true
				gm.toast("Ground fire. Climb out of range.", "bad")
			if hit:
				gm.G.hull -= 4 + randf() * 5
				if randf() < 0.3:
					gm.G.leak += 0.03
					gm.toast("Fuel leak.", "bad")
	var i: int = gm.F.tracers.size() - 1
	while i >= 0:
		gm.F.tracers[i].life -= dt
		if gm.F.tracers[i].life <= 0: gm.F.tracers.remove_at(i)
		i -= 1
	if gm.G.hull <= 0:
		gm.G.hull = 0.0
		gm.die("breakup")
		return
	var dx: float = cos(gm.F.hdg) * gm.F.spd * dt
	var dy: float = sin(gm.F.hdg) * gm.F.spd * dt
	if not gm.F.onGround:
		dx += (gm.F.wind.x + gm.F.gx) * dt
		dy += (gm.F.wind.y + gm.F.gy) * dt
	if dx != 0 or dy != 0: gm.F.trk = atan2(dy, dx)
	gm.F.x += dx; gm.F.y += dy
	gm.G.stats.dist += Vector2(dx, dy).length()
	var lo := -gm.OCEAN_PAD
	var hi := gm.WORLD + gm.OCEAN_PAD
	if gm.F.x < lo or gm.F.y < lo or gm.F.x > hi or gm.F.y > hi:
		gm.F.x = clampf(gm.F.x, lo, hi); gm.F.y = clampf(gm.F.y, lo, hi)
		var toC := atan2(gm.WORLD / 2 - gm.F.y, gm.WORLD / 2 - gm.F.x)
		gm.F.hdg += U.ang_diff(toC, gm.F.hdg) * dt * 2
	if gm.F.onGround:
		var s = gm.F.rollStrip if gm.F.rollStrip else gm.wd.strip_at(gm.F.x, gm.F.y, 0)
		var on: bool = s != null and gm.wd.on_runway(s, gm.F.x, gm.F.y, 1.5)
		if not on and gm.F.spd > 24:
			gm.die("loop")
			return
		if not gm.F.departing and gm.F.spd < 2.5 and eff < 0.1:
			var near = s if s else gm.wd.nearest_strip(gm.F.x, gm.F.y, 500)
			if near:
				arrive(near)
				return
	if not gm.F.onGround:
		gm.F.evT -= dt
		if gm.F.evT <= 0 and gm.G.mayday == null:
			gm.F.evT = 100 + randf() * 80
			var rn := gm.range_now()
			var cand := gm.wd.strips.filter(func(s):
				var d := Vector2(s.x - gm.F.x, s.y - gm.F.y).length()
				return s.type != "haven" and s.type != "road" and not s.get("hostile", false) and s.id != gm.G.strip and d > 1200 and d < minf(5500, rn * 0.9))
			if cand.size():
				var s: Dictionary = cand[randi() % cand.size()]
				gm.known[s.id] = true
				var d := Vector2(s.x - gm.F.x, s.y - gm.F.y).length()
				gm.G.mayday = {"id": s.id, "until": gm.G.time + d / 100 * 2.2 + 40, "reward": int(round((150 + d / 100 * 6) / 5.0)) * 5}
				gm.sfx("rare")
				gm.toast("Radio: \"Mayday, mayday. We are pinned down at %s. Anyone out there?\" Land within %d minutes for $%d." % [s.name, int(round(gm.G.mayday.until - gm.G.time)), gm.G.mayday.reward], "mag")
	if gm.G.mayday and gm.G.time > gm.G.mayday.until:
		gm.toast("The mayday has gone silent.", "bad")
		gm.G.mayday = null
	gm.discT -= dt
	if gm.discT <= 0:
		gm.discT = 0.5
		for s in gm.wd.strips:
			if not gm.known.has(s.id) and Vector2(s.x - gm.F.x, s.y - gm.F.y).length() < 2200:
				gm.known[s.id] = true
				gm.toast("Runway lights on the coast. Haven is real." if s.type == "haven" else ("Spotted a field: " + s.name + (". Armed survivors hold it." if s.get("hostile", false) else "")), "mag")

func align_to(sang: float, a: float) -> bool:
	var d := fmod(fmod(a - sang, PI) + PI, PI)
	d = minf(d, PI - d)
	return d < 0.6

func align_ok(s: Dictionary) -> bool:
	return align_to(s.ang, gm.F.hdg if gm.F.onGround else gm.F.trk)

func approach_info():
	if gm.F == null or gm.F.onGround or gm.F.alt < 4: return null
	var best = null
	var nt = nav_target()
	# GDScript lambdas cannot reassign captured locals, so collect via a holder
	var holder := [null]
	var cand2 := func(s):
		if s == null or not gm.known.has(s.id) or s.type == "road": return
		var d := Vector2(s.x - gm.F.x, s.y - gm.F.y).length()
		if d > 7000: return
		var dir: float = s.ang if absf(U.ang_diff(s.ang, gm.F.hdg)) < PI / 2 else s.ang + PI
		var cx := cos(dir)
		var cy := sin(dir)
		var rx: float = gm.F.x - s.x
		var ry: float = gm.F.y - s.y
		var along := rx * cx + ry * cy
		var lat := -rx * cy + ry * cx
		if along > s.len / 2 or absf(lat) > 700 or absf(U.ang_diff(atan2(s.y - gm.F.y, s.x - gm.F.x), gm.F.hdg)) > 1.1: return
		var td: float = -s.len / 2 + s.len * 0.22 - along
		if holder[0] == null or td < holder[0].td:
			holder[0] = {"s": s, "dir": dir, "cx": cx, "cy": cy, "along": along, "lat": lat, "td": td}
	cand2.call(nt)
	cand2.call(mayday_target())
	if holder[0] == null:
		for s in gm.wd.strips: cand2.call(s)
	best = holder[0]
	if best == null: return null
	var p1 = predict_touchdown(0.33)
	var p0 = predict_touchdown(0.0)
	if p1 == null: return null
	var Dd := Vector2(p1.x - gm.F.x, p1.y - gm.F.y).length()
	var D0 := Vector2(p0.x - gm.F.x, p0.y - gm.F.y).length() if p0 else Dd
	var slack: float = best.td - Dd
	best.D = Dd
	best.slack = slack
	best.canMake = D0 < best.td + best.s.len * 0.7
	best.px = best.s.x + best.cx * (-best.s.len / 2 + best.s.len * 0.22) - best.cx * Dd
	best.py = best.s.y + best.cy * (-best.s.len / 2 + best.s.len * 0.22) - best.cy * Dd
	best.phase = "early" if slack > 220 else ("now" if slack >= -220 else ("late" if best.canMake else "high"))
	return best

func predict_touchdown(thrO: float = -1.0):
	var P := gm.PS()
	var x: float = gm.F.x
	var y: float = gm.F.y
	var spd: float = gm.F.spd
	var alt: float = gm.F.alt
	var vs := 0.0
	var tg: float = ((gm.F.thr if thrO < 0 else thrO) if gm.G.fuel > 0 else 0.0) * P.max
	var c := cos(gm.F.hdg)
	var n := sin(gm.F.hdg)
	var wx: float = gm.F.wind.x
	var wy: float = gm.F.wind.y
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
	var vs: float = gm.F.vs
	gm.F.alt = 0.0
	var s = gm.wd.strip_at(gm.F.x, gm.F.y, 1.7)
	var firm := func():
		if vs < -6:
			gm.G.hull = maxf(1, gm.G.hull - round((-vs - 6) * 2.5))
			gm.toast("Firm touchdown. The airframe felt that.", "bad")
	if s and vs > -19 and align_ok(s):
		gm.F.onGround = true; gm.F.rollStrip = s; gm.F.departing = false; gm.F.vs = 0.0; gm.F.thr = 0.0
		gm.sfx("thump")
		if vs > -6: gm.toast("Smooth touchdown.")
		firm.call()
		return
	if s == null and vs > -15:
		var rd = gm.wd.road_at(gm.F.x, gm.F.y) if gm.wd.terr(gm.F.x, gm.F.y) > 1 else null
		if rd and align_to(rd.r.ang, gm.F.trk):
			var rs := make_road_strip(rd)
			gm.F.onGround = true; gm.F.rollStrip = rs; gm.F.departing = false; gm.F.vs = 0.0; gm.F.thr = 0.0
			gm.sfx("thump")
			gm.toast("Emergency landing on the road.", "mag")
			firm.call()
			return
	var t := gm.wd.terr(gm.F.x, gm.F.y)
	if t <= 1:
		gm.die("ditch")
		return
	if s and vs > -15:
		gm.die("misalign")
		return
	if vs <= -15 or gm.F.spd > P.stall * 1.1:
		gm.die("crash")
		return
	gm.die("overrun")

func make_road_strip(rd: Dictionary) -> Dictionary:
	var r: Dictionary = rd.r
	var cx: float = r.x1 + r.dx * rd.t
	var cy: float = r.y1 + r.dy * rd.t
	for s in gm.wd.strips:
		if s.type == "road" and Vector2(s.x - cx, s.y - cy).length() < 900: return s
	var nb = gm.wd.nearest_strip(cx, cy, 1e9)
	var s := {"id": gm.wd.strips.size(), "type": "road", "arch": "road", "name": "%s, mile %d" % [r.name, maxi(1, int(round(rd.t * r.len / 160.0)))], "x": cx, "y": cy, "ang": r.ang, "len": 640.0, "wid": 40.0,
		"fuel": false, "shop": false, "dealer": false, "danger": clampi((nb.danger if nb else 2) + 1, 1, 5), "fuelPrice": 0, "seed": randi() % 1000000000, "home": false}
	gm.wd.strips.append(s)
	gm.G.roadStrips.append(s.duplicate())
	gm.known[s.id] = true
	return s

func arrive(s: Dictionary) -> void:
	gm.G.strip = s.id
	gm.known[s.id] = true
	if s.type == "haven":
		gm.win()
		return
	var paid := 0
	var n := 0
	var keep: Array = []
	for c in gm.G.contracts:
		if c.dest == s.id and (c.get("type", "") != "rescue" or c.get("stage", "") == "aboard"):
			paid += int(c.reward)
			n += 1
		else:
			keep.append(c)
	gm.G.contracts = keep
	if s.type == "road" and int(gm.G.visits.get(str(s.id), 0)) == 0:
		gm.toast_later(0.9, "No pump and no mechanic out here. Find fuel and get off this road.", "bad")
	if gm.G.mayday and int(gm.G.mayday.id) == s.id:
		var mr: int = gm.G.mayday.reward
		gm.G.cash += mr; gm.G.band += 2; gm.G.ammo += 20; gm.G.mayday = null
		gm.toast_later(0.05, "You made it in time. The survivors pay $%d and press bandages and rounds into your hands." % mr, "good")
	if paid:
		gm.G.cash += paid
		gm.G.stats.deliv += n
		gm.toast("Delivered %s. Paid $%d." % [(str(n) + " loads") if n > 1 else "the load", paid], "good")
	if gm.G.nav == s.id: gm.G.nav = -1
	gm.G.visits[str(s.id)] = int(gm.G.visits.get(str(s.id), 0)) + 1
	gm.G.offers = gm.menu.gen_offers(s)
	gm.enter_ground(s)
	gm.menu.checkpoint()

## Your destination (course you set, or the current job). Maydays have their own marker.
func nav_target():
	if gm.G.nav >= 0: return gm.strip(gm.G.nav)
	if gm.G.contracts.size(): return gm.strip(gm.menu.contract_target(gm.G.contracts[0]))
	return null

## The airfield sending an active mayday, if any (shown in red alongside your destination).
func mayday_target():
	if gm.G == null or gm.G.mayday == null: return null
	return gm.strip(int(gm.G.mayday.id))
