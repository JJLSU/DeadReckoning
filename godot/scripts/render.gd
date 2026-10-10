class_name Render
## Drawing for flight mode, ground mode and both HUDs (port of the canvas renderers).

const TS := 32.0
const CH := 1024.0
# Fair-weather clouds in flight mode. The sky is split into 1,700-unit cells and this
# is the share of cells that hold a cloud: 0 = clear skies, 1 = a cloud in every cell.
# (Originally 0.33.) Covers land and ocean alike. Separate from storms (world.gd).
const CLOUD_DENSITY := 1
const SEA := "#1f3543"   # open-ocean colour, matches the terrain shader's deep water
static var CC := {}

static func hc(s: String) -> Color:
	if CC.has(s): return CC[s]
	var c := Color.html(s)
	CC[s] = c
	return c

static func rgba(r: float, g: float, b: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

static func flight_scale(gm, alt: float) -> float:
	return sqrt(gm.Wv * gm.Hv) / (700.0 + maxf(0.0, alt) * 6.0) * gm.zoom

# =====================================================================
# shared
# =====================================================================
static func draw_plane(g: Pen, P: Dictionary, size: float, prop: float, shadow: bool, bank: float = 0.0) -> void:
	g.save()
	g.scale(size, size)
	if bank != 0.0: g.scale(1, 1 - absf(bank) * 0.18)
	if shadow: g.ga *= 0.3
	g.tex(Tx.PSPR.get(P.name + ("_s" if shadow else "")), -0.64, -0.64, 1.28, 1.28)
	if not shadow:
		for b in P.props:   # [x, y, radius] per propeller, set per airframe in D.PLANES
			var bx: float = b[0]
			var by: float = b[1]
			var br: float = b[2]
			g.ellipse(bx, by, 0.025, br, 0, Color(225 / 255.0, 225 / 255.0, 215 / 255.0, 0.13))
			g.line(bx, by + sin(prop) * (br - 0.01), bx, by - sin(prop) * (br - 0.01), Color(30 / 255.0, 30 / 255.0, 30 / 255.0, 0.7), 0.016)
			g.circle(bx, by, 0.018, hc("#2a2a2a"))
	g.restore()

static func vignette(gm, g: Pen, alpha: float) -> void:
	var m: float = maxf(gm.Wv, gm.Hv)
	g.ga = alpha
	g.radial(gm.Wv / 2, gm.Hv / 2, [[m * 0.32, Color(0, 0, 0, 0)], [m * 0.78, Color(0, 0, 0, 1)]], 40)
	g.ga = 1.0

static func vignette_red(gm, g: Pen, alpha: float) -> void:
	var m: float = maxf(gm.Wv, gm.Hv)
	g.ga = alpha
	g.radial(gm.Wv / 2, gm.Hv / 2, [[m * 0.25, rgba(150, 0, 0, 0)], [m * 0.7, rgba(150, 0, 0, 1)]], 40)
	g.ga = 1.0

static func grade(gm, g: Pen) -> void:
	if gm.G == null: return
	g.set_xf(Transform2D.IDENTITY)
	var ox := randf() * 160
	var oy := randf() * 160
	g.ga = 0.1
	g.ci.draw_texture_rect(Tx.GRAIN, Rect2(-ox, -oy, gm.Wv + 160, gm.Hv + 160), true, Color(1, 1, 1, 0.1))
	g.ga = 1.0
	var h := fmod(gm.G.time / 60.0, 24.0)
	var k := 0.0
	if h >= 5 and h < 8.5: k = 1 - absf(h - 6.6) / 1.9
	elif h >= 16.3 and h < 19.8: k = 1 - absf(h - 18.1) / 1.8
	k = clampf(k, 0, 1)
	if k > 0.01: g.rect(0, 0, gm.Wv, gm.Hv, rgba(255, 150, 70, 0.13 * k))

static func draw_objective(gm, g: Pen, y: float) -> void:
	var txt: String = gm.menu.objective()
	var BW: float = gm.Wv - 24
	if gm.mode == "flight" and gm.F:
		var nt = gm.flight.nav_target()
		if nt:
			var F: Dictionary = gm.F
			var d := Vector2(nt.x - F.x, nt.y - F.y).length()
			var q := rad_to_deg(U.ang_diff(atan2(nt.y - F.y, nt.x - F.x), F.hdg))
			txt += " %d km, %s%s." % [U.km(d), "straight ahead" if absf(q) < 12 else ("turn right" if q > 0 else "turn left"), ", not enough fuel" if d > gm.range_now() else ""]
	var lines: Array = [txt]
	if Pen.measure(txt, 12) + 40 > BW:
		var ws := txt.split(" ")
		var a := ""
		for i in ws.size():
			var tr := (a + " " + ws[i]) if a != "" else ws[i]
			if Pen.measure(tr, 12) + 40 > BW and a != "":
				lines = [a, " ".join(ws.slice(i))]
				break
			a = tr
	var mw := 0.0
	for l in lines: mw = maxf(mw, Pen.measure(l, 12))
	var w := minf(BW, mw + 40)
	var hh := 40.0 if lines.size() > 1 else 24.0
	g.rr(10, y, w, hh, 5, rgba(60, 14, 40, 0.78))
	g.poly(PackedVector2Array([Vector2(21, y + 6), Vector2(26, y + 12), Vector2(21, y + 18), Vector2(16, y + 12)]), hc("#f0c4dd"))
	for i in lines.size():
		g.text(lines[i], 32, y + 12 + i * 16, 12, hc("#f6e8ef"), -1, "600", 0, Color.BLACK, w - 38)
	# mayday: its own bright red line under your destination, for as long as it lasts
	var mt = gm.flight.mayday_target() if (gm.mode == "flight" and gm.F) else null
	if mt:
		var F: Dictionary = gm.F
		var md := Vector2(mt.x - F.x, mt.y - F.y).length()
		var mq := rad_to_deg(U.ang_diff(atan2(mt.y - F.y, mt.x - F.x), F.hdg))
		var mtxt := "MAYDAY at %s, %d min left. %d km, %s%s." % [mt.name, maxi(0, int(round(gm.G.mayday.until - gm.G.time))), U.km(md),
			"straight ahead" if absf(mq) < 12 else ("turn right" if mq > 0 else "turn left"), ", not enough fuel" if md > gm.range_now() else ""]
		var my2 := y + hh + 6
		var mw2 := minf(BW, Pen.measure(mtxt, 12) + 40)
		var flash := 0.5 + 0.5 * sin(gm.T * 6)
		g.rr(10, my2, mw2, 24, 5, rgba(130, 10, 10, 0.82))
		g.poly(PackedVector2Array([Vector2(21, my2 + 6), Vector2(26, my2 + 12), Vector2(21, my2 + 18), Vector2(16, my2 + 12)]), rgba(255, 70 + 80 * flash, 60, 1))
		g.text(mtxt, 32, my2 + 12, 12, hc("#ffe3df"), -1, "700", 0, Color.BLACK, mw2 - 38)

# =====================================================================
# flight world
# =====================================================================
static func draw_world(gm, g: Pen, cx: float, cy: float, sc: float, t: float) -> Dictionary:
	var W: float = gm.Wv
	var H: float = gm.Hv
	var wd: World = gm.wd
	g.set_xf(Transform2D.IDENTITY)
	g.rect(0, 0, W, H, hc(SEA))
	var x0 := cx - W / 2 / sc
	var x1 := cx + W / 2 / sc
	var y0 := cy - H / 2 / sc
	var y1 := cy + H / 2 / sc
	g.set_view(sc, W / 2 - cx * sc, H / 2 - cy * sc)
	var ov: Texture2D = gm.baker.overview
	if ov:
		var opx := float(ov.get_width())
		var k := opx / D.WORLD
		var sx := clampf(x0 * k - 1, 0, opx - 1)
		var sy := clampf(y0 * k - 1, 0, opx - 1)
		var sw := clampf((x1 - x0) * k + 2, 1, opx - sx)
		var sh := clampf((y1 - y0) * k + 2, 1, opx - sy)
		g.tex_region(ov, Rect2(sx / k, sy / k, sw / k, sh / k), Rect2(sx, sy, sw, sh))
	# terrain chunks cover the land and the whole ocean margin around it
	var cmin := int(floor(-gm.OCEAN_PAD / CH)) - 2
	var cmax := int(floor((D.WORLD + gm.OCEAN_PAD) / CH)) + 2
	for gy in range(int(floor(y0 / CH)), int(floor(y1 / CH)) + 1):
		for gx in range(int(floor(x0 / CH)), int(floor(x1 / CH)) + 1):
			if gx < cmin or gy < cmin or gx > cmax or gy > cmax: continue
			var c: Texture2D = gm.baker.get_chunk(gx, gy)
			if c: g.tex(c, gx * CH, gy * CH, CH + 1, CH + 1)
	if sc > 0.5:
		var G2 := 70.0
		var al := clampf((sc - 0.5) / 0.22, 0, 1)
		g.ga = al
		var seed_v: int = wd.SEED
		for gy in range(int(floor(y0 / G2)) - 1, int(floor(y1 / G2)) + 2):
			for gx in range(int(floor(x0 / G2)) - 1, int(floor(x1 / G2)) + 2):
				var h := U.hash3(gx, gy, seed_v + 201)
				if h > 0.85: continue
				var ck := gx * 100003 + gy
				var cc = gm.TCACHE.get(ck)
				if cc == null:
					var wx0 := (gx + U.hash3(gx, gy, seed_v + 202)) * G2
					var wy0 := (gy + U.hash3(gx, gy, seed_v + 203)) * G2
					var t0 := wd.terr(wx0, wy0)
					var rd0 = wd.road_at(wx0, wy0) if (t0 >= 11 and t0 <= 13) else null
					cc = [wx0, wy0, t0, 1 if wd.strip_at(wx0, wy0, 6) else 0, rd0.r.ang if rd0 else null]
					gm.TCACHE[ck] = cc
					if gm.TCACHE.size() > 60000: gm.TCACHE.clear()
				var wx: float = cc[0]
				var wy: float = cc[1]
				var tt: int = cc[2]
				if tt <= 1:
					if h < 0.25:
						var kk := 0.5 + 0.5 * sin(t * 2 + h * 40)
						g.rect(wx - 9, wy, 18, 1.6, rgba(220, 235, 240, 0.18 * kk))
					continue
				if cc[3]: continue
				if tt >= 11 and tt <= 13:
					if h < 0.22 and cc[4] != null:
						g.save(); g.translate(wx, wy); g.rotate(cc[4] + (h - 0.11) * 3)
						g.rect(-7, -2, 18, 10, Color(0, 0, 0, 0.35))
						var cl: String = ["#6b3a2a", "#4a5560", "#7a6a3a", "#2a2826", "#8a8272"][int(h * 50) % 5]
						g.rect(-9, -4.5, 18, 9, hc(cl))
						g.rect(-3, -3.5, 4, 7, rgba(15, 18, 20, 0.85)); g.rect(3, -3, 2.5, 6, rgba(15, 18, 20, 0.85))
						g.restore()
					continue
				if tt == 7 or tt == 8:
					if h < 0.35:
						var rs := 5 + h * 22
						g.ellipse(wx + 3, wy + 4, rs, rs * 0.7, h * 5, Color(0, 0, 0, 0.28))
						g.ellipse(wx, wy, rs, rs * 0.7, h * 5, hc("#c8c8c4") if tt == 8 else hc("#8a857a"))
						g.ellipse(wx - rs * 0.3, wy - rs * 0.25, rs * 0.45, rs * 0.3, h * 5, Color(1, 1, 1, 0.15))
					continue
				if tt == 3 and h >= 0.05 and h < 0.16:
					var bs := 10 + h * 40
					g.tex(Tx.TREES[int(h * 70) % 3] if Tx.TREES.size() else null, wx - bs / 2, wy - bs / 2, bs, bs * 0.8)
					continue
				if tt == 5 or tt == 6:
					for q in 3:
						var hq := U.hash3(gx * 3 + q, gy, seed_v + 211)
						var ox := (U.hash3(gx, gy * 3 + q, seed_v + 212) - 0.5) * 60
						var oy := (U.hash3(gx + q, gy - q, seed_v + 213) - 0.5) * 60
						var sz2 := 30 + hq * 34
						g.tex(Tx.SPUFF, wx + ox - sz2 * 0.45 + 8, wy + oy - sz2 * 0.45 + 11, sz2 * 0.9, sz2 * 0.9)
						if Tx.TREES.size(): g.tex(Tx.TREES[int(hq * 30) % 3], wx + ox - sz2 / 2, wy + oy - sz2 / 2, sz2, sz2)
					continue
				if not ((tt == 3 and h < 0.05) or (tt == 4 and h < 0.012)): continue
				var sz := 24 + h * 38
				g.tex(Tx.SPUFF, wx - sz * 0.45 + 8, wy - sz * 0.45 + 11, sz * 0.9, sz * 0.9)
				if Tx.TREES.size(): g.tex(Tx.TREES[int(h * 30) % 3], wx - sz / 2, wy - sz / 2, sz, sz)
		g.ga = 1.0
	var tgt = gm.flight.nav_target() if (gm.mode == "flight" and gm.G and gm.F) else null
	var mdt = gm.flight.mayday_target() if (gm.mode == "flight" and gm.G and gm.F) else null
	for s in wd.strips:
		if s.x < x0 - 800 or s.x > x1 + 800 or s.y < y0 - 800 or s.y > y1 + 800: continue
		draw_strip(gm, g, s)
		if tgt != null and s.id == tgt.id:
			var pl := 0.5 + 0.5 * sin(t * 3)
			g.dashed_arc(s.x, s.y, s.len / 2 + 90 + pl * 20, 0, TAU, rgba(242, 182, 74, 0.45 + 0.4 * pl), 4 / sc, 18 / sc, 12 / sc)
		if mdt != null and s.id == mdt.id:
			var pm := 0.5 + 0.5 * sin(t * 6)
			g.dashed_arc(s.x, s.y, s.len / 2 + 150 + pm * 25, 0, TAU, rgba(255, 40, 30, 0.55 + 0.45 * pm), 5 / sc, 18 / sc, 12 / sc)
	draw_smoke(gm, g, x0, y0, x1, y1, t)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1}

