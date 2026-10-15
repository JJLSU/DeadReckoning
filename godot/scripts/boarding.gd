class_name Boarding
extends CanvasLayer
## Boarding the plane: fades the on-foot view to black, starts the flight, waits under the
## black screen until the terrain chunks and trees for the first flight view are built, then
## fades into flight. Stops the ground and trees popping in on the first flight frames.

const OUT_S := 0.35        # fade to black
const IN_S := 0.45         # fade into flight
const MAX_WAIT_MS := 4000  # start the flight anyway if the preload takes longer than this
const BUILD_US := 24000    # tree build budget per frame while the screen is black

var gm
var rect := ColorRect.new()
var lbl := Label.new()
var busy := false

## Called by the "Take off" button instead of flight.takeoff().
static func board(game) -> void:
	var b = game.get_node_or_null("Boarding")
	if b == null:
		b = Boarding.new()
		b.name = "Boarding"
		b.gm = game
		game.add_child(b)
	b.run()

func _ready() -> void:
	layer = 120   # over the menus (10), under the FPS counter (128)
	rect.color = Color.BLACK
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	lbl.text = "Loading…"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.94, 0.9, 0.81, 0.7))
	add_child(lbl)
	_alpha(0.0)

func run() -> void:
	if busy: return
	busy = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks on the menu while it fades
	await _fade(0.0, 1.0, OUT_S)
	gm.flight.takeoff()
	gm.uist = "loading"   # holds the plane still and hides the buttons until the fade-in
	await _preload()
	if gm.uist == "loading": gm.uist = ""
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await _fade(1.0, 0.0, IN_S)
	busy = false

func _alpha(a: float) -> void:
	rect.modulate.a = a
	lbl.modulate.a = a
	visible = a > 0.0

func _fade(a: float, b: float, dur: float) -> void:
	_alpha(a)
	var tw := create_tween()
	tw.tween_method(_alpha, a, b, dur).set_trans(Tween.TRANS_SINE)
	await tw.finished

## Waits until everything in the first flight view is built, plus two drawn frames.
func _preload() -> void:
	var t0 := Time.get_ticks_msec()
	var held := 0
	while held < 2 and Time.get_ticks_msec() - t0 < MAX_WAIT_MS:
		await get_tree().process_frame
		if gm.mode != "flight" or gm.F == null: return
		held = held + 1 if _view_built() else 0

## Queues and builds the terrain chunks and trees the first flight view needs (the same
## area draw_world covers); true once they are all ready.
func _view_built() -> bool:
	var F: Dictionary = gm.F
	var sc := Render.flight_scale(gm, F.alt)
	var cx: float = F.x + cos(F.hdg) * F.spd * 0.9
	var cy: float = F.y + sin(F.hdg) * F.spd * 0.9
	var hw: float = gm.Wv / 2 / sc
	var hh: float = gm.Hv / 2 / sc
	var CH := Render.CH
	var ok := true
	var cmin := int(floor(-gm.OCEAN_PAD / CH)) - 2
	var cmax := int(floor((D.WORLD + gm.OCEAN_PAD) / CH)) + 2
	for gy in range(int(floor((cy - hh) / CH)), int(floor((cy + hh) / CH)) + 1):
		for gx in range(int(floor((cx - hw) / CH)), int(floor((cx + hw) / CH)) + 1):
			if gx < cmin or gy < cmin or gx > cmax or gy > cmax: continue
			if not gm.baker.has_chunk(gx, gy):
				gm.baker.get_chunk(gx, gy)
				ok = false
	if sc > 0.512:   # draw_world only draws trees above this scale
		Render._tb_init()
		var pad := Render.SG * 1.5
		var deadline := Time.get_ticks_usec() + BUILD_US
		for ky in range(int(floor((cy - hh - pad) / CH)), int(floor((cy + hh + pad) / CH)) + 1):
			for kx in range(int(floor((cx - hw - pad) / CH)), int(floor((cx + hw + pad) / CH)) + 1):
				if Render._scatter_chunk(gm, kx, ky, deadline) == null: ok = false
	return ok
