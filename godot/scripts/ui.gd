class_name UI
extends CanvasLayer
## Menus, panels, toasts, on-screen buttons and the chart (port of the HTML overlay UI).

var game: Game
var root: Control
var dim: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var box: VBoxContainer
var toasts: VBoxContainer
var map_ov: ColorRect
var map_panel: PanelContainer
var map_cv: MapView
var map_note: Label
var btns := {}
var pal := {}

const LIGHT := {"paper": "#ebe3cb", "panel": "#f4eedd", "panel2": "#e3d9bd", "ink": "#1f2a2e", "dim": "#5f665f", "line": "#c8bb95", "magenta": "#9b2a68", "chart": "#2f5d7c", "good": "#4d6b2a", "bad": "#a3301f", "btn": "#1f2a2e", "btnink": "#f4eedd"}
const DARK := {"paper": "#141a1c", "panel": "#1b2326", "panel2": "#243034", "ink": "#e8e1cc", "dim": "#9aa39a", "line": "#34443f", "magenta": "#d45a9d", "chart": "#79a9c9", "good": "#9cc063", "bad": "#e3644c", "btn": "#e8e1cc", "btnink": "#141a1c"}

## Testing buttons (All weapons / 1,000 rounds / All trinkets / $1,000 / 1,000 gallons) in exploration mode.
## Set to false to hide them for a release build.
const DEBUG_BUTTONS := true
const DBG_KEYS := ["dbg_weapons", "dbg_ammo", "dbg_trinkets", "dbg_cash", "dbg_fuel", "dbg_plane"]

func P(k: String) -> Color: return Color.html(pal[k])

