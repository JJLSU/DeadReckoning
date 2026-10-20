class_name Survivors
## Armed survivors: garrisons at survivor-held strips, patrols, alarms, cover, flanking,
## their guns, and the rescue survivor on pickup missions. Split out of game.gd; the
## per-frame survivor update is upd_survivors().

# Survivor-held strips (see World.HOSTILE_CHANCE)
const GARRISON_MIN := 11       # total armed survivors at one of these strips...
const GARRISON_MAX := 18
const GARRISON_OUT_MIN := 6    # ...of which this many start outside; the rest wait in buildings
const GARRISON_OUT_MAX := 9
const GARRISON_SPREAD_TRIES := 24   # candidate spots per outside patrol group (more = more even)
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
# after a reaction time of SV_FLEE_REACT seconds and runs at SV_FLEE_SPD for a refuge: a spot
# with a wall between them and the blast at least SV_REFUGE_MIN x its radius from it, or failing
# that one clear of the radius. There they wait until it has gone off.
# Under fire (sv_near_miss(), sv_dodge()): in a fight, your bullets passing within SV_SUP_R px of
# a survivor (or hitting them) spook them: after a SV_SUP_WAIT beat, for SV_SUP_T s they get out of the line of fire,
# sideways away from where it passed, at SV_SUP_SPD, loosing off wild snap shots if they can see
# you. Only those with no cover dodge: in cover or heading for it (a wall or smoke) they hold or
# keep going, peekers ducking back in.
const SV_SUP_R := 48.0   # 1.5 tiles (Greg)
const SV_SUP_T := Vector2(0.5, 1.3)   # how long a dodge keeps them moving (Greg: back up from 0.2-0.3 now only the uncovered dodge)
const SV_SUP_NODG := 1.5       # driven out of cover (flanked), they don't dodge for this long while they find more
const SV_SUP_SPD := 1.3
# Driven back into the same cover SV_DUCK_MAX times by your fire while peeking, a survivor gives
# it up for different cover (if there's any), and won't pick a spot within SV_DUCK_AVOID_R px of
# it again for SV_DUCK_AVOID_T s.
const SV_DUCK_MAX := 3
const SV_DUCK_AVOID_R := 48.0
const SV_DUCK_AVOID_T := 10.0
const SV_SUP_WAIT := Vector2(0.3, 0.6)   # a beat before each dodge: they don't react instantly (Greg)
const SV_FLEE_MARGIN := 24.0
# Survivors walking at one another steer round each other (sv_avoid()): anyone within
# SV_AVOID_R px ahead and SV_AVOID_W px either side of their path.
const SV_AVOID_R := 56.0
const SV_AVOID_W := 22.0
const SV_AVOID_K := 1.5
const SV_FLEE_REACT := Vector2(0.25, 0.7)
const SV_FLEE_SPD := 1.25
const SV_CAR_NOTICE := 0.6    # chance a survivor in reach notices a burning car is about to blow, x their iq (Greg)
const SV_CAR_NOTICE_T := 1.0  # ...re-rolled this often while they haven't (Greg)
const SV_REFUGE_MIN := 0.8       # shielded refuge at least this fraction of the blast radius from it
const SV_REFUGE_OPEN_PEN := 96.0 # a refuge in the open (clear of the radius, no wall) scored as if this many px further
const SV_REFUGE_SEARCH := 3      # look this many tiles past the blast's reach round the survivor
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
const SV_SPOT_R := 420.0
# Looking through a window (tile 15), a survivor sees only SV_WINDOW_SIGHT tiles past it.
const SV_WINDOW_SIGHT := 3.0
# Each survivor has an intelligence stat v.iq from SV_IQ (picked when they spawn). Unalerted, their
# spotting range, SV_SENSE and view cone are scaled by it; their reaction time to a lit blast is
# divided by it; and their chance to look for cover each time is SV_COVER_SEEK x iq (capped at 1).
const SV_IQ := Vector2(0.75, 1.25)
const SV_COVER_SEEK := 0.8
# Names, and reacting to a friend's death (sv_mourn()): of those who see a survivor die, only the
# SV_MOURN_MAX closest may cry out "No!" with the dead man's name popping up over them,
# SV_MOURN_ALERT of the time mid-fight, SV_MOURN_CALM if they weren't alerted, and only if they're
# on your screen (nobody cries out off screen). They turn to the body straight away (at
# SV_WHIP_SPD) and stand stunned; the first cries out at once, the others SV_MOURN_STAGGER s
# apart, each staying frozen SV_MOURN_STUN s after their cry.
# Bodies (S.svBodies) stay where they fell. An unalerted survivor who sees one within SV_EXAM_R
# tiles always goes over to look (sv_exam()): cries out "No!" and the name on reaching it, a moment
# later asks one of SV_EXAM_LINES, then patrols round it. Unalerted witnesses of the death that
# close go over too, without crying out again (or at all, if it wasn't their place to).
const SV_NAMES := ["Jack", "Jake", "John", "Joe", "Jim", "Jeff", "Tom", "Tim", "Ted", "Bob", "Bill", "Ben", "Dan", "Dave",
	"Don", "Doug", "Frank", "Fred", "Hank", "Mike", "Mark", "Matt", "Nick", "Pete", "Paul", "Ray", "Rick", "Sam", "Steve", "Walt"]