static func draw_strip(gm, g: Pen, s: Dictionary) -> void:
	if s.type == "road": return
	var wd: World = gm.wd
	var F = gm.F
	g.save()
	g.translate(s.x, s.y)
	g.rotate(s.ang)
	var L: float = s.len
	var Wd: float = s.wid
	var sid: int = s.id
	var h0 := U.hash3(sid, 1, wd.SEED + 5)
	g.rr(-L / 2 - 90, -Wd / 2 - 60, L + 180, Wd + 210, 40, rgba(150, 170, 100, 0.13))
	if F and F.alt < 70 and gm.known.has(sid):
		var pc := rgba(212, 90, 157, 0.45)
		g.dashed(-L / 2 - 900, 0, -L / 2 - 30, 0, pc, 3, 24, 18)
		g.dashed(L / 2 + 30, 0, L / 2 + 900, 0, pc, 3, 24, 18)
	var dirt: bool = s.type == "dirt"
	var hav: bool = s.type == "haven"
	if not dirt:
		g.rect(-L / 4 - 10, Wd / 2, 34, 20, hc("#46443f"))
		g.rect(-L / 4 - 40, Wd / 2 + 18, 200, 56, hc("#46443f"))
	g.rect(-L / 2 - 6, -Wd / 2 - 6, L + 12, Wd + 12, rgba(20, 20, 16, 0.28))
	g.rect(-L / 2, -Wd / 2, L, Wd, hc("#3e4644") if hav else (hc("#8a7550") if dirt else hc("#3c3b38")))
	if dirt:
		g.rect(-L / 2, -6, L, 3, rgba(60, 45, 25, 0.3)); g.rect(-L / 2, 4, L, 3, rgba(60, 45, 25, 0.3))
		var x := -L / 2
		while x <= L / 2 + 0.01:
			g.rect(x - 3, -Wd / 2 - 6, 6, 4, rgba(240, 235, 220, 0.85)); g.rect(x - 3, Wd / 2 + 2, 6, 4, rgba(240, 235, 220, 0.85))
			x += L / 6
	else:
		var wc := hc("#e2dbc6")
		var x := -L / 2 + 50
		while x < L / 2 - 50:
			g.rect(x, -1.5, 24, 3, wc)
			x += 46
		for i in range(-3, 4):
			g.rect(-L / 2 + 8, i * Wd / 8 - 1.5, 26, 3, wc); g.rect(L / 2 - 34, i * Wd / 8 - 1.5, 26, 3, wc)
		for i in 8:
			g.rect(-L / 2 + 60 + U.hash3(sid, i, 3) * (L - 120), -Wd / 4 + U.hash3(i, sid, 4) * Wd / 2, 30, 4, Color(0, 0, 0, 0.25))
	var nh := 4 if hav else (3 if s.type == "airport" else (2 if s.type == "regional" else 1))
	for i in nh:
		var hx := -L / 4 - 30 + i * 72
		var hy := Wd / 2 + (22.0 if dirt else 26.0)
		var hw := 60.0
		var hh := 38.0 if dirt else 46.0
		g.rect(hx + 8, hy + 10, hw, hh, Color(0, 0, 0, 0.35))
		var rc: Array = ["#8a9a86", "#5d6b5a"] if hav else (["#8a8378", "#5a544b"] if U.hash3(sid, i, 9) < 0.5 else ["#8a5a44", "#5a3a2c"])
		g.rect(hx, hy, hw, hh / 2, hc(rc[0])); g.rect(hx, hy + hh / 2, hw, hh / 2, hc(rc[1]))
		g.rect(hx, hy + hh / 2 - 1, hw, 2, Color(1, 1, 1, 0.15))
		if U.hash3(sid, i, 11) < 0.3 and not hav: g.circle(hx + hw * 0.6, hy + hh * 0.4, 10, rgba(20, 16, 12, 0.7))
	if s.fuel and not hav:
		for i in 2:
			var fx := L / 4 + 10 + i * 26
			var fy := Wd / 2 + 40
			g.circle(fx + 5, fy + 6, 11, Color(0, 0, 0, 0.35)); g.circle(fx, fy, 11, hc("#b4aea2")); g.circle(fx - 3, fy - 3, 5, hc("#e2dccf"))
		g.rect(L / 4 + 60, Wd / 2 + 30, 10, 14, hc("#a3301f"))
	if hav:
		var x := -L / 2
		while x <= L / 2:
			g.rect(x - 3, -Wd / 2 - 8, 6, 6, hc("#9cc063")); g.rect(x - 3, Wd / 2 + 2, 6, 6, hc("#9cc063"))
			x += 40
		g.rect(-40, -Wd / 2 - 120, 80, 80, hc("#6f7a6a"))
		g.stroke_rr(-L / 2 - 70, -Wd / 2 - 150, L + 140, Wd + 300, 30, rgba(200, 200, 190, 0.6), 3)
	if not hav:
		var tx := L / 2 + 200
		var ty := Wd / 2 + 160
		var rdc := hc("#46443f")
		g.rect(tx - 190, ty - 7, 380, 14, rdc); g.rect(tx - 7, ty - 130, 14, 260, rdc); g.rect(-L / 4 + 20, Wd / 2 + 62, tx - (-L / 4 + 20), 8, rdc)
		var hi := [0]
		var house := func(hx: float, hy: float, hw: float, hh: float) -> void:
			hi[0] += 1
			var i: int = hi[0]
			if U.hash3(sid, i, 46) < 0.18: return
			g.rect(hx - hw / 2 + 5, hy - hh / 2 + 6, hw, hh, Color(0, 0, 0, 0.35))
			var rc := hc(D.HOUSEROOF[int(U.hash3(i, sid, 45) * D.HOUSEROOF.size())])
			var cA := U.shade(rc, 1.15)
			var cB := U.shade(rc, 0.68)
			if hw >= hh:
				g.rect(hx - hw / 2, hy - hh / 2, hw, hh / 2, cA); g.rect(hx - hw / 2, hy, hw, hh / 2, cB)
			else:
				g.rect(hx - hw / 2, hy - hh / 2, hw / 2, hh, cA); g.rect(hx, hy - hh / 2, hw / 2, hh, cB)
		for k in range(-5, 6):
			if k == 0: continue
			var hx := tx + k * 34
			var w1 := 24 + U.hash3(sid, k, 47) * 8
			house.call(hx, ty - 26, w1, 22.0); house.call(hx, ty + 26, w1, 22.0)
		for k in range(-3, 4):
			if k == 0: continue
			var hy := ty + k * 34
			house.call(tx - 26, hy, 22.0, 24.0); house.call(tx + 26, hy, 22.0, 24.0)
	if h0 < 0.35 and not hav:
		g.save(); g.translate(L / 2 + 50, -Wd / 2 - 40); g.rotate(h0 * 9)
		g.ga = 0.85
		draw_plane(g, D.PLANES[int(h0 * 10) % 2], 30, 0, false)
		g.circle(2, 4, 9, rgba(20, 14, 10, 0.6))
		g.restore()
	var wx := -L / 2 + 40
	var wy := -Wd / 2 - 26
	var wa: float = (atan2(F.wind.y, F.wind.x) - s.ang) if F else 0.6
	g.circle(wx, wy, 2.5, hc("#dddddd"))
	g.save(); g.translate(wx, wy); g.rotate(wa + sin(gm.T * 3) * 0.08)
	g.poly(PackedVector2Array([Vector2(0, -4), Vector2(22, -2), Vector2(22, 2), Vector2(0, 4)]), hc("#ff7a2a"))
	g.rect(8, -3, 4, 6, Color.WHITE)
	g.restore()
	g.restore()

static func draw_smoke(gm, g: Pen, x0: float, y0: float, x1: float, y1: float, t: float) -> void:
	var C := 2600.0
	var wd: World = gm.wd
	for cy in range(int(floor((y0 - 500) / C)), int(floor((y1 + 300) / C)) + 1):
		for cx in range(int(floor((x0 - 500) / C)), int(floor((x1 + 300) / C)) + 1):
			if U.hash3(cx, cy, wd.SEED + 77) > 0.24: continue
			var sx := (cx + 0.2 + U.hash3(cx, cy, wd.SEED + 78) * 0.6) * C
			var sy := (cy + 0.2 + U.hash3(cx, cy, wd.SEED + 79) * 0.6) * C
			var ck := -(cx * 100003 + cy) - 7
			var v = gm.TCACHE.get(ck)
			if v == null:
				v = wd.terr(sx, sy) > 2
				gm.TCACHE[ck] = v
			if not v: continue
			g.circle(sx, sy, 6 + randf() * 3, rgba(255, 120 + randf() * 60, 40, 0.8))
			for i in 8:
				var k := fmod(t * 0.07 + i / 8.0 + U.hash3(cx, cy, 5), 1.0)
				g.circle(sx + k * 300, sy - k * 170, 16 + k * 95, rgba(46, 44, 42, 0.38 * (1 - k)))

static func draw_clouds(gm, g: Pen, cx: float, cy: float, sc: float, alpha: float) -> void:
	var C := 1700.0
	var W: float = gm.Wv
	var H: float = gm.Hv
	var seed_v: int = gm.wd.SEED
	var clouds_in := func(s2: float, pad: float, fn: Callable) -> void:
		var x0 := cx - W / 2 / s2 - pad
		var x1 := cx + W / 2 / s2 + pad
		var y0 := cy - H / 2 / s2 - pad
		var y1 := cy + H / 2 / s2 + pad
		for gy in range(int(floor(y0 / C)), int(floor(y1 / C)) + 1):
			for gx in range(int(floor(x0 / C)), int(floor(x1 / C)) + 1):
				if U.hash3(gx, gy, seed_v + 91) > CLOUD_DENSITY: continue
				var bx := (gx + U.hash3(gx, gy, seed_v + 92)) * C
				var by := (gy + U.hash3(gx, gy, seed_v + 93)) * C
				for i in 6:
					var a := U.hash3(gx * 7 + i, gy, seed_v + 94) * TAU
					var r := U.hash3(gx, gy * 7 + i, seed_v + 95)
					fn.call(bx + cos(a) * r * 150, by + sin(a) * r * 85, 90 + r * 110)
	g.set_view(sc, W / 2 - cx * sc, H / 2 - cy * sc)
	g.ga = 0.13
	clouds_in.call(sc, 800.0, func(x, y, rad): g.tex(Tx.SPUFF, x + 260 - rad, y + 380 - rad, rad * 2, rad * 2))
	if alpha > 0.01:
		var s2 := sc * 1.3
		g.set_view(s2, W / 2 - cx * s2, H / 2 - cy * s2)
		g.ga = minf(1, alpha * 2.6)
		clouds_in.call(s2, 400.0, func(x, y, rad): g.tex(Tx.PUFF, x - rad, y - rad, rad * 2, rad * 2))
	g.ga = 1.0

static var storm_imgs := {}
static func draw_storms(gm, g: Pen, cx: float, cy: float, sc: float) -> void:
	var s2 := sc * 1.3
	var W: float = gm.Wv
	var H: float = gm.Hv
	g.set_view(s2, W / 2 - cx * s2, H / 2 - cy * s2)
	var hw := W / 2 / s2
	var hh := H / 2 / s2
	var fade := 1 - clampf((gm.F.storm if gm.F else 0.0) * 1.6, 0, 0.85)
	var seed_v: int = gm.wd.SEED
	for s in gm.wd.STORMS:
		var q: Vector2 = gm.wd.storm_pos(s)
		var E: float = s.r * 1.3
		if q.x + E < cx - hw or q.x - E > cx + hw or q.y + E < cy - hh or q.y - E > cy + hh: continue
		g.ga = fade * 0.6
		var ri := int(s.r)
		for i in 11:
			var a := U.hash3(i, ri, seed_v + 61) * TAU
			var d: float = U.hash3(i, 7, ri) * s.r * 0.6
			var rad: float = s.r * (0.34 + U.hash3(i, 3, ri) * 0.34)
			g.tex(Tx.DPUFF, q.x + cos(a) * d - rad, q.y + sin(a) * d - rad, rad * 2, rad * 2)
		if randf() < 0.03:
			var a := randf() * TAU
			var d: float = randf() * s.r * 0.5
			var rad: float = s.r * 0.45
			g.ga = 0.35 * fade
			g.tex(Tx.LPUFF, q.x + cos(a) * d - rad, q.y + sin(a) * d - rad, rad * 2, rad * 2)
	g.ga = 1.0

# =====================================================================
# flight frame
# =====================================================================
static func prep_flight(gm) -> void:
	var F: Dictionary = gm.F
	var lx: float = F.x + cos(F.hdg) * F.spd * 0.9
	var ly: float = F.y + sin(F.hdg) * F.spd * 0.9
	if gm.cam_snap:
		gm.camX = lx; gm.camY = ly; gm.cam_snap = false
	else:
		gm.camX = lerpf(gm.camX, lx, 0.08); gm.camY = lerpf(gm.camY, ly, 0.08)
	# prefetch chunks ahead of the plane
	var ax: float = F.x + cos(F.hdg) * 1500
	var ay: float = F.y + sin(F.hdg) * 1500
	for o in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var gx = int(floor(ax / CH)) + o[0]
		var gy = int(floor(ay / CH)) + o[1]
		if gx < -1 or gy < -1 or gx > 30 or gy > 30: continue
		if not gm.baker.has_chunk(gx, gy):
			gm.baker.get_chunk(gx, gy)
			break