func _ready() -> void:
	layer = 10
	pal = DARK if DisplayServer.is_dark_mode() else LIGHT
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var th := Theme.new()
	th.default_font = Pen.font("400")
	th.default_font_size = 15
	root.theme = th
	# HUD buttons
	for spec in [["map", "Map"], ["pause", "Pause"], ["heal", "Heal"], ["throw", "Throw bomb"], ["cruise", "Cruise ×3"], ["board", "Board plane"], ["taxi", "Taxi back to hangar"],
			["dbg_weapons", "All Weapons"], ["dbg_ammo", "1,000 Rounds"], ["dbg_trinkets", "All Trinkets"], ["dbg_cash", "$1,000"], ["dbg_fuel", "1,000 Gallons"], ["dbg_plane", "Best Plane"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		var bg := Color(14 / 255.0, 18 / 255.0, 16 / 255.0, 0.72)
		var fs := 14
		if spec[0] == "throw": bg = Color(120 / 255.0, 40 / 255.0, 20 / 255.0, 0.8)
		if spec[0].begins_with("dbg_"):
			bg = Color(38 / 255.0, 52 / 255.0, 78 / 255.0, 0.8)   # blue-grey marks them as test-only
			fs = 13
		if spec[0] == "board":
			bg = Color.html("#9b2a68")
			fs = 16
		_style_btn(b, bg, Color.html("#efe6cf"), Color(239 / 255.0, 230 / 255.0, 207 / 255.0, 0.25), 6, Vector2(13, 9) if spec[0] != "board" else Vector2(22, 12), fs, "600")
		var key: String = spec[0]
		b.pressed.connect(func(): _hud_press(key))
		root.add_child(b)
		btns[key] = b
	# toasts
	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)
	# overlay panel
	dim = ColorRect.new()
	dim.color = Color(8 / 255.0, 10 / 255.0, 9 / 255.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	root.add_child(dim)
	panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = P("panel")
	ps.set_corner_radius_all(4)
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size = 24
	ps.shadow_offset = Vector2(0, 10)
	ps.content_margin_left = 20; ps.content_margin_right = 20; ps.content_margin_top = 20; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	dim.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	# map overlay
	map_ov = ColorRect.new()
	map_ov.color = dim.color
	map_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_ov.visible = false
	root.add_child(map_ov)
	map_panel = PanelContainer.new()
	var ms := ps.duplicate()
	ms.content_margin_left = 12; ms.content_margin_right = 12; ms.content_margin_top = 12; ms.content_margin_bottom = 12
	map_panel.add_theme_stylebox_override("panel", ms)
	map_ov.add_child(map_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	map_panel.add_child(mv)
	var mh := HBoxContainer.new()
	mv.add_child(mh)
	var mt := Label.new()
	mt.text = "Chart"
	_font(mt, "900d", 26, P("ink"))
	mt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(mt)
	var mc := _btn("Close chart", "b")
	mc.pressed.connect(close_ui)
	mh.add_child(mc)
	map_cv = MapView.new()
	map_cv.ui = self
	map_cv.clip_contents = true
	mv.add_child(map_cv)
	map_note = Label.new()
	map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_font(map_note, "400", 13, P("dim"))
	mv.add_child(map_note)

func _process(_dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(560.0, vs.x - 24.0)
	var inner := w - 40.0
	box.custom_minimum_size.x = inner
	var ch := box.get_combined_minimum_size().y
	var maxh := vs.y - 24.0 - 36.0
	box.custom_minimum_size.x = inner - (14.0 if ch > maxh else 0.0)
	scroll.custom_minimum_size = Vector2(inner, minf(ch, maxh))
	panel.size = Vector2(w, 0)
	panel.reset_size()
	panel.position = ((vs - panel.size) / 2.0).floor()
	if map_ov.visible:
		map_panel.reset_size()
		map_panel.position = ((vs - map_panel.size) / 2.0).floor()
	toasts.position = Vector2((vs.x - minf(vs.x * 0.92, 440.0)) / 2.0, 190)
	toasts.size = Vector2(minf(vs.x * 0.92, 440.0), 0)

# ---------------------------------------------------------------- styles
func _font(c: Control, w: String, size: int, col: Color) -> void:
	c.add_theme_font_override("font", Pen.font(w))
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_color_override("font_color", col)

func _sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, r: int = 3, pad: Vector2 = Vector2(13, 9)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(r)
	s.content_margin_left = pad.x; s.content_margin_right = pad.x; s.content_margin_top = pad.y; s.content_margin_bottom = pad.y
	return s

func _style_btn(b: Button, bg: Color, fg: Color, border: Color, r: int, pad: Vector2, fs: int, w: String, bw: int = -1) -> void:
	var bwv := bw if bw >= 0 else (1 if border.a > 0 else 0)
	var n := _sb(bg, border, bwv, r, pad)
	var h := _sb(bg.lightened(0.08) if bg.a > 0.1 else Color(fg.r, fg.g, fg.b, 0.08), border, bwv, r, pad)
	var pr := _sb(Color(155 / 255.0, 42 / 255.0, 104 / 255.0, 0.8), border, bwv, r, pad)
	var d := _sb(Color(bg.r, bg.g, bg.b, bg.a * 0.35), Color(border.r, border.g, border.b, border.a * 0.35), bwv, r, pad)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", Pen.font(w))
	b.add_theme_font_size_override("font_size", fs)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.35))

func _btn(text: String, kind: String, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	match kind:
		"b": _style_btn(b, P("btn"), P("btnink"), Color(0, 0, 0, 0), 3, Vector2(13, 9), 14, "600")
		"alt": _style_btn(b, Color(0, 0, 0, 0), P("ink"), P("ink"), 3, Vector2(13, 9), 14, "600")
		"go": _style_btn(b, P("magenta"), Color.WHITE, Color(0, 0, 0, 0), 3, Vector2(20, 12), 17, "700")
		"ghost": _style_btn(b, Color(0, 0, 0, 0), P("ink"), P("ink"), 3, Vector2(16, 12), 15, "600")
	return b

# ---------------------------------------------------------------- content builders
func _clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _label(text: String, w: String, size: int, col: Color, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_font(l, w, size, col)
	return l

func kind_line(t: String) -> void: box.add_child(_label(t, "600", 14, P("magenta")))
func h2(t: String) -> void: box.add_child(_label(t, "900d", 34, P("ink")))
func h4(t: String) -> void:
	var l := _label(t, "700", 15, P("chart"))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 10)
	m.add_child(l)
	box.add_child(m)
func para(t: String) -> void: box.add_child(_label(t, "400", 15, P("ink")))
func rich(bb: String) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_override("normal_font", Pen.font("400"))
	r.add_theme_font_override("bold_font", Pen.font("700"))
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	r.add_theme_color_override("default_color", P("ink"))
	box.add_child(r)
func empty(t: String) -> void: box.add_child(_label(t, "400", 14, P("dim")))
func note(t: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = P("magenta")
	bar.custom_minimum_size = Vector2(3, 0)
	h.add_child(bar)
	var l := _label(t, "400", 14, P("dim"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("font", _italic())
	h.add_child(l)
	box.add_child(h)

func _italic() -> Font:
	var f := FontVariation.new()
	f.base_font = Pen.font("400")
	f.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return f

func tags(items: Array) -> void:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 6)
	fl.add_theme_constant_override("v_separation", 6)
	for it in items:
		var on: bool = it[1]
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), P("magenta") if on else P("line"), 1, 3, Vector2(7, 2)))
		pc.add_child(_label(it[0], "400", 13, P("magenta") if on else P("dim"), false))
		fl.add_child(pc)
	box.add_child(fl)

func stats(items: Array) -> void:
	var gc := GridContainer.new()
	gc.columns = items.size()
	gc.add_theme_constant_override("h_separation", 1)
	gc.add_theme_constant_override("v_separation", 1)
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", _sb(P("line"), Color(0, 0, 0, 0), 0, 0, Vector2(1, 1)))
	wrap.add_child(gc)
	for it in items:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.add_theme_stylebox_override("panel", _sb(P("panel2"), Color(0, 0, 0, 0), 0, 0, Vector2(8, 7)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(_label(it[0], "700", 17, P("ink"), false))
		v.add_child(_label(it[1], "400", 12, P("dim"), false))
		pc.add_child(v)
		gc.add_child(pc)
	box.add_child(wrap)

func tabs(items: Array, cur: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	for it in items:
		var on: bool = it[0] == cur
		var b := Button.new()
		b.text = it[1]
		b.focus_mode = Control.FOCUS_NONE
		_style_btn(b, P("ink") if on else Color(0, 0, 0, 0), P("panel") if on else P("dim"), Color(0, 0, 0, 0), 0, Vector2(12, 8), 15, "600")
		var a: String = it[2]
		var v = it[3]
		b.pressed.connect(func(): _click(a, v))
		h.add_child(b)
	var v2 := VBoxContainer.new()
	v2.add_theme_constant_override("separation", 0)
	v2.add_child(h)
	var line := ColorRect.new()
	line.color = P("ink")
	line.custom_minimum_size = Vector2(0, 2)
	v2.add_child(line)
	box.add_child(v2)

## A list row: icon, title + small caption, then buttons [[label, kind, action, value, disabled], ...]
func row(icon: String, title: String, small: String, buttons: Array = []) -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = P("line")
	sb.border_width_bottom = 1
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var ic := _label(icon, "400", 22, P("ink"), false)
	ic.custom_minimum_size = Vector2(28, 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if icon != "": h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label(title, "400", 15, P("ink")))
	if small != "": v.add_child(_label(small, "400", 13, P("dim")))
	h.add_child(v)
	for bs in buttons:
		var b := _btn(bs[0], bs[1], bs[4] if bs.size() > 4 else false)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var a: String = bs[2]
		var val = bs[3]
		b.pressed.connect(func(): _click(a, val))
		h.add_child(b)
	box.add_child(pc)

func stack(buttons: Array) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 10)
	m.add_child(v)
	for bs in buttons:
		if bs is Callable:
			bs.call(v)
			continue
		var b := _btn(bs[0], bs[1])
		var a: String = bs[2]
		var val = bs[3] if bs.size() > 3 else null
		b.pressed.connect(func(): _click(a, val))
		v.add_child(b)
	box.add_child(m)

func foot(left: Array, right: Array) -> void:
	var h := HBoxContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 12)
	m.add_child(h)
	var b1 := _btn(left[0], left[1])
	b1.pressed.connect(func(): _click(left[2], null))
	h.add_child(b1)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var b2 := _btn(right[0], right[1], right[3])
	b2.pressed.connect(func(): _click(right[2], null))
	h.add_child(b2)
	box.add_child(m)

func _click(a: String, v) -> void:
	game.sfx("click")
	game.act(a, v)

# ---------------------------------------------------------------- panels
func show_panel(u: String) -> void:
	dim.visible = true
	game.uist = u
	scroll.scroll_vertical = 0
	game.clear_input()

func close_ui() -> void:
	dim.visible = false
	map_ov.visible = false
	game.uist = ""

func show_title(has_save: bool) -> void:
	_clear()
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -14)
	var vs := get_viewport().get_visible_rect().size
	var fs := int(clampf(vs.x * 0.15, 54, 92))
	logo.add_child(_label("Dead", "900d", fs, P("ink"), false))
	logo.add_child(_label("Reckoning", "900d", fs, P("magenta"), false))
	box.add_child(logo)
	box.add_child(_label("Fly supplies between the last working airstrips. Loot what you can on the ground. Find Haven.", "400", 16, P("dim")))
	var bs: Array = []
	if has_save: bs.append(["Continue", "go", "continue"])
	bs.append(["New run", "ghost" if has_save else "go", "newgame"])
	bs.append(["How to fly", "ghost", "help"])
	bs.append(["Display settings", "ghost", "settings"])
	bs.append(["Quit to desktop", "ghost", "quit_desktop"])
	stack(bs)
	show_panel("title")

func show_help() -> void:
	_clear()
	h2("How to fly")
	help_content()
	stack([["Back", "go", "backtitle"]])
	show_panel("title")

const HELP := [
	["Flying", "Drag left or right anywhere on the screen to steer, or use A and D. The bar on the right is the throttle: drag it, or use W and S."],
	["Landing", "Line up with a runway, then pull the throttle back to the pink approach mark, about a third, roughly 15 km out, and the plane settles onto the runway. A marker on the ground shows where you will touch down. Green means runway, amber means off the runway, red means you are sinking too fast. Wind pushes you sideways, so point the nose into it to hold your line. Touching down anywhere but a runway kills you, with one exception: a gentle landing lined up on a straight road. There is no pump or mechanic out there."],
	["Jobs", "Delivery jobs pay when you land at the destination. Rescue jobs send you to find a survivor hiding in a town. Walk up to them, lead them back to the plane, and fly them home. They can be bitten on the way."],
	["The dead", "Bloated ones burst into toxic gas when they die, so shoot them from range. Pale screamers call more of the dead when they see you, so drop them first."],
	["Flying", "Once you are above about 2,000 feet and clear of weather, click Cruise or press C to fly three times faster. When you are low and near a charted runway, approach assist steers you onto the centerline as long as you let go of the stick. Radio maydays pop up on long flights and pay well if you land there in time."],
	["Weather and damage", "Storms drift across the map and show on your minimap as blue patches. Their cores shake the plane apart. Flying low over towns draws gunfire that can hole the hull or the fuel lines. Hard landings cost hull too. Mechanics patch everything for cash."],
	["Noise", "Your landing, gunfire, running, explosions, and siphoning fuel all fill the noise meter. At each mark a new wave of the dead arrives from the edges of the map. When it fills, the horde comes and does not stop. The crossbow and machete make no noise. Loot what you can and leave in time."],
	["On foot", "WASD to move, aim with the mouse and click to fire. Hold Shift to run, hold right mouse to aim down sights for steadier, slower aim, Space to jump, 1–5 to select Revolver, Pump shotgun, Lever rifle, Submachine gun, or Assault rifle; 6 for Double-barrel, 7 for Crossbow, Q to cycle owned weapons, H to heal, G to throw a pipe bomb, E to board the plane. Jumping clears sandbags and low fences inside the site, but not cars or the outer fence, and nothing can bite you in the air. Running is loud, and some of the bodies on the ground are not dead. Walk over containers to burst them open, then collect what spills out. Rarer finds glow green, blue, or gold. Locked safes take a spare part or a bomb and hold the best loot, including trinkets with permanent perks. Houses sometimes hide stashes under loose floorboards that only show up close. Footlockers hold ammo, bombs, and armor. Registers hold cash and jewelry. Toolboxes hold spare parts for field repairs. Medicine cabinets hold bandages and antibiotics. Every airfield has a small town beside it with shops and houses to search. Roofs lift away when you step inside. Each shop stocks by its trade: the pharmacy has medicine, the hardware store has parts, the gun shop has ammo. Traders pay different prices for goods at each field. Old charts reveal fields and narrow down Haven. The dead sometimes drop rounds. When you run dry you fight with a machete. Red barrels explode when shot. Gunfire draws more of the dead the longer you stay. Night falls at 18:00, and the dead move faster in the dark. You can sleep in the cockpit from the hangar tab. Return to the plane to refuel, take jobs, and upgrade."],
	["The goal", "Haven lies in one of the far corners of the map, across empty country no starter plane can cross. Old charts narrow down which. Earn a bigger airframe or bigger tanks first."],
	["Keys", "M opens the chart. Esc or P pauses. Mouse wheel or + and − zoom the view, 0 resets it. Ctrl with + and − changes the interface size. F11 toggles fullscreen; Esc leaves fullscreen."]]

func help_content() -> void:
	for it in HELP:
		var dt := _label(it[0], "700", 14, P("chart"))
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 6)
		m.add_child(dt)
		box.add_child(m)
		box.add_child(_label(it[1], "400", 14, P("ink")))

func open_pause() -> void:
	if game.uist != "": return
	var G: Dictionary = game.G
	_clear()
	h2("Paused")
	note(game.objective())
	stack([["Resume", "go", "resume"], ["Display settings", "ghost", "settings"],
		["Save and quit to desktop", "ghost", "save_quit_desktop"],
		["Quit to desktop without saving", "ghost", "quit_desktop"]])
	h4("Trinkets, %d of %d" % [G.trinkets.size(), D.TRINKETS.size()])
	if G.trinkets.size():
		for x in D.TRINKETS:
			if G.trinkets.has(x[0]): row("⭐", x[1], x[2])
	else:
		empty("None yet. Safes and hidden stashes are the best places to look.")
	help_content()
	var diff_tabs := func(v: VBoxContainer) -> void:
		var hd := _label("Difficulty", "700", 15, P("chart"))
		v.add_child(hd)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 0)
		for i in D.DIFFS.size():
			var on: bool = G.diff == i
			var b := Button.new()
			b.text = D.DIFFS[i].name
			b.focus_mode = Control.FOCUS_NONE
			_style_btn(b, P("ink") if on else Color(0, 0, 0, 0), P("panel") if on else P("dim"), Color(0, 0, 0, 0), 0, Vector2(12, 8), 15, "600")
			var idx := i
			b.pressed.connect(func(): _click("diff", idx))
			h.add_child(b)
		v.add_child(h)
		v.add_child(_label(D.DIFFS[G.diff].desc, "400", 14, P("dim")))
	stack([diff_tabs, ["Turn sound off" if game.synth.on else "Turn sound on", "ghost", "sound"], ["Save and quit to title", "ghost", "quit"]])
	show_panel("pause")

