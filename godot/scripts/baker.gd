class_name Baker
extends Node
## Renders terrain chunks / the world overview on the GPU with the terrain shader, and bakes
## procedural sprites (planes, trees) into textures. Results are read back into ImageTextures.

const CH := 1024.0   # world units per chunk
const CPX := 256     # pixels per chunk

var vp: SubViewport
var rect: ColorRect
var mat: ShaderMaterial
var chunks := {}          # Vector2i -> ImageTexture
var chunk_order: Array = []
var queue: Array = []     # Vector2i
var queued := {}
var busy := false
var overview: ImageTexture
# Same scale as the overview, but also covering the ocean margin around the land
# (used by the flight minimap so it shows real sea all the way out).
var overview_wide: ImageTexture
var wide_origin := 0.0     # world x/y of the texture's top-left corner
var wide_span := 0.0       # world units the texture covers on each side
var world_ver := 0

func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(CPX, CPX)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	rect = ColorRect.new()
	rect.size = Vector2(CPX, CPX)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	rect.material = mat
	vp.add_child(rect)

func set_world(w: World) -> void:
	world_ver += 1
	chunks.clear()
	chunk_order.clear()
	queue.clear()
	queued.clear()
	mat.set_shader_parameter("seed", w.SEED)
	mat.set_shader_parameter("haven", w.HAVEN)
	var rp := PackedVector4Array()
	for i in 16:
		if i < w.ROADS.size():
			var r = w.ROADS[i]
			rp.append(Vector4(r.x1, r.y1, r.x2, r.y2))
		else:
			rp.append(Vector4.ZERO)
	mat.set_shader_parameter("road_p", rp)
	mat.set_shader_parameter("road_count", w.ROADS.size())

func _render(origin: Vector2, step: float, grid: int, shade: bool) -> Image:
	vp.size = Vector2i(grid, grid)
	rect.size = Vector2(grid, grid)
	mat.set_shader_parameter("origin", origin)
	mat.set_shader_parameter("step_u", step)
	mat.set_shader_parameter("grid", float(grid))
	mat.set_shader_parameter("shade_on", shade)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		img = Image.create(grid, grid, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.17, 0.3, 0.35))
	return img

func build_overview(pad: float = 0.0) -> void:
	while busy: await get_tree().process_frame
	busy = true
	var ver := world_ver
	var step := D.WORLD / 300.0
	var img: Image = await _render(Vector2.ZERO, step, 300, false)
	if ver == world_ver:
		overview = ImageTexture.create_from_image(img)
	if pad > 0.0:
		var grid := int(ceil((D.WORLD + 2.0 * pad) / step))
		var img2: Image = await _render(Vector2(-pad, -pad), step, grid, false)
		if ver == world_ver:
			overview_wide = ImageTexture.create_from_image(img2)
			wide_origin = -pad
			wide_span = grid * step
	busy = false

func get_chunk(cx: int, cy: int, want: bool = true) -> Texture2D:
	var k := Vector2i(cx, cy)
	if chunks.has(k): return chunks[k]
	if want and not queued.has(k):
		queued[k] = true
		queue.push_front(k)
		if queue.size() > 24:
			var old = queue.pop_back()
			queued.erase(old)
	return null

func has_chunk(cx: int, cy: int) -> bool:
	return chunks.has(Vector2i(cx, cy))

func _process(_dt: float) -> void:
	if busy or queue.is_empty(): return
	_run_chunk(queue.pop_front())

func _run_chunk(k: Vector2i) -> void:
	busy = true
	var ver := world_ver
	var img: Image = await _render(Vector2(k.x * CH, k.y * CH), CH / CPX, CPX, true)
	queued.erase(k)
	if ver == world_ver:
		chunks[k] = ImageTexture.create_from_image(img)
		chunk_order.append(k)
		if chunk_order.size() > 90:
			chunks.erase(chunk_order.pop_front())
	busy = false

## Bake a procedural drawing into a texture. draw_fn(pen: Pen) draws in pixel space.
func bake(size: Vector2i, draw_fn: Callable) -> ImageTexture:
	var v := SubViewport.new()
	v.size = size
	v.disable_3d = true
	v.transparent_bg = true
	v.render_target_update_mode = SubViewport.UPDATE_ONCE
	var n := BakeNode.new()
	n.fn = draw_fn
	v.add_child(n)
	add_child(v)
	await RenderingServer.frame_post_draw
	var img := v.get_texture().get_image()
	v.queue_free()
	if img == null or img.is_empty():
		img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)


class BakeNode extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(Pen.new(self))
