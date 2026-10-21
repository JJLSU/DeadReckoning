class_name FarmFolk
extends RefCounted
## Family farms: friendly grass strips with a farmhouse, barns, fields, trucks and tractors.
## Lived in by friendly survivors and their cats and dogs, no dead, no loot. Fuel and
## healing items for sale. World pick (make_family), site layout (build_site), the folk and
## pets on foot (spawn/update/draw), farm vehicles in the site bake, and the strip seen from the air.

const FAMILY_CHANCE := [0.0, 0.5, 0.3, 0.0, 0.0, 0.0]   # share of strips at each danger level that are family farms
const FOLK := Vector2i(4, 8)       # friendly survivors living there
const FEMALE := 0.4                # share of them who are women
const PETS := Vector2i(1, 4)       # cats and dogs (up to 4)
const FOLK_SPD := 38.0             # px/s walking about
const FOLK_R := Vector2(3.0, 7.0)  # how far each wanders from their spot, tiles
const FOLK_PAUSE := Vector2(2.0, 6.0)
const GREET_R := 110.0             # px: close enough for a hello
const GREET_GAP := 5.0             # s between anyone's greetings
const GREET_AGAIN := 45.0          # s before the same person says hello again
const DOG_SPD := 75.0
const DOG_RUN := 125.0             # trotting over to you
const DOG_NOTICE := 220.0          # px: a dog this close comes over to you
const DOG_HEEL := 38.0             # and stops about this far from you
const CAT_SPD := 28.0
const GREETINGS := ["Howdy!", "Welcome to the farm.", "Good to see a living face.", "Fuel's by the strip.", "Stay a while.",
	"Mind the chickens.", "You hungry? We've got eggs.", "Nice landing!", "Don't track mud in the house.", "Any news from out there?"]
const SURNAMES := ["Abbott", "Barlow", "Beckett", "Calloway", "Carver", "Dawson", "Ellison", "Fairbanks", "Garner", "Hadley", "Harlan", "Hollis",
	"Jensen", "Keller", "Larkin", "Lindqvist", "Maddox", "McAllister", "Nolan", "Olsen", "Pruitt", "Quinlan", "Rourke", "Sutter", "Talbot",
	"Tolliver", "Underwood", "Vance", "Whitaker", "Yoder", "Brennan", "Cobb", "Delaney", "Eastwood", "Fenwick", "Grady", "Halvorsen", "Ingram",
	"Kowalski", "Lund", "Mercer", "Novak", "Pickett", "Rasmussen", "Schaefer", "Thornton", "Voss", "Weller", "Haugen", "Brandt"]
const SHIRTS := ["#b8483a", "#3f6a9a", "#5a8a4a", "#c8a24a", "#7a5aa0", "#2f7a7a", "#c86a3a", "#4a5f9a"]
const HAIR := ["#2b2118", "#5a3a22", "#8a6a3a", "#c8b07a", "#9a9a92", "#3a2a20"]
const DOGCOL := ["#8a5a2a", "#2a2420", "#c89a5a", "#e8e0d0", "#6a4a3a"]
const CATCOL := ["#d8843a", "#7a7a78", "#1e1c1c", "#e8e2d8", "#a8763a"]

static var fields: Array = []   # crop fields of the site being built: [Rect2i, wheat?]
static var mill_at := Vector2.ZERO   # windmill of the site being built (px), copied into the site by spawn()
static var solar: Array = []          # solar arrays of the site being built: Rect2i in tiles
static var bell_at := Vector2.ZERO    # Failsafe's bell (px), copied into the site by spawn()
# Failsafe's brass bell (Greg, 2026-10-20): hangs from a wooden frame in the middle of the
# site; stand within BELL_REACH and click it to ring it.
const BELL_REACH := 80.0     # px from the bell you can ring it from
const BELL_CLICK := 30.0     # px round the bell a click counts as on it
const BELL_SWING := 1.2      # swings per second after a ring
const BELL_DAMP := 0.55      # swing left after one second
const DESAT := 0.72          # farm colours keep this much of their saturation, so they sit with the rest of the world
const FALL := ["#e08a2a", "#d0502a", "#e8b83a", "#b8402a"]   # fall foliage tints
const FALL_CHANCE := 0.35    # share of farm trees in fall colours
const MILL_SPIN := 0.7       # windmill wheel, radians per second

var gm: Game

func _init(game: Game) -> void:
	gm = game

# =====================================================================
# World: which strips are family farms
# =====================================================================
## Turns some low-danger strips into family farms. Own random stream, so the rest of the
## world stays the same for a given seed.
static func pick_farms(wd, seed_v: int) -> void:
	var rng := U.Mulberry.new(seed_v * 31 + 5)
	var used := {}
	for s in wd.strips:
		var roll: float = rng.next()
		if s.type == "haven" or s.type == "airport" or s.id == wd.START or s.get("hostile", false): continue
		if roll >= float(FAMILY_CHANCE[clampi(int(s.danger), 0, FAMILY_CHANCE.size() - 1)]): continue
		_make_farm(s, rng, used)

## Greg (2026-10-20): only farms and Failsafe sell fuel, so every world gets one of them
## within HOME_REACH of the home field. If none is there, the nearest free strip becomes
## a farm, or a survivor-held one in reach when no free strip is, or failing both a new farm
## strip is laid. Runs after Failsafe.place; own random stream.
const HOME_REACH := 4500.0   # world units, about 80% of the Kestrel's starting range (18 gal)

