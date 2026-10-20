class_name World
extends RefCounted
## World generation and terrain queries (CPU side). The GPU shader mirrors terr().

const WORLD := D.WORLD   # land size: set in data.gd
const AIRFIELDS := 180     # airfields generated, not counting Haven (one name each in D.NAMES)
const ROAD_COUNT := 64     # roads generated (must not exceed baker.ROAD_SLOTS / road_p[] in the shader)
const DEADZONE := 13500.0
const WORLD_GEN := 3          # map layout version; 2 keeps airfields out of forests, 3 adds bridges,
							  # dirt-track road ends, no long lake crossings and towns that thin out
const ROAD_TRACK := 380.0     # gen 3: last stretch of each road end that is a narrow dirt track
const BRIDGE_MAX := 280.0     # gen 3: longest water crossing a new road may bridge
const FOREST_MAX := 0.25      # most of an airfield's surroundings that may be forest
# Survivor-held strips: no dead, an armed garrison, no fuel/trade/jobs.
# Chance per strip by danger level (index = danger; 0 is Haven, 1 is the lowest tier).
const HOSTILE_CHANCE := [0.0, 0.0, 0.1, 0.2, 0.3, 0.4]
# Haven rumour rings (one per corner; only one corner really has Haven). Units: 100 = 1 km.
const RING_START_MIN := 5000.0   # each ring starts with a random radius in this range
const RING_START_MAX := 7500.0
const RING_MIN := 1000.0         # rings never shrink below this
const RING_SHRINK := 0.9         # each old chart shrinks one ring to this fraction
const RUMOR_OFF_MIN := 1000.0    # rumour point's offset from the corner spot, per axis.
const RUMOR_OFF_MAX := 3500.0    # (max offset x 1.414 must stay under RING_START_MIN so the spot starts inside)  # no airfields within this distance of each corner's Haven spot
# Small islands in the open ocean around the land (no roads, towns or airfields).
# Mirrored exactly in shaders/terrain.gdshader isle().
const ISLE_SCALE := 1800.0   # noise scale: bigger = bigger, fewer islands
const ISLE_T := 0.76         # noise threshold for land: higher = rarer islands
const ISLE_K := 3.2          # how fast islands rise from the shore (peaks / hills)
const ISLE_GAP := 3000.0     # islands fade out this close to the mainland's edge
const STORM_DENSITY := 5.0  # storms per 300 x 300 km, land and ocean alike (originally 20)
const STORM_AREA := 30000.0 * 30000.0

var SEED := 1
var HAVEN := Vector2.ZERO
var RUMOR := Vector2.ZERO   # (old single rumour point, no longer shown)
var RUMORS: Array = []      # rumour point per corner (same order as CORNERS)
var RING0: Array = []       # starting ring radius per corner
var ROADS: Array = []
var STORMS: Array = []
var strips: Array = []
var START := 0
var GEN := WORLD_GEN   # layout version of the current world
var TE := 0.5
var TM := 0.5
var game  # Game node, for G.time
static var HAVEN_DIR := "NE"   # which corner Haven is in: NE, NW, SE or SW
var CORNERS: Array = []         # Haven-style spot at each corner (one of them is Haven)
var PAD := 0.0   # open-ocean margin around the land, set by Game before gen_world()
var _sp_t := -1.0
var _sp := PackedVector2Array()

## Ocean outside the land square: open water with the odd small island.
func isle(x: float, y: float) -> int:
	TM = 0.5
	var f := U.fbm(x / ISLE_SCALE, y / ISLE_SCALE, SEED + 311, 4)
	var dout := maxf(maxf(-x, x - WORLD), maxf(-y, y - WORLD))
	if dout < ISLE_GAP: f -= (ISLE_GAP - dout) / ISLE_GAP * 0.2
	var e := maxf(0.3, 0.36 + (f - ISLE_T) * ISLE_K)
	TE = e
	if e < 0.36: return 0
	if e < 0.40: return 1
	if e < 0.408: return 2
	if e > 0.70: return 8 if e > 0.75 else 7
	var m := U.fbm(x / 4500.0 + 40, y / 4500.0 + 40, SEED + 7, 4)
	TM = m
	if m > 0.62: return 6
	if m > 0.53: return 5
	if m < 0.43: return 4
	return 3

