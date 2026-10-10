class_name Blasts
## Explosions (red barrels, thrown bombs, cars blowing up): blast damage, the push that
## throws people, and the cars themselves (hitpoints, smoke, fuse). Split out of game.gd.

# Cars on the ground (exploration mode). Any bullet that hits one, and any blast that
# reaches it, takes hitpoints off. Somewhere between CAR_SMOKE_MIN and CAR_SMOKE_MAX of its
# hitpoints gone (picked per car) it starts smoking; at 0 it catches fire and blows up after
# a random CAR_FUSE_MIN to CAR_FUSE_MAX seconds. Smoke, fire and the blast all come from one end of the
# car (the middle of its front or rear third, picked per car). The burnt-out wreck stays put and still blocks.
# For scale: revolver 30 a shot, lever rifle 95, a red barrel up close 160.
const CAR_HP := 600.0
const CAR_SMOKE_MIN := 0.6
const CAR_SMOKE_MAX := 0.8
const CAR_FUSE_MIN := 3.0
const CAR_FUSE_MAX := 5.0
const CAR_BLAST_R := 250.0       # px (a red barrel is 130)
const CAR_BLAST_DMG := 100.0     # to zombies, survivors and you at the centre (a barrel: 160 to them, 40 + 8 to you)
const CAR_BLAST_CAR_DMG := 320.0 # to other cars at the centre, so blasts chain from car to car
const CAR_BLAST_NOISE := 40.0    # added to the noise meter (a barrel adds 18)
const CAR_SCORCH_R := 44.0       # scorch mark left on the ground, px (a barrel's is 62)
const CAR_SCORCH_A := 0.4        # and how dark at the centre (a barrel's is 0.75)
const CAR_SMOLDER := 30.0        # seconds the wreck's smoke plume rises afterwards, thinning out
const BOMB_BLAST_R := 130.0       # px, a thrown bomb's (and a red barrel's) blast radius
# Blasts throw zombies, survivors and you away from the centre: they
# fly off at BLAST_PUSH_* px/s (at the centre, falling to 0 at BLAST_PUSH_RANGE x the blast
# radius, so the push reaches a little past the damage), slowing quickly (BLAST_PUSH_DRAG), and walls stop them. While flung they can't
# walk. Survivors cry out (zombies don't). A car's push at the centre carries about
# 210 px, a bomb's or barrel's about 155.
const BLAST_PUSH_CAR := 1300.0
const BLAST_PUSH_BOMB := 600.0
const BLAST_PUSH_RANGE := 1.3    # push reach, x the blast (damage) radius
const BLAST_PUSH_DRAG := 0.02    # fraction of the push speed left after one second
const BLAST_DMG_TIME := 0.4      # blast damage to people (you, zombies, survivors) lands spread over this many seconds,
								 # so they're seen flying before they drop. Cars and barrels take theirs at once.
const BLAST_DEAF_R := 2.0 / 3.0  # deafened (Synth.deafen) within this fraction of a car's or indoor bomb's blast radius
const BLAST_CRY_MAX := 3         # most cries one blast sets off (the nearest survivors)
const BLAST_CRY_DELAY := 0.12     # seconds after a barrel or bomb goes off before the first cry
const BLAST_CRY_DELAY_CAR := 0.3  # ...and after a car blows up (its boom is longer)
const BLAST_CRY_STAGGER := 0.12   # gap between one cry and the next (barrels and bombs; a car's cries come together)
const BLAST_CRY_CAR_VOL := 2.0    # car blasts: cries this many times louder (+6 dB)
# A blinking red dashed ring shows the blast radius around burning cars and thrown bombs
# (drawn in render.gd). It blinks twice as fast in the last BLAST_RING_HURRY seconds of the fuse.
const BLAST_RING_BLINK := 3.0    # blinks per second
const BLAST_RING_HURRY := 1.5
const BLAST_RING_DASH := 6.0     # dash length, px...
const BLAST_RING_GAP := 18.0     # ...and the gap between dashes

var gm: Game   # the game: run state, site, shared helpers

func _init(game: Game) -> void:
	gm = game

