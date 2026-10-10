class_name Survivors
## Armed survivors: garrisons at survivor-held strips, patrols, alarms, cover, flanking,
## their guns, and the rescue survivor on pickup missions. Split out of game.gd; the
## per-frame survivor update is upd_survivors().

# Survivor-held strips (see World.HOSTILE_CHANCE)
const GARRISON_MIN := 11       # total armed survivors at one of these strips...
const GARRISON_MAX := 18
const GARRISON_OUT_MIN := 6    # ...of which this many start outside; the rest wait in buildings
const GARRISON_OUT_MAX := 9
# Reinforcements (noise waves, see Game.upd_spawns()) don't all turn up at once: each wave is
# queued (S.svq) and they arrive in groups of SV_REINF_GROUP, SV_REINF_GAP seconds apart, each
# group together from a random map edge. They only know roughly where you are and sweep toward
# there like the ones called out of buildings (sv_sweep()), so they have to find you.
const SV_REINF_GAP := Vector2(6.0, 12.0)
const SV_REINF_GROUP := Vector2i(2, 3)
# Unalerted survivors pace around their post (see sv_patrol()).
const SV_PATROL_MIN := 2.0     # wander radius from their post, tiles (each picks one in this range)
const SV_PATROL_MAX := 6.0
const SV_PATROL_SPD := 0.4     # walking speed while patrolling, fraction of their normal 85 px/s
# Getting clear of blasts (see sv_flee()): anyone inside the blast radius (plus SV_FLEE_MARGIN) of a
# lit bomb, a burning car or a lit barrel, with no wall shielding them, drops what they're doing
# after a reaction time of SV_FLEE_REACT seconds and runs out of it at SV_FLEE_SPD.
const SV_FLEE_MARGIN := 24.0
const SV_FLEE_REACT := Vector2(0.25, 0.7)
const SV_FLEE_SPD := 1.25
const SV_SPD_VAR := Vector2(0.85, 1.0)   # each survivor's own speed multiplier (on everything they do) is picked from this range
const SV_PAUSE_MIN := 1.5      # seconds standing and looking around between legs
const SV_PAUSE_MAX := 4.5
# Alerted survivors only know where you were when they last saw or heard you. Out of
# sight they head there, search around it, and give up after SV_FORGET seconds.
const SV_FORGET := 12.0        # seconds without seeing/hearing you before they stand down
const SV_SEARCH_R := 5.0       # search radius around your last known spot, tiles
# The ones waiting indoors (v.rm = their building) really are inside, pottering about within the
# walls; walk in and they can spot you like anyone else. They ignore the alarm. Every SV_WANDER_T
# seconds each has SV_WANDER_CHANCE of strolling out of the door on their own (not alerted) to
# patrol outside. When the noise meter passes its first mark they all come out (call_out()),
# unaware of exactly where you are, and sweep toward where you were, then patrol that area.
const SV_WANDER_T := 60.0
const SV_WANDER_CHANCE := 0.10
# Unalerted survivors only spot you inside their field of view: within SV_VIEW_HALF degrees of
# where they're facing (and 420 px). Alerted ones see wider, SV_VIEW_HALF_ALERT either side, but
# still not behind them. Closer than SV_SENSE px they notice you whichever way they face.
const SV_VIEW_HALF := 60.0
const SV_VIEW_HALF_ALERT := 90.0
const SV_SENSE := 80.0
const SV_ALARM_R := 500.0      # a survivor spotting you sends everyone within this many px (of them) searching
const SV_SWEEP_SPREAD := 6.0   # how far off your actual position they aim, tiles
const SV_SWEEP_SPD := 0.8     # sweep speed, fraction of 85 px/s
const SV_SWEEP_R := 7.0        # patrol radius once they get there, tiles
# On first spotting you (since they last stood down) a survivor stops, turns on you and
# yells before opening fire. The yell itself adds nothing to the noise meter.
const SV_YELL_MIN := 0.7       # seconds between the yell and their first shot
const SV_YELL_MAX := 1.0
const SV_YELL_GAP := Vector2(3.0, 15.0)   # seconds (random in this range) before anyone else may yell
# In a firefight (after the yell) survivors fight from cover, see sv_cover_fight(): they pick a
# spot near them with something bullet-proof between it and you (a wall, sandbags, rocks, a
# car), run to it, duck down, then step out sideways to shoot and duck back in. If you flank
# them (you can see or hit them while they're ducked) they find new cover. With none to be
# had they fight in the open as before. Burning cars (and anywhere in their blast radius) and
# smoking cars are never used, and anyone behind a car that starts smoking gets away from it;
# burnt-out wrecks are fine cover.
const SV_COVER_R := 4.5         # how far they'll go for cover, tiles (nothing that close: they fight in the open)
const SV_COVER_MIN_D := 64.0   # 2 tiles; within this many px of you they don't bother with cover (and leave it) and just fight
const SV_COVER_SPD := 1.25      # running to cover, fraction of 85 px/s (they don't shoot on the way)
const SV_COVER_MAXT := 4.0      # give up on a spot they haven't reached in this many seconds
const SV_COVER_RETRY := 1.5     # seconds between looks for cover when there's none to be had
const SV_HIDE_MIN := 0.9        # seconds ducked behind cover between peeks
const SV_HIDE_MAX := 2.1
const SV_PEEK_AIM := 0.35       # stepping out: seconds from seeing you to their first shot
const SV_PEEK_MIN := 1.25       # seconds they stay out shooting once they see you
const SV_PEEK_MAX := 2.5
const SV_PEEK_LOOK := 1.5       # out this long without seeing you counts as a miss...
const SV_PEEK_MISSES := 2       # ...and after this many misses in a row they leave cover to hunt for you
const SV_COVER_CAR_PEN := 64.0  # an intact car is worse cover than a wall: scored as if this many px further away
const SV_COVER_BARREL := 110.0  # won't take cover within this many px of a red barrel
const SV_SNAP_SPREAD := 3.5     # running to cover they fire snap shots, this many times their usual spread
const SV_LEAP_PEEKS := 3        # after this many peeks with shots they move up to cover closer to you...
const SV_LEAP_R := 4.0          # ...looking this many tiles round them, at least a tile nearer you
const SV_RUSH_CHANCE := 0.2     # rushers never take cover or flank: they push in on you firing
const SV_RUSH_NEAR := 130.0     # how close (px) a rusher pushes before strafing round you
# Flanking (see sv_squad() and sv_flank()): while SV_FLANK_MIN or more survivors are fighting
# you, half of them circle round to your left and right, about SV_FLANK_ANGLE from the side
# the rest are on, and take cover there at their gun's range. They hold fire on the way
# unless you get close or hit them. Roles are handed out once every SV_SQUAD_T seconds.
const SV_FLANK_MIN := 4
const SV_SQUAD_T := 1.0          # seconds between squad checks
const SV_FLANK_SEEN := 5.0       # the squad counts as fighting you while one of them saw you this recently, s
const SV_FLANK_ANGLE := 90.0     # degrees round from the main group's side
const SV_FLANK_R := 4.0          # cover search radius around the flanking spot, tiles
const SV_FLANK_PATH := 40        # longest walk to a flanking spot, tiles
const SV_FLANK_MOVE := 4.0       # pick a new flanking spot once you've moved this many tiles
const SV_FLANK_MAXT := 10.0      # give up on a flank not reached in this many seconds
const SV_FLANK_ENGAGE := 150.0   # a flanker this close to you (px) and seeing you stops sneaking and fights
const SV_FLANK_REST := 8.0       # after giving up, not picked to flank again for this many seconds
# Armed survivors' guns. Chance of each weapon ~ exp(-price / (SV_GUN_BASE + SV_GUN_STEP x danger)):
# cheaper guns are always more common (scarcity), but dearer ones show up more where danger is high.
const SV_GUN_BASE := 300.0
const SV_GUN_STEP := 250.0
const SV_DMG_REF := 30.0
const SV_SHOT_NOISE := 0.5   # each survivor gunshot adds this fraction of the gun's noise (as if you'd fired it) to the meter