func show_settings(_from = null) -> void:
	_clear()
	h2("Display")
	var gm := game
	row("🔍", "Zoom: %d%%" % roundi(gm.zoom * 100), "How close the camera sits, in the air and on foot. Mouse wheel, or + and −.",
		[["−", "alt", "zoom", -1], ["Reset", "alt", "zoom", 0], ["+", "alt", "zoom", 1]])
	row("Aa", "Interface size: %d%%" % roundi(gm.ui_scale * 100), "Text, buttons and gauges. Ctrl with + and −.",
		[["−", "alt", "uiscale", -1], ["Reset", "alt", "uiscale", 0], ["+", "alt", "uiscale", 1]])
	row("🖥", "Window: %s" % ("fullscreen" if gm.fullscreen else gm.window_label()), "Cycle sizes. F11 toggles fullscreen; Esc leaves it.",
		[["Next size", "alt", "winsize", null], ["Windowed" if gm.fullscreen else "Fullscreen", "alt", "fullscreen", null]])
	stack([["Back", "go", "settingsback"]])
	if gm.uist != "settings":
		show_panel("settings")

func refresh_settings() -> void:
	if game.uist == "settings":
		var sv := scroll.scroll_vertical
		show_settings()
		scroll.scroll_vertical = sv

func show_dead(kind: String) -> void:
	var G: Dictionary = game.G
	var d: Array = D.DEATHS.get(kind, D.DEATHS.crash)
	_clear()
	kind_line(d[0])
	h2("Dead reckoning")
	para(d[1])
	empty("%d km flown. %d deliveries. %d put down." % [U.km(G.stats.dist), G.stats.deliv, G.stats.kills])
	stack([["Wake up at " + game.strip(G.strip).name, "go", "retry"], ["Start a new run", "ghost", "newgame"]])
	empty("Waking up costs some of your cash and anything you gathered since your last takeoff or landing.")
	show_panel("dead")