const SV_MOURN_ALERT := 0.15
const SV_MOURN_CALM := 0.75
const SV_MOURN_MAX := 3
const SV_MOURN_STUN := 1.0
const SV_MOURN_STAGGER := Vector2(0.12, 0.3)
const SV_EXAM_R := 6.0          # tiles: an unalerted survivor who sees a body this close goes to look
const SV_EXAM_NEAR := 30.0      # px from the body where they stop
const SV_EXAM_SPD := 0.7        # walking over, fraction of 85 px/s
const SV_EXAM_WALK := 10.0      # give up walking over after this many seconds
const SV_EXAM_CRY := 0.4        # seconds at the body before crying out
const SV_EXAM_ASK := Vector2(1.2, 1.8)   # then this long before asking...
const SV_EXAM_LINES := ["What happened here?", "Who did this?"]
const SV_EXAM_DONE := 1.5       # ...and this long standing there before they patrol
const SV_EXAM_PATROL := 4.0     # patrol radius round the body afterwards, tiles
const SV_COVER_SKIP_T := Vector2(2.0, 4.0)
# Smoke grenades (upd_smoke(), sv_smoke_throw()): SV_SMOKE_CHANCE of survivors carry one. In a fight
# with no cover close by they lob it toward you, between you and them: SV_SMOKE_FRAC of the way
# (SV_SMOKE_THROW px min to max), never so far its cloud would reach you. It lands and blooms
# into a cloud of radius SV_SMOKE_R over SV_SMOKE_BLOOM s that stays thick, then thins out and spreads from
# SV_SMOKE_THIN of the way through its SV_SMOKE_LIFE s until it's gone. Thick enough smoke
# (density over SV_SMOKE_SIGHT) blocks sight both ways and hides whoever's in it; survivors use
# it as cover (lying low in it, then firing out of it without stepping out) while it's still
# thicker than SV_SMOKE_HOLD. Other carriers who see a smoke thrown may add theirs to either side
# of it (sv_smoke_join()), never more than SV_SMOKE_MAX out at once.
const SV_SMOKE_CHANCE := 0.35
const SV_SMOKE_THROW := Vector2(80.0, 220.0)   # shortest and longest throw, px
const SV_SMOKE_FRAC := 0.5      # fraction of the way to you they aim for
const SV_SMOKE_R := 72.0
const SV_SMOKE_BLOOM := 1.5
const SV_SMOKE_LIFE := 20.0
const SV_SMOKE_THIN := 0.55
const SV_SMOKE_SIGHT := 0.35
const SV_SMOKE_HOLD := 0.6
const SV_SMOKE_JOIN := 0.6     # chance a smoke carrier who sees a friend throw smoke throws theirs alongside...
const SV_SMOKE_GAP := 0.8      # ...this many cloud diameters to one side of the first, widening the screen
const SV_SMOKE_REACT := Vector2(0.2, 0.6)   # seconds before they start winding up
const SV_SMOKE_MAX := 3        # most smokes out at once (clouds, in the air, or being wound up)
const SV_SMOKE_BLIND := 2.0     # firing out of smoke at where they last saw or heard you: this many times their usual spread
const SV_SMOKE_PEN := 24.0   # smoke scored as if this many px further than a wall   # didn't think of cover: fight in the open this long before the next chance
const SV_ALARM_R := 500.0      # a survivor spotting you sends everyone within this many px (of them) searching
const SV_SWEEP_SPREAD := 6.0   # how far off your actual position they aim, tiles
const SV_SWEEP_SPD := 0.8     # sweep speed, fraction of 85 px/s
const SV_SWEEP_R := 7.0        # patrol radius once they get there, tiles
# On first spotting you (since they last stood down) a survivor stops, turns on you and
# yells before opening fire. The yell itself adds nothing to the noise meter.
const SV_YELL_MIN := 0.7       # seconds between the yell and their first shot
const SV_YELL_MAX := 1.0
# Reacting to spotting you: a startled hop (SV_STARTLE_T s, drawn as a little jump), a fast but
# visible turn to face you while they yell (SV_WHIP_SPD rad/s), and the gun, carried lowered
# across the body while unalerted, coming up to aim over SV_RAISE_T s (lowered again over
# SV_LOWER_T s once they stand down). v.gup: 0 lowered, 1 aiming.
const SV_STARTLE_T := 0.25
const SV_WHIP_SPD := 14.0
const SV_RAISE_T := 0.35
const SV_LOWER_T := 1.2
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
const SV_PEEK_MISSES := 3       # ...and after this many misses in a row they leave cover to hunt for you
const SV_COVER_CAR_PEN := 64.0  # an intact car is worse cover than a wall: scored as if this many px further away
const SV_COVER_BARREL := 110.0  # won't take cover within this many px of a red barrel
const SV_COVER_FAR_PREF := 1.0   # lever rifle and crossbow: prefer cover at the far end of their range, weighted this much (others 0.5, mid-range)
const SV_SNAP_SPREAD := 3.5     # running to cover they fire snap shots, this many times their usual spread
const SV_LEAP_PEEKS := 3        # after this many peeks with shots they move up to cover closer to you...
const SV_LEAP_R := 4.0          # ...looking this many tiles round them, at least a tile nearer you (never inside their gun's near range)
const SV_RANGE_K := 1.25        # scales every gun's preferred fighting distance (sv_range())
const SV_RANGE_CAP := 440.0     # ...but nobody wants to be further than this (they see 520)
const SV_RUSH_CHANCE := 0.2     # rushers never take cover or flank: they push in on you firing
const SV_STRAFE := 0.35        # sideways speed strafing round you in the open, fraction of 85 px/s (was 0.7)
const SV_STRAFE_PAUSE := Vector2(0.5, 1.5)   # standing still (still shooting) between strafes, seconds
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
const SV_FLANK_CALL_GAP := Vector2(3.0, 6.0)   # a new flanker calls out "Flanking!"; nobody else does for this long
const SV_FLANK_REST := 8.0       # after giving up, not picked to flank again for this many seconds
# Armed survivors' guns. Chance of each weapon ~ exp(-price / (SV_GUN_BASE + SV_GUN_STEP x danger)):
# cheaper guns are always more common (scarcity), but dearer ones show up more where danger is high.
const SV_GUN_BASE := 300.0
const SV_GUN_STEP := 250.0
const SV_AUTO_MULT := 3.0     # automatics (SMG, assault rifle) this many times as common as the price curve gives (Greg)
const SV_AR_MULT := 3.0       # ...and of those, assault rifles weighted up this much against SMGs (Greg)
const SV_BURST := Vector2i(6, 9)   # rounds per automatic burst (was 3-5; Greg)
const SV_DMG_REF := 30.0
# Reloading (Greg 2026-10-20): survivors' guns hold D.WEAPONS "mag" rounds (v.mag) and take "rl"
# seconds to reload, like yours (spare ammo unlimited). Empty, they reload: peekers duck back,
# anyone without cover runs for some first. SV_RELOAD_CALL of the time they shout "Reloading!"
# (speech bubble only). Ducked in cover with under SV_RELOAD_TOPUP of a mag, they top up.
const SV_RELOAD_CALL := 0.5
const SV_ATK_MEM := 8.0   # s: whoever hurt a survivor stays their target this long (Greg 2026-10-20)
const SV_RELOAD_TOPUP := 0.5
# Settled aim (Greg 2026-10-13): after standing still SV_SETTLE_T s a survivor's aim wobble (and
# a single-bullet gun's spread) is down to SV_SETTLE_ACC of normal, easing in. Snap shots aren't.
const SV_SETTLE_T := 0.8
const SV_SETTLE_ACC := 0.4
# Leading you (Greg 2026-10-13): shooting at you while you move, they aim where you'll be;
# the share of the lead they get is SV_LEAD_K x iq (0.6-1.0) +- SV_LEAD_ERR / iq.
const SV_LEAD_K := 0.8
const SV_LEAD_ERR := 0.2
const SV_LEAD_CONE := 0.35   # radians: only when they're facing you about this closely
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
	var at := 0.0   # the automatics' share
	for w in D.WEAPONS:
		var x := exp(-float(w.price) / sc)
		ws.append(x)
		tot += x
		if w.get("auto", false): at += x
	# automatics: SV_AUTO_MULT x their price-based odds; then a pick among them (assault
	# rifles weighted up by SV_AR_MULT) or among the rest as before
	var auto := randf() < minf(0.9, at / tot * SV_AUTO_MULT)
	var sub := 0.0
	for i in ws.size():
		if D.WEAPONS[i].get("auto", false) != auto: ws[i] = 0.0
		elif D.WEAPONS[i].name == "Assault rifle": ws[i] *= SV_AR_MULT
		sub += ws[i]
	var r := randf() * sub
	for i in ws.size():
		if ws[i] <= 0.0: continue
		r -= ws[i]
		if r <= 0: return i
	return 0

## A name for a new survivor, one nobody else on this strip has if possible.
func sv_name() -> String:
	var used := {}
	if gm.S:
		for o in gm.S.get("sv", []): used[o.get("name", "")] = true
	var avail: Array = SV_NAMES.filter(func(nm): return not used.has(nm))
	if avail.is_empty(): avail = SV_NAMES
	return avail[randi() % avail.size()]

## Is (x1, y1) close enough to the last window the sightline from (x0, y0) crosses?
## True when the line crosses no window at all.
func window_sight_ok(x0: float, y0: float, x1: float, y1: float) -> bool:
	var S = gm.S
	var d := Vector2(x1 - x0, y1 - y0).length()
	var n := int(ceil(d / 8.0))
	var wc := -1
	var wr := -1
	for i in range(1, n):
		var t := float(i) / n
		var c := int(floor((x0 + (x1 - x0) * t) / gm.TS))
		var r := int(floor((y0 + (y1 - y0) * t) / gm.TS))
		if c >= 0 and r >= 0 and c < S.cols and r < S.rows and S.g[r * S.cols + c] == 15: wc = c; wr = r
	if wc < 0: return true
	return Vector2(x1 - (wc + 0.5) * gm.TS, y1 - (wr + 0.5) * gm.TS).length() <= (SV_WINDOW_SIGHT + 0.5) * gm.TS

## Would survivor v see something happen at (x, y)? Same rules as spotting you.
func sv_sees(v: Dictionary, x: float, y: float) -> bool:
	var d := Vector2(x - v.x, y - v.y).length()
	if d >= 520 or not gm.los(v.x, v.y, x, y) or not window_sight_ok(v.x, v.y, x, y): return false
	var fa := absf(U.ang_diff(atan2(y - v.y, x - v.x), float(v.ang)))
	if v.alert: return d < SV_SENSE or fa < deg_to_rad(SV_VIEW_HALF_ALERT)
	var iq: float = v.get("iq", 1.0)
	return d < SV_SPOT_R * iq and (d < SV_SENSE * iq or fa < deg_to_rad(SV_VIEW_HALF * iq))

## Survivor `dead` has just been killed: their body is left for others to find, and some of
## those who saw it cry out.
func sv_mourn(dead: Dictionary) -> void:
	if gm.S == null or not dead.has("name"): return
	gm.S.svBodyN = int(gm.S.get("svBodyN", 0)) + 1
	var bd := {"id": gm.S.svBodyN, "x": dead.x, "y": dead.y, "name": String(dead.name)}
	if not gm.S.has("svBodies"): gm.S.svBodies = []
	gm.S.svBodies.append(bd)
	var ws: Array = []
	for v in gm.S.sv:
		if v.dead or is_same(v, dead): continue
		if sv_sees(v, dead.x, dead.y): ws.append(v)
	# closest first: only the nearest SV_MOURN_MAX may cry out
	ws.sort_custom(func(a, b): return Vector2(a.x - dead.x, a.y - dead.y).length_squared() < Vector2(b.x - dead.x, b.y - dead.y).length_squared())
	var at := 0.0
	var first := true
	for i in ws.size():
		var v: Dictionary = ws[i]
		sv_know_body(v, bd)
		if i < SV_MOURN_MAX and on_screen(v.x, v.y) and randf() < (SV_MOURN_ALERT if v.alert else SV_MOURN_CALM):
			# frozen, turning to the body, until SV_MOURN_STUN after their cry
			v.mourn = {"name": String(dead.name), "t": at, "x": dead.x, "y": dead.y}
			v.mst = at + SV_MOURN_STUN
			if first: sv_mourn_tick(v, 0.0)   # the first cries out at once
			first = false
			at += randf_range(SV_MOURN_STAGGER.x, SV_MOURN_STAGGER.y)
		if not v.alert and Vector2(v.x - dead.x, v.y - dead.y).length() <= SV_EXAM_R * gm.TS:
			sv_exam_start(v, bd, true)   # then over to look (no second cry)

## A witness frozen by a friend's death: turns to face the body, and cries out "No!" in their
## own voice (quieter further from you) when their turn comes, the name popping up over them.
func sv_mourn_tick(v: Dictionary, dt: float) -> void:
	var m: Dictionary = v.mourn
	v.ang = rotate_toward(float(v.ang), atan2(m.y - v.y, m.x - v.x), SV_WHIP_SPD * dt)
	if m.t < 0: return   # already cried out
	m.t -= dt
	if m.t > 0: return
	m.t = -1.0
	sv_say(v, String(m.name) + "!", "no")

## Survivor v says something over their head, out loud in their own voice if `snd` names a synth
## voice sound ("no", "yep"; quieter further from you). Only if they're on your screen: nobody
## calls out off it.
func sv_say(v: Dictionary, text: String, snd: String = "") -> void:
	if not on_screen(v.x, v.y): return
	if snd != "":
		var d := Vector2(v.x - gm.S.p.x, v.y - gm.S.p.y).length()
		gm.sfx(snd, 0.14 * (1.0 - 0.6 * minf(1.0, d / 900.0)), v.get("voice", 1.0))
	gm.floater(v.x, v.y - 26, text, "#e8d8b0", true)   # over the speaker's head