## A red barrel, thrown bomb, or (big = true) a car blowing up.
func explode(br: Dictionary, big: bool = false) -> void:
	if br.dead: return
	br.dead = true
	gm.add_noise(CAR_BLAST_NOISE if big else 18.0)
	var R := CAR_BLAST_R if big else BOMB_BLAST_R
	var zd := CAR_BLAST_DMG if big else 160.0
	var k := R / 130.0   # visual scale
	for c in gm.S.crates:
		if not c.open and c.ty == "safe" and Vector2(c.x - br.x, c.y - br.y).length() < R * 0.92:
			c.forced = true
			gm.loot_crate(c)
	gm.sfx("bigboom" if big else "boom")
	gm.S.shake = 26.0 if big else 16.0
	gm.S.boomFlash = 0.5 if big else 0.3
	gm.S.scorch.append({"x": br.x, "y": br.y})   # also where the blast's light flash is drawn
	if big: gm.S.bg.stamp(["scorch", br.x, br.y, CAR_SCORCH_R, CAR_SCORCH_A])
	else: gm.stamp_scorch(br.x, br.y)
	for i in (18 if big else 9):
		gm.S.smoke.append({"x": br.x + (randf() - 0.5) * 60 * k, "y": br.y + (randf() - 0.5) * 60 * k, "r": (30 + randf() * 30) * sqrt(k), "life": 2 + randf() * 2 * k, "max": 2.0 + 2.0 * k, "g": false})
	for i in (110 if big else 40):
		var a := randf() * TAU
		var v := (60 + randf() * 260) * sqrt(k)
		gm.S.fx.append({"x": br.x, "y": br.y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.3 + randf() * 0.5 * k, "c": "#ffb347" if randf() < 0.5 else ("#e3644c" if randf() < 0.7 else "#fff0b0"), "sz": 4.0 if big and randf() < 0.4 else 3.0, "drag": false})
	if big:
		for i in 14:   # flying wreckage
			var a := randf() * TAU
			var v := 120 + randf() * 220
			gm.S.fx.append({"x": br.x, "y": br.y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.6 + randf() * 0.6, "c": "#2a2624", "sz": 5.0, "drag": true})
	var push := BLAST_PUSH_CAR if big else BLAST_PUSH_BOMB
	var PR := R * BLAST_PUSH_RANGE
	# Walls, sandbags, rocks and cars (anything that stops a bullet) shelter people, cars
	# and barrels from the blast: no damage, no push. The noise still carries.
	for z in gm.S.zs:
		var d := Vector2(z.x - br.x, z.y - br.y).length()
		if d < PR and not blast_clear(br, z.x, z.y): d = 1e9
		if d < R: blast_burn(z, zd * (1 - d / R / 1.3))
		if d < PR and not z.dead: blast_push(z, br, d, PR, push)
		if d < (900 if big else 700): z.alert = true
	var criers: Array = []
	for v in gm.S.sv:
		var hd := Vector2(v.x - br.x, v.y - br.y).length()   # for hearing
		var d := hd if hd >= PR or blast_clear(br, v.x, v.y) else 1e9
		if d < R:
			var vdm := zd * (1 - d / R / 1.3)
			if gm.survives(v.hp, v.get("armor", 0.0), vdm): gm.blood_spray(v.x, v.y, Vector2(v.x - br.x, v.y - br.y))
			blast_burn(v, vdm)
		if d < PR and not v.dead:
			blast_push(v, br, d, PR, push)
			criers.append([d, v])
		if hd < (900 if big else 700): gm.survivors.sv_hear(v, br.x, br.y)
	criers.sort_custom(func(a, b): return a[0] < b[0])
	# The cries come in just after the bang so the boom doesn't drown them out: one after
	# another for a barrel or bomb, all together (and louder) for a car's much bigger blast.
	for c in mini(criers.size(), BLAST_CRY_MAX):
		var cv: float = 0.14 * (1.0 - 0.6 * float(criers[c][0]) / PR) * (BLAST_CRY_CAR_VOL if big else 1.0)
		var wait: float = (BLAST_CRY_DELAY_CAR if big else BLAST_CRY_DELAY + c * BLAST_CRY_STAGGER) + randf() * 0.05
		var vp: float = criers[c][1].get("voice", 1.0)
		gm.get_tree().create_timer(wait).timeout.connect(func(): gm.sfx("cry", cv, vp))
	for o in gm.S.barrels:
		if not o.dead and o.fuse < 0 and Vector2(o.x - br.x, o.y - br.y).length() < R * 0.85 and blast_clear(br, o.x, o.y): o.fuse = 0.15
	# blasts damage cars too, so a barrel or a burning car can set off the ones nearby
	for car in gm.S.cars:
		if car == br or car.dead: continue
		var d := maxf(0.0, Vector2(car.x - br.x, car.y - br.y).length() - 28.0)   # car body, not just its hot end
		if d < R and blast_clear(br, car.x, car.y, car): car_hit(car, (CAR_BLAST_CAR_DMG if big else zd) * (1 - d / R / 1.3))
	var pd := Vector2(gm.S.p.x - br.x, gm.S.p.y - br.y).length()
	if pd < PR and not blast_clear(br, gm.S.p.x, gm.S.p.y): pd = 1e9
	if pd < R:
		var pdm := zd * (1 - pd / R / 1.3) if big else 40 * (1 - pd / R) + 8
		gm.hurt(0.0, "blast")   # the flinch, splatter and sound now; the damage itself over BLAST_DMG_TIME
		# ears ringing, everything else turned down for a few seconds: only from a car, or a bomb
		# going off inside a building, and only close in (BLAST_DEAF_R of the blast radius)
		if pd < R * BLAST_DEAF_R and (big or (gm.S.thrown.has(br) and gm.survivors.room_at(br.x, br.y) != null)):
			gm.synth.deafen()
		if gm.survives(gm.G.hp, gm.G.armor, pdm): gm.blood_spray(gm.S.p.x, gm.S.p.y, Vector2(gm.S.p.x - br.x, gm.S.p.y - br.y))
		blast_burn(gm.S.p, pdm)
	if pd < PR: blast_push(gm.S.p, br, pd, PR, push)   # you get thrown too

