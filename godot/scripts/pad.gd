extends RefCounted
## Game controller (gamepad) support. Polled sticks and triggers plus button presses,
## mapped onto the same actions as the keyboard and mouse:
##
## On foot:  left stick move, right stick aim, RT fire, LT aim down sights,
##           LB or L3 (hold) run, A jump, B heal, X next weapon, Y board the plane,
##           RB throw a bomb, D-pad up flashlight, Back map, Start pause.
## Flying:   left stick steer, right stick up / down throttle up / down, Y cruise, A taxi back
##           (when that button shows), Back map, Start pause.
## Menus:    D-pad or left stick to move between buttons, A to press, B to go back.
##
## Whichever was used last, the controller or the mouse, drives the aim: moving the
## mouse hands it back to the mouse.

const DEAD := 0.22          # stick dead zone
const TRIG := 0.35          # trigger press threshold
const AIM_MIN := 70.0       # aim point distance from you (world px) at a light push...
const AIM_MAX := 260.0      # ...and at full tilt
const NAV_REPEAT := 0.22    # menu: seconds between moves while a stick or D-pad is held

var gm   # the game
var active := false         # last input came from a controller
var aim := Vector2.ZERO     # aim point offset from you, world px (kept when the stick is let go)
var sel: Button = null      # highlighted menu button
var sel_pos := Vector2.ZERO # where it was, to pick a neighbour when the menu rebuilds
var nav_t := 0.0
var hl: Panel = null        # highlight frame drawn round the selected button

func _init(game) -> void:
	gm = game

func dev() -> int:
	var js := Input.get_connected_joypads()
	return js[0] if js.size() > 0 else -1

func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var d := dev()
	if d < 0: return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(d, ax), Input.get_joy_axis(d, ay))
	var l := v.length()
	if l < DEAD: return Vector2.ZERO
	return v / l * minf(1.0, (l - DEAD) / (1.0 - DEAD))

func _trig(a: JoyAxis) -> float:
	var d := dev()
	if d < 0: return 0.0
	var v := Input.get_joy_axis(d, a)
	return 0.0 if v < 0.08 else v

func _held(b: JoyButton) -> bool:
	var d := dev()
	return d >= 0 and Input.is_joy_button_pressed(d, b)

# ---------------------------------------------------------------- polled inputs
func move() -> Vector2: return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
func sprint() -> bool: return _held(JOY_BUTTON_LEFT_SHOULDER) or _held(JOY_BUTTON_LEFT_STICK)
func fire() -> bool: return _trig(JOY_AXIS_TRIGGER_RIGHT) > TRIG
func ads() -> bool: return _trig(JOY_AXIS_TRIGGER_LEFT) > TRIG
func steer() -> float: return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y).x
## Throttle input -1..1 from the right stick: push up past centre to open the throttle,
## down to close it (faster the further you push); 0 inside the dead zone.
func thr_input() -> float: return -_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).y