static func ensure_near_home(wd, seed_v: int) -> void:
	var st: Dictionary = wd.strips[wd.START]
	var used := {}
	var pick = null
	var pd := 1e18
	for s in wd.strips:
		if s.get("arch", "") == "family":
			if Vector2(s.x - st.x, s.y - st.y).length() <= HOME_REACH: return
			used[String(s.name).split(" ")[0]] = true
			continue
		if s.type == "haven" or s.type == "airport" or s.type == "road" or s.id == wd.START: continue
		var d := Vector2(s.x - st.x, s.y - st.y).length()
		var held: bool = s.get("hostile", false)
		if held and d > HOME_REACH: continue
		# a free strip in reach first, then a survivor-held one in reach, then the nearest free one
		if held: d += 1e6
		elif d > HOME_REACH: d += 2e6
		if d < pd:
			pd = d
			pick = s
	var rng := U.Mulberry.new(seed_v * 37 + 3)
	if pick == null or pd >= 2e6:
		# no strip at all in reach: lay a new farm strip between home and HOME_REACH
		var s = _new_strip(wd, st, rng)
		if s: pick = s
	if pick:
		pick.hostile = false   # only when no free strip is in reach: the survivors there move on
		_make_farm(pick, rng, used)

## A fresh strip near home on open ground, clear of other fields, or null if none fits.
static func _new_strip(wd, st: Dictionary, rng):
	# rings from 2500 out to near HOME_REACH first, then closer in down to 1200
	var radii := range(2500, int(HOME_REACH) - 199, 250) + range(2250, 1199, -250)
	for r in radii:
		var n := maxi(8, int(TAU * r / 300))
		var a0: float = rng.next() * TAU
		for i in n:
			var a := a0 + TAU * i / n
			var x: float = st.x + cos(a) * r
			var y: float = st.y + sin(a) * r
			var ok := true
			for o in wd.strips:
				if Vector2(o.x - x, o.y - y).length() < 1200: ok = false; break
			if not ok: continue
			for k in 4:
				var ang := k * PI / 4
				var good := true
				var q := -1.0
				while q <= 1.0:
					var tt: int = wd.terr(x + cos(ang) * 200 * q, y + sin(ang) * 200 * q)
					if tt <= 2 or tt >= 7: good = false; break
					q += 0.25
				if not good or wd.in_forest(x, y, ang, 360.0, false): continue
				var s := {"id": wd.strips.size(), "name": "", "type": "dirt", "x": x, "y": y, "ang": ang, "len": 360.0, "wid": 40.0,
					"fuel": true, "shop": false, "dealer": false, "fuelPrice": 5, "seed": int(rng.next() * 1e9), "danger": 1,
					"arch": "family", "home": false, "hostile": false}
				wd.strips.append(s)
				return s
	return null

static func _make_farm(s: Dictionary, rng, used: Dictionary) -> void:
	var sn: String = SURNAMES[int(rng.next() * SURNAMES.size())]
	for q in 10:
		if not used.has(sn): break
		sn = SURNAMES[int(rng.next() * SURNAMES.size())]
	used[sn] = true
	s.arch = "family"
	s.type = "dirt"
	s.len = 360.0
	s.wid = 40.0
	s.name = sn + " Family Farm"
	s.fuel = true
	s.fuelPrice = 5
	s.shop = false
	s.dealer = false