## Is there a clear line from blast br to (x, y), with nothing that stops bullets in the
## way? The exploding car's own tiles (and a target car's, `tgt`) don't count.
func blast_clear(br: Dictionary, x: float, y: float, tgt = null) -> bool:
	var d := Vector2(x - br.x, y - br.y).length()
	var n := int(ceil(d / 8.0))
	for i in range(1, n):
		var t := float(i) / n
		var qx: float = br.x + (x - br.x) * t
		var qy: float = br.y + (y - br.y) * t
		if not gm.solid_b(qx, qy): continue
		var c = car_at(qx, qy)
		if c is Dictionary and (c == br or c == tgt): continue
		return false
	return true

## Queue blast damage on a zombie, survivor or the player (S.p), dealt evenly over
## BLAST_DMG_TIME by blast_dmg_tick(). Overlapping blasts stack. No white hit flash.
func blast_burn(e: Dictionary, amt: float) -> void:
	if amt <= 0: return
	if not e.has("burn"): e.burn = []
	e.burn.append([amt / BLAST_DMG_TIME, BLAST_DMG_TIME])

## Deal this frame's share of queued blast damage. Kills zombies and survivors who
## run out of hitpoints (counted as your kills, like before); the player goes through hurt().
func blast_dmg_tick(e: Dictionary, dt: float) -> void:
	if not e.has("burn"): return
	var amt := 0.0
	var i: int = e.burn.size() - 1
	while i >= 0:
		var b: Array = e.burn[i]
		var t := minf(dt, b[1])
		amt += b[0] * t
		b[1] -= t
		if b[1] <= 0.0: e.burn.remove_at(i)
		i -= 1
	if e.burn.is_empty(): e.erase("burn")
	if amt <= 0 or e.get("dead", false): return
	if e == gm.S.p:
		gm.hurt(amt, "blast", false)
		return
	if e.has("armor"): gm.dmg_enemy(e, amt)
	else: e.hp -= amt
	if e.hp <= 0:
		e.dead = true
		gm.G.stats.kills += 1
		gm.blood(e.x, e.y, 6)

## Throw a zombie or survivor at distance d from blast br (push reach R) away from the centre;
## the push fades to nothing at the edge. Adds to any push they're already riding.
func blast_push(e: Dictionary, br: Dictionary, d: float, R: float, push: float) -> void:
	var dir := Vector2(e.x - br.x, e.y - br.y)
	dir = dir / d if d > 0.5 else Vector2.from_angle(randf() * TAU)
	var sp := push * (1.0 - d / R)
	e.kbx = e.get("kbx", 0.0) + dir.x * sp
	e.kby = e.get("kby", 0.0) + dir.y * sp

