class_name Radio
extends Node
## The plane's radio (Greg, 2026-10-24). In flight, with a destination set, you hear that
## airfield's station: friendly fields play the human radio folder with soft static under it
## (so it isn't too clean), survivor-held fields the military radio, zombie fields the zombie
## radio with a clip from its background folder playing under it. Each clip plays for CLIP_T
## seconds (or to its end if shorter), then STATIC_T seconds of static, then the next clip,
## crossfading over XF each way. Setting a new destination cuts straight to static, then fades
## into a clip from the new field's station. A cleared field that nobody holds yet is just
## static. The volume knob sits in the bottom-right corner, under the throttle; turning it all
## the way down, or clicking it, mutes the radio. The setting is kept in user://radio.cfg.
## Left of the knob, the COMM panel names the field you're tuned to and shows the signal level;
## the NAV panel above it names your destination. Left-click a field on the chart or minimap to
## set your course (NAV), right-click one to tune the radio to it (COMM, G.comm). Until you
## tune it, or after right-clicking the tuned field again, the radio follows your course.
## Static files differ a lot in loudness, so the game evens them out as they play (Greg,
## 2026-10-24): each static player has its own bus that measures what comes through and turns
## the file up or down to STATIC_RMS. A hard limiter on the bus keeps loud crackles from clipping.

const DIR := "res://sounds/"
const STATIONS := {"human": "human radio", "military": "military radio", "zombie": "zombie radio"}
const STATIC_DIR := "static radio"
const BG_DIR := "zombie radio/background"   # played under the zombie station's clips
const CLIP_T := Vector2(30.0, 60.0)    # seconds of each clip, fades included (military and zombie)
const HUMAN_END := 5.0                 # music (human station) plays to this many seconds before the end of the track
const STATIC_T := Vector2(2.5, 5.0)    # seconds of static between clips, from the start of the fade into it
const XF := 1.0                        # s: crossfade between static and a clip, each way
const BG_LEVEL := {"zombie": 1.0, "human": 0.6}   # loudness of the layer under the clip: zombie background, soft static under music
const CLIP_START := Vector2(5.0, 10.0)   # s into each clip where it starts playing...
const WHOLE := 30.0                    # ...but a track this long or shorter plays start to finish
const CLIP_LEVEL := {"zombie": 0.6}    # clip loudness by station (others 1.0): the breathing sits under the background
const LEVEL := 0.7                     # loudness with the knob turned right up
const BUS := "Radio"
const STATIC_RMS := -32.0              # dB: the loudness every static file is evened out to
const GAIN_MAX := 8.0                  # most a quiet static file is turned up (x), so a silent patch isn't boosted to a roar
const LEARN_FAST := 0.15               # s: how quickly a file's loudness is learned on first hearing...
const LEARN_SLOW := 2.0                # ...and then followed (long files drift)
const CFG := "user://radio.cfg"

var gm: Game
var vol := 0.6      # knob, 0..1
var muted := false
var files := {}     # folder -> Array of res:// paths
var station := ""   # station playing now ("" = off, "static" = static only)
var dest := -1      # strip id it's tuned to
var clip_p: AudioStreamPlayer
var bg_p: AudioStreamPlayer
var hiss_p: AudioStreamPlayer
var g_clip := 0.0   # fade levels, 0..1
var g_hiss := 0.0
var phase := ""     # "clip" or "static"
var left := 0.0     # seconds left of this clip or static gap
var next_path := "" # clip loading in the background for after the static
var last_path := "" # not the same clip twice running
var knob: Knob
var comm: Comm
var nav: Comm
var dest_name := ""
var nav_name := ""
var nav_km := -1
var nav_freq := -1  # frequencies for the boxes, in tenths of a MHz (-1 none)
var comm_freq := -1
var statics := {}   # static file path -> AudioStream, loaded in the background at startup
var loud := {}      # static file path -> [its loudness (linear RMS) as measured so far, seconds measured]
var cap_h: AudioEffectCapture   # what hiss_p sends out
var cap_b: AudioEffectCapture   # what bg_p sends out
var was_at := {}    # player -> the volume it was played at last frame

func _init(game: Game) -> void:
	gm = game