# =====================================================================
# Site layout (called from SiteGen.build)
# =====================================================================
static func build_site(gen: SiteGen, s: Dictionary) -> void:
	var COLS := SiteGen.COLS
	var ry: int = gen.ry
	var area := [2, 2, COLS - 3, ry - 3]
	# the farmhouse, near the middle, front door facing the strip
	var hw := gen.ri(13, 15)
	var hh := gen.ri(9, 10)
	var hc0 := COLS / 2 - hw / 2 + gen.ri(-3, 3)
	var hr0 := ry / 2 - hh / 2 + gen.ri(-3, 0)
	var fsafe: bool = s.get("failsafe", false)
	if fsafe: hr0 = ry / 2 - hh - 4   # at Failsafe the house stands back so the bell has the middle
	var roofs := ["#3f6f9f", "#4a7a5a", "#7a8088"]
	gen.box(hc0, hr0, hw, hh, {"kind": "house", "split": true, "loot": [0, 0], "floor": "#9a7a52", "roof": dh(roofs[int(gen.R() * roofs.size())]), "flat": false})
	var door: Array = gen.rooms[gen.rooms.size() - 1].door
	# gravel lane from the front door down to the strip, and a yard in front of the house
	var lc: int = door[0]
	gen.rect_(hc0 - 1, hr0 + hh, hw + 2, 2, 11)
	for r in range(hr0 + hh, ry):
		for c in [lc, lc + 1]:
			if gen.at(c, r) == 0: gen.set_(c, r, 11)
	# Failsafe: a gravel square in the middle of the site with the bell frame on it
	bell_at = Vector2.ZERO
	if fsafe:
		var bc: int = COLS / 2 - 2
		var br: int = ry / 2 - 2
		for r in range(br, br + 5):
			for c in range(bc, bc + 5):
				if gen.at(c, r) == 0: gen.set_(c, r, 11)
		bell_at = Vector2((bc + 2.5) * SiteGen.TS, (br + 2.5) * SiteGen.TS)
	# barns: big, red, wide doors
	var nb := gen.ri(1, 2)
	var barns: Array = []
	for k in nb:
		var bw := gen.ri(12, 15)
		var bh := gen.ri(9, 10)
		var q = gen.box_at(bw, bh, {"kind": "barn", "wide": true, "loot": [0, 0], "floor": "#8a7350", "roof": dh("#b03a2a"), "flat": false}, area)
		if q:
			barns.append(q)
			gen.silo(gen.place(2, 2, 1, null, [maxi(2, q.c - 4), maxi(2, q.r - 4), mini(COLS - 3, q.c + bw + 4), mini(ry - 3, q.r + bh + 4)]))
	# smaller outbuildings: sheds, a chicken coop, a workshop
	var sheds := ["#6b8a9a", "#8a6a4a", "#c8b48a", "#5a7a5a", "#9a5a4a"]
	for k in gen.ri(3, 5):
		gen.box_at(gen.ri(5, 7), gen.ri(4, 5), {"kind": "shed", "extra": false, "loot": [0, 0], "floor": "#7a6a52", "roof": dh(sheds[int(gen.R() * sheds.size())]), "flat": false}, area)
	# a fenced pasture with a gate
	var pw := gen.ri(10, 14)
	var ph := gen.ri(6, 8)
	var pp = gen.place(pw, ph, 1, null, area)
	if pp:
		for c in range(pp.c, pp.c + pw):
			gen.set_(c, pp.r, 6); gen.set_(c, pp.r + ph - 1, 6)
		for r in range(pp.r, pp.r + ph):
			gen.set_(pp.c, r, 6); gen.set_(pp.c + pw - 1, r, 6)
		var gc: int = pp.c + gen.ri(2, pw - 4)
		gen.set_(gc, pp.r + ph - 1, 0); gen.set_(gc + 1, pp.r + ph - 1, 0)
	# crop fields
	fields = []
	for k in gen.ri(4, 6):
		var fw := gen.ri(9, 16)
		var fh := gen.ri(5, 8)
		var fq = gen.place(fw, fh, 1, null, area)
		if fq:
			gen.rect_(fq.c, fq.r, fw, fh, 9)
			fields.append([Rect2i(fq.c, fq.r, fw, fh), gen.R() < 0.5])
	# a small orchard
	var ow := gen.ri(7, 11)
	var oh := gen.ri(5, 7)
	var oq = gen.place(ow, oh, 1, null, area)
	if oq:
		for r in range(oq.r, oq.r + oh, 2):
			for c in range(oq.c, oq.c + ow, 2): gen.set_(c, r, 5)
	# pickups by the house and barns, tractors by the barns or out in the fields
	var trucks := ["#c8382a", "#2f5f9f", "#e8e2d4", "#3f7a4a", "#d89a2a", "#5a5f66"]
	var near := func(cx: int, cy: int, rad: int, hz: bool, okv: Array) -> bool:
		for q in 80:
			if gen.car(cx + gen.ri(-rad, rad), cy + gen.ri(-rad, rad), hz, okv): return true
		return false
	var np := gen.ri(2, 3)
	for k in np:
		var at_house := k == 0 or barns.is_empty()
		var b = null if at_house else barns[k % barns.size()]
		var cx: int = hc0 + hw / 2 if at_house else b.c + 4
		var cy: int = hr0 + hh + 2 if at_house else b.r + 6
		if near.call(cx, cy, 8, gen.R() < 0.6, [0, 11]):
			gen.cars[gen.cars.size() - 1].merge({"kind": "pickup", "col": dh(trucks[int(gen.R() * trucks.size())])})
	for k in gen.ri(1, 2):
		var b = barns[k % barns.size()] if barns.size() else null
		var cx: int = b.c + 5 if b else COLS / 2
		var cy: int = b.r + 5 if b else ry / 2
		if near.call(cx, cy, 10, gen.R() < 0.5, [0, 9, 11]):
			gen.cars[gen.cars.size() - 1].merge({"kind": "tractor", "col": dh("#d8402a" if gen.R() < 0.6 else "#4aa83a")})
	# a white windmill (2x2 footing, solid) and one or two solar arrays facing south
	var mq = gen.place(2, 2, 3, null, area)
	mill_at = Vector2.ZERO
	if mq:
		gen.rect_(mq.c, mq.r, 2, 2, 13)
		mill_at = Vector2((mq.c + 1) * SiteGen.TS, (mq.r + 1) * SiteGen.TS)
	solar = []
	for k in gen.ri(1, 2):
		var sw := gen.ri(5, 8)
		var sq = gen.place(sw, 5, 1, null, area)
		if not sq: continue
		for rr in [sq.r, sq.r + 2, sq.r + 4]:   # three rows of panels, a walkway between
			for c in range(sq.c, sq.c + sw): gen.set_(c, rr, 10)
		solar.append(Rect2i(sq.c, sq.r, sw, 5))
	# shade trees round the yard, clear of the parked plane
	var i := 0
	var q2 := 0
	var nt := gen.ri(16, 24)
	while i < nt and q2 < 900:
		q2 += 1
		var c := gen.ri(1, COLS - 2)
		var r := gen.ri(1, ry - 2)
		var ok := true
		for a in range(-1, 2):
			for b2 in range(-1, 2):
				if gen.at(c + a, r + b2) != 0: ok = false
		if ok and not (c < 14 and r > ry - 5):
			gen.set_(c, r, 5)
			i += 1

## Tile colours that differ on a family farm (bright grass strip, cheerful fields). null = the usual.
static func tile_col(v: int, c: int, r: int, gj: float, j: float, sid: int) -> Variant:
	var b = _tile_col(v, c, r, gj, j, sid)
	if b == null: return null
	var l: float = b[0] * 0.3 + b[1] * 0.59 + b[2] * 0.11
	return [l + (b[0] - l) * DESAT, l + (b[1] - l) * DESAT, l + (b[2] - l) * DESAT]

## ds() for a "#rrggbb" string.
static func dh(h: String) -> String:
	return "#" + ds(U.hx(h)).to_html(false)

## Pulls a colour toward grey by DESAT.
static func ds(c: Color) -> Color:
	var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	return Color(l + (c.r - l) * DESAT, l + (c.g - l) * DESAT, l + (c.b - l) * DESAT, c.a)