func terr(x: float, y: float) -> int:
	TM = 0.5
	if x < 0 or y < 0 or x > WORLD or y > WORLD:
		return isle(x, y)
	var dh := Vector2(x - HAVEN.x, y - HAVEN.y).length()
	var e := U.fbm(x / 6500.0, y / 6500.0, SEED, 5)
	var edge: float = min(min(x, y), min(WORLD - x, WORLD - y))
	if edge < 1800: e -= (1800 - edge) / 1800.0 * 0.25
	if dh < 1700: e = maxf(e, 0.47)
	TE = e
	if e >= 0.36 or GEN >= 3:   # gen 3 roads carry on over water as bridges
		for r in ROADS:
			if x < r.minx or x > r.maxx or y < r.miny or y > r.maxy: continue
			var tt := clampf(((x - r.x1) * r.dx + (y - r.y1) * r.dy) / r.len2, 0.0, 1.0)
			var ex: float = r.x1 + r.dx * tt - x
			var ey: float = r.y1 + r.dy * tt - y
			var d2 := ex * ex + ey * ey
			if GEN >= 3:
				var de: float = minf(tt, 1.0 - tt) * r.len
				if de < ROAD_TRACK:   # the road peters out into a dirt track that fades away
					if d2 < 36 and U.hash3(int(x) >> 3, int(y) >> 3, SEED + 65) < de / 60.0: return 13
					continue
				if de < ROAD_TRACK + 160:   # and narrows before it gets there
					var k := (de - ROAD_TRACK) / 160.0
					d2 /= (0.4 + 0.6 * k) * (0.4 + 0.6 * k)
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
		if tn > (0.8 if GEN >= 3 else 0.86) and e < 0.62:
			var gx := int(floor(x / 70.0))
			var gy := int(floor(y / 70.0))
			var street := gx % 4 == 0 or gy % 4 == 0
			if GEN < 3: return 10 if street else 9
			# gen 3: blocks thin out toward the edge, down to the odd house on open ground
			var p := smoothstep(0.82, 0.88, tn + (U.vnoise(x / 600.0, y / 600.0, SEED + 57) - 0.5) * 0.04) * smoothstep(0.62, 0.58, e)
			if street:
				if p > 0.3 + U.hash3(int(floor(gx / 4.0)), int(floor(gy / 4.0)), SEED + 59) * 0.4: return 10
			elif U.hash3(gx, gy, SEED + 61) < p: return 9
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

## Storms drift and wrap around the whole map, land plus ocean margin. Positions are
## worked out once per game-time tick and cached (there are hundreds of storms now).
func storm_pos(s: Dictionary) -> Vector2:
	var tm: float = game.G.time if game and game.G else 420.0
	if tm != _sp_t or _sp.size() != STORMS.size():
		_sp_t = tm
		_sp.resize(STORMS.size())
		var span := WORLD + 2.0 * PAD
		for i in STORMS.size():
			var t: Dictionary = STORMS[i]
			var x := fposmod(t.bx + t.vx * tm + PAD, span) - PAD
			var y := fposmod(t.by + t.vy * tm + PAD, span) - PAD
			_sp[i] = Vector2(x, y)
	return _sp[int(s.i)]

func storm_at(x: float, y: float) -> Dictionary:
	var k := 0.0
	var best = null
	for s in STORMS:
		var q := storm_pos(s)
		if absf(q.x - x) > s.r or absf(q.y - y) > s.r: continue
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

## Storms out over the ocean margin, at STORM_DENSITY like the land. Also adds any land
## storms beyond the original 20 when the density is set above 20. Uses its own random
## stream so the land (airfields, danger levels...) is unchanged.
func _add_ocean_storms(extra_land: int, st: Dictionary) -> void:
	var orng := U.Mulberry.new(SEED * 13 + 101)
	var R := orng.next
	var added := 0
	var t := 0
	while added < extra_land and t < extra_land * 10:
		t += 1
		var lx: float = R.call() * WORLD
		var ly: float = R.call() * WORLD
		if Vector2(lx - st.x, ly - st.y).length() < 5500: continue
		var lvx: float = (R.call() - 0.5) * 30
		var lvy: float = (R.call() - 0.5) * 30
		STORMS.append({"bx": lx - lvx * 420, "by": ly - lvy * 420, "r": 1500 + R.call() * 1600, "vx": lvx, "vy": lvy, "i": STORMS.size()})
		added += 1
	_sp_t = -1.0
	if PAD <= 0.0: return
	var span := WORLD + 2.0 * PAD
	var n := int(round(STORM_DENSITY * (span * span - WORLD * WORLD) / STORM_AREA))
	var placed := 0
	var q := 0
	while placed < n and q < n * 4:
		q += 1
		var x: float = -PAD + R.call() * span
		var y: float = -PAD + R.call() * span
		if x > 0 and y > 0 and x < WORLD and y < WORLD: continue
		var vx: float = (R.call() - 0.5) * 30
		var vy: float = (R.call() - 0.5) * 30
		STORMS.append({"bx": x - vx * 420, "by": y - vy * 420, "r": 1500 + R.call() * 1600, "vx": vx, "vy": vy, "i": STORMS.size()})
		placed += 1
	_sp_t = -1.0

