class_name SiteGen
extends RefCounted
## Procedural airfield site generation (genSite) and background baking (bakeSite).

const TS := 32.0
const BK := 1.5
const AC := 46
const COLS := 76
const ROWS := 44

var rng: U.Mulberry
var g := PackedByteArray()
var A := "farm"
var ry := 0
var rooms: Array = []
var cars: Array = []
var barrels: Array = []
var silos: Array = []
var lights: Array = []

func R() -> float: return rng.next()
func ri(a: int, b: int) -> int: return a + int(rng.next() * (b - a + 1))
func set_(c: int, r: int, v: int) -> void:
	if c > 0 and r > 0 and c < COLS - 1 and r < ROWS - 1: g[r * COLS + c] = v
func at(c: int, r: int) -> int:
	if c < 0 or r < 0 or c >= COLS or r >= ROWS: return 6
	return g[r * COLS + c]
func free_(c0: int, r0: int, w: int, h: int, ok: Array = [0]) -> bool:
	for r in range(r0, r0 + h):
		for c in range(c0, c0 + w):
			if not ok.has(at(c, r)): return false
	return true
func rect_(c0: int, r0: int, w: int, h: int, v: int) -> void:
	for r in range(r0, r0 + h):
		for c in range(c0, c0 + w): set_(c, r, v)
func place(w: int, h: int, m: int = 2, ok = null, area = null):
	if ok == null: ok = [0]
	if area == null: area = [2, 2, AC - 3, ry - 3]
	for q in 200:
		var c := ri(area[0], area[2] - w)
		var r := ri(area[1], area[3] - h)
		if free_(c - m, r - m, w + 2 * m, h + 2 * m, ok): return {"c": c, "r": r}
	return null

func box(c0: int, r0: int, w: int, h: int, o: Dictionary = {}) -> void:
	for r in range(r0, r0 + h):
		for c in range(c0, c0 + w):
			var e := r == r0 or r == r0 + h - 1 or c == c0 or c == c0 + w - 1
			set_(c, r, 1 if e else 2)
	var top: bool = o.get("top", false)
	var dw := 4 if o.get("wide", false) else 2
	var dc := c0 + 1 + int(R() * (w - dw - 1))
	var dr := r0 if top else r0 + h - 1
	for k in dw: set_(dc + k, dr, 2)
	if o.get("extra", true) != false and R() < 0.6:
		if R() < 0.5:
			var d := r0 + 1 + int(R() * (h - 3))
			var sd := c0 if R() < 0.5 else c0 + w - 1
			set_(sd, d, 2); set_(sd, d + 1, 2)
		else:
			var d := c0 + 1 + int(R() * (w - 3))
			var r2 := r0 + h - 1 if top else r0
			set_(d, r2, 2); set_(d + 1, r2, 2)
	if o.get("split", false) and w >= 10:
		var n := 2 if w >= 16 else 1
		for k in range(1, n + 1):
			var sc := c0 + int(round(w * k / float(n + 1)))
			for r in range(r0 + 1, r0 + h - 1): set_(sc, r, 1)
			var gp := r0 + 1 + int(R() * (h - 3))
			set_(sc, gp, 2); set_(sc, gp + 1, 2)
	var rf = o.get("roof", null)
	if rf == null:
		var ar: Array = D.ARCHROOF[A]
		rf = ar[int(R() * ar.size())]
	rooms.append({"c": c0, "r": r0, "w": w, "h": h, "n": o.get("loot", [1, 3]), "kind": o.get("kind", "bld"), "mix": o.get("mix", null), "floor": o.get("floor", null),
		"roof": rf, "flat": o.get("flat", D.FLATARCH[A]), "sign": o.get("sign", null), "door": [dc, dr, top], "ra": 1.0})

func box_at(w: int, h: int, o: Dictionary = {}, area = null):
	var q = place(w, h, 2, null, area)
	if q: box(q.c, q.r, w, h, o)
	return q

const CARCOL := ["#6b3a2a", "#4a5560", "#7a6a3a", "#3a4a3a", "#5a2f2f", "#8a8272"]
func car(c: int, r: int, hz: bool, okv = null) -> bool:
	var w := 2 if hz else 1
	var h := 1 if hz else 2
	if not free_(c - 1, r - 1, w + 2, h + 2, okv if okv != null else [0, 11, 9]): return false
	rect_(c, r, w, h, 7)
	cars.append({"c": c, "r": r, "w": w, "h": h, "col": CARCOL[int(R() * 6)]})
	return true
func cars_rand(n: int, okv = null) -> void:
	var i := 0
	var q := 0
	while i < n and q < 300:
		var c := ri(2, AC - 4)
		var r := ri(2, ry - 3)
		if car(c, r, R() < 0.6, okv): i += 1
		q += 1
func barrel(c: int, r: int) -> bool:
	var v := at(c, r)
	if v == 0 or v == 2 or v == 11:
		barrels.append({"x": (c + 0.5) * TS, "y": (r + 0.5) * TS, "hp": 20.0, "dead": false, "fuse": -1.0})
		return true
	return false
func barrels_rand(n: int) -> void:
	var i := 0
	var q := 0
	while i < n and q < 300:
		var c := ri(2, AC - 3)
		if barrel(c, ri(2, ry - 2)): i += 1
		q += 1
func trees(n: int) -> void:
	var i := 0
	var q := 0
	while i < n and q < 900:
		var c := ri(1, AC - 2)
		var r := ri(1, ry - 2)
		var ok := true
		for a in range(-1, 2):
			for b in range(-1, 2):
				if at(c + a, r + b) != 0: ok = false
		if ok and not (c < 14 and r > ry - 5):
			set_(c, r, 5)
			i += 1
		q += 1
