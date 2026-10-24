class_name TitleScreen
extends CanvasLayer
## The title screen around the menu (Greg, 2026-10-24):
## - startup: a dark screen with "Loading…" in the lower right while the world bakes and the
##   first flyover view (terrain chunks, trees) and the music are preloaded, then a fade in;
## - a live flyover behind the menu: the Kestrel cruising between airfields over the real map,
##   with trees, haze, its shadow and clouds, drawn through the flight renderer;
## - the music in sounds/dead reckoning theme/, faded in on the title and out when a run starts.

const MUSIC_DIR := "res://sounds/dead reckoning theme/"
const MUSIC_DB := -8.0       # music volume (Greg, 2026-10-24: -4, then a little quieter)
const MUSIC_IN := 2.5        # fade in, seconds
const MUSIC_OUT := 1.2       # fade out when a run starts
const FADE_IN := 0.9         # black to the title after loading
const ALT := 70.0            # camera height of the flyover: low enough that the trees show
const PLANE_K := 1.5         # the plane is drawn this much bigger than in flight, as if flying higher (Greg, 2026-10-24: 3x, then 1.5x)
const TURN := 0.09           # flyover turn rate, rad/s (gentle)
const WAIT_MS := 6000        # show the title anyway if the first view takes longer than this
const BUILD_US := 24000      # tree build budget per frame while the screen is black

var gm
var fl := {}                 # the flyover plane: same keys the flight renderer reads from F
var cam := Vector2.ZERO
var target := -1             # airfield the flyover is heading for
var seed_v := -1             # world the flyover was started in
var music := AudioStreamPlayer.new()
var tracks: Array = []
var track := 0
var playing := false
var tw: Tween
var rect := ColorRect.new()
var fx := CanvasLayer.new()   # darkening, vignette and film grain over the flyover (Greg, 2026-10-24)
var fx_mat := ShaderMaterial.new()
var lbl := Label.new()

func _init(game) -> void:
	gm = game
	name = "Title"

func _ready() -> void:
	layer = 120   # over the menus (10), under the FPS counter (128)
	rect.color = Color(0.0627, 0.0824, 0.0588)   # the boot splash colour, so startup is one dark screen
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rect)
	lbl.text = "Loading…"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lbl.offset_right = -28
	lbl.offset_bottom = -22
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", Pen.font("600"))
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.94, 0.9, 0.81, 0.8))
	add_child(lbl)
	fx.layer = 5   # over the flyover and its clouds, under the menu (10)
	fx.visible = false
	var fr := ColorRect.new()
	fx_mat.shader = load("res://shaders/title_fx.gdshader")
	fr.material = fx_mat
	fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(fr)
	add_child(fx)
	music.bus = "Master"
	music.volume_db = -80.0
	music.finished.connect(_next_track)
	add_child(music)

# ======================================================================
# startup
# ======================================================================
## Called by game._ready once the world and textures are baked: builds the first flyover
## view under the dark screen.
func preload_all() -> void:
	_start_flight()
	var t0 := Time.get_ticks_msec()
	var held := 0
	while held < 2 and Time.get_ticks_msec() - t0 < WAIT_MS:
		await get_tree().process_frame
		held = held + 1 if _view_built() else 0

## Fades the dark loading screen away (the title menu is already up under it).
func reveal() -> void:
	_set_fps(true)
	var t := create_tween()
	t.tween_property(rect, "modulate:a", 0.0, FADE_IN).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, FADE_IN * 0.5)
	await t.finished
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _set_fps(on: bool) -> void:
	for c in gm.get_children():
		if c is FpsCounter: c.visible = on

## The dark loading screen is up: the music starts here, while the world bakes (Greg, 2026-10-24).
func loading() -> void:
	_set_fps(false)   # the dark screen shows only "Loading…" in its corner
	_load_music()
	start_music()