## Is (x, y) inside the screen?
func on_screen(x: float, y: float) -> bool:
	var gs: float = gm.ground_scale()
	return absf(x - float(gm.S.get("cx", gm.S.p.x))) < gm.Wv * 0.5 / gs and absf(y - float(gm.S.get("cy", gm.S.p.y))) < gm.Hv * 0.5 / gs

## Survivor v now knows about body bd (won't go and look at it again).
func sv_know_body(v: Dictionary, bd: Dictionary) -> void:
	if not v.has("kd"): v.kd = []
	if not v.kd.has(bd.id): v.kd.append(bd.id)

## Unalerted v looks for bodies they haven't seen yet within SV_EXAM_R tiles; one they spot,
## they go and look at.
func sv_find_body(v: Dictionary) -> void:
	for bd in gm.S.get("svBodies", []):
		if v.get("kd", []).has(bd.id): continue
		if Vector2(bd.x - v.x, bd.y - v.y).length() > SV_EXAM_R * gm.TS or not sv_sees(v, bd.x, bd.y): continue
		sv_know_body(v, bd)
		sv_exam_start(v, bd, false)
		return

## v heads over to look at body bd. `quiet`: they've cried out already (or weren't to).
func sv_exam_start(v: Dictionary, bd: Dictionary, quiet: bool) -> void:
	v.exam = {"x": bd.x, "y": bd.y, "name": bd.name, "ph": 0, "t": SV_EXAM_WALK, "quiet": quiet}

## Looking at a body: walk over, cry out its name, ask what happened, then patrol round it.
## Returns the steer vector.
func sv_exam(v: Dictionary, dt: float) -> Vector2:
	var e: Dictionary = v.exam
	var to := Vector2(e.x - v.x, e.y - v.y)
	if e.ph == 0:   # walking over
		e.t -= dt
		if to.length() > SV_EXAM_NEAR and e.t > 0:
			var nv := sv_nav(v, e.x, e.y) * SV_EXAM_SPD
			if nv.length() > 0: v.ang = atan2(nv.y, nv.x)
			return nv
		e.ph = 1; e.t = SV_EXAM_CRY
	v.ang = rotate_toward(float(v.ang), to.angle(), SV_WHIP_SPD * 0.3 * dt)   # looking down at it
	e.t -= dt
	if e.t > 0: return Vector2.ZERO
	if e.ph == 1:
		if not e.quiet: sv_say(v, String(e.name) + "!", "no")
		e.ph = 2; e.t = randf_range(SV_EXAM_ASK.x, SV_EXAM_ASK.y)
	elif e.ph == 2:
		sv_say(v, String(SV_EXAM_LINES[randi() % SV_EXAM_LINES.size()]))
		e.ph = 3; e.t = SV_EXAM_DONE
	else:
		v.erase("exam")
		if not v.has("rm"): sv_repost(v, e.x, e.y, SV_EXAM_PATROL)   # (indoor ones go back to their room)
	return Vector2.ZERO

## One armed survivor.
func new_sv(x: float, y: float) -> Dictionary:
	var dg: int = int(gm.S.danger) if gm.S else 1
	var arm: float = SV_ARMOR if randf() < float(SV_ARMOR_CHANCE[clampi(dg, 0, SV_ARMOR_CHANCE.size() - 1)]) else 0.0
	var bomb := dg >= 2 and randf() < SV_BOMB_BASE + SV_BOMB_STEP * (dg - 2)
	return {"x": x, "y": y, "w": pick_sv_weapon(dg), "burst": 0, "armor": arm, "shirt": ["#5a5f3a", "#4a3a2a", "#3f4f5f"][randi() % 3], "skin": D.sv_skin(),
		"cap": "#3a3226" if randf() < 0.5 else "", "bomb": bomb, "smk": randf() < SV_SMOKE_CHANCE, "name": sv_name(), "iq": randf_range(SV_IQ.x, SV_IQ.y), "rush": randf() < SV_RUSH_CHANCE, "spm": randf_range(SV_SPD_VAR.x, SV_SPD_VAR.y), "wk": 0.0, "hp": 70.0, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y), "cd": 1 + randf(), "ang": 0.0, "alert": false, "hit": 0.0, "sw": 0.0, "sd": 1.0, "dead": false}

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
	v.erase("exam")
	v.lkx = x; v.lky = y
	v.lost = 0.0
	v.srch = false
	v.trav = false

## One of your bullets is at (bx, by) moving (bvx, bvy): survivors in a fight close enough to
## feel it are spooked (see SV_SUP_R).
func sv_near_miss(bx: float, by: float, bvx: float, bvy: float) -> void:
	for v in gm.S.sv:
		if not v.dead and v.alert and Vector2(v.x - bx, v.y - by).length() < SV_SUP_R:
			sv_suppress(v, bx, by, bvx, bvy)

## Survivor v has had your fire pass at (bx, by) moving (bvx, bvy), or been hit by it.
func sv_suppress(v: Dictionary, bx: float, by: float, bvx: float, bvy: float) -> void:
	if v.dead or not v.alert: return
	if v.has("cv"):   # in cover or on their way to it (a wall or smoke): they don't dodge
		if v.cph == 2:   # peeking out: duck straight back in
			v.cph = 1; v.cpt = 0.0
			v.hide = randf_range(SV_HIDE_MIN, SV_HIDE_MAX)
			var cv: Dictionary = v.cv
			cv.dk = int(cv.get("dk", 0)) + 1
			if cv.dk >= SV_DUCK_MAX:   # pinned here: somewhere else
				v.cvBad = {"x": cv.x, "y": cv.y, "t": gm.S.t + SV_DUCK_AVOID_T}
				var nc = sv_find_cover(v, v.get("tgt", gm.S.p))
				if nc is Dictionary:
					v.cv = nc
					v.cph = 0; v.cpt = 0.0; v.miss = 0; v.flk = 0.0; v.pks = 0
		return
	if gm.S.t < float(v.get("nodg", -1.0)): return   # just driven out of cover: off to find more, not dodging
	if v.has("sup") or v.has("supW"): return   # mid-dodge (it's short, it isn't stretched) or about to
	v.supW = {"t": randf_range(SV_SUP_WAIT.x, SV_SUP_WAIT.y), "bx": bx, "by": by, "bvx": bvx, "bvy": bvy}

## Ticks a dodge survivor v is about to make (v.supW); when the beat is up they go, unless
## they've since got cover or calmed down.
func sv_dodge_wait(v: Dictionary, dt: float) -> void:
	var w: Dictionary = v.supW
	w.t -= dt
	if w.t > 0: return
	v.erase("supW")
	if v.dead or not v.alert or v.has("cv") or v.has("sup") or gm.S.t < float(v.get("nodg", -1.0)): return
	# out of the line of fire: sideways off the bullet's track, on their side of it
	var u := Vector2(w.bvx, w.bvy).normalized()
	var off := Vector2(v.x - w.bx, v.y - w.by)
	off -= u * off.dot(u)
	var dir := off.normalized() if off.length() > 2.0 else Vector2(-u.y, u.x) * (1.0 if randf() < 0.5 else -1.0)
	v.sup = {"dx": dir.x, "dy": dir.y, "t": randf_range(SV_SUP_T.x, SV_SUP_T.y), "age": 0.0, "flip": false}

## Spooked by your fire: getting out of its way. Returns the steer vector while it lasts, else null.
func sv_dodge(v: Dictionary, p: Dictionary, see: bool, dt: float) -> Variant:
	if not v.has("sup"): return null
	var s: Dictionary = v.sup
	s.t -= dt
	s.age += dt
	if s.t <= 0 or v.has("cv"):   # over, or they've got cover to go to
		v.erase("sup")
		return null
	var dir := Vector2(s.dx, s.dy)
	if dir.length() > 0 and not gm.walk_clear(v.x, v.y, v.x + dir.x * 20.0, v.y + dir.y * 20.0):
		# wall that way: the other side of the line (only once), else just hunker where they are
		dir = -dir if not s.flip and gm.walk_clear(v.x, v.y, v.x - dir.x * 20.0, v.y - dir.y * 20.0) else Vector2.ZERO
		s.flip = true
		s.dx = dir.x; s.dy = dir.y
	if see:   # wild shots back as they go
		v.ang = atan2(p.y - v.y, p.x - v.x)
		if v.cd <= 0: sv_fire(v, SV_SNAP_SPREAD)
	elif dir.length() > 0: v.ang = dir.angle()
	return dir * SV_SUP_SPD

## Survivor v about to move along (vx, vy): if another survivor stands in the way within
## SV_AVOID_R px ahead, veer off to the side they're not on (the right if dead ahead, so two
## walking at each other both pass on the right), more sharply the closer they are. Speed kept.
func sv_avoid(v: Dictionary, vx: float, vy: float) -> Vector2:
	var vel := Vector2(vx, vy)
	var spd := vel.length()
	if spd < 0.05: return vel
	var dir := vel / spd
	var side := Vector2(-dir.y, dir.x)   # to their right
	var steer := Vector2.ZERO
	for o in gm.S.sv:
		if o == v or o.dead: continue
		var rel := Vector2(o.x - v.x, o.y - v.y)
		var ahead := rel.dot(dir)
		if ahead <= 0 or ahead > SV_AVOID_R: continue
		var lat := rel.dot(side)
		if absf(lat) > SV_AVOID_W: continue
		var away := -1.0 if lat > 2.0 else 1.0   # they're to the right: go left; else right
		steer += side * away * (1.0 - ahead / SV_AVOID_R) * (1.0 - absf(lat) / SV_AVOID_W)
	if steer == Vector2.ZERO: return vel
	var nd := (dir + steer * SV_AVOID_K).normalized()
	if not gm.walk_clear(v.x, v.y, v.x + nd.x * 20.0, v.y + nd.y * 20.0): return vel   # wall there: just push past
	return nd * spd

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