func silo(q) -> void:
	if q == null: return
	rect_(q.c, q.r, 2, 2, 13)
	silos.append({"x": (q.c + 1) * TS, "y": (q.r + 1) * TS})

## Builds the site layout. Returns the parts of the site dictionary that genSite builds before baking.
func build(gm, s: Dictionary) -> Dictionary:
	rng = U.Mulberry.new(s.seed if s.seed else s.id * 997 + 7)
	g.resize(COLS * ROWS)
	g.fill(0)
	A = s.get("arch", "farm")
	for c in COLS:
		g[c] = 6; g[(ROWS - 1) * COLS + c] = 6
	for r in ROWS:
		g[r * COLS] = 6; g[r * COLS + COLS - 1] = 6
	ry = ROWS - 8
	for r in range(ry, ry + 4):
		for c in range(2, COLS - 2): set_(c, r, 3)
	var dock_end = null
	var town_info = null
	if A == "lakeside":
		var lx := ri(26, 34); var ly := ri(8, 11); var rx := ri(8, 11); var rY := ri(5, 7)
		for r in range(1, ry - 3):
			for c in range(1, AC - 1):
				var d := pow(float(c - lx) / rx, 2) + pow(float(r - ly) / rY, 2) + (U.hash3(c, r, s.id) - 0.5) * 0.25
				if d < 1: set_(c, r, 8)
		for c in range(lx - rx - 2, lx + 1):
			for r in [ly, ly + 1]:
				if at(c, r) == 8 or at(c, r) == 0: set_(c, r, 12)
		dock_end = [lx, ly]
		box_at(8, 6, {"loot": [2, 3]})
		for k in 3:
			var w := ri(5, 7)
			box_at(w, ri(4, 5), {"loot": [1, 2]})
		cars_rand(ri(1, 3)); barrels_rand(ri(2, 3)); trees(ri(45, 60))
	elif A == "county":
		var tw := ri(16, 20); var th := ri(7, 8); var tc0 := ri(13, AC - 3 - tw); var tr0 := ry - 6 - th
		rect_(12, ry - 5, AC - 14, 4, 11); box(tc0, tr0, tw, th, {"split": true, "loot": [3, 5]})
		box_at(11, 8, {"wide": true, "loot": [2, 3]}, [2, 2, AC - 3, ry - 8]); box_at(4, 4, {"extra": false, "loot": [1, 1]})
		var lw := ri(12, 16); var lh := 7
		var lp = place(lw, lh, 1)
		if lp:
			rect_(lp.c, lp.r, lw, lh, 11)
			for r in [lp.r + 1, lp.r + 4]:
				var c: int = lp.c + 1
				while c < lp.c + lw - 2:
					if R() < 0.7: car(c, r, true, [11])
					c += 3
		var fp = place(4, 2, 1)
		if fp:
			for k in 5: barrel(fp.c + (k % 3), fp.r + int(k / 3))
		cars_rand(2, [0, 11]); trees(ri(10, 16))
	elif A == "military":
		var f0 := 3; var f1 := AC - 4; var g0 := 3; var g1 := ry - 3
		for c in range(f0, f1 + 1):
			set_(c, g0, 6); set_(c, g1, 6)
		for r in range(g0, g1 + 1):
			set_(f0, r, 6); set_(f1, r, 6)
		var gc := ri(16, 26)
		for k in 4: set_(gc + k, g1, 0)
		var gr := ri(8, 16)
		for c in [f0, f1]:
			set_(c, gr, 0); set_(c, gr + 1, 0)
		var area := [f0 + 3, g0 + 3, f1 - 2, g1 - 2]
		for k in 2:
			var w := ri(10, 12)
			box_at(w, 5, {"split": true, "loot": [2, 3]}, area)
		box_at(8, 6, {"wide": true, "loot": [3, 4]}, area)
		for k in 3: box_at(5, 4, {"extra": false, "loot": [1, 2]}, area)
		var nsb := ri(4, 6)
		var k2 := 0
		var q2 := 0
		while k2 < nsb and q2 < 100:
			q2 += 1
			var hz := R() < 0.5
			var ln := ri(3, 5)
			var c := ri(area[0], area[2] - 5)
			var r := ri(area[1], area[3] - 5)
			var ok := true
			for i in range(-1, ln + 1):
				for j in range(-1, 2):
					if at(c + (i if hz else j), r + (j if hz else i)) != 0: ok = false
			if not ok: continue
			for i in ln: set_(c + (i if hz else 0), r + (0 if hz else i), 10)
			k2 += 1
		cars_rand(3); barrels_rand(ri(3, 5)); trees(ri(4, 8))
	elif A == "road":
		var gw := 10; var gh := 6
		var gp = place(gw, gh, 2, null, [2, ry - 14, AC - 3, ry - 3])
		if gp:
			box(gp.c, gp.r, gw, gh, {"loot": [3, 4]})
			for k in 3: barrel(gp.c + 2 + k * 3, gp.r + gh + 1)
		box_at(8, 6, {"loot": [2, 3]}); box_at(6, 5, {"loot": [1, 2]}); cars_rand(ri(6, 9)); barrels_rand(2); trees(ri(25, 35))
	elif A == "town":
		var sr := ri(11, 13)
		rect_(1, sr, AC - 2, 3, 11)
		var c := 3
		while c < AC - 10:
			var w := ri(6, 8); var h := ri(5, 7)
			box(c, sr - h - 1, w, h, {"loot": [1, 3]})
			c += w + ri(1, 2)
		c = 3
		while c < AC - 10:
			var w := ri(6, 8); var h := ri(5, 6)
			if sr + 4 + h < ry - 3: box(c, sr + 4, w, h, {"top": true, "loot": [1, 3]})
			c += w + ri(1, 2)
		var nc := ri(5, 8)
		var k := 0
		var q := 0
		while k < nc and q < 120:
			q += 1
			var cc := ri(2, AC - 4)
			if car(cc, sr + ri(0, 1), true, [11, 0]): k += 1
		barrels_rand(ri(2, 4)); trees(ri(10, 16))
	else:
		var nf := ri(1, 2)
		for k in nf:
			var w := ri(10, 15); var h := ri(6, 9)
			var q = place(w, h, 1)
			if q: rect_(q.c, q.r, w, h, 9)
		var w1 := ri(11, 13)
		box_at(w1, ri(7, 8), {"wide": true, "loot": [2, 4]})
		var w2 := ri(7, 8)
		box_at(w2, 6, {"loot": [1, 3]}); box_at(5, 4, {"loot": [1, 2]})
		silo(place(2, 2, 1)); silo(place(2, 2, 1))
		var pw := ri(8, 12); var ph := ri(5, 7)
		var pp = place(pw, ph, 1)
		if pp:
			for cc in range(pp.c, pp.c + pw):
				set_(cc, pp.r, 6); set_(cc, pp.r + ph - 1, 6)
			for r in range(pp.r, pp.r + ph):
				set_(pp.c, r, 6); set_(pp.c + pw - 1, r, 6)
			var gcc: int = pp.c + ri(1, pw - 3)
			set_(gcc, pp.r + ph - 1, 0); set_(gcc + 1, pp.r + ph - 1, 0)
		cars_rand(2); barrels_rand(ri(2, 4)); trees(ri(18, 26))

	# ================= small town =================
	if true:
		var T0 := AC + 1
		var T1 := COLS - 2
		var only := [0, 5]
		var rect_on := func(c0: int, r0: int, w: int, h: int, v: int) -> void:
			for r in range(r0, r0 + h):
				for c in range(c0, c0 + w):
					if only.has(at(c, r)): set_(c, r, v)
		var sr := ri(8, 11)
		rect_on.call(AC - 3, sr, T1 - AC + 4, 3, 14); rect_on.call(T0, sr - 1, T1 - T0 + 1, 1, 11); rect_on.call(T0, sr + 3, T1 - T0 + 1, 1, 11)
		var vc := ri(T0 + 9, T1 - 10)
		rect_on.call(vc, sr + 3, 2, ry - sr - 3, 14); rect_on.call(vc - 1, sr + 4, 1, ry - sr - 5, 11); rect_on.call(vc + 2, sr + 4, 1, ry - sr - 5, 11)
		var kinds := U.shuffle(D.SHOPS.duplicate(true), R)
		var ki := 0
		var c := T0
		while c + 6 <= T1:
			var w := ri(6, 8); var h := ri(5, 6)
			if c + w > T1: break
			var sh: Dictionary = kinds[ki % kinds.size()]
			ki += 1
			var o := sh.duplicate(); o["loot"] = [2, 3]
			box(c, sr - h - 1, w, h, o)
			c += w + ri(1, 2)
		c = T0
		while c + 6 <= T1:
			var w := ri(6, 8); var h := ri(5, 6)
			if c < vc + 3 and c + w > vc - 1:
				c = vc + 3
				continue
			if c + w > T1: break
			var sh: Dictionary = kinds[ki % kinds.size()]
			ki += 1
			var o := sh.duplicate(); o["loot"] = [2, 3]; o["top"] = true
			box(c, sr + 5, w, h, o)
			c += w + ri(1, 2)
		for hr in [sr + 13, sr + 19]:
			if hr + 5 >= ry - 1: continue
			c = T0
			while c + 5 <= T1:
				var w := ri(5, 7); var h := 5
				if c < vc + 3 and c + w > vc - 1:
					c = vc + 3
					continue
				if c + w > T1: break
				var fl: String = ["#6a4a4a", "#4a5a6a", "#6a6048", "#5a4a3a"][int(R() * 4)]
				var rf: String = D.HOUSEROOF[int(R() * D.HOUSEROOF.size())]
				var top := R() < 0.5
				box(c, hr, w, h, {"kind": "house", "mix": {"dresser": 40, "cabinet": 25, "desk": 20, "crate": 15}, "floor": fl, "roof": rf, "flat": false, "loot": [1, 3], "top": top})
				c += w + ri(2, 3)
		var nc := ri(3, 6)
		var k := 0
		var q := 0
		while k < nc and q < 120:
			q += 1
			var cc := ri(T0, T1 - 2)
			if car(cc, sr + ri(0, 2), true, [11, 14, 0]): k += 1
		k = 0; q = 0
		while k < 3 and q < 40:
			q += 1
			var cc := vc + (0 if R() < 0.5 else 1)
			if car(cc, ri(sr + 6, ry - 4), false, [11, 14, 0]): k += 1
		var x := T0 + 1
		while x < T1:
			if at(x, sr - 1) == 11: lights.append({"x": (x + 0.5) * TS, "y": (sr - 1 + 0.5) * TS, "on": R() < 0.6})
			x += 6
		for kk in 2: barrel(vc + 3 + kk, sr + 4)
		var i := 0
		q = 0
		var nt := ri(8, 14)
		while i < nt and q < 600:
			q += 1
			var c2 := ri(T0, T1); var r2 := ri(2, ry - 2)
			var ok := true
			for a in range(-1, 2):
				for b in range(-1, 2):
					if at(c2 + a, r2 + b) != 0: ok = false
			if ok:
				set_(c2, r2, 5)
				i += 1
		town_info = {"sr": sr, "vc": vc, "T0": T0, "T1": T1}

	var crates: Array = []
	var cid := [0]
	var looted: Array = gm.G.looted.get(str(s.id), [])
	var add_crate := func(c: int, r: int, ty: String) -> void:
		crates.append({"id": cid[0], "x": (c + 0.5) * TS, "y": (r + 0.5) * TS, "open": looted.has(cid[0]) or looted.has(float(cid[0])), "ty": ty, "forced": false, "seen": false, "warnT": -9.0})
		cid[0] += 1
	var mix: Dictionary = D.MIX.get(A, D.MIX.farm)
	for o in rooms:
		var n := ri(o.n[0], o.n[1])
		for k in n:
			for q in 12:
				var c: int = o.c + 1 + int(R() * (o.w - 2))
				var r: int = o.r + 1 + int(R() * (o.h - 2))
				if at(c, r) == 2:
					add_crate.call(c, r, D.wpick(o.mix if o.mix else mix, R))
					break
	for k in 3:
		for q in 40:
			var c := ri(2, COLS - 3); var r := ri(2, ry - 2); var v := at(c, r)
			if v == 0 or v == 11 or v == 9:
				add_crate.call(c, r, "jerry" if R() < 0.5 else "crate")
				break
	if dock_end: add_crate.call(dock_end[0], dock_end[1], "crate")
	var SC := {"house": .14, "guns": .5, "post": .4, "bar": .35, "pharmacy": .25}
	var ST := {"house": .4, "bar": .2}
	for o in rooms:
		var sc: float = SC.get(o.kind, 0.3 if A == "military" else 0.07)
		var st2: float = ST.get(o.kind, 0.06)
		for pair in [["safe", sc], ["stash", st2]]:
			if R() >= pair[1]: continue
			for q in 14:
				var c: int = o.c + 1 + int(R() * (o.w - 2))
				var r: int = o.r + 1 + int(R() * (o.h - 2))
				if at(c, r) == 2:
					add_crate.call(c, r, pair[0])
					break
	var tc := PackedColorArray()
	tc.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			var v := g[r * COLS + c]
			var gj := (U.vnoise(c / 5.0, r / 5.0, s.id + 3) - 0.5) * 12
			var j := (U.hash3(c, r, s.id + 11) - 0.5) * 5
			var b: Array
			if v == 2: b = [104 + j, 86 + j, 64 + j]
			elif v == 1: b = [40, 36, 31]
			elif v == 3: b = [122 + j, 104 + j, 72 + j] if s.type == "dirt" else [58 + j * .4, 57 + j * .4, 55 + j * .4]
			elif v == 6: b = [76 + gj, 90 + gj, 52 + gj * .6]
			elif v == 8: b = [40 + j * .3, 66 + j * .3, 78 + j * .3]
			elif v == 9: b = [92 + j, 90 + j, 48 + j]
			elif v == 11: b = [88 + j * .5, 86 + j * .5, 80 + j * .5]
			elif v == 12: b = [110 + j, 84 + j, 56 + j]
			elif v == 14: b = [56 + j * .4, 55 + j * .4, 53 + j * .4]
			else: b = [84 + gj, 92 + gj, 52 + gj * .6] if A == "farm" else [76 + gj, 90 + gj, 52 + gj * .6]
			tc[r * COLS + c] = U.rgb(int(b[0]), int(b[1]), int(b[2]))
	for r in ROWS:
		for c in COLS:
			if g[r * COLS + c] != 7: continue
			var pick = null
			for d in [[0, -1], [0, 1], [-1, 0], [1, 0], [0, -2], [0, 2], [-2, 0], [2, 0]]:
				var q := at(c + d[0], r + d[1])
				if q == 7 or q == 6: continue
				if pick == null or q == 14 or (q == 11 and pick[0] != 14): pick = [q, (r + d[1]) * COLS + c + d[0]]
			if pick: tc[r * COLS + c] = tc[pick[1]]
	var plane := Vector2(8 * TS, (ry + 2) * TS)
	var tanker = null
	var visits: int = int(gm.G.visits.get(str(s.id), 0))
	if not (s.get("home", false) and visits <= 1) and (not s.fuel or R() < 0.3) and R() < 0.7:
		for q in 60:
			var c := ri(4, COLS - 8); var r := ri(3, ry - 3)
			var ok := true
			for a in range(-2, 6):
				for b2 in range(-2, 3):
					var v2 := at(c + a, r + b2)
					if not (v2 == 0 or v2 == 11 or v2 == 14): ok = false
			if ok:
				tanker = {"x": (c + 2) * TS, "y": (r + 0.5) * TS, "gal": 10 + s.danger * 2, "prog": 0.0}
				for a in 4: set_(c + a, r, 7)
				break
	return {"tanker": tanker, "lights": lights, "town": town_info, "arch": A, "cols": COLS, "rows": ROWS, "g": g, "tc": tc, "rooms": rooms, "ry": ry,
		"crates": crates, "plane": plane, "cars": cars, "barrels": barrels, "silos": silos}