static func flight_layer(gm, idx: int, g: Pen) -> void:
	var F: Dictionary = gm.F
	var P: Dictionary = gm.PS()
	var sc := flight_scale(gm, F.alt)
	var alt := maxf(0.0, F.alt)
	var W: float = gm.Wv
	var H: float = gm.Hv
	match idx:
		0:
			var vb := draw_world(gm, g, gm.camX, gm.camY, sc, gm.T)
			gm.set_meta("vb", vb)
			var hz2 := clampf(F.alt / 100.0, 0, 1)
			if hz2 > 0.02:
				g.save(); g.set_xf(Transform2D.IDENTITY); g.rect(0, 0, W, H, rgba(172, 186, 200, hz2 * 0.07)); g.restore()
			var grow := 1 + alt / 260.0
			g.save(); g.translate(F.x + alt * 0.7, F.y + alt * 1.1); g.rotate(F.hdg); draw_plane(g, P, P.size * 1.7, 0, true, F.bank); g.restore()
			g.save(); g.translate(F.x, F.y); g.rotate(F.hdg); draw_plane(g, P, P.size * 1.7 * grow, F.prop, false, F.bank); g.restore()
			if not F.onGround and not F.crashed and (F.vs < -0.5 or F.alt < 30):
				var pt = gm.flight.predict_touchdown()
				if pt and pt.t < 45:
					var s = gm.wd.strip_at(pt.x, pt.y, 1)
					var c := hc("#d9a441")
					if pt.vs <= -15: c = hc("#e3644c")
					else:
						var ok: bool = s != null and gm.flight.align_to(s.ang, F.trk)
						if not ok:
							var rd = gm.wd.road_at(pt.x, pt.y)
							ok = rd != null and gm.flight.align_to(rd.r.ang, F.trk)
						if ok: c = hc("#9cc063")
					var q := 11 / sc
					var cl := c
					cl.a = 0.55
					g.dashed(F.x + alt * 0.7, F.y + alt * 1.1, pt.x, pt.y, cl, 2 / sc, 6 / sc, 7 / sc)
					for k in 2:
						var lw := (2.5 if k else 3.5) / sc
						var col: Color = c if k else Color(0, 0, 0, 0.6)
						g.lines(PackedVector2Array([Vector2(pt.x - q, pt.y - q), Vector2(pt.x + q, pt.y + q), Vector2(pt.x + q, pt.y - q), Vector2(pt.x - q, pt.y + q)]), col, lw)
						g.ring(pt.x, pt.y, q * 1.7, col, lw)
			if F.crashed:
				for i in 14:
					var a := randf() * TAU
					var r: float = randf() * P.size * 0.8
					g.circle(F.x + cos(a) * r, F.y + sin(a) * r, P.size * (0.15 + randf() * 0.3), rgba(255, 120 + randf() * 90, 40, 0.7) if i % 3 else rgba(30, 26, 24, 0.6))
			var tlw := maxf(2, 2.5 / sc)
			for tr in F.tracers:
				var a: float = tr.life / 0.35
				g.line(tr.x + (tr.tx - tr.x) * (1 - a), tr.y + (tr.ty - tr.y) * (1 - a), tr.x + (tr.tx - tr.x) * minf(1, 1.3 - a), tr.y + (tr.ty - tr.y) * minf(1, 1.3 - a), rgba(255, 190, 90, a), tlw)
			var ai = gm.flight.approach_info()
			if ai and ai.phase != "high" and ai.slack > -200:
				var pl := 0.5 + 0.5 * sin(gm.T * 5)
				var nx: float = -ai.cy
				var ny: float = ai.cx
				var now: bool = ai.phase == "now"
				var col := rgba(255, 224, 120, 0.6 + 0.3 * pl) if now else rgba(240, 160, 210, 0.55)
				var GW := maxf(70, 20 / sc)
				var tdx: float = ai.s.x + ai.cx * (-ai.s.len / 2 + ai.s.len * 0.22)
				var tdy: float = ai.s.y + ai.cy * (-ai.s.len / 2 + ai.s.len * 0.22)
				g.dashed(ai.px, ai.py, tdx, tdy, col, 1.5 / sc, 8 / sc, 10 / sc)
				g.line(ai.px - nx * GW, ai.py - ny * GW, ai.px + nx * GW, ai.py + ny * GW, col, 3 / sc)
				g.save(); g.translate(ai.px + nx * (GW + 12 / sc), ai.py + ny * (GW + 12 / sc)); g.scale(1 / sc, 1 / sc)
				g.text("Start down" if now else "Descend here", 0, 0, 12, hc("#ffe08a") if now else hc("#f0d0e2"), -1, "600", 3, Color(0, 0, 0, 0.6))
				g.restore()
			var dk: float = gm.dark()
			if dk >= 0.02:
				g.set_xf(Transform2D.IDENTITY)
				g.rect(0, 0, W, H, rgba(6, 10, 28, 0.7 * dk))
		1:
			night_glows(gm, g, sc, alt, P)
		2:
			draw_storms(gm, g, gm.camX, gm.camY, sc)
			draw_clouds(gm, g, gm.camX, gm.camY, sc, clampf((alt - 45) / 60.0, 0, 1) * (0.28 - 0.2 * gm.dark()))
			g.set_xf(Transform2D.IDENTITY)
			if F.storm > 0:
				var k: float = F.storm
				g.rect(0, 0, W, H, rgba(18, 22, 30, k * 0.45))
				var ln := PackedVector2Array()
				for i in int(90 * k):
					var x := randf() * W
					var y := randf() * H
					ln.append(Vector2(x, y)); ln.append(Vector2(x - 5, y + 16))
				g.lines(ln, rgba(200, 210, 225, 0.35), 1.2)
			if F.flash > 0: g.rect(0, 0, W, H, rgba(235, 240, 255, minf(1, F.flash * 2)))
			vignette(gm, g, 0.34)
			grade(gm, g)
		7:
			hud_flight(gm, g, P, sc)

static func night_glows(gm, g: Pen, sc: float, alt: float, P: Dictionary) -> void:
	var dk: float = gm.dark()
	if dk < 0.02: return
	var F: Dictionary = gm.F
	var W: float = gm.Wv
	var H: float = gm.Hv
	g.set_view(sc, W / 2 - gm.camX * sc, H / 2 - gm.camY * sc)
	var vb: Dictionary = gm.get_meta("vb", {"x0": 0, "y0": 0, "x1": 0, "y1": 0})
	var glow := func(x: float, y: float, r: float, key: String, a: float) -> void:
		g.ga = minf(1, a)
		g.tex(Tx.glow(key), x - r, y - r, r * 2, r * 2)
		g.ga = 1.0
	var lr := maxf(14, 9 / sc)
	for s in gm.wd.strips:
		if not s.fuel or s.x < vb.x0 - 800 or s.x > vb.x1 + 800 or s.y < vb.y0 - 800 or s.y > vb.y1 + 800: continue
		var c := cos(s.ang)
		var n := sin(s.ang)
		var hav: bool = s.type == "haven"
		for i in 7:
			var u: float = -s.len / 2 + s.len * i / 6.0
			for sd in [-1, 1]:
				var o: float = sd * (s.wid / 2 + 6)
				glow.call(s.x + c * u - n * o, s.y + n * u + c * o, lr, "140,230,120" if hav else "255,215,140", dk if hav else 0.85 * dk)
	var C := 2600.0
	var wd: World = gm.wd
	for cy in range(int(floor((vb.y0 - 500) / C)), int(floor((vb.y1 + 300) / C)) + 1):
		for cx in range(int(floor((vb.x0 - 500) / C)), int(floor((vb.x1 + 300) / C)) + 1):
			if U.hash3(cx, cy, wd.SEED + 77) > 0.24: continue
			var sx := (cx + 0.2 + U.hash3(cx, cy, wd.SEED + 78) * 0.6) * C
			var sy := (cy + 0.2 + U.hash3(cx, cy, wd.SEED + 79) * 0.6) * C
			var v = gm.TCACHE.get(-(cx * 100003 + cy) - 7)
			if v == null or not v: continue
			glow.call(sx, sy, 170 + randf() * 20, "255,110,40", 0.45 * dk)
	g.save()
	g.translate(F.x, F.y)
	g.rotate(F.hdg)
	var sz: float = P.size * 1.7 * (1 + alt / 260.0)
	if alt < 75:
		g.radial(0, 0, [[0.0, rgba(255, 240, 200, 0.28 * dk)], [520.0, Color(0, 0, 0, 0)]], 24)
	var blink := fmod(gm.T, 1.2) < 0.12
	glow.call(sz * 0.1, -sz * 0.6, 10, "255,60,50", dk)
	glow.call(sz * 0.1, sz * 0.6, 10, "60,255,120", dk)
	if blink: glow.call(-sz * 0.45, 0, 16, "255,255,255", dk)
	g.restore()