static func _tile_col(v: int, c: int, r: int, gj: float, j: float, sid: int) -> Variant:
	if v == 3: return [118 + j + (8.0 if (c / 2) % 2 == 0 else -4.0), 172 + j + (8.0 if (c / 2) % 2 == 0 else -4.0), 74 + j]
	if v == 0: return [96 + gj, 136 + gj, 62 + gj * .6]
	if v == 9:
		for f in fields:
			if (f[0] as Rect2i).has_point(Vector2i(c, r)):
				if f[1]: return [204 + j, 172 + j, 84 + j]   # ripe wheat
				break
		return [104 + j, 158 + j, 66 + j]                    # green crops
	if v == 11: return [150 + j, 138 + j, 112 + j]          # gravel yard and lane
	return null

# =====================================================================
# Site bake extras
# =====================================================================
## Wildflowers on the grass (in place of the usual litter and bones).
static func bake_flowers(g: Pen, st: Dictionary) -> void:
	var cols: int = st.cols
	var rows: int = st.rows
	var G1: PackedByteArray = st.g
	var sid: int = st.s.id
	var cs := [U.rgb(250, 250, 240, .85), U.rgb(250, 220, 80, .85), U.rgb(220, 120, 200, .75), U.rgb(150, 180, 250, .75)]
	for k in 260:
		var cc := 1 + int(U.hash3(k, 1, sid * 7 + 61) * (cols - 2))
		var r := 1 + int(U.hash3(k, 2, sid * 7 + 62) * (rows - 2))
		if G1[r * cols + cc] != 0: continue
		var x: float = cc * SiteGen.TS + U.hash3(k, 3, sid * 7 + 63) * SiteGen.TS
		var y: float = r * SiteGen.TS + U.hash3(k, 4, sid * 7 + 64) * SiteGen.TS
		var col: Color = cs[k % cs.size()]
		for q in 4:
			g.circle(x + (U.hash3(k, q, sid + 65) - .5) * 14, y + (U.hash3(q, k, sid + 66) - .5) * 10, 1.6, col)

## Solar panels and the windmill's lattice footing, into the baked ground.
static func bake_extra(g: Pen, st: Dictionary) -> void:
	var TS := SiteGen.TS
	for a in st.get("solar", []):
		var rc: Rect2i = a
		for rr in [rc.position.y, rc.position.y + 2, rc.position.y + 4]:
			var x: float = rc.position.x * TS + 2
			var y: float = rr * TS + 4
			var w: float = rc.size.x * TS - 4
			var h := TS - 8.0
			g.rect(x + 3, y + 6, w, h, Color(0, 0, 0, .35))                  # shadow, offset like the other baked shadows
			g.rect(x, y, w, h, U.hx("#262f3e"))
			var px := x
			while px < x + w - 1:
				var pw := minf(TS - 2, x + w - px)
				g.rect(px + 1, y + 1, pw - 2, h - 2, U.hx("#33476a"))
				g.rect(px + 1, y + 1, pw - 2, 3, Color(1, 1, 1, .1))              # top (north) edge, raised
				for q in 3: g.rect(px + 1 + (pw - 2) * (q + 1) / 4.0, y + 1, 1, h - 2, Color(0, 0, 0, .22))
				g.rect(px + 1, y + h / 2, pw - 2, 1, Color(0, 0, 0, .22))
				px += TS
			g.rect(x, y + h - 2, w, 2, U.hx("#9aa2aa"))                         # low south edge, facing the sun
	var m: Vector2 = st.get("mill", Vector2.ZERO)
	if m != Vector2.ZERO:
		var lg := U.hx("#d8d6cf")
		g.rect(m.x - 28, m.y - 28, 56, 56, U.rgb(150, 146, 134, .55))   # concrete footing
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			g.line(m.x + d.x * 22, m.y + d.y * 22, m.x + d.x * 4, m.y + d.y * 4, lg, 3)
			g.rect(m.x + d.x * 22 - 3, m.y + d.y * 22 - 3, 6, 6, U.hx("#8a8a84"))
		g.stroke_rect(m.x - 14, m.y - 14, 28, 28, lg, 1.5)

## Fall tint for some of the trees at a family farm (white elsewhere).
static func tree_tint(S: Dictionary, c: int, r: int) -> Color:
	if S.get("arch", "") != "family" or U.hash3(c, r, 77) >= FALL_CHANCE: return Color.WHITE
	var f := U.hx(FALL[int(U.hash3(r, c, 78) * FALL.size())])
	return Color(f.r * 2.2, f.g * 2.0, f.b * 1.6)

## A click at screen point sp: rings Failsafe's bell when it lands on the bell and you
## stand close enough. True when the click was used (so it isn't taken as anything else).
func click_bell(sp: Vector2) -> bool:
	var S = gm.S
	if S == null or S.get("bell", Vector2.ZERO) == Vector2.ZERO: return false
	var gs: float = gm.ground_scale()
	var w := Vector2(S.cx + (sp.x - gm.Wv / 2) / gs, S.cy + (sp.y - gm.Hv / 2) / gs)
	var b: Vector2 = S.bell
	if w.distance_to(b) > BELL_CLICK: return false
	if Vector2(S.p.x, S.p.y).distance_to(b) > BELL_REACH:
		gm.toast("Get closer to ring the bell.")
		return true
	gm.sfx("bell")
	S.bellA = 0.5
	S.bellP = 0.0
	gm.fields.on_bell()   # settlers come out to fill the plane (fields.gd)
	return true