# =====================================================================
# Background bake (port of bakeSite). Drawn once into a SubViewport.
# =====================================================================
static func bake_draw(g: Pen, st: Dictionary) -> void:
	g.scale(BK, BK)
	var cols: int = st.cols
	var rows: int = st.rows
	var G1: PackedByteArray = st.g
	var tc: PackedColorArray = st.tc
	var ry: int = st.ry
	var sid: int = st.s.id
	var at := func(cc: int, r: int) -> int:
		if cc < 0 or r < 0 or cc >= cols or r >= rows: return 6
		return G1[r * cols + cc]
	var H1 := func(a: int, b: int, k: int) -> float: return U.hash3(a, b, sid * 7 + k)
	var dirt: bool = st.s.type == "dirt"
	for r in rows:
		for cc in cols:
			var i := r * cols + cc
			var v := G1[i]
			var x := cc * TS
			var y := r * TS
			g.rect(x, y, TS + 0.5, TS + 0.5, tc[i])
			if v == 0 or v == 5 or v == 7 or v == 10 or v == 13:
				for k in 7:
					var px: float = x + H1.call(cc * 9 + k, r, 1) * TS
					var py: float = y + H1.call(cc, r * 9 + k, 2) * TS
					var l: float = H1.call(cc + k, r + k, 3)
					g.rect(px, py, 2 + l * 3, 2 + l * 3, Color(0, 0, 0, .09) if l < .5 else Color(1, 1, 200 / 255.0, .06))
				if H1.call(cc, r, 4) < .35:
					var tx: float = x + H1.call(cc, r, 5) * TS
					var ty: float = y + H1.call(cc, r, 6) * TS
					var ln := PackedVector2Array()
					for k in range(-2, 3):
						ln.append(Vector2(tx + k * 2, ty)); ln.append(Vector2(tx + k * 3, ty - 5 - absi(k)))
					g.lines(ln, U.rgb(40, 56, 26, .55), 1)
			elif v == 2:
				for k in 4: g.rect(x, y + k * 8, TS, 1, Color(0, 0, 0, .14))
				var off: float = H1.call(cc, r, 7) * TS
				for k in 4: g.rect(x + fmod(off + k * 13, TS), y + k * 8, 1, 8, Color(0, 0, 0, .14))
				g.rect(x, y, TS, TS, U.rgb(255, 230, 190, H1.call(cc, r, 8) * .07))
			elif v == 3:
				if dirt:
					if r == ry + 1 or r == ry + 2: g.rect(x, y + (20 if r == ry + 1 else 6), TS, 5, U.rgb(60, 45, 25, .2))
					if H1.call(cc, r, 19) < .3: g.rect(x + H1.call(cc, r, 20) * 24, y + H1.call(cc, r, 21) * 24, 6, 4, U.rgb(90, 110, 50, .25))
				else:
					for k in 10:
						g.rect(x + H1.call(cc, r * 3 + k, 10) * TS, y + H1.call(cc + k, r, 11) * TS, 2, 2, Color(0, 0, 0, .12) if H1.call(cc * 3 + k, r, 9) < .5 else Color(1, 1, 1, .05))
					if H1.call(cc, r, 22) < .08:
						g.polyline(PackedVector2Array([Vector2(x + 4, y + 8), Vector2(x + 14, y + 16), Vector2(x + 26, y + 13)]), Color(0, 0, 0, .25), 1)
			elif v == 11:
				if cc % 2 == 0: g.rect(x, y, 1, TS, Color(0, 0, 0, .13))
				if r % 2 == 0: g.rect(x, y, TS, 1, Color(0, 0, 0, .13))
				if H1.call(cc, r, 12) < .15: g.ellipse(x + 16, y + 16, 10, 6, H1.call(cc, r, 13) * 3, U.rgb(30, 25, 20, .22))
			elif v == 8:
				var edge := false
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var q: int = at.call(cc + d[0], r + d[1])
					if q != 8 and q != 12: edge = true
				g.rect(x, y, TS, TS, U.rgb(120, 110, 80, .35) if edge else U.rgb(0, 10, 20, .16))
				var wy: float = y + H1.call(cc, r, 14) * TS
				var wp := PackedVector2Array([Vector2(x + 4, wy)])
				wp.append_array(Tx._quad_path(Vector2(x + 4, wy), Vector2(x + 16, wy - 3), Vector2(x + 28, wy), 6))
				g.polyline(wp, U.rgb(190, 215, 225, .14), 1)
			elif v == 9:
				g.rect(x, y + 3, TS, 5, U.rgb(40, 50, 18, .45)); g.rect(x, y + 19, TS, 5, U.rgb(40, 50, 18, .45))
				for k in 4:
					g.rect(x + k * 8 + 2, y + 4, 3, 3, U.rgb(150, 160, 80, .55)); g.rect(x + k * 8 + 6, y + 20, 3, 3, U.rgb(150, 160, 80, .55))
			elif v == 12:
				for k in range(1, 4): g.rect(x + k * 8, y, 1.2, TS, U.rgb(40, 28, 16, .5))
				if at.call(cc, r + 1) == 8: g.rect(x, y + TS - 3, TS, 3, Color(0, 0, 0, .3))
	if not dirt:
		var wc := U.rgb(226, 219, 198, .75)
		var x := 3 * TS
		while x < (cols - 3) * TS:
			g.rect(x, (ry + 2) * TS - 2, 44, 4, wc)
			x += 90
		for k in 6:
			g.rect(3 * TS, ry * TS + 10 + k * 19, 40, 7, wc); g.rect((cols - 3) * TS - 40, ry * TS + 10 + k * 19, 40, 7, wc)
		g.rect(2 * TS, ry * TS + 3, (cols - 4) * TS, 2, U.rgb(226, 219, 198, .4)); g.rect(2 * TS, (ry + 4) * TS - 5, (cols - 4) * TS, 2, U.rgb(226, 219, 198, .4))
	for r in rows:
		for cc in cols:
			var v := G1[r * cols + cc]
			if v == 1 or v == 10: g.rect(cc * TS + 5, r * TS + 7, TS, TS, Color(0, 0, 0, .3))
	for r in rows:
		for cc in cols:
			if G1[r * cols + cc] == 5: g.ellipse((cc + .5) * TS + 9, (r + .5) * TS + 12, 30, 24, 0, U.rgb(10, 18, 8, .33))
	for r in rows:
		for cc in cols:
			var v := G1[r * cols + cc]
			var x := cc * TS
			var y := r * TS
			if v == 1:
				g.rect(x, y, TS, TS, U.hx("#3a332b"))
				var c1 := U.hx("#5b4f41")
				if at.call(cc, r - 1) != 1: g.rect(x, y, TS, 6, c1)
				if at.call(cc - 1, r) != 1: g.rect(x, y, 4, TS, c1)
				var c2 := U.hx("#221d18")
				if at.call(cc, r + 1) != 1: g.rect(x, y + TS - 4, TS, 4, c2)
				if at.call(cc + 1, r) != 1: g.rect(x + TS - 3, y, 3, TS, c2)
				g.rect(x + int(H1.call(cc, r, 15) * 20), y + 12, 9, 1, Color(0, 0, 0, .2))
			elif v == 6:
				var ln := PackedVector2Array()
				if at.call(cc + 1, r) == 6:
					ln.append_array([Vector2(x + 16, y + 14), Vector2(x + 48, y + 14), Vector2(x + 16, y + 19), Vector2(x + 48, y + 19)])
				if at.call(cc, r + 1) == 6:
					ln.append_array([Vector2(x + 14, y + 16), Vector2(x + 14, y + 48), Vector2(x + 19, y + 16), Vector2(x + 19, y + 48)])
				g.lines(ln, U.rgb(160, 150, 130, .55), 1)
				g.rect(x + 16, y + 18, 6, 4, Color(0, 0, 0, .3))
				g.rect(x + 13, y + 13, 6, 6, U.hx("#4d4135"))
			elif v == 10:
				for k in 3: g.rr(x + 1 + k * 10, y + 7, 10, 17, 4, U.hx("#8f8058"))
				for k in 3: g.rect(x + 3 + k * 10, y + 9, 6, 3, Color(1, 1, 1, .13))
				for k in 3: g.stroke_rr(x + 1 + k * 10, y + 7, 10, 17, 4, Color(0, 0, 0, .25), 1)
	for k in st.cars:
		var x: float = k.c * TS + 3
		var y: float = k.r * TS + 3
		var w: float = k.w * TS - 6
		var h: float = k.h * TS - 6
		var hz: bool = k.w > 1
		var kc := U.hx(k.col)
		g.rr(x + 5, y + 6, w, h, 8, Color(0, 0, 0, .35))
		var pts := g.rr_pts(x, y, w, h, 8)
		var stops := [[0.0, U.shade(kc, 1.3)], [0.5, kc], [1.0, U.shade(kc, .65)]]
		Tx._grad_poly(g, pts, stops, Vector2(0, 1) if hz else Vector2(1, 0), y if hz else x, (y + h) if hz else (x + w))
		var dk := U.rgb(18, 22, 26, .9)
		if hz:
			g.rr(x + w * .24, y + 4, w * .16, h - 8, 3, dk); g.rr(x + w * .64, y + 5, w * .1, h - 10, 3, dk)
			g.rect(x + w * .41, y + 5, w * .22, h - 10, U.shade(kc, 1.12))
		else:
			g.rr(x + 4, y + h * .24, w - 8, h * .16, 3, dk); g.rr(x + 5, y + h * .64, w - 10, h * .1, 3, dk)
			g.rect(x + 5, y + h * .41, w - 10, h * .22, U.shade(kc, 1.12))
		for q in 3: g.circle(x + H1.call(k.c, q, 16) * w, y + H1.call(k.r, q, 17) * h, 2 + H1.call(q, k.c, 18) * 4, U.rgb(120, 60, 30, .45))
		var lc := U.rgb(240, 230, 180, .5)
		if hz:
			g.rect(x + w - 3, y + 3, 2, 4, lc); g.rect(x + w - 3, y + h - 7, 2, 4, lc)
		else:
			g.rect(x + 3, y + h - 3, 4, 2, lc); g.rect(x + w - 7, y + h - 3, 4, 2, lc)
	for si in st.silos:
		g.circle(si.x + 7, si.y + 9, TS * .95, Color(0, 0, 0, .35))
		g.radial(si.x, si.y, [[4.0, U.hx("#c2c8cc")], [TS * .95, U.hx("#6b7278")]], 32, Vector2(-10, -10))
		for k in range(1, 4): g.ring(si.x, si.y, TS * .95 * k / 4.0, U.rgb(40, 44, 48, .5), 1.5)
		g.circle(si.x, si.y, 5, U.hx("#50565c"))
	for rm in st.rooms:
		if rm.floor == null: continue
		var fl: String = rm.floor
		for r in range(rm.r + 1, rm.r + rm.h - 1):
			for cc in range(rm.c + 1, rm.c + rm.w - 1):
				if G1[r * cols + cc] != 2: continue
				var x := cc * TS
				var y := r * TS
				if fl.begins_with("checker"):
					var cA: Array = ["#d8d6cf", "#a9aaa6"] if fl == "checker" else (["#d8d6cf", "#5e7a5a"] if fl == "checker2" else ["#d8d6cf", "#8a3a2a"])
					for a in 2:
						for b in 2: g.rect(x + a * 16, y + b * 16, 16, 16, U.hx(cA[(a + b) & 1]))
					g.rect(x, y, TS, TS, U.rgb(60, 50, 40, .12))
				else:
					g.rect(x, y, TS, TS, U.hx(fl))
					for k in 6: g.rect(x + H1.call(cc, r * 5 + k, 32) * TS, y + H1.call(cc + k, r, 33) * TS, 3, 3, Color(0, 0, 0, .05 + H1.call(cc * 5 + k, r, 31) * .07))
	for l in st.lights:
		g.circle(l.x + 3, l.y + 4, 4, Color(0, 0, 0, .35))
		g.circle(l.x, l.y, 3.5, U.hx("#2e2e2c"))
		g.rect(l.x, l.y - 1.5, 12, 3, U.hx("#2e2e2c"))
		g.rect(l.x + 10, l.y - 3, 5, 6, U.hx("#e8dca0") if l.on else U.hx("#555555"))
	for k in 110:
		var cc := 1 + int(H1.call(k, 1, 61) * (cols - 2))
		var r := 1 + int(H1.call(k, 2, 62) * (rows - 2))
		var v := G1[r * cols + cc]
		if not (v == 0 or v == 3 or v == 11 or v == 14): continue
		var x: float = cc * TS + H1.call(k, 3, 63) * TS
		var y: float = r * TS + H1.call(k, 4, 64) * TS
		var ty: float = H1.call(k, 5, 65)
		if ty < .3:
			var lc := ["#8a5a2a", "#a06a2a", "#6a4a22", "#b08a3a"]
			for q in 7:
				var cl := U.hx(lc[q % 4]); cl.a = .7
				g.ellipse(x + H1.call(k, q, 66) * 22 - 11, y + H1.call(q, k, 67) * 16 - 8, 2.6, 1.6, H1.call(k, q, 68) * 3, cl)
		elif ty < .45:
			g.ellipse(x, y, 14 + H1.call(k, 6, 69) * 14, 7 + H1.call(k, 7, 70) * 6, 0, U.rgb(60, 70, 80, .35))
			g.ellipse(x - 3, y - 2, 6, 2, 0, U.rgb(200, 215, 225, .14))
		elif ty < .6:
			for q in 4: g.rect(x + H1.call(k, q, 71) * 14 - 7, y + H1.call(q, k, 72) * 10 - 5, 2 + H1.call(k, q, 73) * 4, 2, U.rgb(120, 116, 108, .8))
			g.rect(x - 2, y + 3, 6, 2, U.rgb(90, 60, 40, .7))
		elif ty < .7:
			g.ring(x, y, 6, U.hx("#1c1c1c"), 3.5)
			g.arc(x - 1, y - 1, 6, 3.6, 5.2, Color(1, 1, 1, .08), 1)
		elif ty < .8:
			g.lines(PackedVector2Array([Vector2(x - 6, y), Vector2(x + 6, y + 1), Vector2(x - 2, y - 4), Vector2(x + 1, y + 5)]), U.rgb(225, 220, 205, .8), 1.6)
		else:
			g.save(); g.translate(x, y); g.rotate(H1.call(k, 8, 74) * 3); g.rect(-4, -3, 8, 6, U.rgb(230, 226, 212, .75)); g.restore()
	if st.town:
		var tw: Dictionary = st.town
		var yc := U.rgb(230, 200, 90, .75)
		var x: float = (tw.T0 - 3) * TS
		while x < (tw.T1 + 1) * TS:
			g.rect(x, (tw.sr + 1.5) * TS - 1.5, 32, 3, yc)
			x += 64
		var y: float = (tw.sr + 4) * TS
		while y < (ry - 1) * TS:
			g.rect((tw.vc + 1) * TS - 1.5, y, 3, 32, yc)
			y += 64
		for r in rows:
			for cc in cols:
				if G1[r * cols + cc] != 14: continue
				for k in 8:
					g.rect(cc * TS + H1.call(cc, r * 3 + k, 52) * TS, r * TS + H1.call(cc + k, r, 53) * TS, 2, 2, Color(0, 0, 0, .12) if H1.call(cc * 3 + k, r, 51) < .5 else Color(1, 1, 1, .04))
		var sx: float = (tw.T0 - 1) * TS
		var sy: float = (tw.sr + 3) * TS + 4
		g.rect(sx + 3, sy + 4, 92, 22, Color(0, 0, 0, .35))
		g.rect(sx, sy, 92, 22, U.hx("#3b5a3a"))
		g.stroke_rect(sx + 2, sy + 2, 88, 18, U.hx("#e8e2d0"), 1)
		g.text_base("WELCOME TO", sx + 46, sy + 9, 8, U.hx("#e8e2d0"), 0, "700")
		g.text_base(String(st.s.name).split(" ")[0].to_upper(), sx + 46, sy + 18, 9, U.hx("#e8e2d0"), 0, "700")
	for rm in st.rooms:
		for q in 3: g.stroke_rect((rm.c + 1) * TS, (rm.r + 1) * TS, (rm.w - 2) * TS, (rm.h - 2) * TS, Color(0, 0, 0, .09), 6 + q * 6)
		var nf := 2 + int(H1.call(rm.c, rm.r, 81) * 3)
		for q in nf:
			var cc: int = rm.c + 1 + int(H1.call(q, rm.c, 82) * (rm.w - 2))
			var r: int = rm.r + 1 + int(H1.call(rm.r, q, 83) * (rm.h - 2))
			if G1[r * cols + cc] != 2: continue
			var x := (cc + .5) * TS
			var y := (r + .5) * TS
			var ty: float = H1.call(q, q, 84 + rm.c)
			g.save(); g.translate(x, y); g.rotate(H1.call(q, rm.r, 85) * TAU)
			var sh := Color(0, 0, 0, .3)
			if ty < .3:
				g.rect(-9, -6, 22, 16, sh); g.rect(-11, -8, 22, 16, U.hx("#5e4228")); g.rect(-11, -8, 22, 3, Color(1, 1, 1, .07))
			elif ty < .55:
				g.rect(-4, -3, 10, 10, sh); g.rect(-6, -5, 10, 10, U.hx("#6a4a30")); g.rect(-6, -5, 10, 3, U.hx("#4a3220"))
			elif ty < .75:
				g.rect(-14, -2, 30, 10, sh); g.rect(-16, -4, 30, 8, U.hx("#55504a"))
				for z in 5: g.rect(-14 + z * 6, -3, 3, 3, U.hx("#8a7a5a"))
			else:
				g.rect(-10, -5, 26, 18, sh); g.rect(-12, -7, 26, 16, U.hx("#b8ae98")); g.ellipse(2, 1, 6, 4, .3, U.rgb(110, 70, 40, .4))
			g.restore()
	var out_f := func(v2: int) -> bool: return v2 == 0 or v2 == 11 or v2 == 14 or v2 == 3 or v2 == 9
	for r in rows:
		for cc in cols:
			if G1[r * cols + cc] != 1: continue
			var x := cc * TS
			var y := r * TS
			var hz = null
			if out_f.call(at.call(cc, r + 1)) and at.call(cc, r - 1) == 2: hz = [0, 1]
			elif out_f.call(at.call(cc, r - 1)) and at.call(cc, r + 1) == 2: hz = [0, -1]
			elif out_f.call(at.call(cc + 1, r)) and at.call(cc - 1, r) == 2: hz = [1, 0]
			elif out_f.call(at.call(cc - 1, r)) and at.call(cc + 1, r) == 2: hz = [-1, 0]
			if hz == null or (cc + r) % 3 != 0: continue
			var q: float = H1.call(cc, r, 86)
			var horiz: bool = hz[0] == 0
			if horiz: g.rect(x + 6, y + 12, 20, 8, U.hx("#4a5a62"))
			else: g.rect(x + 12, y + 6, 8, 20, U.hx("#4a5a62"))
			if q < .3:
				var bc := U.hx("#6a5236")
				if horiz:
					g.rect(x + 3, y + 11, 26, 3, bc); g.rect(x + 3, y + 18, 26, 3, bc)
				else:
					g.rect(x + 11, y + 3, 3, 26, bc); g.rect(x + 18, y + 3, 3, 26, bc)
			else:
				var gl := U.rgb(220, 235, 240, .5)
				if horiz: g.polyline(PackedVector2Array([Vector2(x + 8, y + 13), Vector2(x + 16, y + 19), Vector2(x + 22, y + 13)]), gl, 1)
				else: g.polyline(PackedVector2Array([Vector2(x + 13, y + 8), Vector2(x + 19, y + 16), Vector2(x + 13, y + 22)]), gl, 1)
				if q < .65:
					for z in 5:
						g.rect(x + 16 + hz[0] * (18 + H1.call(z, cc, 87) * 14) + (H1.call(cc, z, 88) - .5) * 16, y + 16 + hz[1] * (18 + H1.call(z, r, 89) * 14) + (H1.call(r, z, 90) - .5) * 16, 2, 1.5, U.rgb(200, 220, 230, .55))
	for k in 7:
		var cc := 1 + int(H1.call(k, 3, 91) * (cols - 2))
		var r := 1 + int(H1.call(k, 4, 92) * (rows - 2))
		var v := G1[r * cols + cc]
		if not (v == 11 or v == 14 or v == 3): continue
		g.save(); g.translate(cc * TS + 16, r * TS + 16); g.rotate((H1.call(k, 5, 93) - .5) * .6)
		g.text_base(D.TAGS[k % D.TAGS.size()], 0, 0, 18, U.rgb(160, 28, 20, .5) if H1.call(k, 6, 94) < .5 else U.rgb(15, 15, 15, .5), 0, "impact")
		g.restore()
	for rm in st.rooms:
		if rm.kind != "house" or H1.call(rm.c, rm.r, 95) > .6: continue
		var dc: int = rm.door[0]
		var dr: int = rm.door[1]
		var top: bool = rm.door[2]
		var x := (dc + 2.4) * TS
		var y := dr * TS - 10 if top else (dr + 1) * TS + 12
		g.save(); g.translate(x, y)
		g.lines(PackedVector2Array([Vector2(-8, -8), Vector2(8, 8), Vector2(8, -8), Vector2(-8, 8)]), U.rgb(210, 90, 30, .7), 2.5)
		g.text_base(str(int(H1.call(rm.c, 1, 96) * 4)), 0, -10, 7, U.rgb(210, 90, 30, .75), 0, "700")
		g.restore()
	for k in 5:
		var x: float = H1.call(k, 7, 97) * cols * TS
		var y: float = H1.call(k, 8, 98) * (rows - 6) * TS
		var a: float = H1.call(k, 9, 99) * TAU
		var l: float = 40 + H1.call(k, 10, 100) * 90
		var path := PackedVector2Array([Vector2(x, y)])
		path.append_array(Tx._quad_path(Vector2(x, y), Vector2(x + cos(a + .4) * l * .5, y + sin(a + .4) * l * .5), Vector2(x + cos(a) * l, y + sin(a) * l), 10))
		g.polyline(path, U.rgb(80, 12, 8, .35), 5)
	for k in 240:
		var x: float = H1.call(k, 11, 101) * cols * TS
		var y: float = H1.call(k, 12, 102) * rows * TS
		var s2: float = 30 + H1.call(k, 13, 103) * 130
		g.ga = .05 + H1.call(k, 14, 104) * .07
		g.tex(Tx.YPUFF if H1.call(k, 15, 105) < .3 else Tx.SPUFF, x - s2 / 2, y - s2 / 2, s2, s2 * .8)
	g.ga = 1.0
	if st.pump:
		var q: Vector2 = st.pump
		g.rect(q.x - 6, q.y - 8, 22, 30, Color(0, 0, 0, .3))
		g.rr(q.x - 10, q.y - 14, 20, 28, 3, U.hx("#a3301f"))
		g.rect(q.x - 6, q.y - 9, 12, 7, U.hx("#e8dcc0"))
		g.rect(q.x + 8, q.y - 2, 6, 3, U.hx("#1d1d1b"))