static func hud_flight(gm, g: Pen, P: Dictionary, sc: float) -> void:
	var F: Dictionary = gm.F
	var G: Dictionary = gm.G
	var W: float = gm.Wv
	var H: float = gm.Hv
	var T: float = gm.T
	var wd: World = gm.wd
	g.set_xf(Transform2D.IDENTITY)
	var pw := minf(W - 150, 340)
	var px := 10.0
	var py := 10.0
	g.rr(px, py, pw, 70, 6, rgba(12, 16, 14, 0.74))
	var fr: float = G.fuel / P.fuelCap
	g.text("Fuel", px + 10, py + 17, 12, hc("#b9b09a"))
	g.rect(px + 44, py + 11, pw - 56, 12, Color(1, 1, 1, 0.12))
	g.rect(px + 44, py + 11, (pw - 56) * fr, 12, (hc("#e3644c") if fmod(T, 1.0) < 0.5 else hc("#8a2a1c")) if fr < 0.2 else hc("#d9a441"))
	var ink := hc("#efe6cf")
	g.text("%.1f of %d gal, %d km left, hull %d%%" % [G.fuel, int(P.fuelCap), U.km(gm.range_now()), int(ceil(G.hull))], px + 10, py + 38, 13, ink)
	var hdg := int(round(fmod(rad_to_deg(F.hdg) + 90 + 360 * 4, 360)))
	g.text("%d kt   %d ft   %s%d fpm   %s°" % [int(round(F.spd * 0.75)), int(round(maxf(0, F.alt) * 45)), "▲" if F.vs >= 0 else "▼", absi(int(round(F.vs * 27))) * 100, ("00" + str(hdg)).right(3)], px + 10, py + 57, 13, ink)
	# minimap
	var mr := minf(58, W * 0.15)
	var mx := W - mr - 12
	var my := mr + 12
	var R := 6000.0
	var k := mr / R
	# open sea beyond the map edge: same colour the main flight view uses there
	g.circle(mx, my, mr, hc(SEA))
	var ovw: Texture2D = gm.baker.overview_wide
	var ov: Texture2D = gm.baker.overview
	if ovw:
		# real terrain and sea all the way out (the wide overview covers the ocean margin)
		var o: float = gm.baker.wide_origin
		var span: float = gm.baker.wide_span
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			var sp := Vector2(mx + cos(a) * mr, my + sin(a) * mr)
			pts.append(sp)
			uvs.append(Vector2((F.x + (sp.x - mx) / k - o) / span, (F.y + (sp.y - my) / k - o) / span))
		g.ci.draw_colored_polygon(pts, Color.WHITE, uvs, ovw)
	elif ov:
		# Draw the overview inside the circle, but only where it actually covers the
		# world. Past the map edge the texture's UVs would run outside 0..1 and smear
		# its edge pixels into streaks, so clip the circle to the world's rectangle.
		var circ := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			circ.append(Vector2(mx + cos(a) * mr, my + sin(a) * mr))
		var wx0: float = mx + (0.0 - F.x) * k
		var wy0: float = my + (0.0 - F.y) * k
		var wx1: float = mx + (D.WORLD - F.x) * k
		var wy1: float = my + (D.WORLD - F.y) * k
		var wrect := PackedVector2Array([Vector2(wx0, wy0), Vector2(wx1, wy0), Vector2(wx1, wy1), Vector2(wx0, wy1)])
		for pts in Geometry2D.intersect_polygons(circ, wrect):
			var uvs := PackedVector2Array()
			for sp in pts:
				uvs.append(Vector2((F.x + (sp.x - mx) / k) / D.WORLD, (F.y + (sp.y - my) / k) / D.WORLD))
			g.ci.draw_colored_polygon(pts, Color.WHITE, uvs, ov)
	g.circle(mx, my, mr, rgba(10, 14, 12, 0.25))
	for s in wd.STORMS:
		var q: Vector2 = wd.storm_pos(s)
		var sxp = mx + (q.x - F.x) * k
		var syp = my + (q.y - F.y) * k
		var sr: float = s.r * k
		if Vector2(sxp - mx, syp - my).length() - sr > mr: continue
		_clipped_disc(g, sxp, syp, sr, mx, my, mr, rgba(120, 140, 190, 0.35))
	var rn: float = gm.range_now() * k
	if rn < mr: g.dashed_arc(mx, my, rn, 0, TAU, rgba(212, 90, 157, 0.9), 1, 3, 3)
	var nt = gm.flight.nav_target()
	var mdt2 = gm.flight.mayday_target()
	for s in wd.strips:
		if not gm.known.has(s.id): continue
		var dx: float = (s.x - F.x) * k
		var dy: float = (s.y - F.y) * k
		if dx * dx + dy * dy > mr * mr * 0.9: continue
		var isnt: bool = nt != null and nt.id == s.id
		g.ring(mx + dx, my + dy, 4.5 if isnt else 3.0, hc("#9cc063") if s.type == "haven" else hc("#e07ab3"), 2.5 if isnt else 1.5)
		if mdt2 != null and mdt2.id == s.id:
			g.ring(mx + dx, my + dy, 7.0, hc("#ff2a1e"), 2.5)
	g.save(); g.translate(mx, my); g.rotate(F.hdg)
	g.poly(PackedVector2Array([Vector2(6, 0), Vector2(-4, -4), Vector2(-4, 4)]), Color.WHITE)
	g.restore()
	g.ring(mx, my, mr, rgba(239, 230, 207, 0.5), 1.5)
	g.text("N", mx, my - mr + 9, 11, ink, 0, "700")
	draw_objective(gm, g, py + 120)
	var wv: float = F.wind.length()
	var wy := py + 92
	g.rr(px, wy - 13, 172, 26, 5, rgba(12, 16, 14, 0.74))
	if wv > 1:
		g.save(); g.translate(px + 18, wy); g.rotate(atan2(F.wind.y, F.wind.x))
		g.lines(PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(8, 0), Vector2(3, -4), Vector2(8, 0), Vector2(3, 4)]), ink, 2)
		g.restore()
	g.text("%s   Day %d, %s" % [("Wind %d kt" % int(round(wv * 0.75))) if wv > 1 else "Calm", gm.day(), gm.clock()], px + 34, wy, 12, ink)
	var psx: float = W / 2 + (F.x - gm.camX) * sc
	var psy: float = H / 2 + (F.y - gm.camY) * sc
	var ntp = null
	if nt:
		var a2 := atan2(nt.y - F.y, nt.x - F.x)
		var r2 := minf(W, H) * 0.2 + 24
		ntp = Vector2(psx + cos(a2) * r2, psy + sin(a2) * r2)
	for s in wd.strips:
		if not gm.known.has(s.id): continue
		var sx: float = W / 2 + (s.x - gm.camX) * sc
		var sy: float = H / 2 + (s.y - gm.camY) * sc
		if sx < -60 or sx > W + 60 or sy < -30 or sy > H + 30: continue
		var t: String = "Haven" if s.type == "haven" else s.name
		var ly: float = sy - s.wid * sc - 18
		if ntp != null:
			var lw2 := Pen.measure(t, 12) / 2 + 26
			if absf(sx - ntp.x) < lw2 and absf(ly - ntp.y) < 26: continue
		g.text(t, sx, ly, 12, hc("#f0c4dd"), 0, "600", 3, Color(0, 0, 0, 0.65))
	if nt:
		var a := atan2(nt.y - F.y, nt.x - F.x)
		var d := Vector2(nt.x - F.x, nt.y - F.y).length()
		if d > 250:
			var rd := minf(W, H) * 0.2 + 24
			var pl := 0.5 + 0.5 * sin(T * 4)
			var ax := psx + cos(a) * rd
			var ay := psy + sin(a) * rd
			var short: bool = d > gm.range_now()
			var lbl := "%s %d km" % ["Haven" if nt.type == "haven" else String(nt.name).split(" ")[0], U.km(d)]
			var lw := Pen.measure(lbl, 14, "700") + 16
			var lh := 22.0
			var place := func(sgn: float) -> Vector2:
				var off := 26 + absf(cos(a)) * lw / 2 + absf(sin(a)) * lh / 2
				return Vector2(psx + cos(a) * (rd + sgn * off), psy + sin(a) * (rd + sgn * off))
			var fits := func(v: Vector2) -> bool: return v.x - lw / 2 >= 6 and v.x + lw / 2 <= W - 66 and v.y - lh / 2 >= 150 and v.y + lh / 2 <= H - 110
			var tp: Vector2 = place.call(1.0)
			if not fits.call(tp):
				var alt2: Vector2 = place.call(-1.0)
				if fits.call(alt2): tp = alt2
				else: tp = Vector2(clampf(tp.x, lw / 2 + 6, W - lw / 2 - 66), clampf(tp.y, 150 + lh / 2, H - 110 - lh / 2))
			if absf(tp.x - ax) < lw / 2 + 18 and absf(tp.y - ay) < lh / 2 + 18: tp.y = ay + (-1 if ay > H / 2 else 1) * (lh / 2 + 22)
			g.rr(tp.x - lw / 2, tp.y - lh / 2, lw, lh, 5, rgba(12, 16, 14, 0.72))
			g.text(lbl, tp.x, tp.y, 14, hc("#ff8a70") if short else hc("#f3d38c"), 0, "700")
			g.dashed_arc(psx, psy, rd, a - 0.5, a + 0.5, rgba(217, 164, 65, 0.25 + 0.2 * pl), 2, 4, 8)
			g.save(); g.translate(ax, ay); g.rotate(a); var kk := 1.25 + pl * 0.15; g.scale(kk, kk)
			var arrow := PackedVector2Array([Vector2(16, 0), Vector2(-9, -12), Vector2(-3, 0), Vector2(-9, 12)])
			g.poly(arrow, hc("#ff8a70") if short else hc("#f2b64a"))
			var ac := arrow.duplicate(); ac.append(arrow[0])
			g.polyline(ac, Color(0, 0, 0, 0.65), 2.5)
			g.restore()
	var mt = gm.flight.mayday_target()
	if mt:
		var ma := atan2(mt.y - F.y, mt.x - F.x)
		var md := Vector2(mt.x - F.x, mt.y - F.y).length()
		if md > 250:
			var mrd := minf(W, H) * 0.2 + 64
			var mpl := 0.5 + 0.5 * sin(T * 6)
			var max2 := psx + cos(ma) * mrd
			var may2 := psy + sin(ma) * mrd
			var mlbl := "MAYDAY %s %d km" % [String(mt.name).split(" ")[0], U.km(md)]
			var mlw := Pen.measure(mlbl, 14, "700") + 16
			var mlh := 22.0
			var mplace := func(sgn: float) -> Vector2:
				var off := 26 + absf(cos(ma)) * mlw / 2 + absf(sin(ma)) * mlh / 2
				return Vector2(psx + cos(ma) * (mrd + sgn * off), psy + sin(ma) * (mrd + sgn * off))
			var mfits := func(v: Vector2) -> bool: return v.x - mlw / 2 >= 6 and v.x + mlw / 2 <= W - 66 and v.y - mlh / 2 >= 150 and v.y + mlh / 2 <= H - 110
			var mtp: Vector2 = mplace.call(1.0)
			if not mfits.call(mtp):
				var malt: Vector2 = mplace.call(-1.0)
				if mfits.call(malt): mtp = malt
				else: mtp = Vector2(clampf(mtp.x, mlw / 2 + 6, W - mlw / 2 - 66), clampf(mtp.y, 150 + mlh / 2, H - 110 - mlh / 2))
			if absf(mtp.x - max2) < mlw / 2 + 18 and absf(mtp.y - may2) < mlh / 2 + 18: mtp.y = may2 + (-1 if may2 > H / 2 else 1) * (mlh / 2 + 22)
			g.rr(mtp.x - mlw / 2, mtp.y - mlh / 2, mlw, mlh, 5, rgba(12, 16, 14, 0.72))
			g.text(mlbl, mtp.x, mtp.y, 14, hc("#ff5a4a"), 0, "700")
			g.dashed_arc(psx, psy, mrd, ma - 0.5, ma + 0.5, rgba(255, 40, 30, 0.35 + 0.3 * mpl), 2, 4, 8)
			g.save(); g.translate(max2, may2); g.rotate(ma); var mk := 1.25 + mpl * 0.15; g.scale(mk, mk)
			var marrow := PackedVector2Array([Vector2(16, 0), Vector2(-9, -12), Vector2(-3, 0), Vector2(-9, 12)])
			g.poly(marrow, hc("#ff2a1e"))
			var mac := marrow.duplicate(); mac.append(marrow[0])
			g.polyline(mac, Color(0, 0, 0, 0.65), 2.5)
			g.restore()
	# throttle
	var tb: Dictionary = gm.thr_bar
	g.rr(tb.x - 4, tb.y - 24, tb.w + 8, tb.h + 32, 6, rgba(12, 16, 14, 0.74))
	g.rect(tb.x, tb.y, tb.w, tb.h, Color(1, 1, 1, 0.1))
	g.rect(tb.x, tb.y + tb.h * (1 - F.thr), tb.w, tb.h * F.thr, hc("#d9a441") if G.fuel > 0 else hc("#6b5a3a"))
	var ay2: float = tb.y + tb.h * 0.67
	g.line(tb.x - 4, ay2, tb.x + tb.w + 4, ay2, hc("#d45a9d"), 2)
	g.text("%d%%" % int(round(F.thr * 100)), tb.x + tb.w / 2, tb.y - 12, 12, ink, 0, "700")
	g.save(); g.translate(tb.x - 12, ay2); g.rotate(-PI / 2)
	g.text("Approach", 0, 0, 11, hc("#e07ab3"), 0)
	g.restore()
	# status
	var msg := ""
	var c := ink
	var near = wd.nearest_strip(F.x, F.y, 1600)
	var rdh = wd.road_at(F.x, F.y) if (not F.onGround and F.alt < 40) else null
	var blinkc := hc("#e3644c") if fmod(T, 0.5) < 0.25 else ink
	if G.fuel <= 0 and not F.onGround:
		msg = "Engine out. The road below will do." if rdh else "Engine out. Glide to a runway or a road."
		c = hc("#e3644c")
	elif not F.onGround and G.hull < 25:
		msg = "Airframe failing. Land now."; c = blinkc
	elif F.storm > 0.5:
		msg = "Severe turbulence."; c = hc("#e3644c")
	elif F.underFire > 0:
		msg = "Ground fire. Climb."; c = hc("#e3644c")
	elif F.onGround and F.departing:
		msg = "Push the throttle up to roll." if F.spd < 3 else "Rolling. Stay on the runway."
	elif F.onGround:
		msg = "Cut the throttle to stop." if F.thr > 0.1 else "Braking."
	elif F.vs < -15 and F.alt < 35:
		msg = "Sinking too fast. Add power."; c = blinkc
	elif G.fuel / P.fuelCap < 0.15:
		msg = "Low fuel."; c = hc("#e3644c")
	elif G.leak > 0 and not F.onGround:
		msg = "Fuel leak, %.1f gal a minute." % (G.leak * 60); c = hc("#e3644c")
	elif rdh and gm.flight.align_to(rdh.r.ang, F.trk):
		msg = "Over a straight stretch of road. You could put it down here."; c = hc("#f0c4dd")
	else:
		gm.AP = gm.flight.approach_info()
		var AP = gm.AP
		if AP and (AP.phase != "early" or F.alt < 75):
			var nm: String = "Haven" if AP.s.type == "haven" else AP.s.name
			if AP.phase == "early":
				msg = "Hold your altitude. Start down for %s in %d km." % [nm, maxi(1, U.km(AP.slack))]; c = hc("#f0c4dd")
			elif AP.phase == "now":
				msg = "Start your descent now. Pull the throttle to the pink mark."; c = hc("#ffe08a") if fmod(T, 0.6) < 0.3 else hc("#f0c4dd")
			elif AP.phase == "late":
				msg = "You started down late. Cut the power further or you will overshoot."; c = hc("#ffb080")
			else:
				msg = "Too high and fast to land at %s. Circle back and start down earlier." % nm; c = hc("#e3644c")
		elif F.assist and near:
			var nn: String = "Haven" if near.type == "haven" else near.name
			msg = ("Approach assist is bringing you down at %s. Hands off." % nn) if F.thr <= 0.75 else "Approach assist is lining you up. Pull the throttle back to the mark."
			c = hc("#f0c4dd")
		elif near and F.alt < 70 and gm.known.has(near.id):
			var nn: String = "Haven" if near.type == "haven" else near.name
			msg = ("Lined up with %s. Ease down." % nn) if gm.flight.align_ok(near) else ("Line up with the runway at %s." % nn)
			c = hc("#f0c4dd")
	if msg != "":
		var w := minf(W - 20, Pen.measure(msg, 15) + 24)
		g.rr(W / 2 - w / 2, H - 100, w, 30, 5, rgba(12, 16, 14, 0.74))
		g.text(msg, W / 2, H - 85, 15, c, 0, "600", 0, Color.BLACK, w - 16)
	for p in gm.ptrs.values():
		if p.role == "steer":
			g.line(p.sx - 70, p.sy, p.sx + 70, p.sy, rgba(239, 230, 207, 0.35), 2)
			g.circle(clampf(p.x, p.sx - 70, p.sx + 70), p.sy, 14, rgba(239, 230, 207, 0.5))

static func _clipped_disc(g: Pen, x: float, y: float, r: float, cx: float, cy: float, cr: float, col: Color) -> void:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		a.append(Vector2(x + cos(t) * r, y + sin(t) * r))
		b.append(Vector2(cx + cos(t) * cr, cy + sin(t) * cr))
	for poly in Geometry2D.intersect_polygons(a, b):
		if poly.size() >= 3: g.poly(poly, col)

# =====================================================================
# ground frame
# =====================================================================
static func prep_ground(gm) -> void:
	var S: Dictionary = gm.S
	var sh: float = S.shake
	S.rcx = S.cx + (randf() - 0.5) * sh
	S.rcy = S.cy + (randf() - 0.5) * sh
	var dk: float = gm.dark()
	var dr: ColorRect = gm.dark_rect
	if dk > 0.02:
		var gs: float = gm.ground_scale()
		var p: Dictionary = S.p
		var vx: float = gm.Wv / 2 + (p.x - S.rcx) * gs
		var vy: float = gm.Hv / 2 + (p.y - S.rcy) * gs
		var m: ShaderMaterial = gm.dark_mat
		m.set_shader_parameter("dk", dk)
		m.set_shader_parameter("screen", Vector2(gm.Wv, gm.Hv))
		m.set_shader_parameter("ppos", Vector2(vx, vy))
		m.set_shader_parameter("r0", (150.0 if gm.has("monocle") else 110.0) * gs)
		m.set_shader_parameter("cone_a", p.ang)
		m.set_shader_parameter("cone_l", (620.0 if gm.has("monocle") else 430.0) * gs * (0.3 if S.flick > 0 else 1.0))
		m.set_shader_parameter("flash_r", 340.0 * gs if (S.flash > 0 or S.boomFlash > 0) else 0.0)
		var arr := PackedVector3Array()
		for l in S.lights:
			if not l.on: continue
			var sx: float = gm.Wv / 2 + (l.x + 12 - S.rcx) * gs
			var sy: float = gm.Hv / 2 + (l.y - S.rcy) * gs
			var rl := 140 * gs
			if sx < -rl or sx > gm.Wv + rl or sy < -rl or sy > gm.Hv + rl: continue
			if arr.size() < 16: arr.append(Vector3(sx, sy, rl))
		for f in S.get("mf", []):   # survivors' muzzle flashes light up the dark too
			if arr.size() >= 16: break
			var fx: float = gm.Wv / 2 + (f.x - S.rcx) * gs
			var fy: float = gm.Hv / 2 + (f.y - S.rcy) * gs
			var rf := 200 * gs
			if fx < -rf or fx > gm.Wv + rf or fy < -rf or fy > gm.Hv + rf: continue
			arr.append(Vector3(fx, fy, rf))
		var nl := arr.size()
		for i in range(arr.size(), 16): arr.append(Vector3.ZERO)
		m.set_shader_parameter("lights", arr)
		m.set_shader_parameter("nlights", nl)
		dr.visible = true
	else:
		dr.visible = false