# Rescue survivor (pickup missions)
const NPC_GUNS := [0, 1, 2, 5]    # revolver, pump shotgun, lever rifle, double-barrel
const NPC_DMG := 0.7              # their shots do this fraction of the gun's normal damage
const NPC_FIRE_WINDOW := 8.0      # they keep shooting this long after your last loud shot
const NPC_RANGE := 380.0          # how far they'll engage
const SV_GUN_DROP := 0.15     # chance a killed survivor also drops their gun
# Survivor body armour: chance by danger (index = danger), and how much it holds. Like
# the player's armour, it soaks up half of each hit until it's used up.
const SV_ARMOR_CHANCE := [0.0, 0.05, 0.15, 0.25, 0.35, 0.45]
const SV_ARMOR := 50.0      # survivor bullet damage scales with gun damage / this (revolver = 1x)
# Bombs (see sv_bomb()): some survivors carry one. None at danger 1, SV_BOMB_BASE at danger 2,
# plus SV_BOMB_STEP for each level above. A carrier who loses sight of you while you're behind
# cover near where they last saw you rolls SV_BOMB_COVER (once each time you duck out of their
# sight) to lob it there. When you go into a building mid-fight, each carrier rolls SV_BOMB_DOOR
# to come round and throw it in through the door you used. After SV_BOMB_MAX throws, a SV_BOMB_REST pause.
# Lobbed bombs fly over walls and cover, land, then go off SV_BOMB_FUSE seconds later.
const SV_BOMB_BASE := 0.50
const SV_BOMB_STEP := 0.10
const SV_BOMB_COVER := 0.50
const SV_BOMB_DOOR := 0.75
const SV_BOMB_MAX := 2
const SV_BOMB_REST := 30.0      # once SV_BOMB_MAX have been thrown, nobody throws for this many seconds
const SV_BOMB_NOISE := 65.0     # nobody throws until the noise meter is past its second mark (65 of 100)
const SV_BOMB_RANGE := 380.0    # longest throw, px
const SV_BOMB_MIN := 170.0      # won't throw closer than this, px (a bomb's blast is 130)
const SV_BOMB_HID := 3.0        # behind cover = out of their sight within this many tiles of where they last saw you
const SV_BOMB_WAIT := 0.8       # ...for this many seconds before they roll
const SV_BOMB_WIND := 0.5       # seconds standing still, winding up, before the throw
const SV_BOMB_FUSE := 1.0       # seconds from landing to the blast
const SV_BOMB_IN := 1.5         # door throws land this many tiles inside the doorway
const SV_BOMB_OUT := 4.0        # carriers head for a spot this many tiles outside that door...
const SV_BOMB_GO := 10.0        # ...and give up if they can't get a throw in within this many seconds

var gm: Game   # the game: run state, site, shared helpers

func _init(game: Game) -> void:
	gm = game

# ======================================================================
# spawning, patrols and the alarm
# ======================================================================
## Pick a gun for an armed survivor at this danger level (index into D.WEAPONS).
func pick_sv_weapon(danger: int) -> int:
	var sc := SV_GUN_BASE + SV_GUN_STEP * maxi(1, danger)
	var ws: Array = []
	var tot := 0.0
	for w in D.WEAPONS:
		var x := exp(-float(w.price) / sc)
		ws.append(x)
		tot += x
	var r := randf() * tot
	for i in ws.size():
		r -= ws[i]
		if r <= 0: return i
	return 0

## One armed survivor.
func new_sv(x: float, y: float) -> Dictionary:
	var dg: int = int(gm.S.danger) if gm.S else 1
	var arm: float = SV_ARMOR if randf() < float(SV_ARMOR_CHANCE[clampi(dg, 0, SV_ARMOR_CHANCE.size() - 1)]) else 0.0
	var bomb := dg >= 2 and randf() < SV_BOMB_BASE + SV_BOMB_STEP * (dg - 2)
	return {"x": x, "y": y, "w": pick_sv_weapon(dg), "burst": 0, "armor": arm, "shirt": ["#5a5f3a", "#4a3a2a", "#3f4f5f"][randi() % 3], "skin": D.sv_skin(),
		"cap": "#3a3226" if randf() < 0.5 else "", "bomb": bomb, "rush": randf() < SV_RUSH_CHANCE, "spm": randf_range(SV_SPD_VAR.x, SV_SPD_VAR.y), "wk": 0.0, "hp": 70.0, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y), "cd": 1 + randf(), "ang": 0.0, "alert": false, "hit": 0.0, "sw": 0.0, "sd": 1.0, "dead": false}

## Unalerted survivors pace around their post: walk to a nearby spot they can see,
## stop and look around for a few seconds, pick another. Returns a steer vector
## (length = speed fraction of the normal 85 px/s).
func sv_patrol_init(v: Dictionary) -> void:
	if not v.has("hx"):
		v.hx = v.x; v.hy = v.y
	if not v.has("pr"):
		v.pr = (SV_PATROL_MIN + randf() * (SV_PATROL_MAX - SV_PATROL_MIN)) * gm.TS   # how far this one wanders
		v.pt = randf() * 3.0   # pause timer (staggered so they don't all move at once)
		v.go = false; v.tx = v.x; v.ty = v.y
		v.lx = v.x; v.ly = v.y; v.stk = 0.0

## Start patrolling around (x, y) with at least radius r tiles, after a short pause.
func sv_repost(v: Dictionary, x: float, y: float, r: float) -> void:
	sv_patrol_init(v)
	v.hx = x; v.hy = y
	v.pr = maxf(v.pr, r * gm.TS)
	v.go = false
	v.pt = 0.3 + randf() * 1.2

## A survivor hears or feels something at (x, y): alerted, and that's where they think you are.
func sv_hear(v: Dictionary, x: float, y: float) -> void:
	v.alert = true
	v.lkx = x; v.lky = y
	v.lost = 0.0
	v.srch = false
	v.trav = false

## Steer toward (tx, ty): straight if the body fits along the line, otherwise along an A*
## path round the walls (cached per survivor, recomputed when the target tile changes).
## Both checks use walk_clear(), not los(): with the thin sight line a survivor at a
## corner could "see" a way through, bump the corner, slide out of sight, turn back to
## the path, and repeat every frame, flicking between two headings.
func sv_nav(v: Dictionary, tx: float, ty: float) -> Vector2:
	var dx: float = tx - v.x
	var dy: float = ty - v.y
	var dl := Vector2(dx, dy).length()
	if dl < 1: return Vector2.ZERO
	if gm.walk_clear(v.x, v.y, tx, ty):
		v.path = PackedVector2Array()
		return Vector2(dx / dl, dy / dl)
	var tc := Vector2i(int(floor(tx / gm.TS)), int(floor(ty / gm.TS)))
	var path: PackedVector2Array = v.get("path", PackedVector2Array())
	if path.is_empty() or v.get("ptc", Vector2i(-1, -1)) != tc:
		path = astar_path(v.x, v.y, tc)
		v.ptc = tc
	while path.size() and Vector2(path[0].x - v.x, path[0].y - v.y).length() < 10: path.remove_at(0)
	# skip ahead to the next waypoint or the one after if it can walk straight there, so
	# a fresh path doesn't send it back to the centre of the tile it's standing in
	for j in range(mini(path.size() - 1, 2), 0, -1):
		if gm.walk_clear(v.x, v.y, path[j].x, path[j].y):
			path = path.slice(j)
			break
	v.path = path
	if path.is_empty(): return Vector2(dx / dl, dy / dl)
	var wx: float = path[0].x - v.x
	var wy: float = path[0].y - v.y
	var wl := Vector2(wx, wy).length()
	if wl < 0.01: return Vector2.ZERO
	return Vector2(wx / wl, wy / wl)

## Path (tile centres, px) from (x, y) to tile tc over walkable ground; built once per site.
func astar_path(x: float, y: float, tc: Vector2i) -> PackedVector2Array:
	var a: AStarGrid2D = gm.S.get("astar", null)
	if a == null:
		a = AStarGrid2D.new()
		a.region = Rect2i(0, 0, gm.S.cols, gm.S.rows)
		a.cell_size = Vector2(gm.TS, gm.TS)
		a.offset = Vector2(gm.TS / 2, gm.TS / 2)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.update()
		var g: PackedByteArray = gm.S.g
		var cols: int = gm.S.cols
		for r in gm.S.rows:
			for c in cols:
				if gm.MOVE[g[r * cols + c]] == 1: a.set_point_solid(Vector2i(c, r))
		gm.S.astar = a
	var fc := Vector2i(int(floor(x / gm.TS)), int(floor(y / gm.TS)))
	if not a.is_in_boundsv(fc) or not a.is_in_boundsv(tc) or a.is_point_solid(tc): return PackedVector2Array()
	return a.get_point_path(fc, tc, true)