func show_win() -> void:
	var G: Dictionary = game.G
	_clear()
	kind_line("Haven")
	h2("You made it")
	para("Floodlights, a chain-link gate, and people who wave you in instead of raising a rifle. The rumor was true.")
	empty("%d km flown in %d flights. %d deliveries. %d put down. Arrived in the %s." % [U.km(G.stats.dist), G.stats.flights, G.stats.deliv, G.stats.kills, D.PLANES[G.plane].name])
	stack([["Fly a new run", "go", "newgame"]])
	show_panel("win")

func open_menu(tab: String = "") -> void:
	if tab != "": game.menu_tab = tab
	render_menu()
	dim.visible = true
	game.uist = "menu"
	game.clear_input()

func _pips(n: int) -> String: return "●".repeat(n) + "○".repeat(5 - n)
func _type_label(s: Dictionary) -> String:
	return {"dirt": "Dirt strip", "regional": "Regional field", "airport": "Airport", "haven": "Haven", "road": "Road"}[s.type]

func render_menu() -> void:
	var G: Dictionary = game.G
	var s: Dictionary = game.strip(G.strip)
	var Pp: Dictionary = game.PS()
	var known: Dictionary = game.known
	var sc := scroll.scroll_vertical
	_clear()
	var arch: String = D.ARCH.get(s.get("arch", ""), _type_label(s))
	kind_line("%s, danger %s" % [arch, _pips(s.danger)])
	h2(s.name)
	var tg: Array = []
	tg.append(["Fuel pump, $%d/gal" % s.fuelPrice, true] if s.fuel else ["No fuel pump", false])
	if s.shop: tg.append(["Mechanic and trader", true])
	if s.dealer: tg.append(["Aircraft dealer", true])
	tags(tg)
	note("Chalked on the hangar door: “%s”" % String(D.NOTES[int(s.seed) % D.NOTES.size()]).replace("{Dir}", World.haven_dir_name().capitalize()))
	stats([["$%d" % G.cash, "Cash"], ["%.1f/%d" % [G.fuel, int(Pp.fuelCap)], "Gallons aboard"], ["%d km" % U.km(game.range_now()), "Range now"], [str(int(floor(G.carried))), "Gallons in cans"], ["%d%%" % int(ceil(G.hull)), "Hull, leaking" if G.leak > 0 else "Hull"]])
	var mt: String = game.menu_tab
	tabs([["contracts", "Contracts", "tab", "contracts"], ["fuel", "Fuel", "tab", "fuel"], ["shop", "Trader", "tab", "shop"], ["hangar", "Hangar", "tab", "hangar"]], mt)
	if mt == "fuel":
		var need := maxf(0, Pp.fuelCap - G.fuel)
		para("The %s holds %d gallons, about %d km at cruise." % [Pp.name, int(Pp.fuelCap), U.km(game.range_full())])
		row("🛢️", "Pour your cans into the tanks", "%d gal carried" % int(floor(G.carried)), [["Pour", "b", "pour", null, G.carried < 1 or need < 0.1]])
		if s.fuel:
			var c5 := minf(5, need)
			var cf := int(ceil(need))
			row("⛽", "Buy 5 gallons", "$%d" % int(ceil(c5 * s.fuelPrice)), [["Buy", "b", "buy5", null, need < 0.1 or G.cash < int(ceil(c5 * s.fuelPrice))]])
			row("⛽", "Fill the tanks", "%d gal for $%d" % [cf, cf * s.fuelPrice], [["Fill", "b", "fill", null, need < 0.1 or G.cash < s.fuelPrice]])
		else:
			empty("No pump here. Fuel comes from what you can scavenge.")
	elif mt == "contracts":
		h4("Aboard, %d of %d" % [G.contracts.size(), Pp.slots])
		if G.contracts.is_empty(): empty("Nothing aboard. Take a job from the board below.")
		for i in G.contracts.size():
			var c: Dictionary = G.contracts[i]
			var d: Dictionary = game.strip(game.contract_target(c))
			var t: String
			if c.get("type", "") == "rescue":
				t = ("Find %s in %s at %s" % [c.who, D.WHERE[c.where], d.name]) if c.stage == "pickup" else ("%s to %s" % [c.who, d.name])
			else:
				t = "%s to %s" % [c.what, d.name]
			row(c.icon, t, "%d km %s, pays $%d" % [U.km(Vector2(d.x - s.x, d.y - s.y).length()), game.bearing(s, d), c.reward],
				[["On course" if G.nav == d.id else "Set course", "alt", "nav", d.id], ["Drop", "alt", "dump", i]])
		h4("Job board")
		if G.offers.is_empty(): empty("The board is bare. Fields within your range have nothing posted.")
		for i in G.offers.size():
			var c: Dictionary = G.offers[i]
			var d: Dictionary = game.strip(game.contract_target(c))
			var dd := Vector2(d.x - s.x, d.y - s.y).length()
			var dn: String = d.name if known.has(d.id) else "an uncharted field"
			var t: String = ("Rescue %s, hiding in %s at %s, and fly them back here" % [c.who, D.WHERE[c.where], dn]) if c.get("type", "") == "rescue" else ("Fly %s to %s" % [c.what, dn])
			row(c.icon, t, "%d km %s, danger %s, pays $%d%s" % [U.km(dd), game.bearing(s, d), _pips(d.danger), c.reward, ", beyond current fuel" if dd > game.range_now() else ""],
				[["Accept", "b", "accept", i, G.contracts.size() >= Pp.slots]])
	elif mt == "shop":
		if not s.shop:
			empty("Nobody here but the dead. Regional fields and airports have mechanics and traders.")
		else:
			var tp: int = 450 * (G.tanks + 1) + G.plane * 200
			var ep: int = 600 * (G.engine + 1)
			h4("Aircraft")
			row("🛢️", "Auxiliary tank, %d of %d fitted" % [G.tanks, Pp.tankMax], "+%d gallons%s" % [Pp.tankStep, (", $%d" % tp) if G.tanks < Pp.tankMax else ""],
				[["Maxed" if G.tanks >= Pp.tankMax else "Fit", "b", "tank", null, G.tanks >= Pp.tankMax or G.cash < tp]])
			row("⚙️", "Engine overhaul, %d of 2 done" % G.engine, "+8%% speed and range%s" % ((", $%d" % ep) if G.engine < 2 else ""),
				[["Maxed" if G.engine >= 2 else "Overhaul", "b", "engine", null, G.engine >= 2 or G.cash < ep]])
			var rc: int = game.repair_cost()
			row("🛠️", "Patch the airframe and fuel lines", "Hull at %d%%%s. $%d" % [int(ceil(G.hull)), ", fuel leaking" if G.leak > 0 else "", rc],
				[["Sound" if rc <= 0 else "Repair", "b", "repair", null, rc <= 0 or G.cash < rc]])
			h4("Weapons and supplies")
			for i in D.WEAPONS.size():
				var w: Dictionary = D.WEAPONS[i]
				var own: bool = G.weapons.has(i)
				var cap := ("%d pellets" % w.pel) if w.pel > 1 else ("%d damage" % int(w.dmg))
				var st := ("in hand" if G.weapon == i else "owned") if own else ("$%d" % w.price)
				row("🔫" if i == 0 else ("💥" if i == 1 else "🎯"), "[%d] %s" % [i + 1, w.name], "%s, %s" % [cap, st],
					[[("Equipped" if G.weapon == i else "Equip") if own else "Buy", "b", "weapon", i, G.weapon == i or (not own and G.cash < w.price)]])
			row("🧷", "Box of 30 rounds", "$35, you have %d" % G.ammo, [["Buy", "b", "ammo", null, G.cash < 35]])
			row("📦", "Case of 100 rounds", "$100", [["Buy", "b", "ammo100", null, G.cash < 100]])
			row("🩹", "Medkit", "$60, you have %d, heals 45" % G.med, [["Buy", "b", "med", null, G.cash < 60]])
			row("🩹", "Bandage", "$25, you have %d, heals 20" % G.band, [["Buy", "b", "band", null, G.cash < 25]])
			row("💣", "Pipe bomb", "$60, you have %d" % G.bombs, [["Buy", "b", "bomb", null, G.cash < 60]])
			h4("Sell")
			var any := false
			for g in D.GKEYS:
				var n := int(G.goods.get(g, 0))
				if n == 0: continue
				any = true
				var pr: int = game.good_price(s, g)
				var base: int = D.GOODS[g][1]
				row("📦", "%d %s" % [n, D.GOODS[g][0]], "$%d each here%s" % [pr, ", a good price" if pr > base * 1.25 else (", a poor price" if pr < base * 0.8 else "")], [["Sell all", "b", "sell", g]])
			if G.parts > 0:
				any = true
				row("🔩", "%d spare parts" % G.parts, "$15 each. You can also use them to patch the plane anywhere.", [["Sell one", "alt", "sellparts", null]])
			if not any: empty("Nothing to sell. Registers, lockers, and medicine cabinets hold goods that traders want.")
	elif mt == "hangar":
		var pl: Dictionary = D.PLANES[G.plane]
		rich("[b]%s.[/b] %s %d cargo slot%s, %d gal, top speed %d kt." % [Pp.name, pl.desc, Pp.slots, "s" if Pp.slots > 1 else "", int(Pp.fuelCap), int(round(Pp.max * 0.75))])
		var bs: Array = [["Patch", "b", "fieldfix", null, G.parts < 1 or G.hull >= 100]]
		if G.leak > 0: bs.append(["Seal leak", "b", "fieldleak", null, G.parts < 2])
		row("🔩", "Field repair with spare parts", "You have %d. One part patches 15%% hull. Two parts seal a fuel leak." % G.parts, bs)
		var hr := fmod(G.time / 60.0, 24.0)
		var ok := hr >= 17 or hr < 5
		row("🌙", "Sleep in the cockpit until dawn", "Heals 40. The yard fills back up by morning." if ok else ("You can bed down after 17:00. It is %s." % game.clock()), [["Sleep", "b", "sleep", null, not ok]])
		if not s.dealer:
			empty("No aircraft for sale here. Airports sometimes have a dealer.")
		else:
			var trade := int(floor(D.PLANES[G.plane].price * 0.5))
			for i in D.PLANES.size():
				if i <= G.plane: continue
				var p2: Dictionary = D.PLANES[i]
				var cost: int = p2.price - trade
				var rng: float = p2.fuel / (p2.burn * 0.83) * 0.8 * p2.max
				row("✈️", p2.name, "%s %d slots, %d gal, about %d km range. $%d after trade-in." % [p2.desc, p2.slots, int(p2.fuel), U.km(rng), cost], [["Buy", "b", "plane", i, G.cash < cost]])
			if G.plane == D.PLANES.size() - 1: empty("You already fly the best thing on the lot.")
			empty("A new airframe comes without your tank and engine work.")
	foot(["Back on foot", "ghost", "close"], ["Take off", "go", "takeoff", G.fuel < 0.5])
	await get_tree().process_frame
	scroll.scroll_vertical = sc