## A route number (2-98) not used by another road yet, if one is left.
## True when a straight road between these points would cross more than BRIDGE_MAX of
## open water in one go (lakes, sea inlets); rivers and short gaps get bridges.
func _long_water(x1: float, y1: float, x2: float, y2: float) -> bool:
	var ln := Vector2(x2 - x1, y2 - y1).length()
	var n := int(ln / 40.0)
	var run := 0.0
	for i in n + 1:
		var t := float(i) / maxf(1.0, n)
		var x := x1 + (x2 - x1) * t
		var y := y1 + (y2 - y1) * t
		if _wet(x, y):
			run += 40.0
			if run > BRIDGE_MAX: return true
		else:
			run = 0.0
	return false

## Open water (sea or lake; rivers don't count) by the same height noise terr() uses.
func _wet(x: float, y: float) -> bool:
	if x < 0 or y < 0 or x > WORLD or y > WORLD: return true
	var e := U.fbm(x / 6500.0, y / 6500.0, SEED, 5)
	var edge: float = min(min(x, y), min(WORLD - x, WORLD - y))
	if edge < 1800: e -= (1800 - edge) / 1800.0 * 0.25
	return e < 0.40

func _route_no(R: Callable, used: Dictionary) -> int:
	var n := 2 + int(R.call() * 97)
	for _t in 97:
		if not used.has(n): break
		n = 2 + (n - 1) % 97
	used[n] = true
	return n

## Where ring i is drawn for current radius r: it slides from its rumour point toward
## its corner's spot as it shrinks (the same for all four, so the real one doesn't stand out).
func ring_center(i: int, r: float) -> Vector2:
	var q: float = clampf(1.0 - r / float(RING0[i]), 0.0, 1.0)
	return (RUMORS[i] as Vector2).lerp(CORNERS[i], q)

## "northeast" etc. for Haven's corner, for notes and objectives.
static func haven_dir_name() -> String:
	return {"NE": "northeast", "NW": "northwest", "SE": "southeast", "SW": "southwest"}[HAVEN_DIR]

## True when an airfield here would sit in forest: forest anywhere on the runway, or
## more than FOREST_MAX of the ground around it out to 600 units. Forest edges are fine.
## edges false checks only the runway (a crowded map that ran short of open ground).
func in_forest(x: float, y: float, ang: float, ln: float, edges: bool = true) -> bool:
	var k := -1.0
	while k <= 1.0:
		# terr()'s forest noise alone: above 0.53 it is forest or ground no runway can use
		if U.fbm((x + cos(ang) * ln / 2 * k) / 4500.0 + 40, (y + sin(ang) * ln / 2 * k) / 4500.0 + 40, SEED + 7, 4) > 0.53: return true
		k += 0.125
	if not edges: return false
	var nf := 0
	for r in [300.0, 600.0]:
		for i in 12:
			var a := i / 12.0 * TAU
			var t := terr(x + cos(a) * r, y + sin(a) * r)
			if t == 5 or t == 6: nf += 1
	return nf > int(24 * FOREST_MAX)