func sv_patrol(v: Dictionary, dt: float) -> Vector2:
	sv_patrol_init(v)
	if not v.go:
		v.pt -= dt
		if randf() < dt * 0.6: v.ang += (randf() - 0.5) * 2.0   # glance around while standing
		if v.pt > 0: return Vector2.ZERO
		for t in 8:   # a spot near the post, open ground, in a straight line from here
			var a := randf() * TAU
			var r: float = v.pr * (0.3 + randf() * 0.7)
			var tx: float = v.hx + cos(a) * r
			var ty: float = v.hy + sin(a) * r
			if gm.solid(tx, ty) or not gm.los(v.x, v.y, tx, ty): continue
			if v.has("rm") and not is_same(room_at(tx, ty), v.rm): continue   # indoors: stays inside
			v.tx = tx; v.ty = ty; v.stk = 0.0; v.go = true
			break
		if not v.go:
			v.pt = 1.0
			return Vector2.ZERO
	var ddx: float = v.tx - v.x
	var ddy: float = v.ty - v.y
	var dl := Vector2(ddx, ddy).length()
	# arrived, or stuck against something for a while: stop and wait
	var mv := Vector2(v.x - v.lx, v.y - v.ly).length()
	v.lx = v.x; v.ly = v.y
	v.stk = v.stk + dt if mv < SV_PATROL_SPD * 85.0 * dt * 0.3 else 0.0
	if dl < 10 or v.stk > 0.8:
		v.go = false
		v.pt = SV_PAUSE_MIN + randf() * (SV_PAUSE_MAX - SV_PAUSE_MIN)
		return Vector2.ZERO
	v.ang = atan2(ddy, ddx)
	return Vector2(ddx / dl, ddy / dl) * SV_PATROL_SPD

## Is (x, y) open ground a person can stand on, away from the player's start?
func _garrison_spot_ok(site: Dictionary, x: float, y: float) -> bool:
	return not gm.solid(x, y) and Vector2(x - site.p.x, y - site.p.y).length() > 450

## Garrison for a survivor-held strip: a few posted outside near building doors, the
## rest inside the buildings (see upd_garrison() and call_out() for how they come out).
func spawn_garrison(site: Dictionary) -> void:
	var total := GARRISON_MIN + randi() % (GARRISON_MAX - GARRISON_MIN + 1)
	var outside := mini(total, GARRISON_OUT_MIN + randi() % (GARRISON_OUT_MAX - GARRISON_OUT_MIN + 1))
	var rooms: Array = site.rooms
	for i in total:
		var out_now := i < outside
		for t in 40:
			var x: float
			var y: float
			var rm = null
			if rooms.size() and not out_now:
				# somewhere on the floor inside a building
				rm = rooms[randi() % rooms.size()]
				x = (rm.c + 1.5 + randf() * (rm.w - 3)) * gm.TS
				y = (rm.r + 1.5 + randf() * (rm.h - 3)) * gm.TS
				if gm.hit_box(x, y, 10): continue
			elif rooms.size():
				# the tile just outside a building's door
				rm = rooms[randi() % rooms.size()]
				var top: bool = rm.door[2]
				var dirn := -1.0 if top else 1.0
				x = (rm.door[0] + 1.0) * gm.TS
				y = (rm.door[1] + 0.5 + dirn) * gm.TS
				# posted a little way off from the door
				x += (randf() - 0.5) * 6.0 * gm.TS
				y += dirn * randf() * 3.0 * gm.TS
				rm = null
			else:
				x = (1.5 + randf() * (site.cols - 3)) * gm.TS
				y = (1.5 + randf() * (site.ry - 3)) * gm.TS
			if not _garrison_spot_ok(site, x, y): continue
			var v := new_sv(x, y)
			if rm is Dictionary:   # indoors: paces about the building like a patrol, but stays in
				v.rm = rm
				v.unarmed = true   # gun put down; picks it up once alerted (or called out)
				sv_patrol_init(v)
				v.hx = (rm.c + rm.w * 0.5) * gm.TS; v.hy = (rm.r + rm.h * 0.5) * gm.TS
				v.pr = maxf(rm.w, rm.h) * 0.5 * gm.TS
			site.sv.append(v)
			break

## Garrison behaviour each frame: queued reinforcements arrive, the odd one indoors wanders out,
## and ones called out by call_out() leave their buildings when their time comes and sweep toward
## where the player was. (Ones who spot you indoors just fight; they're alerted and leave this.)
func upd_garrison(dt: float) -> void:
	# queued reinforcements: next group in when the gap is up
	if gm.S.get("svq", 0) > 0:
		gm.S.svqT = gm.S.get("svqT", 0.0) - dt
		if gm.S.svqT <= 0:
			var n: int = mini(gm.S.svq, randi_range(SV_REINF_GROUP.x, SV_REINF_GROUP.y))
			gm.S.svq -= n
			gm.S.svqT = randf_range(SV_REINF_GAP.x, SV_REINF_GAP.y)
			spawn_edge_sv(n)
	for v in gm.S.sv:
		if v.dead or not v.has("rm"): continue
		if v.alert:   # spotted you and came to fight: no longer an indoor one
			leave_building(v, SV_SWEEP_SPD)
			continue
		if v.has("cot"):   # called out: off they go when their moment comes
			if gm.S.t >= v.cot:
				leave_building(v, SV_SWEEP_SPD)
				sv_sweep(v, v.ctx, v.cty)
			continue
		v.wt = v.get("wt", randf() * SV_WANDER_T) - dt   # now and then one strolls out on their own
		if v.wt <= 0:
			v.wt = SV_WANDER_T
			if randf() < SV_WANDER_CHANCE:
				var dx: float = (v.rm.door[0] + 1.0) * gm.TS
				var dy: float = (v.rm.door[1] + 0.5 + (-1.0 if v.rm.door[2] else 1.0) * 3.0) * gm.TS
				leave_building(v, SV_PATROL_SPD)
				v.trav = true; v.sx = dx; v.sy = dy; v.travT = 0.0

## An indoor survivor heads out (at speed spd, a fraction of 85 px/s): no longer kept inside.
func leave_building(v: Dictionary, spd: float) -> void:
	v.erase("rm")
	v.erase("cot")
	v.tsp = spd

## A survivor has just spotted the player at (px, py): everyone within SV_ALARM_R px of
## the spotter who's outside and not already fighting heads out to search near there (the ones
## indoors stay put; see call_out()).
func sv_raise(ox: float, oy: float, px: float, py: float) -> void:
	for o in gm.S.sv:
		if o.dead or o.alert or o.has("rm") or Vector2(o.x - ox, o.y - oy).length() >= SV_ALARM_R: continue
		sv_patrol_init(o)
		sv_sweep(o, px, py)

## The noise meter passed its first mark: everyone still indoors comes out over the next few
## seconds and sweeps toward around (px, py).
func call_out(px: float, py: float) -> void:
	for v in gm.S.sv:
		if v.dead or not v.has("rm") or v.alert or v.has("cot"): continue
		v.cot = gm.S.t + 1.0 + randf() * 9.0
		v.erase("unarmed")   # grabbing their gun on the way out
		v.ctx = px; v.cty = py

## Send a survivor (unaware of exactly where the player is) toward a random open spot
## within SV_SWEEP_SPREAD tiles of (px, py); they patrol there once they arrive.
func sv_sweep(v: Dictionary, px: float, py: float) -> void:
	var spr := SV_SWEEP_SPREAD * gm.TS
	var sx := px
	var sy := py
	for t in 12:
		var ox: float = px + (randf() - 0.5) * 2.0 * spr
		var oy: float = py + (randf() - 0.5) * 2.0 * spr
		if not gm.solid(ox, oy):
			sx = ox; sy = oy
			break
	v.trav = true; v.sx = sx; v.sy = sy; v.travT = 0.0

# ======================================================================
# cover and flanking
# ======================================================================
## How close a survivor likes to fight with their gun, Vector2(near, far) in px:
## shotguns close in, rifles hang back.
func sv_range(v: Dictionary) -> Vector2:
	var w: Dictionary = D.WEAPONS[int(v.get("w", 0))]
	if w.pel > 1: return Vector2(110, 200)
	if w.spr < 0.02: return Vector2(260, 380)
	return Vector2(180, 300)

## Is (x, y) a bad place to hide: inside a burning car's blast radius, or next to a red barrel?
func cover_hazard(x: float, y: float) -> bool:
	for car in gm.S.cars:
		if not car.dead and car.fuse >= 0 and Vector2(car.x - x, car.y - y).length() < Blasts.CAR_BLAST_R: return true
	for br in gm.S.barrels:
		if not br.dead and Vector2(br.x - x, br.y - y).length() < SV_COVER_BARREL: return true
	return false

