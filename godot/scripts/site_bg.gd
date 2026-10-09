class_name SiteBg
extends SubViewport
## Holds a site's baked ground texture. After the initial bake it never clears, so blood,
## corpses and scorch marks can be stamped onto it incrementally (like drawing on S.bg).

var st: Dictionary
var bake_node: Node2D
var stamp_node: Node2D
var pending: Array = []
var baked := false

func setup(site: Dictionary) -> void:
	st = site
	size = Vector2i(int(site.cols * SiteGen.TS * SiteGen.BK), int(site.rows * SiteGen.TS * SiteGen.BK))
	disable_3d = true
	transparent_bg = false
	render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	render_target_update_mode = SubViewport.UPDATE_ONCE
	bake_node = _Fn.new()
	bake_node.fn = func(p: Pen): SiteGen.bake_draw(p, st)
	add_child(bake_node)
	stamp_node = _Fn.new()
	stamp_node.fn = _draw_stamps
	add_child(stamp_node)
	RenderingServer.frame_post_draw.connect(_post)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_post):
		RenderingServer.frame_post_draw.disconnect(_post)

func _post() -> void:
	if not is_inside_tree(): return
	if not baked:
		baked = true
		bake_node.visible = false
	pending.clear()

func stamp(rec: Array) -> void:
	pending.append(rec)
	stamp_node.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_stamps(g: Pen) -> void:
	g.scale(SiteGen.BK, SiteGen.BK)
	for rec in pending:
		match rec[0]:
			"blood":
				for b in rec[1]:
					g.circle(b[0], b[1], b[2], U.rgb(90, 12, 8, .5))
					g.circle(b[0] - 1, b[1] - 1, b[2] * .55, U.rgb(140, 24, 16, .3))
			"corpse":
				var k: Dictionary = rec[1]
				g.save(); g.translate(k.x, k.y); g.rotate(k.a)
				var sk := U.hx(k.skin)
				g.ellipse(0, 0, 13, 8, 0, U.shade(U.hx(k.shirt), .6))
				g.lines(PackedVector2Array([Vector2(4, -7), Vector2(10, -14), Vector2(-8, 6), Vector2(-16, 10)]), U.shade(sk, .6), 4)
				g.circle(10, -14, 2, U.shade(sk, .6)); g.circle(-16, 10, 2, U.shade(sk, .6))
				g.circle(14, 1, 5.5, U.shade(sk, .7))
				g.restore()
			"scorch":
				# optional radius and centre darkness (car blasts use a smaller, fainter mark)
				var sr: float = rec[3] if rec.size() > 3 else 62.0
				var sa: float = rec[4] if rec.size() > 4 else 0.75
				g.radial(rec[1], rec[2], [[4.0, U.rgb(8, 6, 4, sa)], [sr, U.rgb(8, 6, 4, 0)]], 32)
			"wreck":
				# burnt-out shell over the baked car: charred body, blown-out glass, bare rims
				var k: Dictionary = rec[1]
				var x: float = k.c * SiteGen.TS + 3
				var y: float = k.r * SiteGen.TS + 3
				var w: float = k.w * SiteGen.TS - 6
				var h: float = k.h * SiteGen.TS - 6
				g.rr(x - 1, y - 1, w + 2, h + 2, 8, U.rgb(22, 19, 17, 1))
				g.rr(x + 2, y + 2, w - 4, h - 4, 6, U.rgb(48, 40, 34, 1))
				if w > h:
					g.rect(x + w * .22, y + 4, w * .56, h - 8, U.rgb(14, 12, 11, 1))
				else:
					g.rect(x + 4, y + h * .22, w - 8, h * .56, U.rgb(14, 12, 11, 1))
				for q in 5: g.circle(x + randf() * w, y + randf() * h, 2 + randf() * 4, U.rgb(110, 58, 30, .55))
			"streaks":
				for s in rec[1]:
					g.line(s[0], s[1], s[2], s[3], U.rgb(95, 10, 6, .5), s[4])

class _Fn extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(Pen.new(self))