# ---------------------------------------------------------------- toasts
func toast(msg: String, cls: String = "") -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(14 / 255.0, 18 / 255.0, 16 / 255.0, 0.82)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 3
	sb.border_color = Color.html({"good": "#9cc063", "bad": "#e3644c", "mag": "#d45a9d"}.get(cls, "#d9a441"))
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 7; sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _label(msg, "500", 14, Color.html("#efe6cf"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := get_viewport().get_visible_rect().size
	l.custom_minimum_size.x = minf(Pen.measure(msg, 14, "500") + 2, minf(vs.x * 0.92, 440.0) - 24)
	pc.add_child(l)
	toasts.add_child(pc)
	while toasts.get_child_count() > 3:
		var c := toasts.get_child(0)
		toasts.remove_child(c)
		c.queue_free()
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.95)
	tw.tween_callback(pc.queue_free)

# ---------------------------------------------------------------- HUD buttons
func _hud_press(k: String) -> void:
	var gm := game
	match k:
		"cruise":
			if gm.F and gm.cruise_ok(): gm.F.cruise = not gm.F.cruise
		"throw": gm.throw_bomb()
		"map": toggle_map()
		"pause": open_pause()
		"heal": gm.heal()
		"board": open_menu()
		"taxi": gm.enter_ground(gm.strip(gm.G.strip))
		"dbg_weapons": gm.dbg_all_weapons()
		"dbg_ammo": gm.dbg_ammo()
		"dbg_trinkets": gm.dbg_all_trinkets()
		"dbg_cash": gm.dbg_cash()
		"dbg_fuel": gm.dbg_fuel()
		"dbg_plane": gm.dbg_best_plane()

func update_buttons() -> void:
	var gm := game
	var play: bool = gm.uist == "" and (gm.mode == "flight" or gm.mode == "ground")
	var G = gm.G
	var F = gm.F
	var S = gm.S
	var vs := get_viewport().get_visible_rect().size
	var gr: bool = play and gm.mode == "ground"
	var fl: bool = play and gm.mode == "flight" and F != null
	btns.map.visible = play
	btns.pause.visible = play
	btns.heal.visible = gr and (G.med > 0 or G.band > 0) and G.hp < 100
	btns.throw.visible = gr and G.bombs > 0
	var ok: bool = fl and gm.cruise_ok()
	btns.cruise.visible = ok
	if not ok and F: F.cruise = false
	var on: bool = F != null and F.cruise
	btns.cruise.text = "Cruise ×3 on" if on else "Cruise ×3"
	btns.cruise.add_theme_stylebox_override("normal", _sb(Color(155 / 255.0, 42 / 255.0, 104 / 255.0, 0.85) if on else Color(14 / 255.0, 18 / 255.0, 16 / 255.0, 0.72), Color.html("#d45a9d") if on else Color(239 / 255.0, 230 / 255.0, 207 / 255.0, 0.25), 1, 6, Vector2(13, 9)))
	if btns.throw.visible: btns.throw.text = "Throw bomb (%d)" % G.bombs
	btns.board.visible = gr and S != null and S.nearPlane
	btns.taxi.visible = fl and F.onGround and F.departing and F.spd < 3
	for k in btns: btns[k].reset_size()
	btns.map.position = Vector2(10, vs.y - 12 - btns.map.size.y)
	btns.pause.position = Vector2(78, vs.y - 12 - btns.pause.size.y)
	btns.cruise.position = Vector2(146, vs.y - 12 - btns.cruise.size.y)
	btns.heal.position = Vector2(10, vs.y - 58 - btns.heal.size.y)
	btns.throw.position = Vector2(vs.x - 12 - btns.throw.size.x, vs.y - 22 - btns.throw.size.y)
	btns.board.position = Vector2((vs.x - btns.board.size.x) / 2, vs.y - 22 - btns.board.size.y)
	btns.taxi.position = Vector2((vs.x - btns.taxi.size.x) / 2, vs.y - 22 - btns.taxi.size.y)
	# testing buttons: right side, stacked under the place name
	var dy := 38.0
	for k in DBG_KEYS:
		var b: Button = btns[k]
		b.visible = DEBUG_BUTTONS and gr
		b.position = Vector2(vs.x - 12 - b.size.x, dy)
		dy += b.size.y + 6

# ---------------------------------------------------------------- map
func toggle_map() -> void:
	if game.uist == "map":
		close_ui()
		return
	if game.uist != "": return
	game.uist = "map"
	map_ov.visible = true
	game.clear_input()
	var vs := get_viewport().get_visible_rect().size
	var ms := maxf(220, minf(minf(vs.x - 48, vs.y - 170), 760))
	map_cv.custom_minimum_size = Vector2(ms, ms)
	map_note.custom_minimum_size.x = ms
	map_note.text = "Click a charted field to set your course. Magenta rings are fields, filled ones sell fuel. Amber rings are delivery stops. Gray squares are road landings you made. Blue patches are storms, which drift. The dashed circle is how far your fuel reaches now."
	map_cv.queue_redraw()


class MapView extends Control:
	var ui: UI

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var gm: Game = ui.game
			var ms := size.x
			var k := ms / D.WORLD
			var best = null
			var bd := 22.0
			for s in gm.wd.strips:
				if not gm.known.has(s.id): continue
				var d := Vector2(s.x * k - e.position.x, s.y * k - e.position.y).length()
				if d < bd:
					bd = d
					best = s
			if best:
				gm.G.nav = -1 if gm.G.nav == best.id else best.id
				queue_redraw()
				gm.toast(("Course set to %s." % best.name) if gm.G.nav >= 0 else "Course cleared.", "mag")

	func _process(_dt: float) -> void:
		if visible and ui.map_ov.visible: queue_redraw()

	func _draw() -> void:
		var gm: Game = ui.game
		if gm.G == null: return
		var g := Pen.new(self)
		var ms := size.x
		var k := ms / D.WORLD
		var G: Dictionary = gm.G
		var wd: World = gm.wd
		if gm.baker.overview: g.tex(gm.baker.overview, 0, 0, ms, ms)
		g.rect(0, 0, ms, ms, Color(235 / 255.0, 227 / 255.0, 203 / 255.0, 0.18))
		var gl := PackedVector2Array()
		for i in range(1, 6):
			var q := i * ms / 6
			gl.append_array([Vector2(q, 0), Vector2(q, ms), Vector2(0, q), Vector2(ms, q)])
		g.lines(gl, Color(20 / 255.0, 30 / 255.0, 34 / 255.0, 0.25), 1)
		var me := Vector3.ZERO
		var has_h := false
		if gm.mode == "flight" and gm.F:
			me = Vector3(gm.F.x, gm.F.y, gm.F.hdg)
			has_h = true
		else:
			var st: Dictionary = gm.strip(G.strip)
			me = Vector3(st.x, st.y, 0)
		g.dashed_arc(me.x * k, me.y * k, gm.range_now() * k, 0, TAU, Color(155 / 255.0, 42 / 255.0, 104 / 255.0, 0.9), 1.5, 5, 4)
		for s in wd.STORMS:
			var q: Vector2 = wd.storm_pos(s)
			g.circle(q.x * k, q.y * k, s.r * k, Color(50 / 255.0, 60 / 255.0, 80 / 255.0, 0.28))
			g.ring(q.x * k, q.y * k, s.r * k, Color(50 / 255.0, 60 / 255.0, 80 / 255.0, 0.5), 1)
		var ink := Color.html("#1f2a2e")
		if not gm.known.has(0):
			# one rumour ring per corner, shown once the first old chart has been read
			var rings: Array = G.get("rings", [])
			for i in mini(rings.size(), wd.RUMORS.size()):
				var rr: float = float(rings[i])
				var rc: Vector2 = wd.ring_center(i, rr)
				g.dashed_arc(rc.x * k, rc.y * k, rr * k, 0, TAU, Color(20 / 255.0, 30 / 255.0, 34 / 255.0, 0.8), 1.5, 5, 4)
				g.text_base("Haven?", rc.x * k, rc.y * k + 4, 13, ink, 0, "700")
		var dests := {}
		for c in G.contracts: dests[gm.contract_target(c)] = true
		var mag := Color.html("#9b2a68")
		for s in wd.strips:
			if not gm.known.has(s.id): continue
			var x: float = s.x * k
			var y: float = s.y * k
			if s.type == "road":
				g.rect(x - 3, y - 3, 6, 6, Color.html("#5f665f"))
				continue
			if s.type == "haven":
				g.circle(x, y, 8, Color.html("#4d6b2a"))
				g.text_base("Haven", x, y - 12, 12, Color.WHITE, 0, "700")
				continue
			var r := 6.0 if s.type == "airport" else (5.0 if s.type == "regional" else 4.0)
			g.ring(x, y, r, mag, 2)
			if s.fuel: g.circle(x, y, r - 2.5, mag)
			if dests.has(s.id): g.ring(x, y, r + 5, Color.html("#d9a441"), 2.5)
			if G.nav == s.id: g.line(me.x * k, me.y * k, x, y, Color.WHITE, 1.5)
			if ms > 420 or dests.has(s.id) or G.nav == s.id or s.id == G.strip:
				g.text_base(s.name, x + r + 4, y + 4, 11, Color(20 / 255.0, 26 / 255.0, 28 / 255.0, 0.85), -1, "600")
		g.save()
		# out over the open ocean you can be off the chart: pin the marker to its edge
		g.translate(clampf(me.x * k, 8, ms - 8), clampf(me.y * k, 8, ms - 8))
		if has_h:
			g.rotate(me.z)
			var arr := PackedVector2Array([Vector2(9, 0), Vector2(-6, -6), Vector2(-3, 0), Vector2(-6, 6)])
			g.poly(arr, Color.WHITE)
			var ac := arr.duplicate(); ac.append(arr[0])
			g.polyline(ac, ink, 1.5)
		else:
			g.circle(0, 0, 5, Color.WHITE)
			g.ring(0, 0, 5, ink, 2)
		g.restore()
		g.text_base("N", ms - 18, 22, 18, ink, 0, "900d")