## A car nobody should hide behind: smoking or on fire. Burnt-out wrecks are fine.
func car_unsafe(car) -> bool:
	return car is Dictionary and not car.dead and (car.fuse >= 0 or car.hp <= car.smokeAt)

## Has another survivor already got cover at (or right by) (x, y)?
func sv_cover_taken(v: Dictionary, x: float, y: float) -> bool:
	for o in gm.S.sv:
		if o == v or o.dead: continue
		if o.has("cv") and Vector2(o.cv.x - x, o.cv.y - y).length() < gm.TS * 1.5: return true
		if o.has("fl") and o.fl.has("cv") and Vector2(o.fl.cv.x - x, o.fl.cv.y - y).length() < gm.TS * 1.5: return true
	return false

## From cover at (x, y), a spot a step or two to the side (n is sideways, across the line to
## the player) they can walk straight to and see the player from. null if there's none.
func sv_peek_spot(x: float, y: float, p: Dictionary, n: Vector2) -> Variant:
	for k in [1.0, -1.0, 1.5, -1.5, 2.0, -2.0]:
		var qx: float = x + n.x * gm.TS * k
		var qy: float = y + n.y * gm.TS * k
		if gm.walk_clear(x, y, qx, qy) and gm.los(qx, qy, p.x, p.y): return Vector2(qx, qy)
	return null

## Look for cover within SV_COVER_R tiles: an open tile with something that stops bullets
## right next to it on the player's side, hiding the whole body from where the player
## stands, with a peek spot beside it, not already taken, not near a burning car or a
## barrel, at a range that suits their gun. Prefers close spots and walls over cars.
## Returns {x, y, pk (peek spot), car (the car it's behind, or null)} or null.
## By default it searches around the survivor; flankers search within rad tiles of `center`
## instead and may walk up to path_max tiles to get there. closer_than: only spots nearer
## the player than this (px), for moving up.
func sv_find_cover(v: Dictionary, p: Dictionary, center = null, rad: float = SV_COVER_R, path_max: float = SV_COVER_R * 1.6, closer_than: float = INF) -> Variant:
	var rg := sv_range(v)
	var pref := (rg.x + rg.y) * 0.5
	var ctr: Vector2 = center if center is Vector2 else Vector2(v.x, v.y)
	var R := int(ceil(rad))
	var vc := int(floor(ctr.x / gm.TS))
	var vr := int(floor(ctr.y / gm.TS))
	var cands: Array = []
	for r in range(vr - R, vr + R + 1):
		for c in range(vc - R, vc + R + 1):
			if not gm.passable(c, r): continue
			var x := (c + 0.5) * gm.TS
			var y := (r + 0.5) * gm.TS
			var dv := Vector2(x - ctr.x, y - ctr.y).length()
			if dv > rad * gm.TS: continue
			var to := Vector2(p.x - x, p.y - y)
			var dp := to.length()
			if dp < SV_COVER_MIN_D or dp > rg.y + 60.0 or dp >= closer_than: continue
			var u := to / dp
			var n := Vector2(-u.y, u.x)
			# something bullet-proof right beside it, toward the player...
			var bx: float = x + u.x * gm.TS * 0.9
			var by: float = y + u.y * gm.TS * 0.9
			if not gm.solid_b(bx, by): continue
			# ...that hides the whole body (centre and both shoulders) from where they stand
			if gm.los(p.x, p.y, x, y) or gm.los(p.x, p.y, x + n.x * 8, y + n.y * 8) or gm.los(p.x, p.y, x - n.x * 8, y - n.y * 8): continue
			if gm.hit_box(x, y, 10) or cover_hazard(x, y): continue
			var car = gm.blasts.car_at(bx, by)
			if car_unsafe(car): continue
			if sv_cover_taken(v, x, y): continue
			var pk = sv_peek_spot(x, y, p, n)
			if not (pk is Vector2): continue
			var sc := dv + absf(dp - pref) * 0.5 + (SV_COVER_CAR_PEN if car is Dictionary and not car.dead else 0.0)
			cands.append([sc, x, y, pk, car])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(cands.size(), 4):   # the best few that are actually a short walk away
		var cd: Array = cands[k]
		if not gm.walk_clear(v.x, v.y, cd[1], cd[2]):
			var path := astar_path(v.x, v.y, Vector2i(int(floor(cd[1] / gm.TS)), int(floor(cd[2] / gm.TS))))
			if path.is_empty() or path.size() > path_max: continue
		return {"x": cd[1], "y": cd[2], "pk": cd[3], "car": cd[4]}
	return null

## Once every SV_SQUAD_T seconds: if SV_FLANK_MIN or more survivors are fighting you, make
## half of them flankers, split left and right of the line from the group to you. Those
## already furthest round to each side are picked first, and existing flankers keep the job.
func sv_squad(p: Dictionary, dt: float) -> void:
	gm.S.sqT = gm.S.get("sqT", 0.0) - dt
	if gm.S.sqT > 0: return
	gm.S.sqT = SV_SQUAD_T
	var fighters: Array = []
	if gm.S.t - gm.S.get("svSeenT", -99.0) < SV_FLANK_SEEN:
		for v in gm.S.sv:
			if not v.dead and v.alert and v.get("called", false) and v.has("lkx"): fighters.append(v)
	if fighters.size() < SV_FLANK_MIN:
		for v in gm.S.sv: v.erase("fl")
		return
	var cen := Vector2.ZERO
	for v in fighters: cen += Vector2(v.x, v.y)
	cen /= fighters.size()
	var back := cen - Vector2(p.x, p.y)   # from you toward the group
	if back.length() < 1: back = Vector2.RIGHT
	back = back.normalized()
	var side_n := Vector2(-back.y, back.x)
	var need: int = int(fighters.size() / 2.0)
	var side_cap: int = int(ceil(need / 2.0))   # most flankers on one side
	var per_side := [0, 0]
	var cand: Array = []
	for v in gm.S.sv:
		if v.has("fl") and not fighters.has(v): v.erase("fl")
	for v in fighters:
		var off := side_n.dot(Vector2(v.x - p.x, v.y - p.y))
		if v.has("fl"):
			var si: int = 0 if v.fl.side < 0 else 1
			if per_side[si] < side_cap and need > 0:
				per_side[si] += 1
				need -= 1
				v.fl.back = back
				continue
			v.erase("fl")
		if v.get("flno", -1.0) > gm.S.t or v.get("rush", false): continue   # rushers just push in
		cand.append([absf(off), signf(off) if off != 0 else 1.0, v])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var left: int = per_side[0]
	var right: int = per_side[1]
	for c in cand:
		if need <= 0: break
		var sd: float = c[1]
		# balance the two sides
		if sd < 0 and left >= side_cap: sd = 1.0
		elif sd > 0 and right >= side_cap: sd = -1.0
		if sd < 0: left += 1
		else: right += 1
		var v: Dictionary = c[2]
		v.fl = {"side": sd, "back": back}
		need -= 1

## A flanker: work out the flanking spot (round to their side of you at their gun's range),
## find cover near it, and go there without shooting. Returns the steer vector, or null once
## they're in position (the cover fight takes over) or have given up.
func sv_flank(v: Dictionary, p: Dictionary, see: bool, d: float, dt: float) -> Variant:
	var fl: Dictionary = v.fl
	if fl.get("in", false):
		# in position: pick a new spot only if you've moved well away from where it was planned
		if Vector2(p.x - fl.ax, p.y - fl.ay).length() < SV_FLANK_MOVE * gm.TS: return null
		fl.erase("in"); fl.erase("cv")
	if not fl.has("cv"):
		var rg := sv_range(v)
		var dir: Vector2 = Vector2(fl.back).rotated(deg_to_rad(SV_FLANK_ANGLE) * float(fl.side))
		var spot := Vector2(p.x, p.y) + dir * (rg.x + rg.y) * 0.5
		var found = sv_find_cover(v, p, spot, SV_FLANK_R, SV_FLANK_PATH)
		if not (found is Dictionary):
			sv_flank_quit(v)
			return null
		fl.cv = found
		fl.ax = p.x; fl.ay = p.y
		fl.t = 0.0
		v.erase("cv")
	fl.t += dt
	if fl.t > SV_FLANK_MAXT or v.hit > 0 or (see and d < SV_FLANK_ENGAGE) or car_unsafe(fl.cv.car) or cover_hazard(fl.cv.x, fl.cv.y):
		sv_flank_quit(v)
		return null
	if Vector2(p.x - fl.ax, p.y - fl.ay).length() > SV_FLANK_MOVE * gm.TS:
		fl.erase("cv")   # you've moved: re-plan next frame
		return Vector2.ZERO
	var cv: Dictionary = fl.cv
	if Vector2(cv.x - v.x, cv.y - v.y).length() < 8.0:
		# there: hand over to the cover fight, ducked down and about to peek
		fl.in = true
		v.cv = cv
		v.cph = 1; v.cpt = 0.0; v.miss = 0; v.flk = 0.0
		v.hide = randf_range(SV_HIDE_MIN * 0.4, SV_HIDE_MIN)
		return null
	var nv := sv_nav(v, cv.x, cv.y)
	if nv.length() > 0: v.ang = atan2(nv.y, nv.x)
	return nv * SV_COVER_SPD

