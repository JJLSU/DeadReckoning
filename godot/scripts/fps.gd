class_name FpsCounter
extends CanvasLayer
## Frame-rate readout in the bottom-right corner, above everything else (menus included).
## Second line, averaged per frame: draw = time spent in the game's own drawing code
## (DrawLayer adds to draw_us), gpu = time the graphics card took to render the frame.
## If draw is close to the frame time, the CPU is the limit; if gpu is, the graphics card is.

const EVERY := 0.25   # seconds between updates, so the number is readable

static var draw_us := 0   # DrawLayer._draw time since the last readout, microseconds

var lbl := Label.new()
var acc := 0.0
var n := 0
var gpu := 0.0

func _ready() -> void:
	layer = 128
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.offset_right = -8
	lbl.offset_bottom = -4
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.9, 1.0, 0.75))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = "-- fps"
	add_child(lbl)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(dt: float) -> void:
	acc += dt
	n += 1
	gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if acc >= EVERY:
		lbl.text = "%d fps  %.1f ms\ndraw %.1f  gpu %.1f" % [roundi(n / acc), acc / n * 1000.0, draw_us / 1000.0 / n, gpu / n]
		acc = 0.0
		n = 0
		gpu = 0.0
		draw_us = 0
