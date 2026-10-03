class_name SpriteAtlas
extends SubViewport
## Draw-once sprite cache. Each sprite is drawn into its own cell of this viewport the first
## time it is asked for, then reused as a texture region every frame after that. The viewport
## never clears, so cells accumulate; only new cells are drawn on any given frame.

var cells := {}        # key -> {"r": Rect2 (pixels), "ready": bool}
var pending: Array = []  # [rect_px: Rect2, scale: float, origin: Vector2, fn: Callable, key]
var drawer: Node2D
var sx := 1
var sy := 1
var row_h := 0
var full := false

func _init(w: int = 2048, h: int = 2048) -> void:
	size = Vector2i(w, h)
	disable_3d = true
	transparent_bg = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	render_target_update_mode = SubViewport.UPDATE_ONCE
	drawer = _Drawer.new()
	drawer.atlas = self
	add_child(drawer)

func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_post)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_post):
		RenderingServer.frame_post_draw.disconnect(_post)

func _post() -> void:
	if pending.is_empty(): return
	for p in pending: cells[p[4]].ready = true
	pending.clear()

## Returns the pixel region for `key` if it has been drawn, otherwise queues it and returns null.
## origin/size are in the sprite's local units; scale is pixels per unit.
func request(key: String, origin: Vector2, sz: Vector2, scale: float, fn: Callable):
	var c = cells.get(key)
	if c != null:
		return c.r if c.ready else null
	if full: return null
	var w := int(ceil(sz.x * scale)) + 2
	var h := int(ceil(sz.y * scale)) + 2
	if sx + w > size.x:
		sx = 1
		sy += row_h + 1
		row_h = 0
	if sy + h > size.y or w > size.x:
		full = true
		return null
	var r := Rect2(sx + 1, sy + 1, w - 2, h - 2)
	sx += w + 1
	row_h = maxi(row_h, h)
	cells[key] = {"r": r, "ready": false}
	pending.append([r, scale, origin, fn, key])
	drawer.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return null

## Draws `key` at local-space rect (origin, size) with the pen if ready; returns false if not.
func blit(g: Pen, key: String, origin: Vector2, sz: Vector2, scale: float, fn: Callable, mod: Color = Color.WHITE) -> bool:
	var r = request(key, origin, sz, scale, fn)
	if r == null: return false
	g.tex_region(get_texture(), Rect2(origin, sz), r, mod)
	return true


class _Drawer extends Node2D:
	var atlas: SpriteAtlas
	func _draw() -> void:
		var g := Pen.new(self)
		for p in atlas.pending:
			var r: Rect2 = p[0]
			var s: float = p[1]
			var o: Vector2 = p[2]
			g.reset(Transform2D(0.0, Vector2(s, s), 0.0, r.position - o * s))
			# clip-free: sprites are sized so their drawing stays inside the cell
			p[3].call(g)