static func ground_layer(gm, idx: int, g: Pen) -> void:
	var S: Dictionary = gm.S
	var gs: float = gm.ground_scale()
	var cx: float = S.rcx
	var cy: float = S.rcy
	var W: float = gm.Wv
	var H: float = gm.Hv
	var T: float = gm.T
	var p: Dictionary = S.p
	var view := func(): g.set_view(gs, W / 2 - cx * gs, H / 2 - cy * gs)
	match idx:
		0:
			g.rect(0, 0, W, H, hc("#1c2216"))
			view.call()
			var vx0 := maxf(0, cx - W / 2 / gs - 40)
			var vy0 := maxf(0, cy - H / 2 / gs - 40)
			var vx1 := minf(S.cols * TS, cx + W / 2 / gs + 40)
			var vy1 := minf(S.rows * TS, cy + H / 2 / gs + 40)
			var BK := SiteGen.BK
			if vx1 > vx0 and vy1 > vy0 and S.bg.baked:
				g.tex_region(S.bg.get_texture(), Rect2(vx0, vy0, vx1 - vx0, vy1 - vy0), Rect2(vx0 * BK, vy0 * BK, (vx1 - vx0) * BK, (vy1 - vy0) * BK))
			if S.tanker:
				var tk: Dictionary = S.tanker
				g.save(); g.translate(tk.x, tk.y)
				g.rr(-58, -10, 124, 30, 6, Color(0, 0, 0, 0.35))
				g.rr(-64, -14, 28, 28, 4, hc("#8a2a1c"))
				g.rect(-60, -11, 8, 22, hc("#1c2226"))
				g.rr(-34, -15, 96, 30, 14, hc("#b8b4aa"))
				g.rect(-30, -13, 88, 6, Color(1, 1, 1, 0.18))
				for q in 5: g.circle(-20 + q * 18, 4, 3 + (q % 2) * 2, rgba(120, 60, 30, 0.35))
				g.rect(10, -3, 8, 6, hc("#3a3a3a"))
				g.restore()
				if tk.gal > 0 and tk.prog > 0: g.arc(p.x, p.y, 22, -PI / 2, -PI / 2 + tk.prog * TAU, hc("#d9a441"), 4)
			for k in S.crates: draw_container(gm, g, k)
			draw_pickups(gm, g)
			for b in S.thrown:
				var bz: float = b.get("z", 0.0)   # height while a survivor's lob is in the air
				g.ellipse(b.x + 3 + bz * 0.3, b.y + 4, 7, 5, 0, Color(0, 0, 0, 0.3 * (1.0 - minf(0.6, bz / 100.0))))
				g.save(); g.translate(b.x, b.y - bz)
				g.rotate(b.spin)
				g.rr(-7, -4, 14, 8, 2, hc("#5b5f63"))
				g.rect(-7, -4, 3, 8, hc("#3a3d40")); g.rect(4, -4, 3, 8, hc("#3a3d40"))
				g.restore()
				if fmod(T, 0.25) < 0.12: g.circle(b.x, b.y - bz - 6, 2.5, hc("#ff4a30"))
			for d in S.drops:
				var pl := 0.5 + 0.5 * sin(T * 5 + d.x)
				g.rect(d.x - 5, d.y - 3, 14, 10, Color(0, 0, 0, 0.3))
				if d.k == "gun":
					# a dropped gun: barrel and stock (short for the revolver), gold glow
					var lg: bool = int(d.get("w", 0)) != 0
					g.rect(d.x - (11.0 if lg else 6.0), d.y - 2, 22.0 if lg else 12.0, 4, hc("#161615"))
					if lg: g.rect(d.x - 13, d.y - 2.5, 8, 5, hc("#5a3e26"))
					else: g.rect(d.x - 7, d.y - 1, 4, 6, hc("#5a3e26"))
					g.ring(d.x, d.y, 15, rgba(255, 210, 122, 0.3 + 0.4 * pl), 1.5)
					continue
				if d.k == "ammo":
					g.rect(d.x - 7, d.y - 5, 14, 10, hc("#4f5530"))
					for q in 4: g.rect(d.x - 5 + q * 3, d.y - 3, 2, 6, hc("#d9b35a"))
				else:
					g.rect(d.x - 7, d.y - 4, 14, 8, hc("#5d7d3a")); g.rect(d.x - 2, d.y - 2, 4, 4, hc("#9cc063"))
				g.ring(d.x, d.y, 12, rgba(240, 220, 140, 0.25 + 0.35 * pl), 1.2)
			for br in S.barrels:
				if br.dead: continue
				g.ellipse(br.x + 4, br.y + 5, 12, 11, 0, Color(0, 0, 0, 0.32))
				var lit: bool = br.fuse >= 0 and fmod(T, 0.1) < 0.05
				g.circle(br.x, br.y, 11.5, hc("#ffc070") if lit else hc("#a8301f"))
				g.circle(br.x - 4, br.y - 4, 5, hc("#ffe8b0") if lit else rgba(255, 140, 110, 0.35))
				g.ring(br.x, br.y, 8, rgba(40, 8, 4, 0.6), 1.5)
				g.circle(br.x + 4, br.y - 3, 2.2, hc("#2a2a28"))
				g.poly(PackedVector2Array([Vector2(br.x - 3.5, br.y + 4), Vector2(br.x, br.y - 2), Vector2(br.x + 3.5, br.y + 4)]), hc("#e8c74a"))
			for car in S.cars:
				# burning car (out of hitpoints, waiting to blow): drawn like the campfires on the
				# map (draw_smoke), a flickering hot core under a drifting plume, at the car's hot end
				if car.dead or car.fuse < 0: continue
				var grow := minf(1.0, float(car.burnT) / 1.5)
				g.ga = 0.55 * grow
				g.tex(Tx.glow("255,110,40"), car.x - 46, car.y - 46, 92, 92)
				g.ga = 1.0
				for q in 3:
					g.circle(car.x + (randf() - 0.5) * 8, car.y + (randf() - 0.5) * 6, (5 + randf() * 3) * (0.5 + 0.5 * grow), rgba(255, 120 + randf() * 60, 40, 0.8))
				g.circle(car.x, car.y, 2.5 + randf() * 1.5, rgba(255, 230, 170, 0.85 * grow))
			# blast-radius rings: burning cars and thrown bombs
			for car in S.cars:
				if not car.dead and car.fuse >= 0: blast_ring(gm, g, car.x, car.y, Blasts.CAR_BLAST_R, car.fuse)
			for b in S.thrown:
				if not b.dead: blast_ring(gm, g, b.x, b.y, Blasts.BOMB_BLAST_R, b.fuse)
			var P: Dictionary = gm.PS()
			g.save(); g.translate(S.plane.x + 10, S.plane.y + 14); draw_plane(g, P, 190, 0, true); g.restore()
			g.save(); g.translate(S.plane.x, S.plane.y); draw_plane(g, P, 190, 0, false); g.restore()
			if S.nearPlane: g.dashed_arc(S.plane.x, S.plane.y, 130, 0, TAU, rgba(212, 90, 157, 0.8), 2, 8, 6)
			for z in S.zs: draw_zombie(gm, g, z)
			for v in S.sv: draw_person(g, v.x, v.y, v.ang, {"body": v.shirt, "skin": v.skin, "hair": "#2b2118", "cap": v.cap, "gun": not v.get("unarmed", false), "bare": v.get("unarmed", false), "long": int(v.get("w", 1)) != 0, "vest": float(v.get("armor", 0.0)) > 0, "walk": v.wk, "hit": v.hit > 0})
			if S.npc:
				var n: Dictionary = S.npc
				draw_person(g, n.x, n.y, n.ang, {"body": "#3f7a7a", "skin": "#e0b894", "hair": "#5a3a22", "gun": true, "long": int(n.get("w", 0)) != 0, "walk": n.wk, "hit": n.hit > 0})
				if not n.follow:
					var pl := 0.5 + 0.5 * sin(T * 5)
					g.ring(n.x, n.y, 22 + pl * 6, rgba(240, 160, 210, 0.3 + 0.5 * pl), 2)
				g.text(n.name, n.x, n.y - 22, 11, hc("#f0c4dd"), 0, "700", 3, Color(0, 0, 0, 0.7))
			var jz: float = sin(PI * (1 - p.jt / 0.46)) * 14 if p.jt > 0 else 0.0
			if jz > 0: g.ellipse(p.x + 3 + jz * 0.4, p.y + 5 + jz * 0.7, 10, 7, 0, Color(0, 0, 0, 0.25))
			g.save()
			if jz > 0:
				g.translate(p.x, p.y - jz * 0.5); g.scale(1 + jz / 45, 1 + jz / 45); g.translate(-p.x, -p.y)
			draw_person(g, p.x, p.y, p.ang, {"body": "#9a3a2a" if S.hurt > 0 else "#6b4a2e", "skin": "#d9b48f", "cap": "#34404c", "gun": gm.G.ammo > 0, "long": gm.G.weapon > 0, "walk": p.wk, "swing": S.swing > 0})
			g.restore()
		1:
			view.call()
			if S.flash > 0:
				var mx: float = p.x + cos(p.ang) * 26
				var my: float = p.y + sin(p.ang) * 26
				g.radial(mx, my, [[0.0, rgba(255, 220, 150, 0.9)], [48 * 0.3, rgba(255, 160, 70, 0.4)], [48.0, rgba(255, 120, 40, 0)]], 24)
			for f in S.get("mf", []):
				g.radial(f.x, f.y, [[0.0, rgba(255, 220, 150, 0.9)], [48 * 0.3, rgba(255, 160, 70, 0.4)], [48.0, rgba(255, 120, 40, 0)]], 24)
			if S.boomFlash > 0 and S.scorch.size():
				var q: Dictionary = S.scorch[S.scorch.size() - 1]
				g.radial(q.x, q.y, [[0.0, rgba(255, 190, 90, minf(1, S.boomFlash * 3))], [200.0, rgba(255, 90, 30, 0)]], 32)
			for b in S.bul:
				if b.bolt:
					g.line(b.x, b.y, b.x - b.vx * 0.02, b.y - b.vy * 0.02, hc("#6a4a2a"), 1)
					continue
				var tx: float = b.x - b.vx * 0.025
				var ty: float = b.y - b.vy * 0.025
				g.line(b.x, b.y, tx, ty, rgba(255, 200, 110, 0.35) if b.pl else rgba(255, 110, 80, 0.35), 2.5)
				g.line(b.x, b.y, tx, ty, rgba(255, 245, 210, 0.95) if b.pl else rgba(255, 190, 170, 0.95), 0.9)
		2:
			view.call()
			for f in S.fx:
				var z: float = f.sz
				g.rect(f.x - z / 2, f.y - z / 2, z, z, hc(f.c))
			for m in S.smoke:
				g.ga = clampf(m.life / m.max, 0, 1) * 0.6
				g.tex(Tx.GPUFF if m.g else Tx.DPUFF, m.x - m.r, m.y - m.r, m.r * 2, m.r * 2)
			g.ga = 1.0
			for car in S.cars:
				# smoke plume like the map campfires' (draw_smoke) at ground scale: while burning,
				# and bigger over the wreck after it blows, thinning out over CAR_SMOLDER seconds
				if car.dead:
					if car.burnT <= 0: continue
					var fade: float = minf(1.0, car.burnT / car.burnMax * 1.5)
					for i in 10:
						var k := fmod(T * 0.22 + i / 10.0 + float(car.c) * 0.13, 1.0)
						g.circle(car.x + k * 200, car.y - k * 120, 12 + k * 70, rgba(40, 38, 36, 0.55 * (1 - k) * fade))
					continue
				if car.fuse < 0: continue
				var grow := minf(1.0, float(car.burnT) / 1.5)
				for i in 8:
					var k := fmod(T * 0.35 + i / 8.0 + float(car.c) * 0.13, 1.0)
					g.circle(car.x + k * 90, car.y - k * 55, (5 + k * 30) * grow, rgba(46, 44, 42, 0.45 * (1 - k)))
			draw_roofs(gm, g)
			for cw in S.crows:
				if cw.gone: continue
				g.save(); g.translate(cw.x, cw.y)
				if cw.fly:
					g.ellipse(10 + cw.h * 0.6, 14 + cw.h, 5, 3, 0, Color(0, 0, 0, 0.2))
					g.rotate(atan2(cw.vy, cw.vx))
					var f := sin(T * 22 + cw.ph) * 6
					g.polyline(PackedVector2Array([Vector2(-8, -f), Vector2(0, 0), Vector2(-8, f)]), hc("#141416"), 2.4)
					g.ellipse(0, 0, 5, 2.5, 0, hc("#141416"))
				else:
					g.rotate(cw.a)
					g.ellipse(1, 2, 5, 3, 0, Color(0, 0, 0, 0.25))
					g.ellipse(0, 0, 5, 3, 0, hc("#18181a"))
					var pk := 2.0 if sin(T * 6 + cw.ph) > 0.7 else 0.0
					g.circle(4 + pk, 0, 2.2, hc("#18181a"))
					g.rect(6 + pk, -0.6, 2, 1.2, hc("#8a7a40"))
				g.restore()
			var mw: float = S.cols * TS
			var mh: float = S.rows * TS
			g.ga = 0.1
			for i in 5:
				var sx := fmod(T * 14 + i * 977, mw + 900) - 450
				var sy := fmod(i * 613 + T * 5, mh)
				var sz := 380 + i * 60
				g.tex(Tx.SPUFF, sx - sz / 2, sy - sz / 2, sz, sz * 0.7)
			g.ga = 1.0
			var c0 := maxi(0, int(floor((cx - W / 2 / gs - 40) / TS)))
			var c1 := mini(S.cols - 1, int(floor((cx + W / 2 / gs + 40) / TS)))
			var r0 := maxi(0, int(floor((cy - H / 2 / gs - 40) / TS)))
			var r1 := mini(S.rows - 1, int(floor((cy + H / 2 / gs + 40) / TS)))
			if Tx.TREES.size():
				for r in range(r0, r1 + 1):
					for c in range(c0, c1 + 1):
						if S.g[r * S.cols + c] != 5: continue
						var x := (c + 0.5) * TS
						var y := (r + 0.5) * TS
						var j := U.hash3(c, r, 3)
						var sz := 70 + j * 14
						g.ga = 0.45 if Vector2(p.x - x, p.y - y).length() < 34 else 1.0
						g.tex(Tx.TREES[int(j * 3)], x - sz / 2, y - sz / 2, sz, sz)
				g.ga = 1.0
			for f in S.fl:
				g.ga = clampf(f.life, 0, 1)
				g.text(f.txt, f.x, f.y, 14, hc(f.c), 0, "700", 3, Color(0, 0, 0, 0.7))
			g.ga = 1.0
			g.set_xf(Transform2D.IDENTITY)
			var dk: float = gm.dark()
			vignette(gm, g, 0.8 + dk * 0.15)
			grade(gm, g)
			if S.rain > 0:
				g.rect(0, 0, W, H, rgba(20, 26, 34, S.rain * 0.3))
				var ln := PackedVector2Array()
				for i in int(100 * S.rain):
					var x := randf() * W
					var y := randf() * H
					ln.append(Vector2(x, y)); ln.append(Vector2(x - 4, y + 14))
				g.lines(ln, rgba(200, 210, 225, 0.3), 1.2)
			if S.nd < 150:
				var k: float = (1 - S.nd / 150.0) * (0.55 + 0.45 * sin(T * 8))
				vignette_red(gm, g, 0.3 * k)
		4:
			var dk: float = gm.dark()
			if dk <= 0.02: return
			g.set_xf(Transform2D.IDENTITY)
			if dk > 0.2:
				for z in S.zs:
					if z.dormant or z.rise > 0: continue
					var sx: float = W / 2 + (z.x - cx) * gs
					var sy: float = H / 2 + (z.y - cy) * gs
					if sx < -20 or sx > W + 20 or sy < -20 or sy > H + 20: continue
					var a: float = z.ang
					var hx := (7.0 if z.kind == "crawler" else 3.2) + 3
					var s := (1.4 if z.kind == "bloat" else 1.0) * gs
					for e in [-2.1, 2.1]:
						var ex = sx + (cos(a) * hx - sin(a) * e) * s
						var ey = sy + (sin(a) * hx + cos(a) * e) * s
						g.ga = dk * 0.85
						g.tex(Tx.glow("255,60,30"), ex - 4.5, ey - 4.5, 9, 9)
						g.ga = 1.0
						g.rect(ex - 0.8, ey - 0.8, 1.6, 1.6, rgba(255, 150, 110, dk))
			for l in S.lights:
				if not l.on: continue
				var sx: float = W / 2 + (l.x + 12 - cx) * gs
				var sy: float = H / 2 + (l.y - cy) * gs
				var rl := 130 * gs
				if sx < -rl or sx > W + rl or sy < -rl or sy > H + rl: continue
				g.ga = 0.28 * dk
				g.tex(Tx.glow("255,210,140"), sx - rl, sy - rl, rl * 2, rl * 2)
			g.ga = 1.0
		5:
			g.set_xf(Transform2D.IDENTITY)
			if S.hurt > 0: g.rect(0, 0, W, H, rgba(160, 20, 10, S.hurt * 0.6))
			for sp in S.splat:
				var a := minf(1, sp.life / 1.2) * 0.7
				var col := rgba(105, 8, 5, a)
				var si := int(sp.s)
				for q in 7:
					var an := U.hash3(q, si, 5) * TAU
					var dd: float = U.hash3(si, q, 6) * sp.r * 0.7
					var rr2: float = sp.r * (0.18 + U.hash3(q, q, si) * 0.3)
					g.circle(sp.x + cos(an) * dd, sp.y + sin(an) * dd, rr2, col)
				g.rect(sp.x - 2, sp.y, 4, sp.r * 0.6 + (1.8 - sp.life) * 40, col)
				g.rect(sp.x + sp.r * 0.3, sp.y, 3, sp.r * 0.4 + (1.8 - sp.life) * 25, col)
			if S.boomFlash > 0: g.rect(0, 0, W, H, rgba(255, 190, 110, minf(1, S.boomFlash * 1.2)))
		7:
			g.set_xf(Transform2D.IDENTITY)
			hud_ground(gm, g)
			if gm.uist == "" and not gm.cursor_on_btn: draw_ads_reticle(gm, g)