## Is (x, y) inside one of the site's buildings?
func _in_room(site: Dictionary, x: float, y: float) -> bool:
	var ts: float = gm.TS
	for rm in site.rooms:
		if x > rm.c * ts and x < (rm.c + rm.w) * ts and y > rm.r * ts and y < (rm.r + rm.h) * ts: return true
	return false

## The outside patrols: groups of one or two, spread evenly over the whole map (each group's
## spot is the best of GARRISON_SPREAD_TRIES random ones, farthest from the groups already out).
## A pair starts a tile or two apart and paces about the same post.
func _spawn_patrols(site: Dictionary, n: int) -> void:
	var posts: Array = []
	var ts: float = gm.TS
	while n > 0:
		var size := 2 if n >= 2 and randf() < 0.5 else 1
		var best = null
		var best_d := -1.0
		for t in GARRISON_SPREAD_TRIES:
			var x: float = (2.0 + randf() * (site.cols - 4)) * ts
			var y: float = (2.0 + randf() * (site.rows - 4)) * ts
			if not _garrison_spot_ok(site, x, y) or _in_room(site, x, y): continue
			var md := INF
			for q in posts: md = minf(md, Vector2(x - q.x, y - q.y).length())
			if md > best_d: best_d = md; best = Vector2(x, y)
		if not (best is Vector2): break   # nowhere left to stand
		var bp: Vector2 = best
		posts.append(bp)
		var lead := new_sv(bp.x, bp.y)
		sv_patrol_init(lead)
		site.sv.append(lead)
		n -= 1
		if size == 2:
			for t in 20:   # their mate, a tile or two off where they can see each other
				var a := randf() * TAU
				var r := (1.0 + randf()) * ts
				var x := bp.x + cos(a) * r
				var y := bp.y + sin(a) * r
				if not _garrison_spot_ok(site, x, y) or _in_room(site, x, y) or not gm.los(bp.x, bp.y, x, y): continue
				var mate := new_sv(x, y)
				mate.hx = bp.x; mate.hy = bp.y   # same post
				sv_patrol_init(mate)
				mate.pr = lead.pr
				site.sv.append(mate)
				n -= 1
				break

## Garrison for a survivor-held strip: patrols of one or two spread over the map outside, the
## rest inside the buildings (see upd_garrison() and call_out() for how they come out).
func spawn_garrison(site: Dictionary) -> void:
	var total := GARRISON_MIN + randi() % (GARRISON_MAX - GARRISON_MIN + 1)
	var outside := mini(total, GARRISON_OUT_MIN + randi() % (GARRISON_OUT_MAX - GARRISON_OUT_MIN + 1))
	var rooms: Array = site.rooms
	_spawn_patrols(site, outside if rooms.size() else total)
	if rooms.is_empty(): return
	for i in total - outside:
		for t in 40:
			var x: float
			var y: float
			var rm = null
			# somewhere on the floor inside a building
			rm = rooms[randi() % rooms.size()]
			x = (rm.c + 1.5 + randf() * (rm.w - 3)) * gm.TS
			y = (rm.r + 1.5 + randf() * (rm.h - 3)) * gm.TS
			if gm.hit_box(x, y, 10): continue
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
## shotguns close in, rifles hang back. All scaled by SV_RANGE_K, far end capped at SV_RANGE_CAP.
func sv_range(v: Dictionary) -> Vector2:
	var w: Dictionary = D.WEAPONS[int(v.get("w", 0))]
	var rg := Vector2(180, 300)
	if w.pel > 1: rg = Vector2(110, 200)
	elif w.spr < 0.02: rg = Vector2(260, 380)
	rg *= SV_RANGE_K
	return Vector2(minf(rg.x, SV_RANGE_CAP - 60.0), minf(rg.y, SV_RANGE_CAP))

## Lever rifle or crossbow (the accurate long guns).
func long_gun(v: Dictionary) -> bool:
	return float(D.WEAPONS[int(v.get("w", 0))].spr) < 0.02

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
	var pw := 0.5
	if long_gun(v):   # lever rifle, crossbow: hang back
		pref = rg.y; pw = SV_COVER_FAR_PREF
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
			if gm.hit_box(x, y, 10) or cover_hazard(x, y) or sv_cover_given_up(v, x, y): continue
			var car = gm.blasts.car_at(bx, by)
			if car_unsafe(car): continue
			if sv_cover_taken(v, x, y): continue
			var pk = sv_peek_spot(x, y, p, n)
			if not (pk is Vector2): continue
			var sc := dv + absf(dp - pref) * pw + (SV_COVER_CAR_PEN if car is Dictionary and not car.dead else 0.0)
			cands.append([sc, x, y, pk, car, null])
	# smoke clouds: a spot inside to shoot out of (pk, at the edge facing you, just has to see you)
	for cl in gm.S.get("clouds", []):
		if cl.den < SV_SMOKE_HOLD or cl.age > SV_SMOKE_LIFE * SV_SMOKE_THIN: continue
		var cc := Vector2(cl.x, cl.y)
		var cr: float = cl.r
		for t2 in 4:
			var q := cc + Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)) * cr
			var dv := q.distance_to(ctr)
			if dv > rad * gm.TS: continue
			var dp := q.distance_to(Vector2(p.x, p.y))
			if dp < SV_COVER_MIN_D or dp > rg.y + 60.0 or dp >= closer_than: continue
			if gm.solid(q.x, q.y) or gm.hit_box(q.x, q.y, 10) or cover_hazard(q.x, q.y) or sv_cover_taken(v, q.x, q.y) or sv_cover_given_up(v, q.x, q.y): continue
			var u := (Vector2(p.x, p.y) - cc).normalized()
			var pk := cc + u * (cr * 0.95)
			if not gm.walk_clear(q.x, q.y, pk.x, pk.y) or not gm.los(pk.x, pk.y, p.x, p.y): continue
			cands.append([dv + absf(dp - pref) * pw + SV_SMOKE_PEN, q.x, q.y, pk, null, cl])
			break
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(cands.size(), 4):   # the best few that are actually a short walk away
		var cd: Array = cands[k]
		if not gm.walk_clear(v.x, v.y, cd[1], cd[2]):
			var path := astar_path(v.x, v.y, Vector2i(int(floor(cd[1] / gm.TS)), int(floor(cd[2] / gm.TS))))
			if path.is_empty() or path.size() > path_max: continue
		var out := {"x": cd[1], "y": cd[2], "pk": cd[3], "car": cd[4]}
		if cd[5] is Dictionary: out.sm = cd[5]
		return out
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
		if gm.S.t >= float(gm.S.get("flankCallT", -1.0)) and on_screen(v.x, v.y):   # one call at a time
			gm.S.flankCallT = gm.S.t + randf_range(SV_FLANK_CALL_GAP.x, SV_FLANK_CALL_GAP.y)
			sv_say(v, "Flanking!")   # (text only, no voice)

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
	if cv.has("sm") and (cv.sm.dead or cv.sm.den < SV_SMOKE_HOLD): return false   # the smoke's thinning out
	var dp := Vector2(p.x - cv.x, p.y - cv.y).length()
	if dp < SV_COVER_MIN_D or dp > sv_range(v).y + 160.0: return false
	if v.cph == 0 and v.cpt > SV_COVER_MAXT: return false
	if v.cph == 1 and not cv.has("sm") and Vector2(cv.x - v.x, cv.y - v.y).length() < 8.0 and (see or v.hit > 0):
		# (a hit in smoke is just a lucky shot: they stay put)
		v.flk += dt
		if v.flk > 0.3 or v.hit > 0:
			v.nodg = gm.S.t + SV_SUP_NODG   # straight off to better cover, no dodging on the way
			return false
	else:
		v.flk = 0.0
	return true