func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, BUS)
		AudioServer.set_bus_send(bi, "Master")
	cap_h = _static_bus("RadioStatic")
	cap_b = _static_bus("RadioStatic2")
	clip_p = AudioStreamPlayer.new()
	clip_p.bus = BUS
	add_child(clip_p)
	bg_p = AudioStreamPlayer.new()
	bg_p.bus = BUS
	bg_p.finished.connect(func(): if g_clip > 0.0: bg_p.play())   # loops while the clip lasts
	add_child(bg_p)
	hiss_p = AudioStreamPlayer.new()
	hiss_p.bus = "RadioStatic"
	hiss_p.finished.connect(func(): if g_hiss > 0.0: hiss_p.play())   # short static files loop
	add_child(hiss_p)
	for k in STATIONS.values() + [STATIC_DIR, BG_DIR]: files[k] = _list(DIR + k)
	for p in files[STATIC_DIR]: ResourceLoader.load_threaded_request(p)   # some static files are big: load them now, off the main thread
	_load_setting()
	knob = Knob.new(self)
	knob.visible = false
	gm.ui.root.add_child(knob)
	comm = Comm.new(self, false)
	comm.visible = false
	gm.ui.root.add_child(comm)
	nav = Comm.new(self, true)
	nav.visible = false
	gm.ui.root.add_child(nav)

## A bus for one static player, sending to the radio bus: it measures the sound (capture) and
## stops peaks from clipping once a quiet file has been turned up (limiter).
func _static_bus(nm: String) -> AudioEffectCapture:
	var bi := AudioServer.get_bus_index(nm)
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, nm)
		AudioServer.set_bus_send(bi, BUS)
		var c := AudioEffectCapture.new()
		c.buffer_length = 0.5
		AudioServer.add_bus_effect(bi, c)
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(bi, lim)
	return AudioServer.get_bus_effect(bi, 0) as AudioEffectCapture

## The sound files in a folder. ResourceLoader.list_directory also works in an exported game,
## where the folder holds only .import/.remap files.
func _list(path: String) -> Array:
	var out := []
	for f in ResourceLoader.list_directory(path):
		if f.get_extension().to_lower() in ["mp3", "ogg", "wav"]: out.append(path + "/" + f)
	return out

func _load_setting() -> void:
	var f := FileAccess.open(CFG, FileAccess.READ)
	if f:
		var p := f.get_line().split(" ")
		if p.size() >= 1 and p[0].is_valid_float(): vol = clampf(float(p[0]), 0.0, 1.0)
		muted = p.size() >= 2 and p[1] == "muted"
	_apply()

func _save_setting() -> void:
	var f := FileAccess.open(CFG, FileAccess.WRITE)
	if f: f.store_line("%.3f %s" % [vol, "muted" if muted else "on"])

func set_vol(v: float) -> void:
	vol = clampf(v, 0.0, 1.0)
	muted = false
	_apply()
	_save_setting()

func toggle_mute() -> void:
	if silent():
		muted = false
		if vol < 0.05: vol = 0.5   # unmuting a knob turned right down
	else:
		muted = true
	_apply()
	_save_setting()

func silent() -> bool: return muted or vol < 0.01

func _apply() -> void:
	var bi := AudioServer.get_bus_index(BUS)
	if bi < 0: return
	AudioServer.set_bus_mute(bi, silent())
	AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(vol * vol * LEVEL, 0.0001)))

## Left edge of the radio's panels on screen (the screen width when none is showing), so the
## flight status line can keep clear of them.
func hud_left() -> float:
	if nav.visible: return nav.position.x
	if comm.visible: return comm.position.x
	return gm.Wv

## The field the radio is tuned to: the one you right-clicked, else your destination.
func comm_target():
	var id := int(gm.G.get("comm", -1)) if gm.G else -1
	if id >= 0 and id < gm.wd.strips.size(): return gm.wd.strips[id]
	return gm.flight.nav_target() if gm.G else null

## A right-click on field s (chart or minimap): tune the radio to it, or back to following the
## course if it's already tuned there.
func set_comm(s: Dictionary) -> void:
	if s.type == "road": return
	if int(gm.G.get("comm", -1)) == int(s.id):
		gm.G.comm = -1
		var nt = gm.flight.nav_target()
		gm.toast(("Radio back on %s, your course." % nt.name) if nt else "Radio follows your course.", "mag")
	else:
		gm.G.comm = int(s.id)
		gm.toast("Radio tuned to %s." % s.name, "mag")