# ======================================================================
# music
# ======================================================================
func _load_music() -> void:
	tracks.clear()
	var names: Array = []
	for f in ResourceLoader.list_directory(MUSIC_DIR):
		var e := f.get_extension().to_lower()
		if e in ["mp3", "ogg", "wav"]: names.append(f)
	names.sort()
	for f in names:
		var s = load(MUSIC_DIR + f)
		if s is AudioStream: tracks.append(s)
	if tracks.size() == 1 and "loop" in tracks[0]: tracks[0].loop = true   # one track: loop it seamlessly
	track = randi() % maxi(1, tracks.size())

func _next_track() -> void:
	if not playing or tracks.is_empty(): return
	track = (track + 1) % tracks.size()
	music.stream = tracks[track]
	music.play()

## The title (or the win screen) is showing: fade the music in if it isn't playing.
func enter() -> void:
	if seed_v != gm.wd.SEED: _start_flight()   # a new run made a new world: start over its first airfield
	start_music()

## Fades the music in if it isn't playing.
func start_music() -> void:
	if playing or tracks.is_empty(): return
	playing = true
	if not music.playing:
		music.stream = tracks[track]
		music.volume_db = -40.0
		music.play()
	_fade_music(MUSIC_DB, MUSIC_IN)

## A run is starting: fade the music out.
func leave() -> void:
	if not playing: return
	playing = false
	_fade_music(-60.0, MUSIC_OUT, true)

func _fade_music(db: float, dur: float, stop_after: bool = false) -> void:
	if tw: tw.kill()
	tw = create_tween()
	tw.tween_property(music, "volume_db", db, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if db > music.volume_db else Tween.EASE_IN)
	if stop_after: tw.tween_callback(music.stop)

# ======================================================================
# flyover
# ======================================================================
func _start_flight() -> void:
	var st: Dictionary = gm.wd.strips[gm.wd.START]
	var h := randf() * TAU
	fl = {"x": st.x - cos(h) * 900.0, "y": st.y - sin(h) * 900.0, "hdg": h, "spd": D.PLANES[0].cruise, "alt": ALT,
		"bank": 0.0, "pitch": 0.0, "prop": 0.0, "storm": 0.0, "wind": Vector2(8, 3), "trk": h}
	target = gm.wd.START
	seed_v = gm.wd.SEED
	cam = _cam_goal()

## Next airfield to fly over: a random one a fair way off, so the route crosses open country.
func _pick_target() -> void:
	var here := Vector2(fl.x, fl.y)
	var best := -1
	var tries := 0
	while tries < 40:
		tries += 1
		var s: Dictionary = gm.wd.strips[randi() % gm.wd.strips.size()]
		if s.type == "haven" or s.type == "road" or s.id == target: continue
		var d := here.distance_to(Vector2(s.x, s.y))
		if d > 2500.0 and d < 9000.0:
			best = s.id
			break
		if best < 0: best = s.id
	target = best

## The camera leads the plane like the flight view, shifted so the plane flies in the open
## part of the screen to the right of the menu.
func _cam_goal() -> Vector2:
	var sc := Render.flight_scale(gm, ALT)
	var side: float = gm.Wv * 0.14 / sc if gm.Wv > 900 else 0.0
	return Vector2(fl.x + cos(fl.hdg) * fl.spd * 0.9 - side, fl.y + sin(fl.hdg) * fl.spd * 0.9)

func _process(_dt: float) -> void:
	fx.visible = gm.ready_done and gm.mode == "title"
	if fx.visible:
		fx_mat.set_shader_parameter("t", gm.T)
		if not fl.is_empty():   # the candlelight sits on the plane
			var sc := Render.flight_scale(gm, ALT)
			var sp := Vector2((fl.x - cam.x) * sc / gm.Wv + 0.5, (fl.y - cam.y) * sc / gm.Hv + 0.5)
			fx_mat.set_shader_parameter("center", sp)