## Carry a zombie, survivor or the player (S.p) along on a blast push (walls stop them), slowing it down.
## Returns how much of their own walking they can do this frame: none while flung hard,
## all of it once the push has nearly died away.
func knock_tick(e: Dictionary, dt: float) -> float:
	if not e.has("kbx"): return 1.0
	var kv := Vector2(e.kbx, e.kby)
	var ox: float = e.x
	var oy: float = e.y
	gm.move_c(e, kv.x * dt, kv.y * dt, 10)
	if e != gm.S.p and gm.in_safe(e.x, e.y) and not gm.in_safe(ox, oy):
		e.x = ox; e.y = oy   # not into the rescue survivor's hiding place (you can go in)
	kv *= pow(BLAST_PUSH_DRAG, dt)
	if kv.length() < 8.0:
		e.erase("kbx"); e.erase("kby")
		return 1.0
	e.kbx = kv.x; e.kby = kv.y
	return clampf(1.0 - kv.length() / 150.0, 0.0, 1.0)

# ---------------- cars ----------------
## Gives the site's parked cars hitpoints, and maps their tiles so bullets can find them.
func init_cars() -> void:
	gm.S["carAt"] = {}
	for car in gm.S.cars:
		# x, y is the hot end, not the middle: the centre of the front or rear third
		var end := (1.0 if randf() < 0.5 else -1.0) * 2.0 * gm.TS / 3.0
		var hz: bool = car.w > car.h
		car.merge({"x": (car.c + car.w * 0.5) * gm.TS + (end if hz else 0.0), "y": (car.r + car.h * 0.5) * gm.TS + (0.0 if hz else end), "hp": CAR_HP,
			"smokeAt": CAR_HP * (1.0 - randf_range(CAR_SMOKE_MIN, CAR_SMOKE_MAX)),
			"fuse": -1.0, "dead": false, "puff": 0.0, "burnT": 0.0, "burnMax": CAR_SMOLDER})
		for r in range(car.r, car.r + car.h):
			for c in range(car.c, car.c + car.w):
				gm.S.carAt[r * gm.S.cols + c] = car

## The car (if any) parked on the tile under world point (x, y).
func car_at(x: float, y: float):
	var c := int(floor(x / gm.TS))
	var r := int(floor(y / gm.TS))
	if c < 0 or r < 0 or c >= gm.S.cols or r >= gm.S.rows: return null
	return gm.S.carAt.get(r * gm.S.cols + c)

func car_hit(car: Dictionary, d: float) -> void:
	if car.dead or car.fuse >= 0: return
	car.hp -= d
	if car.hp <= 0:
		car.fuse = randf_range(CAR_FUSE_MIN, CAR_FUSE_MAX)
		gm.sfx("pop")
		for i in 12: gm.S.fx.append({"x": car.x, "y": car.y, "vx": (randf() - 0.5) * 160, "vy": (randf() - 0.5) * 160, "life": 0.4, "c": "#ffb347", "sz": 3.0, "drag": true})

## Smoke from damaged cars, the countdown on burning ones, smouldering wrecks.
func update_cars(dt: float) -> void:
	for car in gm.S.cars:
		var rate := 0.0
		if car.dead:
			car.burnT -= dt   # the plume itself is drawn in render.gd
		elif car.fuse >= 0:
			rate = 3.0
			car.burnT += dt
		elif car.hp <= car.smokeAt:
			# thin grey wisps at first, thicker as it nears 0
			rate = 1.5 + 4.0 * (1.0 - car.hp / maxf(1.0, car.smokeAt))
		if rate > 0:
			car.puff -= dt * rate
			while car.puff <= 0:
				car.puff += 1.0
				var hot: bool = car.fuse >= 0 and not car.dead
				gm.S.smoke.append({"x": car.x + (randf() - 0.5) * 12, "y": car.y + (randf() - 0.5) * 12, "r": (8 + randf() * 8) * (1.6 if hot else 1.0), "life": 1.6 + randf() * 1.4, "max": 3.0, "g": false})
		if car.fuse >= 0 and not car.dead:
			car.fuse -= dt
			if car.fuse <= 0:
				car.burnT = CAR_SMOLDER
				car.burnMax = CAR_SMOLDER
				gm.S.bg.stamp(["wreck", car])
				explode(car, true)
				if gm.S == null or gm.uist == "dead": return
