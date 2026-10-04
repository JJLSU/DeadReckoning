class_name World
extends RefCounted
## World generation and terrain queries (CPU side). The GPU shader mirrors terr().

const WORLD := 30000.0

var SEED := 1
var HAVEN := Vector2.ZERO
var RUMOR := Vector2.ZERO
var ROADS: Array = []
var STORMS: Array = []
var strips: Array = []
var START := 0
var TE := 0.5
var TM := 0.5
var game  # Game node, for G.time

func terr(x: float, y: float) -> int:
	TM = 0.5
	if x < 0 or y < 0 or x > WORLD or y > WORLD:
		TE = 0.3
		return 0
	var dh := Vector2(x - HAVEN.x, y - HAVEN.y).length()
	var e := U.fbm(x / 6500.0, y / 6500.0, SEED, 5)
	var edge: float = min(min(x, y), min(WORLD - x, WORLD - y))
	if edge < 1800: e -= (1800 - edge) / 1800.0 * 0.25
	if dh < 1700: e = maxf(e, 0.47)
	TE = e
	if e >= 0.36:
		for r in ROADS:
			if x < r.minx or x > r.maxx or y < r.miny or y > r.maxy: continue
			var tt := clampf(((x - r.x1) * r.dx + (y - r.y1) * r.dy) / r.len2, 0.0, 1.0)
			var ex: float = r.x1 + r.dx * tt - x
			var ey: float = r.y1 + r.dy * tt - y
			var d2 := ex * ex + ey * ey
			if d2 < 400:
				return 12 if (d2 < 9 and (int(floor(tt * r.len / 40.0)) & 1) == 1) else 11
			if d2 < 800: return 13
	if e < 0.36: return 0
	if e < 0.40: return 1
	var rv := absf(U.fbm(x / 8000.0 + 17.3, y / 8000.0 + 3.1, SEED + 99, 3) - 0.5)
	if rv < 0.009 and e < 0.62 and dh > 1700: return 1
	if rv < 0.0125 and e < 0.62 and dh > 1700: return 14
	if e < 0.408: return 2
	if e > 0.70: return 8 if e > 0.75 else 7
	if dh > 1700:
		var tn := U.vnoise(x / 2200.0 + 5, y / 2200.0 + 5, SEED + 55)
		if tn > 0.86 and e < 0.62:
			var gx := int(floor(x / 70.0))
			var gy := int(floor(y / 70.0))
			return 10 if (gx % 4 == 0 or gy % 4 == 0) else 9
	var m := U.fbm(x / 4500.0 + 40, y / 4500.0 + 40, SEED + 7, 4)
	TM = m
	if m > 0.62: return 6
	if m > 0.53: return 5
	if m < 0.43: return 4
	return 3

# ---------------- strips / roads / storms ----------------
func on_runway(s: Dictionary, x: float, y: float, m: float) -> bool:
	var dx: float = x - s.x
	var dy: float = y - s.y
	var c := cos(s.ang)
	var n := sin(s.ang)
	var lx := dx * c + dy * n
	var ly := -dx * n + dy * c
	var mm := m * 14.0
	return absf(lx) < s.len / 2.0 + mm and absf(ly) < s.wid / 2.0 + mm

func strip_at(x: float, y: float, m: float):
	for s in strips:
		if on_runway(s, x, y, m): return s
	return null

func road_at(x: float, y: float):
	for r in ROADS:
		var tt := clampf(((x - r.x1) * r.dx + (y - r.y1) * r.dy) / r.len2, 0.0, 1.0)
		if Vector2(r.x1 + r.dx * tt - x, r.y1 + r.dy * tt - y).length() < 24 and tt > 0.02 and tt < 0.98:
			return {"r": r, "t": tt}
	return null

func storm_pos(s: Dictionary) -> Vector2:
	var tm: float = game.G.time if game and game.G else 420.0
	var x := fmod(s.bx + s.vx * tm, WORLD)
	var y := fmod(s.by + s.vy * tm, WORLD)
	if x < 0: x += WORLD
	if y < 0: y += WORLD
	return Vector2(x, y)