## Which station the field broadcasts.
static func station_of(s) -> String:
	if s == null or s.type == "road": return ""
	if s.type == "haven" or Fields.friendly(s): return "human"
	if s.get("hostile", false): return "military"
	if s.get("cleared", false): return "static"
	return "zombie"

func _process(dt: float) -> void:
	var F = gm.F
	var on: bool = gm.mode == "flight" and F != null and not F.crashed and gm.G != null
	var nt = comm_target() if on else null
	var want := station_of(nt)
	var nv = gm.flight.nav_target() if on else null
	knob.visible = on and gm.uist == ""
	comm.visible = knob.visible and want != ""
	nav.visible = knob.visible and nv != null
	dest_name = String(nt.name) if nt != null else ""
	nav_name = String(nv.name) if nv != null else ""
	comm_freq = int(nt.get("freq", -1)) if nt != null else -1
	nav_freq = int(nv.get("freq", -1)) if nv != null else -1
	nav_km = U.km(Vector2(nv.x - F.x, nv.y - F.y).length()) if nv != null else -1
	if knob.visible:
		knob.place(gm.Wv, gm.Hv)
		knob.queue_redraw()
	if comm.visible:
		comm.place(knob.position)
		comm.tick(dt)
	if nav.visible:
		nav.place(knob.position)
		nav.tick(dt)
	if want != station or (nt != null and int(nt.id) != dest): _tune(want, int(nt.id) if nt != null else -1)
	var paused: bool = gm.uist == "pause" or gm.uist == "settings"
	clip_p.stream_paused = paused
	bg_p.stream_paused = paused
	hiss_p.stream_paused = paused
	if station == "" or paused:
		cap_h.clear_buffer()   # nothing worth measuring meanwhile
		cap_b.clear_buffer()
		return
	if station != "static":
		left -= dt
		if phase == "clip":
			var rest := INF   # the clip running out before its time is up
			if clip_p.stream and clip_p.playing: rest = clip_p.stream.get_length() - clip_p.get_playback_position()
			if left <= XF or rest <= XF or not clip_p.playing: _static()
		elif phase == "static" and left <= 0.0:
			if next_path == "" or ResourceLoader.load_threaded_get_status(next_path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS: _clip()
	# crossfade: the clip (and its background) up while static goes down, or the other way round
	var k := dt / XF
	g_clip = move_toward(g_clip, 1.0 if phase == "clip" else 0.0, k)
	g_hiss = move_toward(g_hiss, 0.0 if phase == "clip" else 1.0, k)
	_learn(hiss_p, cap_h, g_hiss, dt)
	if bg_p.bus == &"RadioStatic2": _learn(bg_p, cap_b, g_clip * float(BG_LEVEL.get(station, 0.0)), dt)
	else: cap_b.clear_buffer()
	_levels()

## Measures the static file a player is playing (what came through its bus, less the volume it
## was played at) and keeps a running figure for that file.
func _learn(p: AudioStreamPlayer, cap: AudioEffectCapture, fade: float, dt: float) -> void:
	var n := cap.get_frames_available()
	var buf := cap.get_buffer(n) if n > 0 else PackedVector2Array()
	var at := fade * _even(p)   # the volume it was played at
	var prev: float = was_at.get(p, -1.0)
	was_at[p] = at
	if not p.playing or p.stream == null or n < 64 or at < 0.02: return
	if prev <= 0.0 or absf(at / prev - 1.0) > 0.1: return   # the volume just changed: this sound was played at another one
	var sum := 0.0
	var cnt := 0
	for i in range(0, n, 4):   # every 4th sample is plenty for noise
		var v: Vector2 = buf[i]
		sum += v.x * v.x + v.y * v.y
		cnt += 2
	var rms := sqrt(sum / cnt) / at
	var path := p.stream.resource_path
	var e: Array = loud.get(path, [rms, 0.0])
	var tau := LEARN_FAST if float(e[1]) < 1.0 else LEARN_SLOW
	e[0] = lerpf(float(e[0]), rms, 1.0 - exp(-dt / tau))
	e[1] = float(e[1]) + dt
	loud[path] = e

## The extra volume that brings a static player's file to STATIC_RMS (1 for anything else, or a
## file not measured yet).
func _even(p: AudioStreamPlayer) -> float:
	if p.stream == null or p.bus == &"Radio": return 1.0
	var e = loud.get(p.stream.resource_path)
	if e == null or float(e[0]) <= 0.0: return 1.0
	return clampf(db_to_linear(STATIC_RMS) / float(e[0]), 0.05, GAIN_MAX)

func _levels() -> void:
	clip_p.volume_db = linear_to_db(maxf(g_clip * float(CLIP_LEVEL.get(station, 1.0)), 0.0001))
	bg_p.volume_db = linear_to_db(maxf(g_clip * float(BG_LEVEL.get(station, 0.0)) * _even(bg_p), 0.0001))
	hiss_p.volume_db = linear_to_db(maxf(g_hiss * _even(hiss_p), 0.0001))
	if g_clip <= 0.0:
		if clip_p.playing: clip_p.stop()
		if bg_p.playing: bg_p.stop()
	if g_hiss <= 0.0 and hiss_p.playing: hiss_p.stop()

## A new destination: straight to static (no fade), then a clip from the new station.
func _tune(want: String, id: int) -> void:
	station = want
	dest = id
	g_clip = 0.0
	phase = ""
	if station == "":
		g_hiss = 0.0
		_levels()
		return
	g_hiss = 1.0
	_static()
	_levels()

## Into static: the clip fades out as the static fades in (or it's already there).
func _static() -> void:
	phase = "static"
	left = randf_range(STATIC_T.x, STATIC_T.y)
	if not hiss_p.playing: _hiss()
	if station == "static": return
	var pool: Array = files.get(STATIONS[station], [])
	next_path = ""
	if pool.is_empty(): return
	var choices := pool.filter(func(p): return p != last_path)
	next_path = (choices if choices.size() else pool).pick_random()
	if not ResourceLoader.has_cached(next_path): ResourceLoader.load_threaded_request(next_path)   # big files load while the static plays, no hitch

func _hiss() -> void:
	var st = _static_stream()
	if st == null: return
	hiss_p.stream = st
	cap_h.clear_buffer()
	hiss_p.play(randf() * maxf(st.get_length() - 1.0, 0.0))

## A random static file, from those that have finished loading.
func _static_stream() -> AudioStream:
	for p in files.get(STATIC_DIR, []):
		if not statics.has(p) and ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			statics[p] = ResourceLoader.load_threaded_get(p)
	var ready := statics.values().filter(func(v): return v != null)
	if ready.is_empty(): return null
	return ready.pick_random()

## Out of static into the next clip, fading in.
func _clip() -> void:
	var st: AudioStream = null
	if next_path != "":
		st = ResourceLoader.load_threaded_get(next_path) if not ResourceLoader.has_cached(next_path) else load(next_path)
	if st == null:   # nothing to play: more static
		_static()
		return
	last_path = next_path
	phase = "clip"
	left = randf_range(CLIP_T.x, CLIP_T.y)
	clip_p.stream = st
	var ln := st.get_length()
	var whole := ln <= WHOLE
	var from := 0.0 if whole else randf_range(CLIP_START.x, CLIP_START.y)
	clip_p.play(from)
	if station == "human": left = ln if whole else maxf(ln - from - HUMAN_END, XF * 2.0)   # the whole track, bar its last seconds unless it's short
	bg_p.stop()
	var b: AudioStream = null
	if station == "zombie" and files.get(BG_DIR, []).size(): b = load(files[BG_DIR].pick_random())
	elif station == "human": b = _static_stream()   # soft static under the music, evened out like the rest
	if b:
		bg_p.stream = b
		bg_p.bus = &"RadioStatic2" if station == "human" else StringName(BUS)
		cap_b.clear_buffer()
		bg_p.play(randf() * maxf(b.get_length() - 5.0, 0.0))

## The knob control, under the throttle on the flight HUD.
class Knob extends Control:
	const R := 15.0
	const A0 := -PI * 0.75   # knob angle at 0 (pointing down-left), from straight up
	const A1 := PI * 0.75
	var radio: Radio
	var drag := false
	var moved := false
	var sy := 0.0
	var sv := 0.0

	func _init(r: Radio) -> void:
		radio = r
		size = Vector2(54, 62)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = ""

	func place(w: float, h: float) -> void:   # bottom-right corner
		position = Vector2(w - 12 - size.x, h - 12 - size.y)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				radio.set_vol((0.0 if radio.muted else radio.vol) + (0.05 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05))
			elif e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					drag = true; moved = false; sy = e.position.y; sv = radio.vol
				else:
					if drag and not moved: radio.toggle_mute()   # a click mutes and unmutes
					drag = false
			accept_event()
			queue_redraw()
		elif e is InputEventMouseMotion and drag:
			var dy: float = sy - e.position.y
			if absf(dy) > 3: moved = true
			if moved: radio.set_vol(sv + dy / 120.0)   # drag up to turn it up
			accept_event()
			queue_redraw()

	func _draw() -> void:
		var off := radio.silent()
		var ink := Color.html("#efe6cf")
		var amber := Color.html("#d9a441")
		draw_style_box(Radio.panel(), Rect2(Vector2.ZERO, size))
		var c := Vector2(size.x / 2, 22)
		var v := 0.0 if off else radio.vol
		# scale ring, then the turned part in amber
		draw_arc(c, R + 4, A0 - PI / 2, A1 - PI / 2, 32, Color(1, 1, 1, 0.15), 2.5, true)
		if v > 0.0: draw_arc(c, R + 4, A0 - PI / 2, A0 + (A1 - A0) * v - PI / 2, 32, amber, 2.5, true)
		draw_circle(c, R, Color.html("#2a2f2a"))
		draw_arc(c, R, 0, TAU, 32, Color(0, 0, 0, 0.7), 1.5, true)
		var a := A0 + (A1 - A0) * v - PI / 2
		draw_line(c + Vector2(cos(a), sin(a)) * 4, c + Vector2(cos(a), sin(a)) * (R - 3), ink if not off else Color(ink, 0.4), 2.5, true)
		var f := Pen.font("700")
		var t := "OFF" if off else "RADIO"
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2((size.x - tw) / 2, size.y - 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.html("#e3644c") if off else Color.html("#b9b09a"))

static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(12 / 255.0, 16 / 255.0, 14 / 255.0, 0.74)
	sb.set_corner_radius_all(6)
	return sb

## The COMM panel, left of the knob: "COMM", the field's name in a window (a name too long for
## it pans slowly back and forth) and a little level meter that moves with the sound. The NAV
## panel above it is the same with your destination and its distance in place of the meter.
class Comm extends Control:
	const H := 36.0
	const NAME_W := 180.0   # fits most field names at NAME_FS
	const NAME_FS := 14
	const PAN := 18.0       # px/s a long name pans
	const PAN_HOLD := 1.5   # s it rests at each end
	const BARS := 6
	const FREQ_W := 74.0    # the frequency box, right of the name
	const TUNE_T := Vector2(0.35, 0.9)   # s the box takes to wind to a new frequency: short hops quick, long ones longer
	var radio: Radio
	var field: Control      # the name window, clips the text
	var pan := 0.0          # px the name is panned
	var pan_t := 0.0        # s along the pan cycle
	var lvl := 0.0          # meter, 0..1, smoothed
	var shown := ""
	var is_nav := false
	var f_from := -1.0      # frequency box: winding from this...
	var f_to := -1          # ...to this (tenths of a MHz)
	var f_t := 1.0          # 0..1 along the wind
	var f_dur := 0.5

	func _init(r: Radio, nav_panel: bool) -> void:
		radio = r
		is_nav = nav_panel
		size = Vector2(52 + NAME_W + 6 + FREQ_W + 8 + BARS * 5 + 10, H)
		mouse_filter = Control.MOUSE_FILTER_STOP   # clicks here don't steer the plane
		field = Control.new()
		field.clip_contents = true
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		field.position = Vector2(52, 7)
		field.size = Vector2(NAME_W, H - 14)
		field.draw.connect(_draw_name)
		add_child(field)

	func place(knob_pos: Vector2) -> void:
		position = Vector2(knob_pos.x - 8 - size.x, knob_pos.y + 62 - H)   # bottoms line up with the knob
		if is_nav: position.y -= H + 6   # NAV sits on top of COMM

	func tick(dt: float) -> void:
		var fq: int = radio.nav_freq if is_nav else radio.comm_freq
		if fq != f_to:   # new field: wind the dial over from where it shows now
			f_from = _freq_now() if f_to >= 0 and fq >= 0 else float(fq)
			f_to = fq
			f_t = 0.0
			f_dur = lerpf(TUNE_T.x, TUNE_T.y, clampf(absf(f_to - f_from) / 190.0, 0.0, 1.0))
		f_t = minf(f_t + dt / f_dur, 1.0)
		var nm: String = radio.nav_name if is_nav else radio.dest_name
		if nm != shown:
			shown = nm
			pan_t = 0.0
		var over := maxf(Pen.font("600").get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x - (NAME_W - 12), 0.0)
		if over > 0.0:
			var run := over / PAN
			pan_t = fmod(pan_t + dt, (run + PAN_HOLD) * 2.0)
			var t := pan_t
			if t < PAN_HOLD: pan = 0.0
			elif t < PAN_HOLD + run: pan = (t - PAN_HOLD) * PAN
			elif t < PAN_HOLD * 2.0 + run: pan = over
			else: pan = over - (t - PAN_HOLD * 2.0 - run) * PAN
		else: pan = 0.0
		# signal level on the radio bus, before the knob: the meter shows what's coming in
		var bi := AudioServer.get_bus_index(Radio.BUS)
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(bi, 0), AudioServer.get_bus_peak_volume_right_db(bi, 0)) - AudioServer.get_bus_volume_db(bi)
		var k := 0.0 if radio.silent() else clampf((db + 36.0) / 33.0, 0.0, 1.0)
		lvl = k if k > lvl else move_toward(lvl, k, dt * 1.6)   # jumps up, falls back slowly
		queue_redraw()
		field.queue_redraw()

	func _draw() -> void:
		draw_style_box(Radio.panel(), Rect2(Vector2.ZERO, size))
		var f := Pen.font("700")
		draw_string(f, Vector2(10, H / 2 + 4), "NAV" if is_nav else "COMM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.html("#d9a441"))
		draw_rect(Rect2(field.position, field.size), Color(0, 0, 0, 0.45))
		# frequency box: "123.4 MHz"
		var fr := Rect2(field.position.x + NAME_W + 6, field.position.y, FREQ_W, field.size.y)
		draw_rect(fr, Color(0, 0, 0, 0.45))
		if f_to >= 0:
			var fv := int(round(_freq_now()))
			var fq := "%d.%d" % [fv / 10, fv % 10]
			var f6 := Pen.font("600")
			var wn := f6.get_string_size(fq, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x
			var wu := f.get_string_size(" MHz", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			var fx := fr.position.x + (FREQ_W - wn - wu) / 2
			draw_string(f6, Vector2(fx, fr.position.y + fr.size.y / 2 + 5), fq, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS, Color.html("#efe6cf"))
			draw_string(f, Vector2(fx + wn, fr.position.y + fr.size.y / 2 + 5), " MHz", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.html("#b9b09a"))
		var x0 := fr.end.x + 8
		if is_nav:
			if radio.nav_km >= 0:
				var t := "%d km" % radio.nav_km
				var fs := 10 if radio.nav_km < 1000 else 9
				draw_string(f, Vector2(size.x - 6 - f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, H / 2 + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.html("#b9b09a"))
			return
		var bh := H - 16
		for i in BARS:
			var on := lvl * BARS > i + 0.15
			var h := bh * (0.35 + 0.65 * float(i + 1) / BARS)
			var c := (Color.html("#e3644c") if i == BARS - 1 else Color.html("#d9a441")) if on else Color(1, 1, 1, 0.12)
			draw_rect(Rect2(x0 + i * 5, H - 8 - h, 3, h), c)

	## The frequency the box shows now, mid-wind: fast at first, settling onto the new one.
	func _freq_now() -> float:
		var e := 1.0 - pow(1.0 - f_t, 3.0)
		return lerpf(f_from, float(f_to), e)

	func _draw_name() -> void:
		var f := Pen.font("600")
		field.draw_string(f, Vector2(6 - pan, field.size.y / 2 + 5), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS, Color.html("#efe6cf"))

## The dashed circle round the field the radio is tuned to, on the chart and the minimap.
const RING := Color(0.17, 0.70, 0.75)