## Stop flanking (and don't get picked for it again for a while); they fight normally.
func sv_flank_quit(v: Dictionary) -> void:
	v.erase("fl")
	v.flno = gm.S.t + SV_FLANK_REST

## Is the survivor's cover still good? Not if their car has started smoking or burning,
## a fire or barrel makes it dangerous, the player has come too close or gone too far,
## they can't get there, or they've been flanked (the player can see or hit them while
## they're ducked down at the spot).
func sv_cover_holds(v: Dictionary, p: Dictionary, see: bool, dt: float) -> bool:
	var cv: Dictionary = v.cv
	if car_unsafe(cv.car) or cover_hazard(cv.x, cv.y): return false
	var dp := Vector2(p.x - cv.x, p.y - cv.y).length()
	if dp < SV_COVER_MIN_D or dp > sv_range(v).y + 160.0: return false
	if v.cph == 0 and v.cpt > SV_COVER_MAXT: return false
	if v.cph == 1 and Vector2(cv.x - v.x, cv.y - v.y).length() < 8.0 and (see or v.hit > 0):
		v.flk += dt
		if v.flk > 0.3 or v.hit > 0: return false
	else:
		v.flk = 0.0
	return true

## Leave cover; look for more no sooner than `wait` seconds from now.
func sv_drop_cover(v: Dictionary, wait: float) -> void:
	v.erase("cv")
	v.cvT = wait

## An alerted survivor fighting from cover: run to it (phase 0), duck down (1), step out
## to the peek spot and shoot, then duck back (2). Returns their steer vector, or null when
## they have no cover (none found, can't see you to look for any, or they just gave up on
## it) and use the open-ground behaviour instead.
func sv_cover_fight(v: Dictionary, p: Dictionary, see: bool, dt: float) -> Variant:
	v.cvT = v.get("cvT", 0.0) - dt
	if v.get("rush", false): return null   # rushers don't bother with cover
	if Vector2(p.x - v.x, p.y - v.y).length() < SV_COVER_MIN_D:   # you're right on them: no time for cover
		if v.has("cv"): sv_drop_cover(v, SV_COVER_RETRY)
		return null
	if v.has("cv") and not sv_cover_holds(v, p, see, dt): sv_drop_cover(v, 0.0)
	if not v.has("cv"):
		if not see or v.cvT > 0: return null
		var found = sv_find_cover(v, p)
		v.cvT = SV_COVER_RETRY
		if not (found is Dictionary): return null
		v.cv = found
		v.cph = 0; v.cpt = 0.0; v.miss = 0; v.flk = 0.0; v.pks = 0
	var cv: Dictionary = v.cv
	v.cpt += dt
	var at_cover := Vector2(cv.x - v.x, cv.y - v.y).length() < 8.0
	if v.cph == 0:   # running to it
		if at_cover:
			v.cph = 1; v.cpt = 0.0
			v.hide = randf_range(SV_HIDE_MIN * 0.4, SV_HIDE_MIN)   # first time in, only a quick breather
			return Vector2.ZERO
		var nv := sv_nav(v, cv.x, cv.y)
		if see:   # snap shots on the way, wild
			v.ang = atan2(p.y - v.y, p.x - v.x)
			if v.cd <= 0: sv_fire(v, SV_SNAP_SPREAD)
		elif nv.length() > 0: v.ang = atan2(nv.y, nv.x)
		return nv * SV_COVER_SPD
	if v.cph == 1:   # ducked down, gun on where they last saw you
		v.ang = atan2(v.lky - v.y, v.lkx - v.x)
		if v.cpt >= v.hide:
			v.cph = 2; v.cpt = 0.0; v.seen = -1.0; v.shots = 0
		return Vector2.ZERO if at_cover else sv_nav(v, cv.x, cv.y)
	# stepping out
	if see:
		if v.seen < 0:   # there you are: a moment to aim, then shoot for a second or two
			v.seen = 0.0
			v.peek = randf_range(SV_PEEK_MIN, SV_PEEK_MAX)
			v.cd = maxf(v.cd, SV_PEEK_AIM)
		v.seen += dt
		v.miss = 0
		v.ang = atan2(p.y - v.y, p.x - v.x)
		if v.cd <= 0:
			sv_fire(v)
			v.shots += 1
		if v.seen >= v.peek and v.shots > 0 and v.burst <= 0:   # finish the burst, then duck back
			v.cph = 1; v.cpt = 0.0
			v.hide = randf_range(SV_HIDE_MIN, SV_HIDE_MAX)
			v.pks = v.get("pks", 0) + 1
			if v.pks >= SV_LEAP_PEEKS:   # move up: cover at least a tile nearer you, if there's any
				var dp := Vector2(p.x - cv.x, p.y - cv.y).length()
				var nc = sv_find_cover(v, p, null, SV_LEAP_R, SV_LEAP_R * 1.6, dp - gm.TS)
				if nc is Dictionary:
					v.cv = nc
					v.cph = 0; v.cpt = 0.0; v.miss = 0; v.flk = 0.0; v.pks = 0
		return Vector2.ZERO   # stand there and shoot, no need to go further out
	if v.seen >= 0 or v.cpt > SV_PEEK_LOOK:
		# lost sight of you mid-peek, or nothing there to shoot at
		if v.seen < 0:
			v.miss += 1
			if v.miss >= SV_PEEK_MISSES:   # you've moved on: go and find you
				sv_drop_cover(v, SV_COVER_RETRY)
				return null
		v.cph = 1; v.cpt = 0.0
		v.hide = randf_range(SV_HIDE_MIN, SV_HIDE_MAX)
		return sv_nav(v, cv.x, cv.y)
	v.ang = atan2(v.lky - v.y, v.lkx - v.x)
	var pk: Vector2 = cv.pk
	if Vector2(pk.x - v.x, pk.y - v.y).length() < 4.0: return Vector2.ZERO
	return sv_nav(v, pk.x, pk.y)

# ======================================================================
# shooting and reinforcements
# ======================================================================
## A survivor fires their gun. Automatics fire short bursts; shotguns fire a spread of
## pellets. Damage per bullet is the normal survivor damage x (gun damage / SV_DMG_REF).
func sv_fire(v: Dictionary, spread: float = 1.0) -> void:
	var w: Dictionary = D.WEAPONS[int(v.get("w", 0))]
	var auto: bool = w.get("auto", false)
	var dmg: float = (8 + gm.S.danger) * gm.DF().dmg * float(w.dmg) / SV_DMG_REF
	var aim: float = v.ang + (randf() - 0.5) * 0.22 * spread * (1.6 if auto and v.burst > 0 else 1.0)
	for k in int(w.pel):
		var a: float = aim + (randf() - 0.5) * float(w.spr) * 2.0
		gm.S.bul.append({"x": v.x + cos(a) * 14, "y": v.y + sin(a) * 14, "vx": cos(a) * w.spd * 0.65, "vy": sin(a) * w.spd * 0.65,
			"life": w.life * 1.6, "dmg": dmg, "pl": false, "kb": 0.0, "bolt": w.bolt})
	gm.sfx("bow" if w.silent else "enemy")
	if not w.silent: gm.add_noise(float(w.noise) * SV_SHOT_NOISE)
	if not w.silent: gm.muzzle_flash(v.x, v.y, aim)
	if auto:
		if v.burst <= 0: v.burst = 3 + randi() % 3
		v.burst -= 1
		if v.burst > 0:
			v.cd = w.rate * 2.0          # next shot in the burst
			return
	v.cd = (0.75 + w.rate) * (1.0 + randf() * 0.6)