func update(dt: float) -> void:
	if fl.is_empty(): return
	if target < 0: _pick_target()
	var s: Dictionary = gm.wd.strips[target]
	var to := Vector2(s.x - fl.x, s.y - fl.y)
	if to.length() < 350.0:
		_pick_target()
	var want := angle_difference(fl.hdg, to.angle())
	var rate := clampf(want * 0.6, -TURN, TURN)
	fl.hdg = wrapf(fl.hdg + rate * dt, -PI, PI)
	fl.trk = fl.hdg
	fl.bank = lerpf(fl.bank, clampf(rate / TURN * 0.55, -1, 1), 1.0 - exp(-dt * 1.5))
	fl.x += cos(fl.hdg) * fl.spd * dt
	fl.y += sin(fl.hdg) * fl.spd * dt
	fl.prop += dt * 30.0
	var g := _cam_goal()
	cam = cam.lerp(g, 1.0 - pow(0.92, minf(dt, 0.2) * 60.0))
	gm.camX = cam.x; gm.camY = cam.y
	# keep the terrain and trees ahead of the plane built
	var ax: float = fl.x + cos(fl.hdg) * 1500
	var ay: float = fl.y + sin(fl.hdg) * 1500
	for o in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var gx = int(floor(ax / Render.CH)) + o[0]
		var gy = int(floor(ay / Render.CH)) + o[1]
		if not gm.baker.has_chunk(gx, gy):
			gm.baker.get_chunk(gx, gy)
			break
	Render.prefetch_scatter(gm, cam.x, cam.y, Render.flight_scale(gm, ALT), fl.hdg)

func draw(idx: int, g: Pen) -> void:
	if fl.is_empty(): return
	var sc := Render.flight_scale(gm, ALT)
	var P: Dictionary = D.PLANES[0]
	match idx:
		0:
			Render.draw_world(gm, g, cam.x, cam.y, sc, gm.T)
			Render.draw_fog(gm, g, cam.x, cam.y, sc, ALT)
			var hi := fl.duplicate()   # the plane flies higher than the camera's ground view: its shadow falls farther off
			hi.alt = ALT * PLANE_K
			var psd := Vector2.from_angle(Render.SUN_ANG) * ALT * PLANE_K * 1.31
			var sh := Render.plane_shadow(gm, hi, psd, P.size * 1.7)
			g.save(); g.translate(sh.x, sh.y); g.rotate(fl.hdg); Render.draw_plane(g, P, P.size * 1.7 * sh.z, 0, true, fl.bank); g.restore()
			g.save(); g.translate(fl.x, fl.y); g.rotate(fl.hdg); Render.draw_plane(g, P, P.size * 1.7 * Render.plane_grow(P, ALT) * PLANE_K, fl.prop, false, fl.bank); g.restore()
		2:
			Render.draw_clouds(gm, g, cam.x, cam.y, sc, clampf((ALT - 45) / 60.0, 0, 1) * 0.28)

## Same check as boarding: true once the terrain and trees of the first view are built.
func _view_built() -> bool:
	var sc := Render.flight_scale(gm, ALT)
	var hw: float = gm.Wv / 2 / sc
	var hh: float = gm.Hv / 2 / sc
	var CH := Render.CH
	var ok := true
	for gy in range(int(floor((cam.y - hh) / CH)), int(floor((cam.y + hh) / CH)) + 1):
		for gx in range(int(floor((cam.x - hw) / CH)), int(floor((cam.x + hw) / CH)) + 1):
			if not gm.baker.has_chunk(gx, gy):
				gm.baker.get_chunk(gx, gy)
				ok = false
	Render._tb_init()
	var pad := Render.SG * 1.5
	var deadline := Time.get_ticks_usec() + BUILD_US
	for ky in range(int(floor((cam.y - hh - pad) / CH)), int(floor((cam.y + hh + pad) / CH)) + 1):
		for kx in range(int(floor((cam.x - hw - pad) / CH)), int(floor((cam.x + hw + pad) / CH)) + 1):
			if Render._scatter_chunk(gm, kx, ky, deadline) == null: ok = false
	return ok