## Failsafe's bell: the frame's shadow, two posts, the crossbeam and the brass bell,
## swinging after a ring. Drawn above people so you can stand under it.
func _draw_bell(g: Pen, b: Vector2) -> void:
	var S: Dictionary = gm.S
	var sw: float = float(S.get("bellA", 0.0)) * sin(float(S.get("bellP", 0.0)))
	var wood := U.hx("#6a4a2a")
	var brass := U.hx("#c8a040")
	# shadows, offset like the trees'
	g.rect(b.x - 30 + 10, b.y - 3 + 14, 60, 6, Color(0, 0, 0, .22))
	g.circle(b.x + 9 + sw * 30, b.y + 14, 13, Color(0, 0, 0, .25))
	# posts (seen from above) and the beam across them
	g.rect(b.x - 34, b.y - 5, 10, 10, U.shade(wood, 0.8))
	g.rect(b.x + 24, b.y - 5, 10, 10, U.shade(wood, 0.8))
	g.rect(b.x - 32, b.y - 3, 64, 6, wood)
	g.rect(b.x - 32, b.y - 3, 64, 2, U.shade(wood, 1.3))
	# the bell, swinging toward the viewer and back along the beam's normal
	var by: float = b.y + sw * 22
	g.circle(b.x, by, 13, U.shade(brass, 0.6))          # lip
	g.circle(b.x, by - 1, 11, brass)                     # shoulder
	g.circle(b.x - 3, by - 4, 5, U.shade(brass, 1.35))   # shine
	g.circle(b.x, by - 1, 3, U.shade(brass, 0.75))       # crown and the hanger
	# a soft pulse while it's still ringing, so you can see it was rung
	var a: float = float(S.get("bellA", 0.0))
	if a > 0.05: g.ring(b.x, by, 16 + (1.0 - a / 0.5) * 18, Color(1.0, 0.85, 0.4, a * 0.9), 2)

## The windmill's wheel and tail vane, drawn above roofs and trees.
func draw_top(g: Pen) -> void:
	var S: Dictionary = gm.S
	if S.get("bell", Vector2.ZERO) != Vector2.ZERO: _draw_bell(g, S.bell)
	var m: Vector2 = S.get("mill", Vector2.ZERO)
	if m == Vector2.ZERO: return
	var T: float = gm.T
	var wh := U.hx("#f2f0ea")
	var a0 := T * MILL_SPIN
	# shadow on the ground, offset like the trees'
	g.circle(m.x + 16, m.y + 20, 30, Color(0, 0, 0, .18))
	g.save(); g.translate(m.x, m.y)
	g.rect(-36, -2, 30, 4, U.hx("#c8c6be"))                 # tail boom
	g.poly(PackedVector2Array([Vector2(-50, -10), Vector2(-32, -3), Vector2(-32, 3), Vector2(-50, 10)]), wh)   # vane
	for i in 18:
		var a := a0 + i * TAU / 18
		var p0 := Vector2(cos(a), sin(a)) * 9
		var p1 := Vector2(cos(a + 0.08), sin(a + 0.08)) * 30
		var p2 := Vector2(cos(a + 0.2), sin(a + 0.2)) * 30
		g.poly(PackedVector2Array([p0, p1, p2]), wh if i % 2 == 0 else U.hx("#dcdad2"))
	g.ring(0, 0, 30, U.hx("#bcbab2"), 1.2)
	g.ring(0, 0, 19, U.hx("#bcbab2"), 1)
	g.circle(0, 0, 6, U.hx("#8a8a84"))
	g.restore()

## Pickup trucks and tractors, drawn instead of the usual car.
static func draw_vehicle(g: Pen, k: Dictionary) -> void:
	var x: float = k.c * SiteGen.TS + 3
	var y: float = k.r * SiteGen.TS + 3
	var w: float = k.w * SiteGen.TS - 6
	var h: float = k.h * SiteGen.TS - 6
	var hz: bool = k.w > 1
	var L := maxf(w, h)
	var Wd := minf(w, h)
	var kc := U.hx(k.col)
	g.save()
	g.translate(x + w / 2, y + h / 2)
	if not hz: g.rotate(PI / 2)
	# local frame: length along x (front at +x), width along y
	g.rr(-L / 2 + 5, -Wd / 2 + 6, L, Wd, 6, Color(0, 0, 0, .35))
	if k.kind == "tractor":
		var tire := U.hx("#1c1c1a")
		var hub := U.hx("#e8c84a")
		g.rr(-L / 2, -Wd / 2 - 2, 18, 9, 3, tire); g.rr(-L / 2, Wd / 2 - 7, 18, 9, 3, tire)   # big rear wheels
		g.rr(L / 2 - 14, -Wd / 2 + 1, 11, 6, 2, tire); g.rr(L / 2 - 14, Wd / 2 - 7, 11, 6, 2, tire)   # small front wheels
		g.circle(-L / 2 + 9, -Wd / 2 + 2.5, 2.5, hub); g.circle(-L / 2 + 9, Wd / 2 - 2.5, 2.5, hub)
		g.rr(-L / 2 + 6, -Wd / 2 + 6, L * .5, Wd - 12, 3, kc)   # body under the seat
		g.rr(-L / 2 + 20, -Wd / 4, L - 26, Wd / 2, 3, kc)       # long hood
		g.rect(-L / 2 + 20, -Wd / 4, L - 26, 2, U.shade(kc, 1.3))
		g.circle(-L / 2 + 14, 0, 4.5, U.hx("#2a2a28"))           # seat
		g.rect(L / 2 - 14, -1.5, 4, 3, U.hx("#4a4a48"))         # exhaust stack
		g.circle(L / 2 - 12, 0, 2, U.hx("#222222"))
	else:
		var pts := g.rr_pts(-L / 2, -Wd / 2, L, Wd, 6)
		Tx._grad_poly(g, pts, [[0.0, U.shade(kc, 1.25)], [0.5, kc], [1.0, U.shade(kc, .7)]], Vector2(0, 1), -Wd / 2, Wd / 2)
		var dk := U.rgb(18, 22, 26, .9)
		g.rr(-L / 2 + 3, -Wd / 2 + 3, L * .42, Wd - 6, 2, U.shade(kc, .55))   # open bed
		g.rect(-L / 2 + 6, -Wd / 2 + 6, L * .36, 2, Color(0, 0, 0, .25))
		g.rr(-L / 2 + L * .47, -Wd / 2 + 4, L * .12, Wd - 8, 3, dk)            # rear window
		g.rect(-L / 2 + L * .59, -Wd / 2 + 4, L * .14, Wd - 8, U.shade(kc, 1.12))   # cab roof
		g.rr(-L / 2 + L * .73, -Wd / 2 + 4, L * .1, Wd - 8, 3, dk)             # windscreen
		var lc := U.rgb(255, 245, 200, .7)
		g.rect(L / 2 - 3, -Wd / 2 + 3, 2, 4, lc); g.rect(L / 2 - 3, Wd / 2 - 7, 2, 4, lc)
	g.restore()