## gen 1 is the original layout, kept for runs saved before airfields avoided forest.
func gen_world(seed_v: int, gen: int = WORLD_GEN) -> void:
	SEED = seed_v
	GEN = gen
	var rng := U.Mulberry.new(SEED * 7 + 3)
	var R := rng.next
	# Haven sits near one of the four corners, picked at random. The same inset is used
	# at every corner, and each corner gets the airfield-free dead zone around it.
	var ix: float = 2300 + R.call() * 700
	var iy: float = 1900 + R.call() * 800
	CORNERS = [Vector2(WORLD - ix, iy), Vector2(ix, iy), Vector2(WORLD - ix, WORLD - iy), Vector2(ix, WORLD - iy)]
	var hc := int(R.call() * 4) % 4
	HAVEN = CORNERS[hc]
	HAVEN_DIR = ["NE", "NW", "SE", "SW"][hc]
	var inx := -1.0 if HAVEN.x > WORLD / 2 else 1.0   # pointing back toward the middle
	var iny := -1.0 if HAVEN.y > WORLD / 2 else 1.0
	RUMOR = Vector2(HAVEN.x + inx * (600 + R.call() * 1400), HAVEN.y + iny * (600 + R.call() * 1400))
	# Rumour rings: one per corner, each with its own rumour point and starting size.
	# Own random stream so the rest of the world generation is unaffected.
	var hrng := U.Mulberry.new(SEED * 17 + 5)
	var HR := hrng.next
	RUMORS = []
	RING0 = []
	for c in CORNERS:
		var sx := -1.0 if c.x > WORLD / 2 else 1.0
		var sy := -1.0 if c.y > WORLD / 2 else 1.0
		var ox: float = RUMOR_OFF_MIN + HR.call() * (RUMOR_OFF_MAX - RUMOR_OFF_MIN)
		var oy: float = RUMOR_OFF_MIN + HR.call() * (RUMOR_OFF_MAX - RUMOR_OFF_MIN)
		RUMORS.append(Vector2(c.x + sx * ox, c.y + sy * oy))
		RING0.append(RING_START_MIN + HR.call() * (RING_START_MAX - RING_START_MIN))
	ROADS = []
	strips = [{"id": 0, "name": "Haven", "type": "haven", "x": HAVEN.x, "y": HAVEN.y, "ang": R.call() * PI, "len": 720.0, "wid": 80.0, "fuel": true, "shop": false, "dealer": false, "danger": 0, "fuelPrice": 0, "seed": 1, "arch": "farm", "home": false}]
	var names := U.shuffle(D.NAMES.duplicate(), R)
	var tries := 0
	var near := {}   # 2300-unit grid of placed airfields, for the spacing check
	while strips.size() < AIRFIELDS + 1 and tries < (30000 if GEN < 2 else 120000):
		tries += 1
		var x: float = 1200 + R.call() * (WORLD - 2400)
		var y: float = 1200 + R.call() * (WORLD - 2400)
		var ok := true
		for c in CORNERS:
			if Vector2(x - c.x, y - c.y).length() < DEADZONE: ok = false
		if not ok: continue
		var gc := Vector2i(int(floor(x / 2300)), int(floor(y / 2300)))
		for nx in range(gc.x - 1, gc.x + 2):
			for ny in range(gc.y - 1, gc.y + 2):
				for s in near.get(Vector2i(nx, ny), []):
					if Vector2(s.x - x, s.y - y).length() < 2300: ok = false
		if not ok: continue
		# quick reject: where terr()'s forest noise is above 0.53 the centre is forest or
		# some other ground an airfield can't use, so skip the full check
		if GEN >= 2 and U.fbm(x / 4500.0 + 40, y / 4500.0 + 40, SEED + 7, 4) > 0.53: continue
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
		if GEN >= 2 and in_forest(x, y, ang, ln, tries < 40000): continue
		var nm: String = names[strips.size() - 1] if strips.size() - 1 < names.size() else ("Field " + str(strips.size()))
		var sf: Array = D.SUF[type]
		var nm2: String = nm + " " + sf[int(R.call() * sf.size())]
		var fuel: bool = type != "dirt" or R.call() < 0.3
		strips.append({"id": strips.size(), "name": nm2, "type": type, "x": x, "y": y, "ang": ang, "len": ln, "wid": wd,
			"fuel": fuel, "shop": type != "dirt", "dealer": type == "airport",
			"fuelPrice": 3 if type == "airport" else (4 if type == "regional" else 5), "seed": int(R.call() * 1e9), "danger": 1, "arch": "farm", "home": false})
		if not near.has(gc): near[gc] = []
		near[gc].append(strips[-1])
	var best := 1e18
	for s in strips:
		if s.type == "haven": continue
		var d := Vector2(s.x - WORLD / 2, s.y - WORLD / 2).length()   # start near the middle
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
	var linked := {}     # airfield pairs that already have a road
	var route_nos := {}  # route numbers already used
	while kk < ROAD_COUNT and q < 3000:
		q += 1
		var a = pool[int(R.call() * pool.size())]
		var cands := pool.filter(func(b):
			var d := Vector2(b.x - a.x, b.y - a.y).length()
			return b != a and d > 2500 and d < 7500)
		if cands.is_empty(): continue
		var b = cands[int(R.call() * cands.size())]
		var pk := "%d-%d" % [mini(a.id, b.id), maxi(a.id, b.id)]
		if linked.has(pk): continue
		linked[pk] = true
		var an := atan2(b.y - a.y, b.x - a.x)
		var px := -sin(an) * 320
		var py := cos(an) * 320
		var x1: float = a.x + px - cos(an) * 600
		var y1: float = a.y + py - sin(an) * 600
		var x2: float = b.x + px + cos(an) * 600
		var y2: float = b.y + py + sin(an) * 600
		if GEN >= 3:
			# pull road ends that run out into water back to the shore
			var cs := cos(an)
			var sn := sin(an)
			var pull := 0.0
			while pull < 600 and _wet(x1, y1):
				x1 += cs * 20; y1 += sn * 20; pull += 20
			pull = 0.0
			while pull < 600 and _wet(x2, y2):
				x2 -= cs * 20; y2 -= sn * 20; pull += 20
			if _long_water(x1, y1, x2, y2): continue
		var dx := x2 - x1
		var dy := y2 - y1
		var len2 := dx * dx + dy * dy
		ROADS.append({"x1": x1, "y1": y1, "x2": x2, "y2": y2, "dx": dx, "dy": dy, "len2": len2, "len": sqrt(len2), "ang": atan2(dy, dx),
			"minx": minf(x1, x2) - 22, "maxx": maxf(x1, x2) + 22, "miny": minf(y1, y2) - 22, "maxy": maxf(y1, y2) + 22, "name": "Route " + str(_route_no(R, route_nos))})
		kk += 1
	STORMS = []
	kk = 0
	q = 0
	# Land storms: STORM_DENSITY of them. This loop always draws the original 20 sets
	# of random numbers so everything generated after it (airfield danger levels and
	# types) stays the same for a given seed; it just keeps fewer when the density is lower.
	var n_land := int(round(STORM_DENSITY * WORLD * WORLD / STORM_AREA))
	while kk < 20 and q < 200:
		q += 1
		var x: float = R.call() * WORLD
		var y: float = R.call() * WORLD
		if Vector2(x - st.x, y - st.y).length() < 5500: continue
		var vx: float = (R.call() - 0.5) * 30
		var vy: float = (R.call() - 0.5) * 30
		var sr: float = 1500 + R.call() * 1600
		if kk < n_land:
			STORMS.append({"bx": x - vx * 420, "by": y - vy * 420, "r": sr, "vx": vx, "vy": vy, "i": STORMS.size()})
		kk += 1
	_add_ocean_storms(n_land - 20, st)
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
	# Survivor-held strips. Never the home field or an airport you can reach from it
	# (so a new run always has somewhere to refuel). Own random stream, so the rest
	# of the world is unaffected.
	var hrng2 := U.Mulberry.new(SEED * 23 + 11)
	var HH := hrng2.next
	for s in strips:
		s.hostile = false
		if s.type == "haven" or s.id == START: continue
		if s.type == "airport" and reach.has(s.id): continue
		if HH.call() < float(HOSTILE_CHANCE[clampi(int(s.danger), 0, HOSTILE_CHANCE.size() - 1)]):
			s.hostile = true
			s.fuel = false
			s.shop = false
			s.dealer = false
	# Family farms: friendly grass strips at low danger (FarmFolk.FAMILY_CHANCE). Own random stream too.
	FarmFolk.pick_farms(self, SEED)
	# Failsafe, the airfield by Greg's farm model, near the middle of the map (failsafe.gd)
	Failsafe.place(self)
	# a farm or Failsafe within reach of home, since nowhere else sells fuel (farm.gd)
	FarmFolk.ensure_near_home(self, SEED)
	# Trade (Greg, 2026-10-19): hangars at zombie and survivor-held fields sell nothing.
	# Family farms sell fuel (plus their farm store), and Failsafe sells everything.
	for s in strips:
		if s.type == "haven": continue
		var fs: bool = s.get("failsafe", false)
		s.fuel = fs or s.get("arch", "") == "family"
		s.shop = fs
		s.dealer = fs
	# what each strip is before any clearing or settling (Fields.apply puts the run's on top)
	Fields.record_base(self)