## Is (x, y) near the cover survivor v was driven out of a moment ago (see SV_DUCK_MAX)?
func sv_cover_given_up(v: Dictionary, x: float, y: float) -> bool:
	if not v.has("cvBad"): return false
	var b: Dictionary = v.cvBad
	if gm.S.t >= float(b.t):
		v.erase("cvBad")
		return false
	return Vector2(x - b.x, y - b.y).length() < SV_DUCK_AVOID_R

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
		if randf() >= SV_COVER_SEEK * float(v.get("iq", 1.0)):   # doesn't think of it this time
			v.cvT = randf_range(SV_COVER_SKIP_T.x, SV_COVER_SKIP_T.y)
			return null
		var found = sv_find_cover(v, p)
		v.cvT = SV_COVER_RETRY
		if not (found is Dictionary):
			if v.get("smk", false) and sv_smoke_throw(v, p):
				v.cvT = SV_BOMB_WIND + 0.6   # look again once it's up
				return Vector2.ZERO
			return null
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
		if at_cover and not v.has("rl") and int(v.get("mag", sv_mag_cap(v))) < sv_mag_cap(v) * SV_RELOAD_TOPUP:
			sv_start_reload(v)   # a quiet moment: top up
		if v.cpt >= v.hide and not v.has("rl"):   # (reloaded first)
			v.cph = 2; v.cpt = 0.0; v.seen = -1.0; v.shots = 0
		return Vector2.ZERO if at_cover else sv_nav(v, cv.x, cv.y)
	if cv.has("sm"):   # in smoke: no stepping out, they shoot from inside it
		return sv_smoke_fire(v, p, see, cv, dt)
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
			var rgx := sv_range(v).x
			var dp := Vector2(p.x - cv.x, p.y - cv.y).length()
			if v.pks >= SV_LEAP_PEEKS and dp - gm.TS >= rgx:   # move up: cover at least a tile nearer you, if there's any
				var nc = sv_find_cover(v, p, null, SV_LEAP_R, SV_LEAP_R * 1.6, dp - gm.TS)
				if nc is Dictionary and Vector2(p.x - nc.x, p.y - nc.y).length() >= rgx:
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
## A survivor fires their gun. Automatics fire SV_BURST-round bursts; shotguns fire a spread of
## pellets. Damage per bullet is the normal survivor damage x (gun damage / SV_DMG_REF).
func sv_fire(v: Dictionary, spread: float = 1.0) -> void:
	if v.has("rl"): return   # reloading
	var w: Dictionary = D.WEAPONS[int(v.get("w", 0))]
	var auto: bool = w.get("auto", false)
	var dmg: float = (8 + gm.S.danger) * gm.DF().dmg * float(w.dmg) / SV_DMG_REF
	# settled: standing still a while steadies their aim (wobble, and a rifle's own spread)
	var st := clampf(float(v.get("still", 0.0)) / SV_SETTLE_T, 0.0, 1.0) if spread <= 1.0 else 0.0
	var steady := lerpf(1.0, SV_SETTLE_ACC, st)
	var aim: float = sv_lead(v, float(w.spd)) + (randf() - 0.5) * 0.22 * spread * steady * (1.6 if auto and v.burst > 0 else 1.0)
	var spr: float = float(w.spr) * (steady if int(w.pel) == 1 else 1.0)
	for k in int(w.pel):
		var a: float = aim + (randf() - 0.5) * spr * 2.0
		gm.S.bul.append({"x": v.x + cos(a) * 14, "y": v.y + sin(a) * 14, "vx": cos(a) * w.spd * 0.65, "vy": sin(a) * w.spd * 0.65,
			"life": w.life, "dmg": dmg, "pl": false, "kb": 0.0, "bolt": w.bolt, "src": v})
	gm.sfx("bow" if w.silent else "enemy")
	if not w.silent: gm.add_noise(float(w.noise) * SV_SHOT_NOISE)
	if not w.silent: gm.muzzle_flash(v.x, v.y, aim)
	v.mag = int(v.get("mag", sv_mag_cap(v))) - 1
	if v.mag <= 0:   # empty
		sv_start_reload(v)
		return
	if auto:
		if v.burst <= 0: v.burst = randi_range(SV_BURST.x, SV_BURST.y)
		v.burst -= 1
		if v.burst > 0:
			v.cd = w.rate * 2.0          # next shot in the burst
			return
	v.cd = (0.75 + w.rate) * (1.0 + randf() * 0.6)

## Where survivor v points the gun: v.ang, except that when that's at you and you're moving
## they aim ahead, at where you'll be when a bullet at speed spd gets there. How much of that
## lead they get right is SV_LEAD_K x their iq, give or take SV_LEAD_ERR / iq.
func sv_lead(v: Dictionary, spd: float) -> float:
	var p: Dictionary = gm.S.p
	var u: Vector2 = gm.S.get("plv", Vector2.ZERO)
	if u.length() < 5.0: return v.ang
	var r := Vector2(p.x - v.x, p.y - v.y)
	var direct := r.angle()
	if absf(wrapf(v.ang - direct, -PI, PI)) > SV_LEAD_CONE: return v.ang   # not shooting at you
	# time for the bullet to meet you: |r + u t| = spd t
	var qa := u.dot(u) - spd * spd
	var qb := 2.0 * r.dot(u)
	var qc := r.dot(r)
	var t := r.length() / spd
	var disc := qb * qb - 4.0 * qa * qc
	if absf(qa) > 0.001 and disc >= 0.0:
		var t1 := (-qb - sqrt(disc)) / (2.0 * qa)
		var t2 := (-qb + sqrt(disc)) / (2.0 * qa)
		t = t1 if t1 > 0.0 and (t1 < t2 or t2 <= 0.0) else t2
		if t <= 0.0: t = r.length() / spd
	var iq: float = v.get("iq", 1.0)
	var k := clampf(SV_LEAD_K * iq + randf_range(-SV_LEAD_ERR, SV_LEAD_ERR) / iq, 0.0, 1.2)
	var ahead := r + u * t * k
	return v.ang + wrapf(ahead.angle() - direct, -PI, PI)

## Who survivor v fights (Greg 2026-10-20): first whoever attacked them in the last SV_ATK_MEM s
## (you, a rescue survivor, or a zombie while both are on screen); else the nearest of you and the
## rescue survivors out of hiding that they can see; else you.
func sv_target(v: Dictionary, p: Dictionary) -> Dictionary:
	var a = v.get("atk")
	if a is Dictionary and gm.S.t - float(v.get("atkT", -99.0)) < SV_ATK_MEM and sv_atk_live(v, a): return a
	v.erase("atk")
	var best: Dictionary = p
	var bd := Vector2(p.x - v.x, p.y - v.y).length()
	var pvis := gm.los(v.x, v.y, p.x, p.y)
	for n in gm.S.npcs:
		if gm.in_safe(n.x, n.y): continue   # hidden away: they don't know about them
		var nd := Vector2(n.x - v.x, n.y - v.y).length()
		if nd < 520 and (nd < bd or not pvis) and gm.los(v.x, v.y, n.x, n.y):
			best = n; bd = nd; pvis = true
	return best

## Is attacker a still worth fighting for survivor v?
func sv_atk_live(_v: Dictionary, a: Dictionary) -> bool:
	if is_same(a, gm.S.p): return true
	if gm.S.npcs.has(a): return not gm.in_safe(a.x, a.y)
	return gm.S.zs.has(a) and not a.dead   # a zombie, while it's up

## How many rounds survivor v's gun holds.
func sv_mag_cap(v: Dictionary) -> int:
	return int(D.WEAPONS[int(v.get("w", 0))].get("mag", 6))

## Survivor v starts reloading (D.WEAPONS "rl" seconds, no shooting meanwhile): any burst ends,
## SV_RELOAD_CALL of the time they shout it, and they get into cover to do it: a peeker ducks
## back, someone in the open runs for cover if there's any (rushers just reload where they are).
func sv_start_reload(v: Dictionary) -> void:
	if v.has("rl"): return
	v.rl = float(D.WEAPONS[int(v.get("w", 0))].get("rl", 2.0))
	v.burst = 0
	v.cd = maxf(v.cd, v.rl)
	if randf() < SV_RELOAD_CALL: sv_say(v, "Reloading!")
	if v.has("cv"):
		if v.cph == 2 and not v.cv.has("sm"):
			v.cph = 1; v.cpt = 0.0
			v.hide = randf_range(SV_HIDE_MIN, SV_HIDE_MAX)
	elif v.alert and not v.get("rush", false):
		var nc = sv_find_cover(v, v.get("tgt", gm.S.p))
		if nc is Dictionary:
			v.cv = nc
			v.cph = 0; v.cpt = 0.0; v.miss = 0; v.flk = 0.0; v.pks = 0

## Reinforcement survivor arriving from the edge of the map (noise waves at held strips).
func spawn_edge_sv(n: int = 1) -> void:
	if gm.S.has("pool"):   # a field you're clearing has only so many left to send (fields.gd)
		n = mini(n, int(gm.S.pool))
		if n <= 0: return
		gm.S.pool = int(gm.S.pool) - n
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
	if gm.S == null: return
	var used: Array = []
	for k in gm.G.contracts:
		if k.get("type", "") == "rescue" and k.stage == "pickup" and int(k.pickup) == s.id:
			_spawn_one(k.who, k.where, k.id, used)
	# a mayday you landed for (Greg, 2026-10-20): 1-3 people hiding in different buildings
	var md = gm.G.mayday
	if md and int(md.id) == s.id and md.get("landed", false):
		for pp in md.ppl: _spawn_one(pp.who, pp.where, "", used)
		var n: int = md.ppl.size()
		gm.toast_later(1.6, ("%d survivors are hiding in town. Find them and bring them to the plane." % n) if n > 1 else "One survivor is hiding in town. Find them and bring them to the plane.", "mag")