# ---------------------------------------------------------------- events
## Button presses. Returns true when the event was used.
func event(e: InputEvent) -> bool:
	if e is InputEventMouseMotion:
		if active and e.relative.length() > 3.0: active = false   # the mouse takes over again
		return false
	if e is InputEventJoypadMotion:
		if absf(e.axis_value) > 0.5: active = true
		return false
	if not (e is InputEventJoypadButton) or not e.pressed: return false
	active = true
	var b: int = e.button_index
	var play: bool = gm.mode == "ground" or gm.mode == "flight"
	if gm.uist != "":
		match b:
			JOY_BUTTON_DPAD_UP: nav(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN: nav(Vector2.DOWN)
			JOY_BUTTON_DPAD_LEFT: nav(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT: nav(Vector2.RIGHT)
			JOY_BUTTON_A: press()
			JOY_BUTTON_B, JOY_BUTTON_START: back()
			JOY_BUTTON_BACK:
				if gm.uist == "map": gm.ui.toggle_map()
		return true
	if not play: return false
	match b:
		JOY_BUTTON_START: gm.ui.open_pause()
		JOY_BUTTON_BACK: gm.ui.toggle_map()
	if gm.mode == "ground" and gm.S:
		match b:
			JOY_BUTTON_A: gm.jump()
			JOY_BUTTON_B: gm.heal()
			JOY_BUTTON_X, JOY_BUTTON_DPAD_RIGHT: gm.swap_weapon()
			JOY_BUTTON_DPAD_LEFT: gm.start_reload()
			JOY_BUTTON_Y:
				if gm.S.nearPlane: gm.ui.open_menu()
			JOY_BUTTON_RIGHT_SHOULDER: gm.throw_bomb()
			JOY_BUTTON_DPAD_UP: gm.toggle_torch()
	elif gm.mode == "flight" and gm.F:
		match b:
			JOY_BUTTON_Y:
				if gm.flight.cruise_ok(): gm.F.cruise = not gm.F.cruise
			JOY_BUTTON_A:
				if gm.ui.btns.taxi.visible: gm.ui._hud_press("taxi")
	return true

## B / Start in a menu: the same as Escape (close the pause menu or map, settings back to
## pause); elsewhere presses the screen's own way out ("Back", "Back on foot") if it has one.
func back() -> void:
	match gm.uist:
		"pause", "map": gm.ui.close_ui()
		"settings":
			gm.ui.close_ui()
			gm.ui.open_pause()
		_:
			for bt in _buttons():
				if bt.text == "Back" or bt.text == "Back on foot":
					bt.pressed.emit()
					return

# ---------------------------------------------------------------- per frame
func update(dt: float) -> void:
	if gm.uist != "":
		_menu_frame(dt)
		return
	if hl: hl.visible = false
	sel = null
	if not active or gm.mode != "ground" or gm.S == null: return
	# right stick moves the aim point around you; let go and it stays put
	var r := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if r != Vector2.ZERO:
		aim = r.normalized() * lerpf(AIM_MIN, AIM_MAX, r.length())
	elif aim == Vector2.ZERO:
		aim = Vector2(cos(gm.S.p.ang), sin(gm.S.p.ang)) * 140.0
	var gs: float = gm.ground_scale()
	var pt: Vector2 = (gm.player_screen() + aim * gs).clamp(Vector2.ZERO, Vector2(gm.Wv, gm.Hv))
	if gm.ads_virtual:
		gm.ads_off = aim
		gm.ads_cur = pt
	gm.mouse.x = pt.x; gm.mouse.y = pt.y
	gm.mouse.active = true

# ---------------------------------------------------------------- menus
func _buttons() -> Array:
	var root: Control = gm.ui.map_ov if gm.ui.map_ov.visible else gm.ui.panel
	var out: Array = []
	_collect(root, out)
	return out

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and c.is_visible_in_tree() and not c.disabled: out.append(c)
		_collect(c, out)

func _menu_frame(dt: float) -> void:
	if not active:
		if hl: hl.visible = false
		return
	var bs := _buttons()
	if sel == null or not is_instance_valid(sel) or not bs.has(sel):
		sel = _nearest(bs, sel_pos) if bs.size() > 0 else null
	# left stick navigation, with repeat while held
	var v := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	nav_t -= dt
	if v.length() > 0.6:
		if nav_t <= 0:
			nav(Vector2(signf(v.x), 0) if absf(v.x) > absf(v.y) else Vector2(0, signf(v.y)))
			nav_t = NAV_REPEAT
	else:
		nav_t = 0.0
	_draw_hl()

func _center(b: Button) -> Vector2:
	return b.get_global_rect().get_center()

func _nearest(bs: Array, p: Vector2) -> Button:
	if p == Vector2.ZERO: return bs[0]
	var best: Button = bs[0]
	var bd := INF
	for b in bs:
		var d := _center(b).distance_to(p)
		if d < bd:
			bd = d
			best = b
	return best

## Move the highlight to the nearest button in direction dir.
func nav(dir: Vector2) -> void:
	var bs := _buttons()
	if bs.is_empty(): return
	if sel == null or not is_instance_valid(sel) or not bs.has(sel):
		sel = bs[0]
	else:
		var c := _center(sel)
		var best: Button = null
		var bd := INF
		for b in bs:
			if b == sel: continue
			var d := _center(b) - c
			var along := d.dot(dir)
			if along <= 4.0: continue
			var side := absf(d.dot(Vector2(dir.y, -dir.x)))
			var score := along + side * 2.5
			if score < bd:
				bd = score
				best = b
		if best: sel = best
	sel_pos = _center(sel)
	if gm.ui.scroll.is_ancestor_of(sel): gm.ui.scroll.ensure_control_visible(sel)
	gm.sfx("click")

func press() -> void:
	if sel == null or not is_instance_valid(sel) or sel.disabled: return
	sel_pos = _center(sel)
	sel.pressed.emit()

func _draw_hl() -> void:
	if hl == null:
		hl = Panel.new()
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color.html("#d45a9d")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(5)
		hl.add_theme_stylebox_override("panel", sb)
		gm.ui.root.add_child(hl)
	if sel == null or not is_instance_valid(sel):
		hl.visible = false
		return
	gm.ui.root.move_child(hl, -1)   # stay on top of panels opened since
	var r := sel.get_global_rect().grow(3)
	hl.global_position = r.position
	hl.size = r.size
	hl.visible = true
	sel_pos = r.get_center()