## Reinforcement survivor arriving from the edge of the map (noise waves at held strips).
func spawn_edge_sv(n: int = 1) -> void:
	for t2 in 40:
		var side := randi() % 4
		var c: int = 1 if side == 0 else (gm.S.cols - 2 if side == 1 else 1 + int(randf() * (gm.S.cols - 2)))
		var r: int = 1 if side == 2 else (gm.S.ry - 2 if side == 3 else 1 + int(randf() * (gm.S.rows - 2)))
		var x: float = (c + 0.5) * gm.TS
		var y: float = (r + 0.5) * gm.TS
		if gm.solid(x, y) or Vector2(x - gm.S.p.x, y - gm.S.p.y).length() < 380: continue
		# a group of n arriving together and heading for the same rough spot near you
		var lead := new_sv(x, y)
		sv_patrol_init(lead)
		sv_sweep(lead, gm.S.p.x, gm.S.p.y)   # heads for roughly where you are; has to find you
		gm.S.sv.append(lead)
		for k in n - 1:
			for t3 in 12:
				var mx := x + (randf() - 0.5) * 3.0 * gm.TS
				var my := y + (randf() - 0.5) * 3.0 * gm.TS
				if gm.hit_box(mx, my, 10): continue
				var v := new_sv(mx, my)
				sv_patrol_init(v)
				v.trav = true; v.travT = 0.0
				v.sx = lead.sx; v.sy = lead.sy
				if not gm.solid(lead.sx + (mx - x), lead.sy + (my - y)):   # keep a little spacing on arrival
					v.sx = lead.sx + (mx - x); v.sy = lead.sy + (my - y)
				gm.S.sv.append(v)
				break
		return

# ======================================================================
# the rescue survivor (pickup missions)
# ======================================================================
func spawn_npc(s: Dictionary) -> void:
	var c = null
	for k in gm.G.contracts:
		if k.get("type", "") == "rescue" and k.stage == "pickup" and int(k.pickup) == s.id:
			c = k
			break
	if c == null or gm.S == null: return
	var rm = null
	for r in gm.S.rooms:
		if r.kind == c.where:
			rm = r
			break
	if rm == null:
		for r in gm.S.rooms:
			if r.kind == "house":
				rm = r
				break
	if rm == null and gm.S.rooms.size(): rm = gm.S.rooms[gm.S.rooms.size() - 1]
	if rm == null: return
	var x: float = (rm.c + rm.w / 2.0) * gm.TS
	var y: float = (rm.r + rm.h / 2.0) * gm.TS
	var q := 0
	while q < 30 and gm.solid(x, y):
		x = (rm.c + 1.5 + randf() * (rm.w - 3)) * gm.TS
		y = (rm.r + 1.5 + randf() * (rm.h - 3)) * gm.TS
		q += 1
	var where: String = c.where if rm.kind == c.where else "house"
	gm.S.npc = {"x": x, "y": y, "ang": PI / 2, "hp": 60.0, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y), "name": c.who, "where": where, "cid": c.id, "follow": false, "wk": 0.0, "hit": 0.0,
		"w": NPC_GUNS[randi() % NPC_GUNS.size()], "cd": 0.0, "fire_t": -1.0}
	# The building they're hiding in is safe for the mission: nothing spawns in it,
	# zombies can't walk in, and anything already inside is removed.
	gm.S.safe = Rect2(rm.c * gm.TS, rm.r * gm.TS, rm.w * gm.TS, rm.h * gm.TS)
	gm.S.zs = gm.S.zs.filter(func(z): return not gm.in_safe(z.x, z.y))
	gm.S.sv = gm.S.sv.filter(func(v): return not gm.in_safe(v.x, v.y))
	gm.toast_later(0.7, "%s is hiding in %s." % [c.who, D.WHERE[where]], "mag")

## The rescue survivor shoots back: only once they're following you, and only for a
## while after you fire something loud (crossbow shots keep them quiet too).
func npc_fight(n: Dictionary, dt: float) -> void:
	if not n.follow or gm.S.t > float(n.get("fire_t", -1.0)): return
	n.cd = float(n.get("cd", 0.0)) - dt
	var best = null
	var bd := NPC_RANGE
	for e in gm.S.zs + gm.S.sv:
		if e.dead or e.get("dormant", false) or e.get("rise", 0.0) > 0: continue
		var d := Vector2(e.x - n.x, e.y - n.y).length()
		if d < bd and gm.los(n.x, n.y, e.x, e.y):
			bd = d
			best = e
	if best == null: return
	var aim := atan2(best.y - n.y, best.x - n.x)
	n.ang = aim
	if n.cd > 0: return
	var w: Dictionary = D.WEAPONS[int(n.w)]
	var a0: float = aim + (randf() - 0.5) * 0.16
	for k in int(w.pel):
		var a: float = a0 + (randf() - 0.5) * float(w.spr) * 2.0
		gm.S.bul.append({"x": n.x + cos(a) * 14, "y": n.y + sin(a) * 14, "vx": cos(a) * w.spd, "vy": sin(a) * w.spd, "life": w.life,
			"dmg": float(w.dmg) * NPC_DMG, "pl": true, "kb": float(w.kb) * 0.5, "bolt": false})
	gm.sfx(w.snd)
	if not w.silent: gm.muzzle_flash(n.x, n.y, a0)
	gm.add_noise(float(w.noise) * 0.5)
	n.cd = (0.75 + float(w.rate)) * (1.0 + randf() * 0.4)

func npc_hurt(d: float, dir: Vector2 = Vector2.ZERO) -> void:
	var n = gm.S.npc
	if n == null: return
	n.hp -= d
	n.hit = 0.15
	gm.hurt_cry(n)
	gm.blood(n.x, n.y, 2)
	if n.hp > 0: gm.blood_spray(n.x, n.y, dir)
	if n.hp <= 0:
		gm.blood(n.x, n.y, 8)
		gm.stamp_corpse({"x": n.x, "y": n.y, "a": randf() * TAU, "shirt": "#3f7a7a", "skin": "#e0b894"})
		gm.G.contracts = gm.G.contracts.filter(func(k): return k.id != n.cid)
		gm.toast("%s did not make it. The job is gone." % gm.cap(n.name), "bad")
		gm.S.npc = null
		gm.S.safe = null

func upd_npc(dt: float) -> void:
	var n = gm.S.npc
	if n == null: return
	var p: Dictionary = gm.S.p
	var dx: float = p.x - n.x
	var dy: float = p.y - n.y
	var d := Vector2(dx, dy).length()
	if d == 0: d = 1
	n.hit -= dt
	if not n.follow and d < 70:
		n.follow = true
		gm.toast("%s: \"%s\"" % [gm.cap(n.name), D.FOUND[randi() % D.FOUND.size()]], "mag")
		gm.sfx("loot")
	if n.follow and d > 44:
		var vx := dx / d
		var vy := dy / d
		if d > 120 and not gm.los(n.x, n.y, p.x, p.y):
			var fd = gm.flow_dir(n.x, n.y)
			if fd:
				vx = fd.x; vy = fd.y
		var ox: float = n.x
		var oy: float = n.y
		var sp := 175.0 if d > 160 else 140.0
		gm.move_c(n, vx * sp * dt, vy * sp * dt, 9)
		n.wk += Vector2(n.x - ox, n.y - oy).length() * 0.22
		n.ang = atan2(vy, vx)
	npc_fight(n, dt)
	if n.follow and (Vector2(n.x - gm.S.plane.x, n.y - gm.S.plane.y).length() < 160 or (gm.S.nearPlane and d < 120)):
		for c in gm.G.contracts:
			if c.id == n.cid:
				c.stage = "aboard"
				gm.G.nav = int(c.dest)
				gm.toast("%s climbs into the back. Fly them to %s." % [gm.cap(n.name), gm.strip(int(c.dest)).name], "good")
				gm.sfx("cash")
				break
		gm.S.npc = null
		gm.S.safe = null

# ======================================================================
# bombs
# ======================================================================
## The building you're in (any part of its rectangle, doorway included), or null.
func room_at(x: float, y: float) -> Variant:
	var ts: float = gm.TS
	for rm in gm.S.rooms:
		if x > rm.c * ts and x < (rm.c + rm.w) * ts and y > rm.r * ts and y < (rm.r + rm.h) * ts: return rm
	return null