## The exploration-mode cursor (replaces the Windows pointer). Follows the mouse
## normally; while aiming down sights it follows the slowed virtual cursor and
## tightens up as the camera settles in.
## Blinking red dashed ring showing how far a blast will reach from (x, y); blinks
## faster once the fuse is nearly out.
static func blast_ring(gm, g: Pen, x: float, y: float, rad: float, fuse: float) -> void:
	var rate: float = Blasts.BLAST_RING_BLINK * (2.0 if fuse < Blasts.BLAST_RING_HURRY else 1.0)
	if fmod(gm.T * rate, 1.0) >= 0.5: return   # off half the time
	g.dashed_arc(x, y, rad, 0, TAU, rgba(255, 40, 30, 0.75), 2.5, Blasts.BLAST_RING_DASH, Blasts.BLAST_RING_GAP)

static func draw_ads_reticle(gm, g: Pen) -> void:
	var c: Vector2 = gm.reticle_pos()
	var k: float = gm.ads_ease()
	var a := 0.8 + 0.15 * k
	var r := 14.0 - 5.0 * k   # tightens as you settle in
	var shade := Color(0, 0, 0, 0.45 * a)
	var ink := rgba(239, 230, 207, a)
	g.ring(c.x, c.y, r, shade, 3.0)
	g.ring(c.x, c.y, r, ink, 1.5)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		g.line(c.x + d.x * (r + 3), c.y + d.y * (r + 3), c.x + d.x * (r + 9), c.y + d.y * (r + 9), ink, 1.5)
	# red dot only while a shot would actually get there (range, walls, cars, barrels)
	var wp: Vector2 = gm.s2w_g(c.x, c.y)
	if gm.shot_reaches(wp.x, wp.y): g.circle(c.x, c.y, 1.6, rgba(227, 100, 76, a))

# =====================================================================
# ground sprites
# =====================================================================
static func draw_roofs(gm, g: Pen) -> void:
	var S: Dictionary = gm.S
	var p: Dictionary = S.p
	var sid: int = S.s.id
	for rm in S.rooms:
		var inside: bool = p.x > rm.c * TS and p.x < (rm.c + rm.w) * TS and p.y > rm.r * TS and p.y < (rm.r + rm.h) * TS
		var goal := 0.05 if inside else (PEEK_ALPHA if peeking(S, p, rm) else 1.0)
		rm.ra = lerpf(rm.ra, goal, 0.18)
		if rm.ra < 0.02: continue
		var x: float = rm.c * TS + 10
		var y: float = rm.r * TS + 10
		var w: float = rm.w * TS - 20
		var h: float = rm.h * TS - 20
		g.rect(x + 8, y + 10, w, h, Color(0, 0, 0, rm.ra * 0.35))
		g.ga = rm.ra
		g.save(); g.translate(x, y)
		draw_roof(g, rm, sid, w, h)
		g.restore()
		g.ga = 1.0
	for rm in S.rooms:
		if rm.sign == null: continue
		var dc: int = rm.door[0]
		var dr: int = rm.door[1]
		var top: bool = rm.door[2]
		var x := (dc + 1) * TS
		var y := (dr + 1) * TS + 4 if top else dr * TS - 4
		var tw := Pen.measure(rm.sign, 8, "700") + 12
		g.rect(x - tw / 2 + 2, y - 6, tw, 14, Color(0, 0, 0, 0.35))
		g.rect(x - tw / 2, y - 8, tw, 14, hc("#e8dcc0"))
		g.stroke_rect(x - tw / 2 + 1.5, y - 6.5, tw - 3, 11, hc("#3a3028"), 1)
		g.text(rm.sign, x, y - 0.5, 8, hc("#2a221a"), 0, "700")

## Looking in through a doorway: standing near one of the building's door openings
## (outside, or in the doorway) and facing that opening makes the roof see-through.
const PEEK_DIST := 3.0    # tiles from the door opening's centre
const PEEK_CONE := 60.0   # degrees either side of looking straight at the door opening
const PEEK_ALPHA := 0.3   # roof opacity while peeking (inside the building it's 0.05)

static func peeking(S: Dictionary, p: Dictionary, rm: Dictionary) -> bool:
	var c0: int = rm.c
	var r0: int = rm.r
	var c1: int = rm.c + rm.w - 1
	var r1: int = rm.r + rm.h - 1
	var reach := PEEK_DIST * TS
	# quick reject: player nowhere near this building
	if p.x < c0 * TS - reach or p.x > (c1 + 1) * TS + reach or p.y < r0 * TS - reach or p.y > (r1 + 1) * TS + reach: return false
	var fx := cos(p.ang)
	var fy := sin(p.ang)
	var cone := cos(deg_to_rad(PEEK_CONE))
	var cols: int = S.cols
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var edge_c := c == c0 or c == c1
			var edge_r := r == r0 or r == r1
			if not (edge_c or edge_r) or (edge_c and edge_r): continue   # perimeter only, skip corners
			if S.g[r * cols + c] != 2: continue   # not an opening
			var ix := 0.0
			var iy := 0.0
			if r == r0: iy = 1.0
			elif r == r1: iy = -1.0
			elif c == c0: ix = 1.0
			else: ix = -1.0
			var dx: float = p.x - (c + 0.5) * TS
			var dy: float = p.y - (r + 0.5) * TS
			if dx * dx + dy * dy > reach * reach: continue
			if dx * ix + dy * iy > 0.5 * TS: continue   # already past the doorway (inside test handles that)
			# facing the opening itself; when standing right in it, facing in through it
			var dl := sqrt(dx * dx + dy * dy)
			var tx := -dx / dl if dl > 0.4 * TS else ix
			var ty := -dy / dl if dl > 0.4 * TS else iy
			if fx * tx + fy * ty >= cone: return true
	return false

static func draw_roof(g: Pen, rm: Dictionary, sid: int, w: float, h: float) -> void:
	var col := hc(rm.roof if rm.roof else "#6b5a4a")
	var H1 := func(a: int, b: int) -> float: return U.hash3(a, b, sid * 13 + rm.c * 7 + rm.r)
	if rm.flat:
		g.rect(0, 0, w, h, col)
		var x := 6.0
		while x < w:
			g.rect(x, 4, 1, h - 8, Color(1, 1, 1, 0.05))
			x += 12
		g.stroke_rect(2, 2, w - 4, h - 4, U.shade(col, 0.62), 4)
		g.stroke_rect(4.5, 4.5, w - 9, h - 9, Color(1, 1, 1, 0.12), 1)
		var nac := 3 if w > 200 else 2
		for k in nac:
			var ax: float = 8 + (k + H1.call(k, 1) * 0.6) * (w - 40) / nac
			var ay: float = 8 + H1.call(1, k) * (h - 34)
			g.rect(ax + 4, ay + 5, 24, 18, Color(0, 0, 0, 0.35))
			g.rect(ax, ay, 24, 18, hc("#9ea2a4"))
			g.circle(ax + 12, ay + 9, 6, hc("#6c7072"))
			g.lines(PackedVector2Array([Vector2(ax + 6, ay + 9), Vector2(ax + 18, ay + 9), Vector2(ax + 12, ay + 3), Vector2(ax + 12, ay + 15)]), hc("#4a4e50"), 1)
		for k in 4:
			g.ellipse(H1.call(k, 5) * w, H1.call(5, k) * h, 8 + H1.call(k, k) * 14, 5 + H1.call(k, 7) * 8, 0, rgba(30, 25, 20, 0.12))
	else:
		var hz := w >= h
		var L := h if hz else w
		var c1 := U.shade(col, 1.28)
		var c2 := U.shade(col, 1.05)
		var c3 := U.shade(col, 0.72)
		var c4 := U.shade(col, 0.58)
		if hz:
			g.poly_grad(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h / 2), Vector2(0, h / 2)]), PackedColorArray([c1, c1, c2, c2]))
			g.poly_grad(PackedVector2Array([Vector2(0, h / 2), Vector2(w, h / 2), Vector2(w, h), Vector2(0, h)]), PackedColorArray([c3, c3, c4, c4]))
		else:
			g.poly_grad(PackedVector2Array([Vector2(0, 0), Vector2(w / 2, 0), Vector2(w / 2, h), Vector2(0, h)]), PackedColorArray([c1, c2, c2, c1]))
			g.poly_grad(PackedVector2Array([Vector2(w / 2, 0), Vector2(w, 0), Vector2(w, h), Vector2(w / 2, h)]), PackedColorArray([c3, c4, c4, c3]))
		var ln := PackedVector2Array()
		var q := 5.0
		while q < L:
			if hz: ln.append_array([Vector2(0, q), Vector2(w, q)])
			else: ln.append_array([Vector2(q, 0), Vector2(q, h)])
			q += 6
		g.lines(ln, Color(0, 0, 0, 0.16), 1)
		var tk := PackedVector2Array()
		q = 5.0
		var row := 0
		var span := w if hz else h
		while q < L:
			var s2 := float((row % 2) * 5)
			while s2 < span:
				if hz: tk.append_array([Vector2(s2, q - 6), Vector2(s2, q)])
				else: tk.append_array([Vector2(q - 6, s2), Vector2(q, s2)])
				s2 += 10
			q += 6
			row += 1
		g.lines(tk, Color(0, 0, 0, 0.08), 1)
		if hz: g.rect(0, h / 2 - 1.5, w, 3, U.shade(col, 1.4))
		else: g.rect(w / 2 - 1.5, 0, 3, h, U.shade(col, 1.4))
		g.stroke_rect(1, 1, w - 2, h - 2, Color(0, 0, 0, 0.3), 2)
		if rm.kind == "house" or H1.call(3, 3) < 0.4:
			var cx2: float = w * (0.25 + H1.call(2, 2) * 0.5) if hz else w * 0.3
			var cy2: float = h * 0.28 if hz else h * (0.25 + H1.call(2, 2) * 0.5)
			g.rect(cx2 + 3, cy2 + 4, 10, 10, Color(0, 0, 0, 0.35))
			g.rect(cx2, cy2, 10, 10, hc("#6a4a3a"))
			g.rect(cx2 + 2, cy2 + 2, 6, 6, hc("#2a2220"))
		if H1.call(9, 9) < 0.18:
			var hx: float = w * (0.3 + H1.call(4, 4) * 0.4)
			var hy: float = h * (0.3 + H1.call(6, 6) * 0.4)
			g.ellipse(hx, hy, 12, 9, 0, rgba(15, 10, 8, 0.85))
			g.stroke_ellipse(hx, hy, 12, 9, 0, hc("#3a2a1e"), 2)
	var ga0 := g.ga
	for k in 7:
		var s2: float = 18 + H1.call(k, 20) * 50
		g.ga = ga0 * (0.1 + H1.call(k, 21) * 0.08)
		g.tex(Tx.SPUFF, H1.call(k, 22) * w - s2 / 2, H1.call(k, 23) * h - s2 / 2, s2, s2)
	if not rm.flat:
		for k in 4:
			var s2: float = 10 + H1.call(k, 24) * 22
			g.ga = ga0 * 0.25
			g.tex(Tx.GPUFF, H1.call(k, 25) * w - s2 / 2, H1.call(k, 26) * h - s2 / 2, s2, s2 * 0.7)
		g.ga = ga0
		for k in 6: g.rect(H1.call(k, 27) * w, H1.call(k, 28) * h, 5, 4, rgba(20, 16, 12, 0.45))
		if H1.call(8, 8) < 0.2:
			g.save(); g.translate(w * (0.3 + H1.call(5, 5) * 0.4), h * (0.3 + H1.call(6, 5) * 0.4)); g.rotate(H1.call(7, 7) - 0.5)
			g.rect(-16, -12, 32, 24, hc("#3a5f8a"))
			g.rect(-16, -12, 32, 3, Color(1, 1, 1, 0.15))
			for c in [[-14, -10], [14, -10], [-14, 10], [14, 10]]: g.rect(c[0] - 1, c[1] - 1, 2, 2, hc("#dddddd"))
			g.restore()
	else:
		g.ga = ga0
		var ln := PackedVector2Array()
		for k in 5:
			var x2: float = H1.call(k, 29) * w
			ln.append_array([Vector2(x2, 2), Vector2(x2 + (H1.call(k, 30) - 0.5) * 6, 8 + H1.call(k, 31) * h * 0.5)])
		g.lines(ln, rgba(120, 60, 30, 0.22), 2)
		g.ellipse(w * H1.call(1, 32), h * H1.call(2, 32), 14, 8, 0, rgba(30, 40, 50, 0.25))
	g.ga = ga0