# =====================================================================
# Folk and pets on foot
# =====================================================================
func spawn(site: Dictionary) -> void:
	site.ff = []
	site.pets = []
	site.mill = mill_at
	site.solar = solar.duplicate()
	site.bell = bell_at
	site.bellA = 0.0   # swing amplitude (rad), set by a ring and dying away
	site.bellP = 0.0   # swing phase
	site.greetT = 0.0
	var house = null
	for rm in site.rooms:
		if rm.kind == "house":
			house = rm
			break
	var cx: float = (house.c + house.w * 0.5) * gm.TS if house else site.cols * gm.TS * 0.5
	var cy: float = (house.r + house.h * 0.5) * gm.TS if house else site.ry * gm.TS * 0.5
	var n := randi_range(FOLK.x, FOLK.y)
	for i in n:
		var inside: bool = house != null and i < 2
		var sp = _spot(site, house, inside, cx, cy, 14.0)
		if sp == null: continue
		site.ff.append({"x": sp.x, "y": sp.y, "hx": sp.x, "hy": sp.y, "pr": randf_range(FOLK_R.x, FOLK_R.y) * gm.TS * (0.5 if inside else 1.0),
			"pt": randf() * 3.0, "go": false, "tx": sp.x, "ty": sp.y, "ang": randf() * TAU, "wk": 0.0, "spd": FOLK_SPD * randf_range(0.85, 1.1),
			"shirt": SHIRTS[randi() % SHIRTS.size()], "skin": D.sv_skin(), "hair": HAIR[randi() % HAIR.size()], "cap": "",
			"fem": randf() < FEMALE, "greetT": -99.0, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y)})
	var np := randi_range(PETS.x, PETS.y)
	for i in np:
		var sp = _spot(site, house, false, cx, cy, 12.0)
		if sp == null: continue
		var dog := randf() < 0.5
		site.pets.append({"x": sp.x, "y": sp.y, "hx": sp.x, "hy": sp.y, "pr": (8.0 if dog else 5.0) * gm.TS, "pt": randf() * 3.0, "go": false, "tx": sp.x, "ty": sp.y,
			"ang": randf() * TAU, "wk": 0.0, "dog": dog, "col": (DOGCOL if dog else CATCOL)[randi() % 5], "spd": DOG_SPD if dog else CAT_SPD, "woof": false, "sit": 0.0})

## A walkable spot near (cx, cy), or inside the house.
func _spot(site: Dictionary, house, inside: bool, cx: float, cy: float, rad: float) -> Variant:
	for q in 60:
		var x: float
		var y: float
		if inside:
			x = (house.c + 1.5 + randf() * (house.w - 3)) * gm.TS
			y = (house.r + 1.5 + randf() * (house.h - 3)) * gm.TS
		else:
			x = cx + (randf() - 0.5) * 2 * rad * gm.TS
			y = cy + (randf() - 0.5) * 2 * rad * gm.TS
		if x < gm.TS * 2 or y < gm.TS * 2 or x > (site.cols - 2) * gm.TS or y > (site.ry - 1) * gm.TS: continue
		var t := gm.tile_at(x, y)
		if inside and t != 2: continue
		if not inside and t != 0 and t != 11: continue
		if gm.hit_box(x, y, 10): continue
		if Vector2(x - site.p.x, y - site.p.y).length() < 120: continue
		return Vector2(x, y)
	return null

## Wander: walk to a nearby spot in a straight line, pause, pick another. Returns px moved.
func _wander(e: Dictionary, spd: float, pause: Vector2, dt: float) -> float:
	if not e.go:
		e.pt -= dt
		if e.pt > 0: return 0.0
		for q in 10:
			var a := randf() * TAU
			var d := randf() * float(e.pr)
			var tx: float = e.hx + cos(a) * d
			var ty: float = e.hy + sin(a) * d
			if gm.hit_box(tx, ty, 10) or not gm.walk_clear(e.x, e.y, tx, ty): continue
			e.tx = tx; e.ty = ty; e.go = true
			break
		if not e.go:
			e.pt = 1.0
			return 0.0
	return _step_to(e, e.tx, e.ty, spd, 4.0, pause, dt)