## The door of building rm nearest (x, y): its middle (x, y), which way is in (ix, iy),
## where a bomb thrown in through it lands (tx, ty) and where to throw it from (ox, oy).
func door_near(rm: Dictionary, x: float, y: float) -> Variant:
	var ts: float = gm.TS
	var c0: int = rm.c
	var r0: int = rm.r
	var c1: int = rm.c + rm.w - 1
	var r1: int = rm.r + rm.h - 1
	var cols: int = gm.S.cols
	var best = null
	var bd := INF
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var edge_c := c == c0 or c == c1
			var edge_r := r == r0 or r == r1
			if not (edge_c or edge_r) or (edge_c and edge_r): continue   # perimeter only, skip corners
			if gm.S.g[r * cols + c] != 2: continue   # not an opening
			var dd := Vector2((c + 0.5) * ts - x, (r + 0.5) * ts - y).length_squared()
			if dd < bd:
				bd = dd
				best = Vector2i(c, r)
	if not (best is Vector2i): return null
	# the whole opening: walk along the wall both ways while it stays open
	var horiz: bool = best.y == r0 or best.y == r1
	var along := Vector2i(1, 0) if horiz else Vector2i(0, 1)
	var lo := c0 if horiz else r0
	var hi := c1 if horiz else r1
	var a: Vector2i = best
	var b: Vector2i = best
	while (a - along)[0 if horiz else 1] > lo and gm.S.g[(a - along).y * cols + (a - along).x] == 2: a -= along
	while (b + along)[0 if horiz else 1] < hi and gm.S.g[(b + along).y * cols + (b + along).x] == 2: b += along
	var mx := (a.x + b.x + 1) * 0.5 * ts
	var my := (a.y + b.y + 1) * 0.5 * ts
	var inw := Vector2(0, 1) if best.y == r0 else (Vector2(0, -1) if best.y == r1 else (Vector2(1, 0) if best.x == c0 else Vector2(-1, 0)))
	return {"x": mx, "y": my, "ix": inw.x, "iy": inw.y, "tx": mx + inw.x * SV_BOMB_IN * ts, "ty": my + inw.y * SV_BOMB_IN * ts,
		"ox": mx - inw.x * SV_BOMB_OUT * ts, "oy": my - inw.y * SV_BOMB_OUT * ts, "rm": rm}

## Is there still a bomb throw to spare (SV_BOMB_MAX, then a SV_BOMB_REST pause)? Counts the
## ones already thrown and the carriers already on their way to throw.
func bomb_slot() -> bool:
	if gm.S.t < gm.S.get("svBombT", -1.0): return false   # resting after the last pair
	var n: int = gm.S.get("svBombN", 0)
	for o in gm.S.sv:
		if not o.dead and (o.has("bw") or o.has("bgo")): n += 1
	return n < SV_BOMB_MAX

## Once a frame: resets the per-fight throw count when nobody's after you, and when you go
## into a building mid-fight, each bomb carrier fighting you rolls to throw one in through
## the door you used.
func sv_bomb_watch(p: Dictionary) -> void:
	var any := false
	for v in gm.S.sv:
		if v.dead: continue
		if v.alert: any = true
		else:   # stood down: whatever throw they were set on is off
			v.erase("bgo")
			v.erase("bw")
	if not any: gm.S.svBombN = 0
	var rm = room_at(p.x, p.y)
	var was = gm.S.get("pRoom", null)
	gm.S.pRoom = rm
	if not (rm is Dictionary) or was is Dictionary: return
	if gm.S.t - gm.S.get("svSeenT", -99.0) >= SV_FLANK_SEEN: return   # not in a fight
	if gm.S.noise < SV_BOMB_NOISE: return   # not loud enough yet for bombs
	var dr = door_near(rm, p.x, p.y)
	if not (dr is Dictionary): return
	for v in gm.S.sv:
		if v.dead or not v.get("bomb", false) or not v.alert or not v.get("called", false) or v.has("bw") or v.has("bgo"): continue
		if randf() < SV_BOMB_DOOR and bomb_slot():
			v.bgo = dr.duplicate()
			v.bgo.t = 0.0

## A bomb carrier's throwing: winding up (stands still), heading round to a building's door
## to throw one in, or deciding to lob one at where they last saw you when you've ducked
## behind cover. Returns a steer vector while busy with a throw, otherwise null.
func sv_bomb(v: Dictionary, p: Dictionary, see: bool, dt: float) -> Variant:
	if v.has("bw"):   # winding up
		var w: Dictionary = v.bw
		w.t -= dt
		v.ang = atan2(w.y - v.y, w.x - v.x)
		if w.t <= 0:
			v.erase("bw")
			sv_throw(v, w.x, w.y)
		return Vector2.ZERO
	if not v.get("bomb", false): return null
	if v.has("bgo"):   # throwing one in through the door you went in by
		var g: Dictionary = v.bgo
		g.t += dt
		if not is_same(gm.S.get("pRoom", null), g.rm) or g.t > SV_BOMB_GO:   # you came out, or no way to get a throw in
			v.erase("bgo")
			return null
		var td := Vector2(g.tx - v.x, g.ty - v.y).length()
		if td <= SV_BOMB_RANGE and td >= SV_BOMB_MIN and gm.los(v.x, v.y, g.tx, g.ty):
			v.erase("bgo")
			v.bw = {"x": g.tx, "y": g.ty, "t": SV_BOMB_WIND}
			return Vector2.ZERO
		var nv := sv_nav(v, g.ox, g.oy)
		if nv.length() > 0: v.ang = atan2(nv.y, nv.x)
		return nv * SV_COVER_SPD
	# you ducked behind cover: once each time, a chance they lob it at where they last saw you
	if see:
		v.bht = 0.0
		v.brl = false
		return null
	if v.get("brl", false) or not v.has("lkx") or v.has("fl") or gm.S.get("pRoom", null) is Dictionary: return null
	if gm.S.noise < SV_BOMB_NOISE: return null   # not loud enough yet for bombs
	if v.has("cv") and v.get("cph", 0) == 1: return null   # they're the one ducked down
	if Vector2(p.x - v.lkx, p.y - v.lky).length() > SV_BOMB_HID * gm.TS: return null   # you've moved off
	var ld := Vector2(v.lkx - v.x, v.lky - v.y).length()
	if ld > SV_BOMB_RANGE or ld < SV_BOMB_MIN or not gm.los(v.x, v.y, v.lkx, v.lky): return null
	v.bht = v.get("bht", 0.0) + dt
	if v.bht < SV_BOMB_WAIT: return null
	v.brl = true
	if randf() < SV_BOMB_COVER and bomb_slot():
		v.bw = {"x": v.lkx, "y": v.lky, "t": SV_BOMB_WIND}
		return Vector2.ZERO
	return null

## Lob the bomb at (tx, ty): it arcs over walls and cover, lands there, and goes off
## SV_BOMB_FUSE seconds later (see Game.upd_effects()).
func sv_throw(v: Dictionary, tx: float, ty: float) -> void:
	v.bomb = false
	gm.S.svBombN = gm.S.get("svBombN", 0) + 1
	if gm.S.svBombN >= SV_BOMB_MAX:   # that's the pair: a pause before anyone throws again
		gm.S.svBombN = 0
		gm.S.svBombT = gm.S.t + SV_BOMB_REST
	var a := atan2(ty - v.y, tx - v.x)
	var sx: float = v.x + cos(a) * 14
	var sy: float = v.y + sin(a) * 14
	var l := Vector2(tx - sx, ty - sy).length()
	var ft := 0.35 + l / 700.0   # seconds in the air
	gm.S.thrown.append({"x": sx, "y": sy, "vx": (tx - sx) / ft, "vy": (ty - sy) / ft, "fuse": ft + SV_BOMB_FUSE, "dead": false, "spin": 0.0,
		"air": ft, "air0": ft, "h": clampf(l * 0.22, 18.0, 70.0), "z": 0.0})
	gm.floater(v.x, v.y - 18, "Bomb!", "#ff6a50")
	gm.sfx("swing")

# ======================================================================
# getting clear of blasts
# ======================================================================
## Everything about to go off: lit bombs, burning cars and lit barrels, as {x, y, r, src}.
func blast_dangers() -> Array:
	var out: Array = []
	for b in gm.S.thrown:
		if not b.dead: out.append({"x": b.x, "y": b.y, "r": Blasts.BOMB_BLAST_R, "src": b})
	for car in gm.S.cars:
		if not car.dead and car.fuse >= 0: out.append({"x": car.x, "y": car.y, "r": Blasts.CAR_BLAST_R, "src": car})
	for br in gm.S.barrels:
		if not br.dead and br.fuse >= 0: out.append({"x": br.x, "y": br.y, "r": Blasts.BOMB_BLAST_R, "src": br})
	return out