static var zseeds := {}
static func _zkey_seed(key: String) -> int:
	if zseeds.has(key): return zseeds[key]
	var sd := 0
	for ch in key:
		sd = (sd * 31 + ch.unicode_at(0)) & 0xFFFFFFFF
		if sd >= 0x80000000: sd -= 0x100000000
	zseeds[key] = sd
	return sd

static func z_sprite(g: Pen, z: Dictionary) -> void:
	var kind: String = z.kind
	var shirt: String = "#5d6b3e" if kind == "bloat" else ("#2e2e30" if kind == "scream" else z.shirt)
	var skin: String = "#9fb07a" if kind == "bloat" else ("#d4d2c4" if kind == "scream" else z.skin)
	var v: int = z["var"]
	var key := (kind if kind != "" else "n") + shirt + skin + str(v) + ("a" if z.arm else "")
	var Rn := U.Mulberry.new(_zkey_seed(key))
	var sc := hc(skin)
	var tw := 9.5 if kind == "bloat" else (7.0 if kind == "crawler" else 7.5)
	var th := 13.0 if kind == "bloat" else (10.0 if kind == "crawler" else 11.5)
	var body := PackedVector2Array()
	for i in 22:
		var a := float(i) / 22 * TAU
		var rj := 1 + (Rn.next() - 0.5) * 0.2
		body.append(Vector2(cos(a) * tw * rj, sin(a) * th * rj))
	Rn.next()
	g.poly(body, hc(shirt))
	var bc := body.duplicate(); bc.append(body[0])
	g.polyline(bc, Color(0, 0, 0, 0.5), 0.8)
	for i in 3: g.ellipse((Rn.next() - 0.5) * 8, (Rn.next() - 0.5) * 14, 1.2 + Rn.next() * 1.8, 0.8 + Rn.next() * 1.3, Rn.next() * 3, sc)
	if v == 2:
		g.ellipse(-1, 0, 4, 6, 0, U.shade(sc, 0.85))
		var ln := PackedVector2Array()
		for i in range(-2, 3):
			ln.append(Vector2(-4, i * 2.2)); ln.append(Vector2(2, i * 2.2))
		g.lines(ln, rgba(70, 15, 12, 0.8), 0.8)
	for i in 5:
		var r := 70 + int(Rn.next() * 45)
		var a := 0.5 + Rn.next() * 0.4
		g.ellipse((Rn.next() - 0.3) * 9, (Rn.next() - 0.5) * 16, 1.4 + Rn.next() * 3, 1 + Rn.next() * 2.3, Rn.next() * 3, rgba(r, 6, 4, a))
	if kind == "bloat":
		for i in 7: g.circle((Rn.next() - 0.5) * 14, (Rn.next() - 0.5) * 20, 0.8 + Rn.next() * 1.5, rgba(205, 200, 90, 0.75))
	g.ellipse(-3.5, 0, 4, tw * 1.15, 0, Color(0, 0, 0, 0.2))
	var hx := 7.0 if kind == "crawler" else 3.2
	g.circle(hx, 0, 5.6, sc)
	g.ring(hx, 0, 5.6, Color(0, 0, 0, 0.45), 0.6)
	g.pie(hx - 1.5, 0, 4.6, PI * 0.5, PI * 1.5, Color(0, 0, 0, 0.15))
	var vl := PackedVector2Array()
	for i in 4:
		vl.append(Vector2(hx - 3 + Rn.next() * 2, (Rn.next() - 0.5) * 6))
		vl.append(Vector2(hx - 1 + Rn.next() * 3, (Rn.next() - 0.5) * 8))
	g.lines(vl, rgba(50, 60, 90, 0.45), 0.4)
	if z.arm:
		g.pie(hx - 0.5, 0, 6.7, PI * 0.4, PI * 1.6, hc("#50584a"))
	elif kind != "scream":
		for i in 6:
			var a := PI * (0.55 + Rn.next() * 0.9)
			g.ellipse(hx + cos(a) * 3.9, sin(a) * 3.9, 1.9, 1, a, hc("#211d19"))
	g.ellipse(hx + 3, -2.1, 1.4, 1.05, 0, rgba(15, 4, 4, 0.95))
	g.ellipse(hx + 3, 2.1, 1.4, 1.05, 0, rgba(15, 4, 4, 0.95))
	g.ellipse(hx + 5, 0, 1.15, 2.9 if kind == "scream" else 1.9, 0, hc("#3a0806"))
	g.ellipse(hx + 4.4, 1.6, 1, 2, 0.3, rgba(130, 10, 8, 0.65))
	g.rect(hx + 5.3, -1, 0.6, 0.7, rgba(230, 225, 200, 0.7))
	g.rect(hx + 5.3, 0.4, 0.6, 0.7, rgba(230, 225, 200, 0.7))

static func draw_zombie(gm, g: Pen, z: Dictionary) -> void:
	var kind: String = z.kind
	var sc := 1.4 if kind == "bloat" else (0.95 if kind == "crawler" else 1.0)
	g.save()
	g.translate(z.x, z.y)
	if z.dormant:
		g.rotate(z.da)
		var sk := hc(z.skin)
		g.ellipse(0, 0, 13, 8, 0, U.shade(hc(z.shirt), 0.6))
		g.lines(PackedVector2Array([Vector2(4, -7), Vector2(10, -14), Vector2(-8, 6), Vector2(-16, 10)]), U.shade(sk, 0.6), 4)
		g.circle(14, 1, 5.5, U.shade(sk, 0.7))
		g.restore()
		return
	g.ellipse(3 * sc, 5 * sc, 12 * sc, 9 * sc, 0, Color(0, 0, 0, 0.34))
	var wk: float = z.wk
	var a: float = z.ang + (0.0 if kind == "crawler" else sin(wk * 0.45) * 0.14)
	if z.wind > 0: a += (randf() - 0.5) * 0.25
	g.rotate(a)
	g.scale(sc, sc)
	if z.rise > 0:
		var k: float = 1 - z.rise / 0.7
		g.rotate((1 - k) * 1.3)
		g.scale(0.65 + 0.35 * k, 0.65 + 0.35 * k)
	if z.wind > 0: g.translate(-3, 0)
	var hit: bool = z.hit > 0
	var skin := Color.WHITE if hit else hc("#9fb07a" if kind == "bloat" else ("#d4d2c4" if kind == "scream" else z.skin))
	if kind != "crawler":
		var w := sin(wk)
		g.ellipse(w * 6, -4.5, 4.5, 3, 0, hc("#1c1a17"))
		g.ellipse(-w * 6, 4.5, 4.5, 3, 0, hc("#1c1a17"))
	else:
		g.line(-5, 0, -15, sin(wk) * 2, rgba(70, 10, 8, 0.75), 6)
	var reach := 25.0 if z.lng > 0 else (12.0 if z.wind > 0 else (21.0 if kind == "crawler" else 18.0))
	var sw := sin(wk * 0.7) * 2.5
	var sleeve := Color.WHITE if hit else U.shade(hc("#5d6b3e" if kind == "bloat" else ("#2e2e30" if kind == "scream" else z.shirt)), 0.8)
	var arm := func(sy: float, ph: float) -> void:
		g.line(1, sy, 10, sy + ph * 0.5, sleeve, 5)
		g.line(10, sy + ph * 0.5, reach, sy * 0.8 + ph, skin, 3.6)
		var fl := PackedVector2Array()
		for f in range(-1, 2):
			fl.append(Vector2(reach, sy * 0.8 + ph)); fl.append(Vector2(reach + 3.8, sy * 0.8 + ph + f * 2.2))
		g.lines(fl, skin, 1.1)
	arm.call(-8.0, sw)
	if z["var"] != 3: arm.call(8.0, -sw)
	else: g.circle(2, 9, 2.6, hc("#5a0e0a"))
	z_sprite(g, z)
	if hit: g.ellipse(0, 0, 8, 12, 0, Color(1, 1, 1, 0.55))
	g.restore()

static func draw_person(g: Pen, x: float, y: float, a: float, o: Dictionary) -> void:
	g.save()
	g.translate(x, y)
	g.ellipse(3, 5, 12, 9, 0, Color(0, 0, 0, 0.3))
	g.rotate(a)
	var w := sin(o.get("walk", 0.0))
	var hit: bool = o.get("hit", false)
	var skin := Color.WHITE if hit else hc(o.skin)
	var body := Color.WHITE if hit else hc(o.body)
	g.ellipse(w * 6, -4.5, 4.5, 3, 0, hc("#211d19"))
	g.ellipse(-w * 6, 4.5, 4.5, 3, 0, hc("#211d19"))
	var swing: bool = o.get("swing", false)
	if o.get("gun", false):
		var lng: bool = o.get("long", false)
		g.rect(7, 0.5, 23.0 if lng else 15.0, 3.5, hc("#161615"))
		if lng: g.rect(3, 0, 8, 4.5, hc("#5a3e26"))
		g.lines(PackedVector2Array([Vector2(0, -8), Vector2(8, -2), Vector2(0, 8), Vector2(10, 4)]), body, 4.5)
		g.circle(9, -1.5, 2.6, skin)
		g.circle(11, 3.5, 2.6, skin)
	elif o.get("bare", false):   # empty-handed: arms in, nothing in them
		g.lines(PackedVector2Array([Vector2(0, -8), Vector2(5, -7), Vector2(0, 8), Vector2(5, 7)]), body, 4.5)
		g.circle(6, -6.5, 2.4, skin)
		g.circle(6, 6.5, 2.4, skin)
	else:
		g.lines(PackedVector2Array([Vector2(0, -8), Vector2(6, -9), Vector2(0, 8), Vector2(9, 5)]), body, 4.5)
		g.line(10, 5, 30.0 if swing else 22.0, -8.0 if swing else 9.0, hc("#9a9a92"), 2.5)
	if swing: g.arc(0, 0, 30, -1, 1, rgba(230, 230, 220, 0.35), 10)
	var capc: String = o.get("cap", "")
	if capc != "":
		g.rect(-12, -6, 6, 12, hc("#4a4232"))
		g.rect(-12, -6, 2, 12, Color(0, 0, 0, 0.25))
	g.ellipse(0, 0, 7.5, 11.5, 0, body)
	if o.get("vest", false) and not hit:
		# body armour: grey plate vest over the shirt
		g.ellipse(0, 0, 6.2, 9.6, 0, hc("#4b5259"))
		g.rect(-3.2, -6, 6.4, 12, hc("#5f676f"))
	g.stroke_ellipse(0, 0, 7.5, 11.5, 0, Color(0, 0, 0, 0.35), 1)
	g.ellipse(-2, -3.5, 4, 6, 0, Color(1, 1, 1, 0.13))
	g.circle(1, 0, 5.8, skin)
	if capc != "":
		g.circle(0, 0, 5.9, hc(capc))
		g.rect(3, -3.6, 4.5, 7.2, hc(capc))
	else:
		g.pie(-0.5, 0, 5.6, PI * 0.55, PI * 1.45, hc(o.get("hair", "#2a2620")))
	g.restore()