func _step_to(e: Dictionary, tx: float, ty: float, spd: float, stop: float, pause: Vector2, dt: float) -> float:
	var dv := Vector2(tx - e.x, ty - e.y)
	var d := dv.length()
	if d <= stop:
		e.go = false
		e.pt = randf_range(pause.x, pause.y)
		return 0.0
	var st := minf(d - stop, spd * dt)
	var ox: float = e.x
	var oy: float = e.y
	var u := dv / d
	if not e.has("dog"): u = gm.survivors.sv_avoid(e, u.x, u.y, gm.survivors.people())   # folk walk round people
	gm.move_c(e, u.x * st, u.y * st, 8)
	var moved := Vector2(e.x - ox, e.y - oy).length()
	e.ang = lerp_angle(float(e.ang), dv.angle(), minf(1.0, dt * 10))
	if moved < st * 0.3:   # stuck on something: stop and think again
		e.go = false
		e.pt = randf_range(0.5, 1.5)
	return moved

func update(p: Dictionary, dt: float) -> void:
	var S: Dictionary = gm.S
	if not S.has("ff"): return
	if S.get("bellA", 0.0) > 0.001:
		S.bellA *= pow(BELL_DAMP, dt)
		S.bellP += TAU * BELL_SWING * dt
	S.greetT -= dt
	for v in S.ff:
		var dp := Vector2(p.x - v.x, p.y - v.y)
		var ox: float = v.x
		var oy: float = v.y
		_wander(v, v.spd, FOLK_PAUSE, dt)
		gm.survivors.fr_jostle(v, dt)   # pushes past others; you push past them
		var moved := Vector2(v.x - ox, v.y - oy).length()
		v.wk += moved * 0.22
		if not v.go and dp.length() < 90: v.ang = lerp_angle(float(v.ang), dp.angle(), minf(1.0, dt * 6))
		if dp.length() < GREET_R and S.greetT <= 0 and S.t - float(v.greetT) > GREET_AGAIN and gm.los(v.x, v.y, p.x, p.y):
			v.greetT = S.t
			S.greetT = GREET_GAP
			gm.survivors.sv_say(v, GREETINGS[randi() % GREETINGS.size()])
	for a in S.pets:
		var dp := Vector2(p.x - a.x, p.y - a.y)
		var moved := 0.0
		if a.dog and dp.length() < DOG_NOTICE and gm.los(a.x, a.y, p.x, p.y):
			if not a.woof:
				a.woof = true
				gm.floater(a.x, a.y - 18, "Woof!", "#f0e0b0", true)
			if dp.length() > DOG_HEEL + 6:
				a.go = true
				moved = _step_to(a, p.x, p.y, DOG_RUN, DOG_HEEL, Vector2(0.3, 0.8), dt)
			else:
				a.go = false
				a.pt = 0.5
				a.ang = lerp_angle(float(a.ang), dp.angle(), minf(1.0, dt * 6))
			a.hx = a.x; a.hy = a.y   # wander from wherever it followed you to
		else:
			moved = _wander(a, a.spd, Vector2(2.0, 5.0) if a.dog else Vector2(4.0, 10.0), dt)
		a.wk += moved * 0.3
		a.sit = minf(1.0, a.sit + dt * 2) if not a.go else 0.0

func draw(g: Pen) -> void:
	var S: Dictionary = gm.S
	if not S.has("ff"): return
	var T: float = gm.T
	for a in S.pets: _draw_pet(g, a, T)
	for v in S.ff:
		Render.draw_person(g, v.x, v.y, v.ang, {"body": v.shirt, "skin": v.skin, "hair": v.hair, "cap": v.cap, "bare": true, "fem": v.fem, "walk": v.wk})

func _draw_pet(g: Pen, a: Dictionary, T: float) -> void:
	var col := U.hx(a.col)
	var dk := U.shade(col, 0.7)
	var w := sin(float(a.wk))
	g.save()
	g.translate(a.x, a.y)
	if a.dog:
		g.ellipse(2, 4, 12, 6, 0, Color(0, 0, 0, 0.25))
		g.rotate(a.ang)
		var wag := sin(T * (14.0 if a.go or a.woof else 5.0)) * 0.6
		g.line(-10, 0, -10 - cos(wag) * 8, sin(wag) * 8, col, 2.5)   # tail
		for s2 in [-1.0, 1.0]:
			g.ellipse(-5 + w * 2.5 * s2, 4.5 * s2, 2.2, 1.6, 0, dk)
			g.ellipse(5 - w * 2.5 * s2, 4.5 * s2, 2.2, 1.6, 0, dk)
		g.ellipse(0, 0, 10, 5, 0, col)
		g.circle(10, 0, 4.5, col)
		g.ellipse(13.5, 0, 2.5, 2, 0, dk)                            # snout
		g.ellipse(9, -4, 2.5, 1.6, 0.4, dk); g.ellipse(9, 4, 2.5, 1.6, -0.4, dk)   # ears
		g.circle(15.5, 0, 1, U.hx("#111111"))
	else:
		g.ellipse(1, 3, 8, 4.5, 0, Color(0, 0, 0, 0.22))
		g.rotate(a.ang)
		var sw := sin(T * 2.0 + float(a.x)) * 0.5
		var tail := PackedVector2Array([Vector2(-6, 0), Vector2(-10, 2 + sw * 3), Vector2(-13, -1 + sw * 5)])
		g.polyline(tail, col, 2)
		if float(a.sit) < 0.5:
			for s2 in [-1.0, 1.0]:
				g.circle(-3 + w * 2 * s2, 3 * s2, 1.4, dk)
				g.circle(3 - w * 2 * s2, 3 * s2, 1.4, dk)
		g.ellipse(-0.5 if float(a.sit) >= 0.5 else 0.0, 0, 6.5 if float(a.sit) < 0.5 else 5.5, 3.5 if float(a.sit) < 0.5 else 4.2, 0, col)
		g.circle(6, 0, 3.2, col)
		g.poly(PackedVector2Array([Vector2(5, -2), Vector2(7.5, -4.8), Vector2(7.6, -1.6)]), dk)
		g.poly(PackedVector2Array([Vector2(5, 2), Vector2(7.5, 4.8), Vector2(7.6, 1.6)]), dk)
	g.restore()