## Is survivor v in the open inside one of these blasts? After a moment to react they run
## straight out of the nearest one (or round a wall if that's blocked). Returns a steer
## vector while running, otherwise null.
func sv_flee(v: Dictionary, dangers: Array, dt: float) -> Variant:
	var worst = null
	var depth := 0.0
	for dg in dangers:
		var reach: float = dg.r + SV_FLEE_MARGIN
		var dd := Vector2(v.x - dg.x, v.y - dg.y).length()
		if dd >= reach or not gm.blasts.blast_clear(dg.src, v.x, v.y): continue
		if not (worst is Dictionary) or reach - dd > depth:
			worst = dg
			depth = reach - dd
	if not (worst is Dictionary):
		v.erase("flT")
		return null
	if not v.has("flT"): v.flT = randf_range(SV_FLEE_REACT.x, SV_FLEE_REACT.y)
	v.flT -= dt
	if v.flT > 0: return null   # hasn't clocked it yet
	var away := Vector2(v.x - worst.x, v.y - worst.y)
	if away.length() < 1: away = Vector2.RIGHT.rotated(randf() * TAU)
	away = away.normalized()
	var out_r: float = worst.r + SV_FLEE_MARGIN + 16.0
	for deg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var dir := away.rotated(deg_to_rad(deg))
		var tx: float = worst.x + dir.x * out_r
		var ty: float = worst.y + dir.y * out_r
		if gm.walk_clear(v.x, v.y, tx, ty):
			var mv := Vector2(tx - v.x, ty - v.y).normalized()
			v.ang = mv.angle()
			return mv * SV_FLEE_SPD
	var nv := sv_nav(v, worst.x + away.x * out_r, worst.y + away.y * out_r)
	if nv.length() > 0: v.ang = nv.angle()
	return nv * SV_FLEE_SPD

# ======================================================================
# per-frame update
# ======================================================================
## Armed survivors: alarm, flanking, cover, open-ground fighting, searching, patrols.
## (Per-frame survivor update; the behaviour itself is in the functions above.)
func upd_survivors(p: Dictionary, dt: float) -> void:
	if gm.S.get("hostile", false): upd_garrison(dt)
	sv_squad(p, dt)
	sv_bomb_watch(p)
	var dangers := blast_dangers()
	for v in gm.S.sv:
		gm.blasts.blast_dmg_tick(v, dt)
		if v.dead: continue
		if v.alert: v.erase("unarmed")   # alerted: picks up their gun
		var dx: float = p.x - v.x
		var dy: float = p.y - v.y
		var d := Vector2(dx, dy).length()
		if d == 0: d = 1
		var see := d < 520 and gm.los(v.x, v.y, p.x, p.y)
		var fa := absf(U.ang_diff(atan2(dy, dx), float(v.ang)))   # how far off their facing you are
		if v.alert: see = see and (d < SV_SENSE or fa < deg_to_rad(SV_VIEW_HALF_ALERT))
		var spot: bool = see and (v.alert or (d < 420 and (d < SV_SENSE or fa < deg_to_rad(SV_VIEW_HALF))))
		if spot:   # seen: alerted, knows exactly where you are
			sv_hear(v, p.x, p.y)
			gm.S.svSeenT = gm.S.t   # (for the squad: someone has eyes on you)
			if not v.get("called", false):   # first sighting (since they last stood down): raise the alarm
				v.called = true
				sv_raise(v.x, v.y, p.x, p.y)
				v.yell = SV_YELL_MIN + randf() * (SV_YELL_MAX - SV_YELL_MIN)
				v.cd = maxf(v.cd, v.yell)
				# one "Hey!" at a time: after a yell the rest wait SV_YELL_GAP seconds (they still
				# stop and raise the alarm, just silently)
				if gm.S.t >= float(gm.S.get("yellT", -1.0)):
					gm.S.yellT = gm.S.t + randf_range(SV_YELL_GAP.x, SV_YELL_GAP.y)
					gm.sfx("yell", -1.0, v.get("voice", 1.0))
		v.cd -= dt
		v.yell = maxf(0.0, v.get("yell", 0.0) - dt)
		v.hit -= dt
		var vx := 0.0
		var vy := 0.0
		var fv = sv_flee(v, dangers, dt)
		if fv is Vector2:   # something's about to blow: getting clear comes first
			vx = fv.x; vy = fv.y
		elif v.alert:
			var bs = sv_bomb(v, p, see, dt) if v.yell <= 0 else null
			var fls = sv_flank(v, p, see, d, dt) if not (bs is Vector2) and v.yell <= 0 and v.has("fl") else null
			var cvs = null
			if not (bs is Vector2) and not (fls is Vector2) and v.yell <= 0: cvs = sv_cover_fight(v, p, see, dt)
			if bs is Vector2:   # going to throw a bomb, or winding up to
				vx = bs.x; vy = bs.y
			elif fls is Vector2:   # circling round to flank you, holding fire
				vx = fls.x; vy = fls.y
			elif cvs is Vector2:   # fighting from cover
				vx = cvs.x; vy = cvs.y
			elif see and v.yell > 0:
				v.ang = atan2(dy, dx)   # just spotted you: standing and yelling, not shooting yet
			elif see:
				v.ang = atan2(dy, dx)
				# preferred distance depends on the gun: shotguns close in, rifles hang back
				var rg := sv_range(v)
				var near := rg.x
				var far := rg.y
				if v.get("rush", false):   # rushers keep closing in
					near = minf(near, SV_RUSH_NEAR); far = SV_RUSH_NEAR + 20.0
				if d > far:
					vx = dx / d; vy = dy / d
				elif d < near:
					vx = -dx / d; vy = -dy / d
				v.sw -= dt
				if v.sw <= 0:
					v.sw = 1 + randf() * 1.5
					v.sd = 1.0 if randf() < 0.5 else -1.0
				vx += -dy / d * v.sd * 0.7
				vy += dx / d * v.sd * 0.7
				if v.cd <= 0: sv_fire(v)
			else:
				# can't see you: go to where they last saw/heard you, search there, then give up
				if not v.has("lkx"): sv_hear(v, p.x, p.y)   # alerted by a hit: they know where it came from
				v.lost = v.get("lost", 0.0) + dt
				if v.lost > SV_FORGET:
					v.alert = false
					v.called = false
					v.erase("lkx")
					v.srch = false
					v.erase("cv")
					v.erase("fl")
					sv_repost(v, v.x, v.y, SV_SEARCH_R)
				elif not v.get("srch", false) and Vector2(v.lkx - v.x, v.lky - v.y).length() > 24:
					var nv := sv_nav(v, v.lkx, v.lky)
					vx = nv.x; vy = nv.y
					# for a moment after losing sight they keep their gun on where you were,
					# so stepping in and out of view at a doorway doesn't spin them back and forth
					if v.lost < 0.6: v.ang = atan2(v.lky - v.y, v.lkx - v.x)
					elif nv.length() > 0: v.ang = atan2(vy, vx)
				else:
					if not v.get("srch", false):
						v.srch = true
						sv_repost(v, v.lkx, v.lky, SV_SEARCH_R)
					var pv := sv_patrol(v, dt)
					vx = pv.x; vy = pv.y
		elif v.get("trav", false):
			# sweeping out toward where the player was when the alarm went up
			v.travT += dt
			if Vector2(v.sx - v.x, v.sy - v.y).length() < 24 or v.travT > 40.0:
				v.trav = false
				v.erase("tsp")
				sv_repost(v, v.x, v.y, SV_SWEEP_R)
			else:
				var nv := sv_nav(v, v.sx, v.sy) * float(v.get("tsp", SV_SWEEP_SPD))
				vx = nv.x; vy = nv.y
				if nv.length() > 0: v.ang = atan2(vy, vx)
		else:
			var pv := sv_patrol(v, dt)
			vx = pv.x; vy = pv.y
		# keep clear of other survivors and of zombies: the same soft push zombies use
		# on each other (bodies within 20 px steer apart)
		for others in [gm.S.sv, gm.S.zs]:
			for o in others:
				if o == v or o.dead: continue
				var ox2: float = v.x - o.x
				var oy2: float = v.y - o.y
				var dd := ox2 * ox2 + oy2 * oy2
				if dd < 400:
					if dd > 0.01:
						var q := sqrt(dd)
						vx += ox2 / q * 0.8
						vy += oy2 / q * 0.8
					else:   # exactly on top of each other (e.g. two out of the same door)
						vx += randf() - 0.5
						vy += randf() - 0.5
		var own := gm.blasts.knock_tick(v, dt)   # thrown by a blast?
		var vx0: float = v.x
		var vy0: float = v.y
		var spm: float = v.get("spm", 1.0)   # this survivor's own pace
		gm.move_c(v, vx * 85 * spm * dt * own, vy * 85 * spm * dt * own, 10)
		gm.body_block(v, p, vx0, vy0, vx, vy)
		v.wk += Vector2(v.x - vx0, v.y - vy0).length() * 0.22