## Puts one rescue survivor in their hiding place: the building of kind `where` if the
## town has one nobody else is using, else any free building. cid "" marks a mayday survivor.
func _spawn_one(who: String, where: String, cid: String, used: Array) -> void:
	var rm = null
	for r in gm.S.rooms:
		if r.kind == where and not used.has(r):
			rm = r
			break
	if rm == null:
		for r in gm.S.rooms:
			if r.kind == "house" and not used.has(r):
				rm = r
				break
	if rm == null:
		for r in gm.S.rooms:
			if D.WHERE.has(r.kind) and not used.has(r):
				rm = r
				break
	if rm == null: return
	used.append(rm)
	var x: float = (rm.c + rm.w / 2.0) * gm.TS
	var y: float = (rm.r + rm.h / 2.0) * gm.TS
	var q := 0
	while q < 30 and gm.solid(x, y):
		x = (rm.c + 1.5 + randf() * (rm.w - 3)) * gm.TS
		y = (rm.r + 1.5 + randf() * (rm.h - 3)) * gm.TS
		q += 1
	var wh: String = where if rm.kind == where else (rm.kind if D.WHERE.has(rm.kind) else "house")
	# The building they're hiding in is safe for the mission: nothing spawns in it,
	# zombies can't walk in, and anything already inside is removed.
	var safe := Rect2(rm.c * gm.TS, rm.r * gm.TS, rm.w * gm.TS, rm.h * gm.TS)
	gm.S.npcs.append({"x": x, "y": y, "ang": PI / 2, "hp": 60.0, "voice": randf_range(Synth.VOICE.x, Synth.VOICE.y), "name": who, "where": wh, "cid": cid, "follow": false, "wk": 0.0, "hit": 0.0,
		"w": NPC_GUNS[randi() % NPC_GUNS.size()], "cd": 0.0, "fire_t": -1.0, "safe": safe})
	gm.S.safes.append(safe)
	gm.S.zs = gm.S.zs.filter(func(z): return not gm.in_safe(z.x, z.y))
	gm.S.sv = gm.S.sv.filter(func(v): return not gm.in_safe(v.x, v.y))
	if cid != "": gm.toast_later(0.7, "%s is hiding in %s." % [who, D.WHERE[wh]], "mag")

## Takes a rescue survivor off the map (boarded or dead) and opens their hiding place again.
func _drop_npc(n: Dictionary) -> void:
	gm.S.npcs.erase(n)
	gm.S.safes.erase(n.safe)

## A mayday survivor is out of the mission (boarded or dead). When nobody is left, it's over.
func _mayday_done(n: Dictionary) -> void:
	var md = gm.G.mayday
	if md == null: return
	md.ppl = md.ppl.filter(func(pp): return pp.who != n.name)
	if md.ppl.is_empty(): gm.G.mayday = null

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
			"dmg": float(w.dmg) * NPC_DMG, "pl": true, "kb": float(w.kb) * 0.5, "bolt": false, "src": n})
	gm.sfx(w.snd)
	if not w.silent: gm.muzzle_flash(n.x, n.y, a0)
	gm.add_noise(float(w.noise) * 0.5)
	n.cd = (0.75 + float(w.rate)) * (1.0 + randf() * 0.4)

func npc_hurt(n: Dictionary, d: float, dir: Vector2 = Vector2.ZERO) -> void:
	n.hp -= d
	n.hit = 0.15
	gm.hurt_cry(n)
	gm.blood(n.x, n.y, 2)
	if n.hp > 0: gm.blood_spray(n.x, n.y, dir)
	if n.hp <= 0:
		gm.blood(n.x, n.y, 8)
		gm.stamp_corpse({"x": n.x, "y": n.y, "a": randf() * TAU, "shirt": "#3f7a7a", "skin": "#e0b894"})
		if n.cid == "":
			_mayday_done(n)
			gm.toast("%s did not make it." % gm.cap(n.name), "bad")
		else:
			gm.G.contracts = gm.G.contracts.filter(func(k): return k.id != n.cid)
			gm.toast("%s did not make it. The job is gone." % gm.cap(n.name), "bad")
		_drop_npc(n)

func upd_npc(dt: float) -> void:
	for n in gm.S.npcs.duplicate():
		_upd_one(n, dt)
		if gm.S == null: return

func _upd_one(n: Dictionary, dt: float) -> void:
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
		if n.cid == "":
			# a mayday survivor rides along and pays their share at a family farm (Greg, 2026-10-20)
			var md = gm.G.mayday
			if md:
				var share: int = int(round(float(md.reward) / float(md.total) / 5.0)) * 5
				gm.G.pax.append({"who": n.name, "pay": share})
				_mayday_done(n)
				var farm = gm.flight.nearest_farm(gm.S.s)
				if farm and gm.G.nav < 0: gm.G.nav = int(farm.id)
				var left: String = " Fly them to a family farm." if gm.G.mayday == null else (" %d still out there." % gm.G.mayday.ppl.size())
				gm.toast("%s climbs into the back.%s" % [gm.cap(n.name), left], "good")
				gm.sfx("cash")
		else:
			for c in gm.G.contracts:
				if c.id == n.cid:
					c.stage = "aboard"
					gm.G.nav = int(c.dest)
					gm.toast("%s climbs into the back. Fly them to %s." % [gm.cap(n.name), gm.strip(int(c.dest)).name], "good")
					gm.sfx("cash")
					break
		_drop_npc(n)

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
	gm.floater(v.x, v.y - 18, "Bomb Out!", "#ff6a50", true)
	gm.sfx("swing")

# ======================================================================
# smoke grenades
# ======================================================================
## No cover close by: wind up to lob a smoke grenade the way they want to go (thrown just like a
## pipe bomb: SV_BOMB_WIND s standing still, then sv_smoke_launch()). Returns true if they will.
func sv_smoke_throw(v: Dictionary, p: Dictionary) -> bool:
	var to := Vector2(p.x - v.x, p.y - v.y)
	var d := to.length()
	if smoke_out() >= SV_SMOKE_MAX: return false
	# between you and them, its cloud stopping short of you
	var far := minf(clampf(d * SV_SMOKE_FRAC, SV_SMOKE_THROW.x, SV_SMOKE_THROW.y), d - SV_SMOKE_R)
	if far < SV_SMOKE_THROW.x: return false   # you're too close for it to help
	var u := to / d
	for cl in gm.S.get("clouds", []):   # there's already smoke that way
		if Vector2(cl.x - (v.x + u.x * far), cl.y - (v.y + u.y * far)).length() < far * 0.5 + cl.r and cl.den >= SV_SMOKE_HOLD: return false
	for k in [1.0, 0.75]:   # shorten the throw if the spot can't be reached
		for deg in [0.0, 15.0, -15.0, 30.0, -30.0]:
			var dd := u.rotated(deg_to_rad(deg))
			var l: float = maxf(SV_SMOKE_THROW.x, far * k)
			var tx: float = v.x + dd.x * l
			var ty: float = v.y + dd.y * l
			if gm.solid(tx, ty) or not gm.walk_clear(v.x, v.y, tx, ty): continue
			v.smk = false
			v.smw = {"x": tx, "y": ty, "t": SV_BOMB_WIND}
			v.ang = dd.angle()
			return true
	return false

## Winding up a smoke grenade throw: stand still facing the spot, then let it go. Returns the
## steer vector while busy, else null.
func sv_smoke_wind(v: Dictionary, dt: float) -> Variant:
	if not v.has("smw"): return null
	var w: Dictionary = v.smw
	w.t -= dt
	v.ang = atan2(w.y - v.y, w.x - v.x)
	if w.t <= 0:
		v.erase("smw")
		sv_smoke_launch(v, w.x, w.y, w.get("o", Vector2(w.x, w.y)))
	return Vector2.ZERO

## The smoke grenade leaves their hand: the same lob as a pipe bomb (sv_throw()), but it goes
## off as soon as it lands. `o`: where the first smoke of this screen went.
func sv_smoke_launch(v: Dictionary, tx: float, ty: float, o: Vector2) -> void:
	var a := atan2(ty - v.y, tx - v.x)
	var sx: float = v.x + cos(a) * 14
	var sy: float = v.y + sin(a) * 14
	var l := Vector2(tx - sx, ty - sy).length()
	var ft := 0.35 + l / 700.0   # seconds in the air
	if not gm.S.has("smk"): gm.S.smk = []
	gm.S.smk.append({"x": sx, "y": sy, "vx": (tx - sx) / ft, "vy": (ty - sy) / ft, "air": ft, "air0": ft,
		"h": clampf(l * 0.22, 18.0, 70.0), "z": 0.0, "spin": 0.0, "tx": tx, "ty": ty})
	gm.floater(v.x, v.y - 18, "Smoke Out!", "#cfcfc4", true)
	gm.sfx("swing")
	sv_smoke_join(v, o)

## Smokes out right now: clouds, grenades in the air and throws being wound up.
func smoke_out() -> int:
	var n: int = gm.S.get("clouds", []).size() + gm.S.get("smk", []).size()
	for w in gm.S.sv:
		if not w.dead and w.has("smw"): n += 1
	return n

## Survivor `v` has just thrown smoke (the screen started at `o`): other smoke carriers who saw it
## may throw theirs SV_SMOKE_GAP cloud diameters to one side of it, across your view, to widen it.
func sv_smoke_join(v: Dictionary, o: Vector2) -> void:
	var g := SV_SMOKE_GAP * 2.0 * SV_SMOKE_R
	var to := o - Vector2(gm.S.p.x, gm.S.p.y)
	var side := Vector2(-to.y, to.x).normalized() if to.length() > 1.0 else Vector2.RIGHT
	var ws: Array = gm.S.sv.duplicate()
	ws.shuffle()
	for w in ws:
		if smoke_out() >= SV_SMOKE_MAX: return
		if w.dead or is_same(w, v) or not w.alert or not w.get("smk", false) or w.has("smw"): continue
		if w.get("mst", 0.0) > 0 or w.get("yell", 0.0) > 0 or not sv_sees(w, v.x, v.y): continue
		if randf() >= SV_SMOKE_JOIN: continue
		# the free side of the first smoke nearest them that they can reach
		var best = null
		var bd := INF
		for sp in [o + side * g, o - side * g]:
			var dw := Vector2(sp.x - w.x, sp.y - w.y).length()
			if dw > SV_BOMB_RANGE or dw >= bd or gm.solid(sp.x, sp.y) or not gm.los(w.x, w.y, sp.x, sp.y): continue
			if smoke_near(sp, g * 0.5): continue   # that side's already covered
			best = sp; bd = dw
		if best is Vector2:
			w.smk = false
			w.smw = {"x": best.x, "y": best.y, "t": SV_BOMB_WIND + randf_range(SV_SMOKE_REACT.x, SV_SMOKE_REACT.y), "o": o}
			w.ang = atan2(best.y - w.y, best.x - w.x)