# =====================================================================
# From the air
# =====================================================================
## The strip seen in flight, in the strip's own frame (already translated and rotated).
static func draw_air(gm, g: Pen, s: Dictionary, L: float, Wd: float) -> void:
	var sid: int = s.id
	var H := func(a: int, b: int) -> float: return U.hash3(sid, a, b + 700)
	# fields first, in a loose patchwork on the farm side of the strip
	for i in 7:
		var fx: float = -L / 2 + H.call(i, 1) * L * 1.1 - 40
		var fy: float = Wd / 2 + 70 + H.call(i, 2) * 220
		var fw: float = 70 + H.call(i, 3) * 90
		var fh: float = 40 + H.call(i, 4) * 60
		var wheat: bool = H.call(i, 5) < 0.5
		var fc := ds(U.rgb(206, 178, 92) if wheat else U.rgb(110, 166, 70))
		g.rect(fx, fy, fw, fh, fc)
		var y := fy + 4
		while y < fy + fh:
			g.rect(fx, y, fw, 1.5, U.shade(fc, 0.82))
			y += 7
	# the grass strip: bright and mown in stripes, white tyre markers down the edges
	g.rect(-L / 2 - 6, -Wd / 2 - 6, L + 12, Wd + 12, rgba(20, 30, 10, 0.2))
	g.rect(-L / 2, -Wd / 2, L, Wd, ds(U.hx("#86c24e")))
	var x := -L / 2
	var k := 0
	while x < L / 2:
		if k % 2 == 0: g.rect(x, -Wd / 2, minf(30, L / 2 - x), Wd, ds(U.rgb(160, 214, 100, 0.45)))
		x += 30
		k += 1
	x = -L / 2
	while x <= L / 2 + 0.01:
		g.rect(x - 3, -Wd / 2 - 6, 6, 4, U.rgb(250, 250, 245, 0.95)); g.rect(x - 3, Wd / 2 + 2, 6, 4, U.rgb(250, 250, 245, 0.95))
		x += L / 6
	# farmhouse, barns and sheds
	var bld := func(bx: float, by: float, bw: float, bh: float, c: String) -> void:
		var rc := ds(U.hx(c))
		g.rect(bx + 6, by + 7, bw, bh, Color(0, 0, 0, 0.35))
		g.rect(bx, by, bw, bh / 2, U.shade(rc, 1.15)); g.rect(bx, by + bh / 2, bw, bh / 2, U.shade(rc, 0.75))
	var hx: float = -20 + (H.call(9, 1) - 0.5) * 60
	var hy: float = Wd / 2 + 120
	bld.call(hx, hy, 46, 34, "#3f6f9f")
	g.rect(hx + 20, Wd / 2 + 6, 6, hy - Wd / 2 - 6, U.rgb(150, 140, 120))   # lane down to the strip
	bld.call(hx + 80, hy - 20, 60, 42, "#b03a2a")
	if H.call(9, 2) < 0.6: bld.call(hx - 100, hy + 30, 56, 40, "#b03a2a")
	for i in 3:
		bld.call(hx - 60 + i * 50 + H.call(i, 6) * 20, hy + 70 + H.call(i, 7) * 30, 18, 14, "#8a6a4a")
	g.circle(hx + 150, hy - 6, 9, U.hx("#c2c8cc")); g.ring(hx + 150, hy - 6, 9, U.rgb(80, 86, 92), 1.5)
	for i in 8:   # shade trees
		var tx: float = hx - 140 + H.call(i, 8) * 320
		var ty: float = hy - 30 + H.call(i, 9) * 160
		g.circle(tx + 4, ty + 5, 9, Color(0, 0, 0, 0.3)); g.circle(tx, ty, 9, ds(U.hx(FALL[i % FALL.size()])) if i % 3 == 0 else ds(U.rgb(62, 110, 48)))
	var mx: float = hx + 190
	var my: float = hy + 50
	for i in 2:   # solar arrays
		var sx: float = hx - 150 + i * 60
		var sy: float = hy + 120
		for q in 3: g.rect(sx, sy + q * 8, 40, 5, U.hx("#33476a"))
	g.circle(mx + 5, my + 6, 10, Color(0, 0, 0, 0.25))
	for i in 6:
		var a: float = gm.T * MILL_SPIN + i * TAU / 6
		g.line(mx, my, mx + cos(a) * 10, my + sin(a) * 10, U.hx("#f2f0ea"), 2)
	if s.fuel:
		for i in 2:
			var fx := L / 4 + 10 + i * 26
			var fy := Wd / 2 + 40
			g.circle(fx + 5, fy + 6, 11, Color(0, 0, 0, 0.35)); g.circle(fx, fy, 11, U.hx("#b4aea2")); g.circle(fx - 3, fy - 3, 5, U.hx("#e2dccf"))
		g.rect(L / 4 + 60, Wd / 2 + 30, 10, 14, U.hx("#a3301f"))
	# windsock
	var F = gm.F
	var wx := -L / 2 + 40
	var wy := -Wd / 2 - 26
	var wa: float = (atan2(F.wind.y, F.wind.x) - s.ang) if F else 0.6
	g.circle(wx, wy, 2.5, U.hx("#dddddd"))
	g.save(); g.translate(wx, wy); g.rotate(wa + sin(gm.T * 3) * 0.08)
	g.poly(PackedVector2Array([Vector2(0, -4), Vector2(22, -2), Vector2(22, 2), Vector2(0, 4)]), U.hx("#ff7a2a"))
	g.rect(8, -3, 4, 6, Color.WHITE)
	g.restore()

static func rgba(r: float, g: float, b: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)