func storm_at(x: float, y: float) -> Dictionary:
	var k := 0.0
	var best = null
	for s in STORMS:
		var q := storm_pos(s)
		var d := Vector2(q.x - x, q.y - y).length()
		var v: float = 1.0 - d / s.r
		if v > k:
			k = v
			best = {"s": s, "p": q}
	return {"k": k, "best": best}

func nearest_strip(x: float, y: float, maxd: float):
	var best = null
	var bd := maxd
	for s in strips:
		var d := Vector2(s.x - x, s.y - y).length()
		if d < bd:
			bd = d
			best = s
	return best

func reachable(from: int, hop: float) -> Dictionary:
	var seen := {from: true}
	var q := [from]
	while q.size():
		var a = strips[q.pop_front()]
		for b in strips:
			if seen.has(b.id) or b.type == "haven": continue
			if Vector2(a.x - b.x, a.y - b.y).length() <= hop:
				seen[b.id] = true
				q.append(b.id)
	return seen

func gen_world(seed_v: int) -> void:
	SEED = seed_v
	var rng := U.Mulberry.new(SEED * 7 + 3)
	var R := rng.next
	HAVEN = Vector2(WORLD - 2300 - R.call() * 700, 1900 + R.call() * 800)
	RUMOR = Vector2(HAVEN.x - 600 - R.call() * 1400, HAVEN.y + 600 + R.call() * 1400)
	ROADS = []
	strips = [{"id": 0, "name": "Haven", "type": "haven", "x": HAVEN.x, "y": HAVEN.y, "ang": R.call() * PI, "len": 720.0, "wid": 80.0, "fuel": true, "shop": false, "dealer": false, "danger": 0, "fuelPrice": 0, "seed": 1, "arch": "farm", "home": false}]
	var names := U.shuffle(D.NAMES.duplicate(), R)
	var tries := 0
	while strips.size() < 64 and tries < 9000:
		tries += 1
		var x: float = 1200 + R.call() * (WORLD - 2400)
		var y: float = 1200 + R.call() * (WORLD - 2400)
		if Vector2(x - HAVEN.x, y - HAVEN.y).length() < 13500: continue
		var ok := true
		for s in strips:
			if Vector2(s.x - x, s.y - y).length() < 2300:
				ok = false
				break
		if not ok: continue
		var r: float = R.call()
		var type := "dirt" if r < 0.52 else ("regional" if r < 0.86 else "airport")
		var ln := 320.0 if type == "dirt" else (440.0 if type == "regional" else 600.0)
		var wd := 36.0 if type == "dirt" else (48.0 if type == "regional" else 64.0)
		var ang: float = R.call() * PI
		var k := -1.0
		while k <= 1.0:
			var t := terr(x + cos(ang) * ln / 2 * k, y + sin(ang) * ln / 2 * k)
			if t <= 2 or t >= 7:
				ok = false
				break
			k += 0.5
		if not ok: continue
		var nm: String = names[strips.size() - 1] if strips.size() - 1 < names.size() else ("Field " + str(strips.size()))
		var sf: Array = D.SUF[type]
		var nm2: String = nm + " " + sf[int(R.call() * sf.size())]
		var fuel: bool = type != "dirt" or R.call() < 0.3
		strips.append({"id": strips.size(), "name": nm2, "type": type, "x": x, "y": y, "ang": ang, "len": ln, "wid": wd,
			"fuel": fuel, "shop": type != "dirt", "dealer": type == "airport",
			"fuelPrice": 3 if type == "airport" else (4 if type == "regional" else 5), "seed": int(R.call() * 1e9), "danger": 1, "arch": "farm", "home": false})
	var best := 1e18
	for s in strips:
		if s.type == "haven": continue
		var d := Vector2(s.x - 2600, s.y - (WORLD - 2600)).length()
		if d < best:
			best = d
			START = s.id
	var st: Dictionary = strips[START]
	st.fuel = true
	st.fuelPrice = 4
	st.home = true
	var pool := strips.filter(func(s): return s.type != "haven")
	var kk := 0
	var q := 0
	while kk < 16 and q < 300:
		q += 1
		var a = pool[int(R.call() * pool.size())]
		var cands := pool.filter(func(b):
			var d := Vector2(b.x - a.x, b.y - a.y).length()
			return b != a and d > 2500 and d < 7500)
		if cands.is_empty(): continue
		var b = cands[int(R.call() * cands.size())]
		var an := atan2(b.y - a.y, b.x - a.x)
		var px := -sin(an) * 320
		var py := cos(an) * 320
		var x1: float = a.x + px - cos(an) * 600
		var y1: float = a.y + py - sin(an) * 600
		var x2: float = b.x + px + cos(an) * 600
		var y2: float = b.y + py + sin(an) * 600
		var dx := x2 - x1
		var dy := y2 - y1
		var len2 := dx * dx + dy * dy
		ROADS.append({"x1": x1, "y1": y1, "x2": x2, "y2": y2, "dx": dx, "dy": dy, "len2": len2, "len": sqrt(len2), "ang": atan2(dy, dx),
			"minx": minf(x1, x2) - 22, "maxx": maxf(x1, x2) + 22, "miny": minf(y1, y2) - 22, "maxy": maxf(y1, y2) + 22, "name": "Route " + str(2 + int(R.call() * 97))})
		kk += 1
	STORMS = []
	kk = 0
	q = 0
	while kk < 20 and q < 200:
		q += 1
		var x: float = R.call() * WORLD
		var y: float = R.call() * WORLD
		if Vector2(x - st.x, y - st.y).length() < 5500: continue
		var vx: float = (R.call() - 0.5) * 30
		var vy: float = (R.call() - 0.5) * 30
		STORMS.append({"bx": x - vx * 420, "by": y - vy * 420, "r": 1500 + R.call() * 1600, "vx": vx, "vy": vy})
		kk += 1
	for s in strips:
		if s.type == "haven": continue
		var d := Vector2(s.x - st.x, s.y - st.y).length()
		var town := 0
		var wat := 0
		for k2 in 8:
			var a := k2 / 8.0 * TAU
			var tt := terr(s.x + cos(a) * 900, s.y + sin(a) * 900)
			if tt == 9 or tt == 10: town = 1
			if tt <= 1: wat = 1
		s.danger = clampi(int(round(1 + d / 9000.0 + town + R.call() * 0.8 - 0.4)), 1, 5)
		var qq: float = R.call()
		if s.type == "dirt":
			s.arch = ("lakeside" if (wat and qq < 0.6) else ("town" if (town and qq < 0.8) else "farm"))
		elif s.type == "regional":
			s.arch = ("town" if (town and qq < 0.7) else ("lakeside" if (wat and qq < 0.35) else "county"))
		else:
			s.arch = "military" if qq < 0.35 else "county"
		if s.arch == "military": s.danger = mini(5, s.danger + 1)
	st.danger = 1
	st.arch = "farm"
	var reach := reachable(START, 6500)
	var has_ap := false
	for s in strips:
		if reach.has(s.id) and s.type == "airport": has_ap = true
	if not has_ap:
		var pick = null
		var pd := 1e18
		for s in strips:
			if not reach.has(s.id) or s.id == START: continue
			var d := Vector2(s.x - st.x, s.y - st.y).length()
			if d > 2500 and d < pd:
				pd = d
				pick = s
		if pick:
			pick.type = "airport"; pick.dealer = true; pick.shop = true; pick.fuel = true; pick.fuelPrice = 3; pick.len = 600.0; pick.wid = 64.0
			pick.name = pick.name.split(" ")[0] + " Regional"