## In smoke cover, their turn to shoot: they stay inside and fire out of it for a peek's length,
## at you if they can see you, else blind (SV_SMOKE_BLIND) at where they last saw or heard you,
## then hide again.
func sv_smoke_fire(v: Dictionary, p: Dictionary, see: bool, cv: Dictionary, dt: float) -> Vector2:
	if v.seen < 0:
		v.seen = 0.0
		v.peek = randf_range(SV_PEEK_MIN, SV_PEEK_MAX)
		v.cd = maxf(v.cd, SV_PEEK_AIM)
	v.seen += dt
	var tx: float = p.x if see else float(v.get("lkx", p.x))
	var ty: float = p.y if see else float(v.get("lky", p.y))
	v.ang = atan2(ty - v.y, tx - v.x)
	if v.cd <= 0:
		sv_fire(v, 1.0 if see else SV_SMOKE_BLIND)
		v.shots += 1
	if v.seen >= v.peek and v.shots > 0 and v.burst <= 0:   # finish the burst, then lie low a while
		v.cph = 1; v.cpt = 0.0
		v.hide = randf_range(SV_HIDE_MIN, SV_HIDE_MAX)
	if Vector2(cv.x - v.x, cv.y - v.y).length() < 8.0: return Vector2.ZERO
	return sv_nav(v, cv.x, cv.y)

## Is there smoke (a cloud, a grenade landing, or a throw being wound up) within r of q?
func smoke_near(q: Vector2, r: float) -> bool:
	for cl in gm.S.get("clouds", []):
		if q.distance_to(Vector2(cl.x, cl.y)) < r: return true
	for c in gm.S.get("smk", []):
		if q.distance_to(Vector2(c.tx, c.ty)) < r: return true
	for w in gm.S.sv:
		if not w.dead and w.has("smw") and q.distance_to(Vector2(w.smw.x, w.smw.y)) < r: return true
	return false

## Smoke grenades in the air land and become clouds; clouds bloom, hold, then thin and spread
## out until they're gone. cl.den: 0..1 thickness.
func upd_smoke(dt: float) -> void:
	if not gm.S.has("clouds"): gm.S.clouds = []
	var cans: Array = gm.S.get("smk", [])
	var i := cans.size() - 1
	while i >= 0:
		var c: Dictionary = cans[i]
		c.air -= dt
		c.spin += dt * 12
		c.x += c.vx * dt; c.y += c.vy * dt
		var k: float = 1.0 - maxf(0.0, c.air) / c.air0
		c.z = 4.0 * c.h * k * (1.0 - k)
		if c.air <= 0:   # landed: starts pouring smoke
			gm.S.clouds.append({"x": c.x, "y": c.y, "age": 0.0, "r": SV_SMOKE_R * 0.4, "den": 0.0, "dead": false, "seed": randi() % 1000})
			var dp := Vector2(c.x - gm.S.p.x, c.y - gm.S.p.y).length()
			gm.sfx("smoke", 0.14 * (1.0 - 0.7 * minf(1.0, dp / 900.0)))
			cans.remove_at(i)
		i -= 1
	i = gm.S.clouds.size() - 1
	while i >= 0:
		var cl: Dictionary = gm.S.clouds[i]
		cl.age += dt
		var k: float = cl.age / SV_SMOKE_LIFE
		var bloom := minf(1.0, cl.age / SV_SMOKE_BLOOM)
		var thin := clampf((k - SV_SMOKE_THIN) / (1.0 - SV_SMOKE_THIN), 0.0, 1.0)
		cl.den = bloom * (1.0 - thin)
		cl.r = SV_SMOKE_R * (0.4 + 0.6 * bloom) * (1.0 + 0.35 * thin)   # spreads as it thins
		if cl.age >= SV_SMOKE_LIFE:
			cl.dead = true
			gm.S.clouds.remove_at(i)
		i -= 1

## Does thick smoke lie across the line from (x0, y0) to (x1, y1)?
func smoke_blocks(x0: float, y0: float, x1: float, y1: float) -> bool:
	for cl in gm.S.get("clouds", []):
		if cl.den < SV_SMOKE_SIGHT: continue
		var c := Vector2(cl.x, cl.y)
		var a := Vector2(x0, y0)
		var ab := Vector2(x1, y1) - a
		var t: float = clampf((c - a).dot(ab) / maxf(1.0, ab.length_squared()), 0.0, 1.0)
		if c.distance_to(a + ab * t) < float(cl.r) * 0.8 * float(cl.den): return true
	return false

# ======================================================================
# getting clear of blasts
# ======================================================================
## Everything about to go off: lit bombs, burning cars and lit barrels, as {x, y, r, src}.
func blast_dangers() -> Array:
	var out: Array = []
	for b in gm.S.thrown:
		if not b.dead: out.append({"x": b.x, "y": b.y, "r": Blasts.BOMB_BLAST_R, "src": b})
	for car in gm.S.cars:
		if not car.dead and car.fuse >= 0: out.append({"x": car.x, "y": car.y, "r": Blasts.CAR_BLAST_R, "src": car, "car": true})
	for br in gm.S.barrels:
		if not br.dead and br.fuse >= 0: out.append({"x": br.x, "y": br.y, "r": Blasts.BOMB_BLAST_R, "src": br})
	return out

## Has survivor v noticed that this burning car is about to blow? While inside its reach they
## roll SV_CAR_NOTICE x their iq (45-75%) every SV_CAR_NOTICE_T s until they do; once noticed,
## it stays noticed. v.cark[car.nid] is true once noticed, else the time of their next roll.
func sv_notices_car(v: Dictionary, car: Dictionary) -> bool:
	if not car.has("nid"): car.nid = randi()
	if not v.has("cark"): v.cark = {}
	var k = v.cark.get(car.nid, -1.0)
	if k is bool: return k
	if gm.S.t < float(k): return false
	if randf() < SV_CAR_NOTICE * float(v.get("iq", 1.0)):
		v.cark[car.nid] = true
		return true
	v.cark[car.nid] = gm.S.t + SV_CAR_NOTICE_T
	return false

## Is survivor v in the open inside one of these blasts? After a moment to react they run
## for a refuge (sv_refuge()) and wait there until that blast has gone off, firing at you if
## they're alerted and can see you. Returns a steer vector while fleeing or waiting, else null.
func sv_flee(v: Dictionary, dangers: Array, see: bool, dt: float) -> Variant:
	var worst = null
	var depth := 0.0
	for dg in dangers:
		var reach: float = dg.r + SV_FLEE_MARGIN
		var dd := Vector2(v.x - dg.x, v.y - dg.y).length()
		if dd >= reach or not gm.blasts.blast_clear(dg.src, v.x, v.y): continue
		if dg.get("car", false) and not sv_notices_car(v, dg.src): continue
		if not (worst is Dictionary) or reach - dd > depth:
			worst = dg
			depth = reach - dd
	if v.has("rfg"):
		var live := false
		for dg in dangers:
			if is_same(dg.src, v.rfg.src): live = true
		var there := Vector2(v.rfg.x - v.x, v.rfg.y - v.y).length() < 6.0
		# gone off (or fizzled): back to normal. Caught in the open by some other blast once
		# they're at the refuge: find another
		if not live or (there and worst is Dictionary and not is_same(worst.src, v.rfg.src)):
			v.erase("rfg")
		elif there:
			if v.alert and see and v.get("yell", 0.0) <= 0 and not v.has("unarmed"):
				var tg: Dictionary = v.get("tgt", gm.S.p)
				v.ang = atan2(tg.y - v.y, tg.x - v.x)
				if v.cd <= 0: sv_fire(v)
			return Vector2.ZERO
		else:
			var nv := sv_nav(v, v.rfg.x, v.rfg.y)
			if nv.length() > 0: v.ang = nv.angle()
			return nv * SV_FLEE_SPD
	if not (worst is Dictionary):
		v.erase("flT")
		return null
	if not v.has("flT"): v.flT = randf_range(SV_FLEE_REACT.x, SV_FLEE_REACT.y) / float(v.get("iq", 1.0))
	v.flT -= dt
	if v.flT > 0: return null   # hasn't clocked it yet
	var rf = sv_refuge(v, worst, dangers)
	if rf is Vector2:
		v.rfg = {"x": rf.x, "y": rf.y, "src": worst.src}
		v.erase("cv")   # (their old cover may be in the blast; they'll look again afterwards)
		v.erase("flT")
		var nv := sv_nav(v, rf.x, rf.y)
		if nv.length() > 0: v.ang = nv.angle()
		return nv * SV_FLEE_SPD
	# nowhere to go that they can reach: just run straight out of it
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
	var nv2 := sv_nav(v, worst.x + away.x * out_r, worst.y + away.y * out_r)
	if nv2.length() > 0: v.ang = nv2.angle()
	return nv2 * SV_FLEE_SPD

