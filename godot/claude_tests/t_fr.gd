extends Node
## Claude test harness (friendly survivor AI). Safe to delete.
var game
var frames := 0
var started := false
func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
func _process(_d: float) -> void:
	frames += 1
	if not started:
		if game.ready_done:
			started = true
			run()
		if frames == 120: game.ready_done = true
func step(n: int) -> void:
	for i in n:
		game._process(1.0 / 60.0)
		if game.S == null: return
func run() -> void:
	game.set_process(false)
	seed(77)
	game.menu.start_new()
	var town = null
	var farm = null
	for s in game.wd.strips:
		if s.type == "haven" or s.type == "road": continue
		if s.get("arch", "") == "family":
			if farm == null and not s.get("failsafe", false): farm = s
		elif town == null and not s.get("hostile", false): town = s
	game.G.mayday = {"id": town.id, "until": game.G.time + 100, "reward": 300, "ppl": [{"who": "Mara Ellis", "where": "house"}], "total": 1, "landed": true}
	game.enter_ground(town)
	var S = game.S
	var n = S.npcs[0]
	S.p.x = n.x + 30; S.p.y = n.y
	step(2)
	print("T follow ", n.follow)
	# out in the open, well away from the plane
	var base := Vector2(S.plane.x + 420, S.plane.y - 200)
	for t in 40:
		if not game.hit_box(base.x, base.y, 12) and not game.hit_box(base.x + 40, base.y, 12): break
		base = Vector2(S.plane.x + 300 + randf() * 500, S.plane.y - 400 + randf() * 600)
	S.p.x = base.x; S.p.y = base.y
	n.x = base.x + 40; n.y = base.y
	S.zs.clear(); S.sv.clear()
	var v = game.survivors.new_sv(base.x + 260, base.y + 30)
	v.rush = false
	S.sv.append(v)
	game.survivors.sv_hear(v, S.p.x, S.p.y)
	n.fire_t = S.t + 1000.0
	print("T start npc ", Vector2(n.x, n.y), " hostile ", Vector2(v.x, v.y))
	for k in 12:
		if k == 6: print("T player starts running")
		for f in 30:
			if k >= 6: S.p.x += 3.0
			step(1)
			if game.S == null: break
		if game.S == null: break
		var nb := 0
		for b in S.bul: if is_same(b.get("src"), n): nb += 1
		print("T t%.1f npc %s d%.0f alert %s tgt %s cv %s mag %s rl %s hp %.0f | sv hp %.0f dead %s cv %s | npcBul %d" % [S.t, Vector2(n.x, n.y).round(), Vector2(n.x - S.p.x, n.y - S.p.y).length(), n.alert, n.has("tgt"), n.has("cv"), n.get("mag", "-"), n.has("rl"), n.hp, v.hp, v.dead, v.has("cv"), nb])
		if not S.npcs.has(n): break
	# push test: stand on the npc
	if S.npcs.has(n):
		n.fire_t = -1.0
		S.p.x = n.x + 3; S.p.y = n.y
		step(2)
		print("T push gap ", Vector2(n.x - S.p.x, n.y - S.p.y).length())
	# farm folk
	game.enter_ground(farm)
	step(60)
	var ff = game.S.ff
	if ff.size():
		var o = ff[ff.size() - 1]
		var t0: float = game.S.t
		game.S.p.x = o.x + 2; game.S.p.y = o.y
		var o0 := Vector2(o.x, o.y)
		step(3)
		print("T folk ", ff.size(), " gap ", Vector2(o.x - game.S.p.x, o.y - game.S.p.y).length(), " moved ", Vector2(o.x, o.y) - o0, " dt ", game.S.t - t0, " mode ", game.mode, " uist '", game.uist, "' hitbox ", game.hit_box(o.x - 18, o.y, 8))
	step(120)
	print("T done")
	pass