static func draw_container(gm, g: Pen, k: Dictionary) -> void:
	var S: Dictionary = gm.S
	var x: float = k.x
	var y: float = k.y
	var o: bool = k.open
	var pl := 0.5 + 0.5 * sin(gm.T * 4 + k.id)
	var near_d := Vector2(S.p.x - x, S.p.y - y).length()
	g.save()
	g.translate(x, y)
	var shadow := func(w: float, h: float): g.rect(-w / 2 + 4, -h / 2 + 5, w, h, Color(0, 0, 0, 0.32))
	match k.ty:
		"locker":
			shadow.call(30, 16)
			g.rect(-15, -8, 30, 16, hc("#3c4228") if o else hc("#5a6236"))
			g.rect(-15, -8, 30, 3, Color(1, 1, 1, 0.12))
			if o: g.rect(-12, -5, 24, 10, hc("#2b2e1c"))
			else:
				g.rect(-11, -2, 3, 5, hc("#2b2e1c")); g.rect(8, -2, 3, 5, hc("#2b2e1c"))
				g.text_base("U.S.", 0, 3, 6, hc("#c8b070"), 0, "700")
		"register":
			shadow.call(20, 18)
			g.rr(-10, -9, 20, 18, 3, hc("#4a4c4e") if o else hc("#6d7174"))
			g.rect(-7, -7, 14, 5, hc("#1d2a22"))
			g.rect(-8, 2, 16, 6, hc("#23180e") if o else hc("#b8bcbf"))
			if not o: g.rect(-5, -6, 6, 2, hc("#8ee07a"))
		"toolbox":
			shadow.call(24, 12)
			g.rr(-12, -6, 24, 12, 2, hc("#6e2016") if o else hc("#b8321f"))
			g.rect(-12, -6, 24, 2, Color(1, 1, 1, 0.18))
			g.polyline(PackedVector2Array([Vector2(-5, -6), Vector2(-5, -9), Vector2(5, -9), Vector2(5, -6)]), hc("#2a2a2a"), 2)
			if o: g.rect(-10, -3, 20, 7, hc("#2a1a12"))
		"cabinet":
			shadow.call(20, 20)
			g.rect(-10, -10, 20, 20, hc("#9c9a92") if o else hc("#e4e1d6"))
			g.stroke_rect(-10, -10, 20, 20, Color(0, 0, 0, 0.25), 1)
			if o: g.rect(-8, -8, 16, 16, hc("#4a4842"))
			else:
				g.rect(-2, -7, 4, 14, hc("#c0392b")); g.rect(-7, -2, 14, 4, hc("#c0392b"))
		"jerry":
			for cn in [[-7, -3, "#8a2a1c"], [5, 2, "#4b5a2f"], [-2, 8, "#8a2a1c"]]:
				var ccx: float = cn[0]
				var ccy: float = cn[1]
				g.rect(ccx - 5, ccy - 5, 14, 12, Color(0, 0, 0, 0.3))
				g.rr(ccx - 7, ccy - 6, 13, 11, 2, U.shade(hc(cn[2]), 0.5) if o else hc(cn[2]))
				g.rect(ccx - 6, ccy - 5, 11, 2, Color(1, 1, 1, 0.15))
				g.rect(ccx + 2, ccy - 7, 3, 2, hc("#222222"))
		"dresser":
			shadow.call(26, 14)
			g.rect(-13, -7, 26, 14, hc("#3a2818") if o else hc("#5e3f26"))
			g.lines(PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(0, -7), Vector2(0, 7)]), Color(0, 0, 0, 0.35), 1)
			for d in [[-6, -3.5], [6, -3.5], [-6, 3.5], [6, 3.5]]: g.rect(d[0] - 1, d[1] - 1, 2, 2, hc("#c8a860"))
			if o: g.rect(1, 1, 11, 5, hc("#1c130b"))
		"desk":
			shadow.call(34, 18)
			g.rect(-17, -9, 34, 18, hc("#4a3522") if o else hc("#6e4e30"))
			g.rect(-17, -9, 34, 3, Color(1, 1, 1, 0.08))
			if not o:
				g.save(); g.rotate(0.2); g.rect(-10, -5, 10, 8, hc("#e8e2d0")); g.restore()
				g.rect(4, -4, 8, 6, hc("#e8e2d0"))
			else: g.rect(-14, 0, 12, 7, hc("#2a1c10"))
		"safe":
			shadow.call(20, 20)
			g.rect(-10, -10, 20, 20, hc("#4a4f54"))
			g.rect(-10, -10, 20, 3, Color(1, 1, 1, 0.12))
			g.stroke_rect(-8, -8, 16, 16, hc("#2a2e32"), 1.5)
			if o:
				g.rect(-7, -7, 14, 14, hc("#15181a"))
				g.save(); g.translate(8, -8); g.rotate(-0.9); g.rect(0, 0, 16, 3, hc("#5a6066")); g.restore()
			else:
				g.circle(0, 0, 4, hc("#b8bcc0"))
				g.rect(-0.7, -4, 1.4, 3, hc("#2a2e32"))
				g.rect(5, -1, 3, 6, hc("#8a8e92"))
		"stash":
			if o:
				g.rect(-9, -4, 18, 8, hc("#15100a"))
				g.save(); g.rotate(0.4); g.rect(4, -10, 18, 5, hc("#6a5236")); g.restore()
			elif near_d < 110:
				g.save(); g.rotate(0.06); g.rect(-10, -3.5, 20, 7, hc("#7a5c3a")); g.rect(-10, 3.5, 20, 1.5, Color(0, 0, 0, 0.4)); g.restore()
				var tw := 0.5 + 0.5 * sin(gm.T * 9)
				g.poly(PackedVector2Array([Vector2(3, -8), Vector2(4, -5), Vector2(7, -4), Vector2(4, -3), Vector2(3, 0), Vector2(2, -3), Vector2(-1, -4), Vector2(2, -5)]), rgba(255, 235, 170, tw))
		_:
			shadow.call(22, 22)
			if o:
				g.rect(-11, -11, 22, 22, hc("#5e4629"))
				g.rect(-8, -8, 16, 16, hc("#231a11"))
				g.save(); g.translate(12, -4); g.rotate(0.5); g.rect(-10, -3, 20, 6, hc("#7a5c36")); g.restore()
			else:
				g.rect(-11, -11, 22, 22, hc("#8c6c40"))
				g.rect(-11, -11, 11, 11, rgba(255, 230, 180, 0.14))
				g.stroke_rect(-10, -10, 20, 20, hc("#4d3920"), 1.5)
				g.lines(PackedVector2Array([Vector2(-10, -3.5), Vector2(10, -3.5), Vector2(-10, 3.5), Vector2(10, 3.5)]), hc("#4d3920"), 1.5)
				g.rect(-10, -10, 20, 2, rgba(255, 240, 200, 0.2))
	if not o and (k.ty != "stash" or near_d < 110):
		g.ring(0, 0, 21, rgba(240, 200, 120, 0.2 + 0.35 * pl), 1.5)
	g.restore()

static func draw_item(g: Pen, k: String, x: float, y: float) -> void:
	g.save()
	g.translate(x, y)
	match k:
		"fuel":
			g.rr(-5, -6, 10, 12, 2, hc("#a8301f")); g.rect(1, -8, 3, 2, hc("#222222")); g.rect(-4, -5, 8, 2, Color(1, 1, 1, 0.2))
		"ammo":
			for q in range(-1, 2):
				g.rect(q * 4 - 1.5, -4, 3, 8, hc("#d9b35a")); g.rect(q * 4 - 1.5, -6, 3, 3, hc("#8a5a2a"))
		"cash":
			g.rect(-7, -4, 14, 8, hc("#4f7a3a")); g.rect(-6, -3, 12, 6, hc("#8fc06a")); g.ellipse(0, 0, 2.5, 2, 0, hc("#4f7a3a"))
		"band":
			g.rect(-6, -3, 12, 6, hc("#e8e4d8")); g.rect(-1, -2.5, 2, 5, hc("#c0392b")); g.rect(-3, -1, 6, 2, hc("#c0392b"))
		"med":
			g.rect(-6, -6, 12, 12, hc("#e8e4d8")); g.rect(-1.5, -4.5, 3, 9, hc("#c0392b")); g.rect(-4.5, -1.5, 9, 3, hc("#c0392b"))
		"parts":
			var pts := PackedVector2Array()
			for q in 8:
				var a := q / 8.0 * TAU
				pts.append(Vector2(cos(a) * 6.5, sin(a) * 6.5)); pts.append(Vector2(cos(a + 0.2) * 4.5, sin(a + 0.2) * 4.5))
			g.poly(pts, hc("#9aa0a4")); g.circle(0, 0, 2, hc("#3a3e40"))
		"goods":
			g.rect(-6, -5, 12, 10, hc("#7a4a7a")); g.rect(-1, -5, 2, 10, hc("#c9a0c9")); g.rect(-6, -1, 12, 2, hc("#c9a0c9"))
		"bomb":
			g.rr(-6, -3, 12, 6, 2, hc("#55595c")); g.rect(5, -1, 2, 2, hc("#ff4a30"))
		"armor":
			g.poly(PackedVector2Array([Vector2(-6, -6), Vector2(-2, -6), Vector2(0, -3), Vector2(2, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)]), hc("#4a5a70"))
		"chart":
			g.rect(-7, -5, 14, 10, hc("#e0d6b8")); g.polyline(PackedVector2Array([Vector2(-5, 2), Vector2(-1, -2), Vector2(4, 1)]), hc("#9b2a68"), 1)
		"weapon":
			g.rect(-8, -2, 16, 3, hc("#1c1c1c")); g.rect(-8, -2, 5, 6, hc("#5a3e26"))
		_:
			var pts := PackedVector2Array()
			for q in 10:
				var a := q / 10.0 * TAU - PI / 2
				var r2 := 3.0 if q % 2 else 7.0
				pts.append(Vector2(cos(a) * r2, sin(a) * r2))
			g.poly(pts, hc("#ffd27a"))
			var pc := pts.duplicate(); pc.append(pts[0])
			g.polyline(pc, hc("#8a6a20"), 1)
	g.restore()

const RCRGB := ["232,226,208", "156,192,99", "127,178,240", "255,210,122"]
static func draw_pickups(gm, g: Pen) -> void:
	var T: float = gm.T
	for q in gm.S.pk:
		var rar: int = D.RAR[q.k]
		var bob := sin(T * 6 + q.x) * 1.5
		if rar >= 2:
			var pl := 0.6 + 0.4 * sin(T * 5 + q.y)
			g.ga = 0.55 * pl
			g.tex(Tx.glow(RCRGB[rar]), q.x - 9, q.y - 80, 18, 86)
			g.ga = 0.7
			g.tex(Tx.glow(RCRGB[rar]), q.x - 22, q.y - 22, 44, 44)
			g.ga = 1.0
		g.ellipse(q.x + 2, q.y + 3, 7, 4, 0, Color(0, 0, 0, 0.3))
		var rc := hc(D.RCOL[rar]); rc.a = 0.6
		g.ring(q.x, q.y - q.z + bob, 10, rc, 1.2)
		draw_item(g, q.k, q.x, q.y - q.z + bob)

static func hud_ground(gm, g: Pen) -> void:
	var S: Dictionary = gm.S
	var G: Dictionary = gm.G
	var W: float = gm.Wv
	var H: float = gm.Hv
	var T: float = gm.T
	var pw := minf(W - 24, 330)
	var px := 10.0
	var py := 10.0
	var ink := hc("#efe6cf")
	g.rr(px, py, pw, 106, 6, rgba(12, 16, 14, 0.74))
	if G.armor > 0: g.rect(px + 54, py + 24, (pw - 66) * G.armor / 100, 3, hc("#9fb6e0"))
	if S.p.stam < 100: g.rect(px + 54, py + 28, (pw - 66) * S.p.stam / 100, 2, hc("#e3644c") if S.p.stam < 15 else hc("#e8c860"))
	g.text("Health", px + 10, py + 17, 12, hc("#b9b09a"))
	g.rect(px + 54, py + 11, pw - 66, 12, Color(1, 1, 1, 0.12))
	g.rect(px + 54, py + 11, (pw - 66) * G.hp / 100, 12, hc("#e3644c") if G.hp < 30 else hc("#9cc063"))
	g.text("%s   %d bomb%s" % [(D.WEAPONS[G.weapon].name + ", " + str(G.ammo) + " rounds") if G.ammo > 0 else "Machete, no rounds", G.bombs, "" if G.bombs == 1 else "s"], px + 10, py + 40, 13, ink)
	g.text("%d bandage%s   %d medkit%s   %d part%s%s" % [G.band, "" if G.band == 1 else "s", G.med, "" if G.med == 1 else "s", G.parts, "" if G.parts == 1 else "s", ("   armor " + str(int(ceil(G.armor)))) if G.armor > 0 else ""], px + 10, py + 58, 13, ink)
	var awake := 0
	for z in S.zs:
		if not z.dormant: awake += 1
	g.text("$%d   %d gal in cans   %d dead in sight" % [G.cash, int(floor(G.carried)), awake], px + 10, py + 76, 13, ink)
	var dk: float = gm.dark()
	g.text("Day %d, %s%s" % [gm.day(), gm.clock(), ". Night, they move faster" if dk > 0.5 else ""], px + 10, py + 94, 13, hc("#9fb6e0") if dk > 0.5 else hc("#b9b09a"))
	if gm.ASH.is_empty():
		for i in 22: gm.ASH.append({"x": randf(), "y": randf(), "s": 0.4 + randf(), "o": randf() * 9})
	for a in gm.ASH:
		var x := fposmod(a.x + T * 0.012 * a.s + sin(T * 0.7 + a.o) * 0.01, 1.0) * W
		var y := fmod(a.y + T * 0.02 * a.s, 1.0) * H
		g.circle(x, y, 0.8 + a.s * 0.7, rgba(200, 196, 188, 0.2))
	draw_objective(gm, g, py + 112)
	var nx := 10.0
	var ny := py + 162
	var nw := minf(W - 24, 220)
	var f: float = S.noise / 100.0
	g.rr(nx, ny, nw, 20, 5, rgba(12, 16, 14, 0.74))
	g.rect(nx + 56, ny + 7, nw - 64, 6, Color(1, 1, 1, 0.1))
	var nc: Color
	if f >= 1: nc = hc("#ff5a3a") if fmod(T, 0.4) < 0.2 else hc("#a3301f")
	elif f > 0.65: nc = hc("#e3644c")
	elif f > 0.35: nc = hc("#e0a040")
	else: nc = hc("#b9b09a")
	g.rect(nx + 56, ny + 7, (nw - 64) * f, 6, nc)
	for q in [0.35, 0.65]: g.rect(nx + 56 + (nw - 64) * q - 1, ny + 5, 2, 10, Color(0, 0, 0, 0.5))
	g.text("HORDE" if f >= 1 else "Noise", nx + 8, ny + 10, 11, hc("#ff8a70") if f >= 1 else ink)
	var gs: float = gm.ground_scale()
	if S.npc == null and G.contracts.size():
		var sx: float = W / 2 + (S.plane.x - S.cx) * gs
		var sy: float = H / 2 + (S.plane.y - S.cy) * gs
		if sx < 20 or sx > W - 20 or sy < 150 or sy > H - 20:
			var a := atan2(sy - H / 2, sx - W / 2)
			var ex := clampf(sx, 34, W - 34)
			var ey := clampf(sy, 170, H - 40)
			g.save(); g.translate(ex, ey); g.rotate(a)
			var tri := PackedVector2Array([Vector2(14, 0), Vector2(-8, -10), Vector2(-8, 10)])
			g.poly(tri, hc("#f2b64a"))
			var tc := tri.duplicate(); tc.append(tri[0])
			g.polyline(tc, Color(0, 0, 0, 0.6), 2)
			g.restore()
			g.text("Plane", ex - cos(a) * 24, ey - sin(a) * 18, 11, hc("#f3d38c"), 0, "700")
	if S.npc:
		var n: Dictionary = S.npc
		var sx: float = W / 2 + (n.x - S.cx) * gs
		var sy: float = H / 2 + (n.y - S.cy) * gs
		if sx < 20 or sx > W - 20 or sy < 150 or sy > H - 20:
			var a := atan2(sy - H / 2, sx - W / 2)
			g.save(); g.translate(clampf(sx, 30, W - 30), clampf(sy, 170, H - 40)); g.rotate(a)
			g.poly(PackedVector2Array([Vector2(12, 0), Vector2(-7, -8), Vector2(-7, 8)]), hc("#e07ab3"))
			g.restore()
	if W > 480:
		g.text(S.s.name, W - 14, py + 17, 13, hc("#f0c4dd"), 1, "700")
		# danger level under the name: five dots, filled up to the danger level
		var dg: int = clampi(int(S.danger), 0, 5)
		for i in 5:
			var cxp: float = W - 18 - (4 - i) * 12
			if i < dg: g.circle(cxp, py + 31, 4.2, hc("#f0c4dd"))
			else: g.ring(cxp, py + 31, 3.8, rgba(240, 196, 221, 0.6), 1.3)