## Somewhere for survivor v to sit out blast dg: an open tile safe from every lit blast,
## meaning either behind something solid from it and at least SV_REFUGE_MIN x its radius
## away, or out of its reach. Shielded spots are preferred; then the shortest run. Not one
## another survivor is already heading for. Returns the spot, or null if none is reachable.
func sv_refuge(v: Dictionary, dg: Dictionary, dangers: Array) -> Variant:
	var R := int(ceil((float(dg.r) + SV_FLEE_MARGIN) / gm.TS)) + SV_REFUGE_SEARCH
	var vc := int(floor(v.x / gm.TS))
	var vr := int(floor(v.y / gm.TS))
	var cands: Array = []
	for r in range(vr - R, vr + R + 1):
		for c in range(vc - R, vc + R + 1):
			if not gm.passable(c, r): continue
			var x := (c + 0.5) * gm.TS
			var y := (r + 0.5) * gm.TS
			var dv := Vector2(x - v.x, y - v.y).length()
			if dv > R * gm.TS: continue
			var ok := true
			var cov := false
			for d2 in dangers:
				var dd := Vector2(x - d2.x, y - d2.y).length()
				if dd >= float(d2.r) + SV_FLEE_MARGIN: continue
				if dd >= float(d2.r) * SV_REFUGE_MIN and not gm.blasts.blast_clear(d2.src, x, y):
					if is_same(d2.src, dg.src): cov = true
					continue
				ok = false
				break
			if not ok or gm.hit_box(x, y, 10): continue
			var taken := false
			for o in gm.S.sv:
				if o != v and not o.dead and o.has("rfg") and Vector2(o.rfg.x - x, o.rfg.y - y).length() < 20.0:
					taken = true
					break
			if taken: continue
			cands.append([dv + (0.0 if cov else SV_REFUGE_OPEN_PEN), x, y])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(cands.size(), 6):
		var cd: Array = cands[k]
		if gm.walk_clear(v.x, v.y, cd[1], cd[2]): return Vector2(cd[1], cd[2])
		var path := astar_path(v.x, v.y, Vector2i(int(floor(cd[1] / gm.TS)), int(floor(cd[2] / gm.TS))))
		if not path.is_empty() and path.size() <= R * 1.6: return Vector2(cd[1], cd[2])
	return null

# ======================================================================
# per-frame update
# ======================================================================
## Armed survivors: alarm, flanking, cover, open-ground fighting, searching, patrols.
## (Per-frame survivor update; the behaviour itself is in the functions above.)
func upd_survivors(p: Dictionary, dt: float) -> void:
	if gm.S.get("hostile", false): upd_garrison(dt)
	sv_squad(p, dt)
	sv_bomb_watch(p)
	upd_smoke(dt)
	var dangers := blast_dangers()
	# your velocity, smoothed (survivors lead you with it, see sv_lead)
	if dt > 0.0:
		var pl: Vector2 = gm.S.get("plp", Vector2(p.x, p.y))
		var pv := (Vector2(p.x, p.y) - pl) / dt
		if pv.length() > 600.0: pv = Vector2.ZERO   # teleported (landing, building swap)
		gm.S.plv = (gm.S.get("plv", Vector2.ZERO) as Vector2).lerp(pv, minf(1.0, dt * 8.0))
		gm.S.plp = Vector2(p.x, p.y)
	for v in gm.S.sv:
		gm.blasts.blast_dmg_tick(v, dt)
		if v.dead: continue
		if v.alert: v.erase("unarmed")   # alerted: picks up their gun
		v.gup = move_toward(float(v.get("gup", 0.0)), 1.0 if v.alert else 0.0, dt / (SV_RAISE_T if v.alert else SV_LOWER_T))
		if v.has("jt"):
			v.jt -= dt
			if v.jt <= 0: v.erase("jt")
		var tp := sv_target(v, p)   # who they're fighting: you, a rescue survivor, or whoever's attacking them
		v.tgt = tp
		var isp := is_same(tp, p)
		var dx: float = tp.x - v.x
		var dy: float = tp.y - v.y
		var d := Vector2(dx, dy).length()
		if d == 0: d = 1
		var lit: float = gm.seen_k() if isp else 1.0   # a flashlight at night carries farther
		var see := d < 520 * lit and gm.los(v.x, v.y, tp.x, tp.y) and not smoke_blocks(v.x, v.y, tp.x, tp.y) and window_sight_ok(v.x, v.y, tp.x, tp.y)
		var fa := absf(U.ang_diff(atan2(dy, dx), float(v.ang)))   # how far off their facing you are
		if v.alert: see = see and (d < SV_SENSE or fa < deg_to_rad(SV_VIEW_HALF_ALERT))
		var iq: float = v.get("iq", 1.0)
		var spot: bool = see and (v.alert or (d < SV_SPOT_R * iq * lit and (d < SV_SENSE * iq or fa < deg_to_rad(SV_VIEW_HALF * iq))))
		if spot:   # seen: alerted, knows exactly where you are
			sv_hear(v, tp.x, tp.y)
			if isp: gm.S.svSeenT = gm.S.t   # (for the squad: someone has eyes on you)
			if not v.get("called", false):   # first sighting (since they last stood down): raise the alarm
				v.called = true
				v.jt = SV_STARTLE_T   # startled hop
				sv_raise(v.x, v.y, tp.x, tp.y)
				v.yell = SV_YELL_MIN + randf() * (SV_YELL_MAX - SV_YELL_MIN)
				v.cd = maxf(v.cd, v.yell)
				# one "Hey!" at a time: after a yell the rest wait SV_YELL_GAP seconds (they still
				# stop and raise the alarm, just silently)
				if gm.S.t >= float(gm.S.get("yellT", -1.0)):
					gm.S.yellT = gm.S.t + randf_range(SV_YELL_GAP.x, SV_YELL_GAP.y)
					gm.sfx("yell", -1.0, v.get("voice", 1.0))
		v.cd -= dt
		if v.has("rl"):   # reloading
			v.rl -= dt
			if v.rl <= 0:
				v.erase("rl")
				v.mag = sv_mag_cap(v)
		v.yell = maxf(0.0, v.get("yell", 0.0) - dt)
		v.hit -= dt
		if v.has("supW"): sv_dodge_wait(v, dt)   # a dodge coming once the beat is up
		var vx := 0.0
		var vy := 0.0
		if not v.alert and not v.has("exam"):   # a body lying nearby?
			v.bdT = float(v.get("bdT", 0.0)) - dt
			if v.bdT <= 0:
				v.bdT = 0.3
				sv_find_body(v)
		var fv = sv_flee(v, dangers, see, dt)
		if fv is Vector2:   # something's about to blow: getting clear (or waiting it out) comes first
			vx = fv.x; vy = fv.y
		elif v.get("mst", 0.0) > 0:   # just saw a friend die: stunned, not moving or shooting
			v.mst -= dt
			if v.has("mourn"):
				sv_mourn_tick(v, dt)
				if v.mst <= 0: v.erase("mourn")
		elif v.alert and v.has("sup"):   # under fire: out of its way first
			var dg = sv_dodge(v, tp, see, dt)
			if dg is Vector2:
				vx = dg.x; vy = dg.y
		elif v.alert:
			var sw = sv_smoke_wind(v, dt)
			# (bombs and flanking are for you; other fights are just cover and shooting)
			var bs = sv_bomb(v, p, see, dt) if isp and v.yell <= 0 and not (sw is Vector2) else null
			var fls = sv_flank(v, p, see, d, dt) if isp and not (sw is Vector2) and not (bs is Vector2) and v.yell <= 0 and v.has("fl") else null
			var cvs = null
			if not (sw is Vector2) and not (bs is Vector2) and not (fls is Vector2) and v.yell <= 0: cvs = sv_cover_fight(v, tp, see, dt)
			if sw is Vector2:   # winding up a smoke grenade
				vx = sw.x; vy = sw.y
			elif bs is Vector2:   # going to throw a bomb, or winding up to
				vx = bs.x; vy = bs.y
			elif fls is Vector2:   # circling round to flank you, holding fire
				vx = fls.x; vy = fls.y
			elif cvs is Vector2:   # fighting from cover
				vx = cvs.x; vy = cvs.y
			elif see and v.yell > 0:
				# just spotted you: whipping round to face you and yelling, not shooting yet
				v.ang = rotate_toward(float(v.ang), atan2(dy, dx), SV_WHIP_SPD * dt)
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
				# strafe one way for a while, stop for a moment, then pick a way again
				v.sw -= dt
				if v.sw <= 0:
					if v.get("sps", false):
						v.sps = false
						v.sw = 1 + randf() * 1.5
						v.sd = 1.0 if randf() < 0.5 else -1.0
					else:
						v.sps = true
						v.sw = randf_range(SV_STRAFE_PAUSE.x, SV_STRAFE_PAUSE.y)
				if not v.get("sps", false):
					vx += -dy / d * v.sd * SV_STRAFE
					vy += dx / d * v.sd * SV_STRAFE
				if v.cd <= 0: sv_fire(v)
			else:
				# can't see you: go to where they last saw/heard you, search there, then give up
				if not v.has("lkx"): sv_hear(v, tp.x, tp.y)   # alerted by a hit: they know where it came from
				v.lost = v.get("lost", 0.0) + dt
				if v.lost > SV_FORGET:
					v.alert = false
					v.called = false
					v.erase("lkx")
					v.srch = false
					v.erase("cv")
					v.erase("fl")
					v.erase("smw")
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
		elif v.has("exam"):   # going to look at a body
			var ev := sv_exam(v, dt)
			vx = ev.x; vy = ev.y
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
		var av := sv_avoid(v, vx, vy)   # someone in the way ahead: step round them
		vx = av.x; vy = av.y
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
		# how long they've stood still (settled aim, see sv_fire)
		v.still = float(v.get("still", 0.0)) + dt if Vector2(v.x - vx0, v.y - vy0).length() < 20.0 * dt else 0.0
		v.wk += Vector2(v.x - vx0, v.y - vy0).length() * 0.22
