class_name Synth
extends Node
## Synthesized audio, ported from the WebAudio code: one-shot effects are rendered offline
## into PCM buffers (cached), and the engine/wind/rain bed is generated live.

const FS := 22050.0
var on := true
var sounds := {}   # key -> AudioStreamWAV
var players: Array = []
var pi_ := 0
var gen_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var noise_buf := PackedFloat32Array()

# live bed state
var e_freq := 38.0
var e_cut := 250.0
var e_gain := 0.0
var w_gain := 0.0
var r_gain := 0.0
var t_freq := 38.0
var t_cut := 250.0
var t_gain := 0.0
var t_w := 0.0
var t_r := 0.0
var ph1 := 0.0
var ph2 := 0.0
var bq_e := [0.0, 0.0, 0.0, 0.0]
var bq_w := [0.0, 0.0, 0.0, 0.0]
var bq_r := [0.0, 0.0, 0.0, 0.0]
var co_w: Array
var co_r: Array
# Deafened by a blast (see deafen()): straight away every other sound drops to DEAF_VOL for
# DEAF_HOLD seconds, then fades back up to full over DEAF_FADE seconds. The blast's own boom
# isn't turned down (UNDUCKED). A ringing in the ears starts DEAF_RING_DELAY after the blast,
# fades in over DEAF_RING_IN and fades out again as hearing comes back.
const DEAF_VOL := 0.25
const DEAF_HOLD := 3.0
const DEAF_FADE := 2.0
const DEAF_RING_DELAY := 0.5
const DEAF_RING_IN := 0.8
const DEAF_RING_VOL := 0.025  # loudness of the ringing at its peak
const FX_BUS := "Fx"         # every sound but the ringing and the booms plays on this bus, so it can be turned down
const UNDUCKED := ["boom", "bigboom"]   # played on Master instead, at full volume while deafened
var deaf_on := false
var deaf_t := 0.0   # seconds since the deafness started
var ring_player: AudioStreamPlayer

func _ready() -> void:
	seed(12345)
	noise_buf.resize(int(FS))
	for i in noise_buf.size(): noise_buf[i] = randf() * 2.0 - 1.0
	randomize()
	if AudioServer.get_bus_index(FX_BUS) < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, FX_BUS)
		AudioServer.set_bus_send(bi, "Master")
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = FX_BUS
		add_child(p)
		players.append(p)
	ring_player = AudioStreamPlayer.new()   # on Master, so the deafness doesn't turn it down
	ring_player.stream = _ring_stream()
	add_child(ring_player)
	gen_player = AudioStreamPlayer.new()
	gen_player.bus = FX_BUS
	var g := AudioStreamGenerator.new()
	g.mix_rate = FS
	g.buffer_length = 0.12
	gen_player.stream = g
	add_child(gen_player)
	gen_player.play()
	playback = gen_player.get_stream_playback()
	co_w = _coef("lowpass", 380.0, 0.6)
	co_r = _coef("highpass", 1500.0, 1.0)
	_load_setting()

func _load_setting() -> void:
	var f := FileAccess.open("user://settings.cfg", FileAccess.READ)
	if f:
		on = f.get_line() != "off"
	_apply()

func set_on(v: bool) -> void:
	on = v
	var f := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
	if f: f.store_line("on" if v else "off")
	_apply()

func _apply() -> void:
	var k := 1.0      # volume of everything else
	var ring := 0.0   # volume of the ringing
	if deaf_on:
		var back := clampf((deaf_t - DEAF_HOLD) / DEAF_FADE, 0.0, 1.0)   # 0 deaf .. 1 hearing again
		k = DEAF_VOL + (1.0 - DEAF_VOL) * back
		ring = clampf((deaf_t - DEAF_RING_DELAY) / DEAF_RING_IN, 0.0, 1.0) * (1.0 - back)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(FX_BUS), linear_to_db(k))
	AudioServer.set_bus_volume_db(0, 0.0 if on else -80.0)
	AudioServer.set_bus_mute(0, not on)
	if ring_player:
		if ring > 0.001:
			ring_player.volume_db = linear_to_db(ring)
			if not ring_player.playing: ring_player.play()
		elif ring_player.playing: ring_player.stop()

## A one-second loop of high, slightly beating tones: the ringing in your ears after a blast.
func _ring_stream() -> AudioStreamWAV:
	var n := int(FS)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := i / FS
		# whole numbers of cycles per second, so the loop joins up without a click
		b[i] = DEAF_RING_VOL * (sin(TAU * 2200.0 * t) + 0.6 * sin(TAU * 2205.0 * t) + 0.15 * sin(TAU * 4401.0 * t)) / 1.75
	var w := _to_stream(b)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

# ---------------- filters ----------------
func _coef(type: String, f: float, q: float) -> Array:
	f = clampf(f, 10.0, FS * 0.45)
	var w0 := TAU * f / FS
	var cw := cos(w0)
	var qq := q
	if type != "bandpass": qq = pow(10.0, q / 20.0)
	var alpha := sin(w0) / (2.0 * maxf(0.05, qq))
	var b0: float; var b1: float; var b2: float
	if type == "lowpass":
		b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
	elif type == "highpass":
		b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
	else:
		b0 = alpha; b1 = 0; b2 = -alpha
	var a0 := 1 + alpha
	return [b0 / a0, b1 / a0, b2 / a0, (-2 * cw) / a0, (1 - alpha) / a0]

static func _bq(x: float, co: Array, st: Array) -> float:
	var y: float = co[0] * x + co[1] * st[0] + co[2] * st[1] - co[3] * st[2] - co[4] * st[3]
	st[1] = st[0]; st[0] = x; st[3] = st[2]; st[2] = y
	return y

static func _osc(type: String, ph: float) -> float:
	match type:
		"square": return 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		"sawtooth": return 2.0 * fmod(ph, 1.0) - 1.0
		"triangle":
			var p := fmod(ph, 1.0)
			return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
	return sin(TAU * ph)

# ---------------- offline rendering ----------------
func _ensure(buf: PackedFloat32Array, n: int) -> void:
	if buf.size() < n: buf.resize(n)

func _noise(buf: PackedFloat32Array, dur: float, freq: float, q: float, vol: float, type: String = "bandpass", dl: float = 0.0) -> void:
	var n := int((dur + 0.05) * FS)
	var off := int(dl * FS)
	_ensure(buf, off + n)
	var co := _coef(type, freq, q)
	var st := [0.0, 0.0, 0.0, 0.0]
	var start := randi() % int(FS * 0.5)
	for i in n:
		var t := i / FS
		var g := vol * pow(0.001 / vol, minf(1.0, t / dur)) if vol > 0.001 else 0.0
		var x := _bq(noise_buf[(start + i) % noise_buf.size()], co, st)
		buf[off + i] += x * g

func _tone(buf: PackedFloat32Array, f0: float, f1: float, dur: float, vol: float, type: String = "sine", dl: float = 0.0, vib: float = 0.0, vibf: float = 0.0, lin: bool = false, att: float = 0.01, bp: Array = []) -> void:
	var n := int((dur + 0.05) * FS)
	var off := int(dl * FS)
	_ensure(buf, off + n)
	var ph := 0.0
	var st := [0.0, 0.0, 0.0, 0.0]
	for i in n:
		var t := i / FS
		var k := minf(1.0, t / dur)
		var f := (f0 + (f1 - f0) * k) if lin else f0 * pow(f1 / f0, k)
		if vib > 0: f += sin(TAU * vibf * t) * vib
		ph += f / FS
		var g: float
		if t < att: g = 0.0001 * pow(vol / 0.0001, t / att)
		else: g = vol * pow(0.001 / vol, minf(1.0, (t - att) / maxf(0.001, dur - att)))
		var x := _osc(type, ph)
		if bp.size(): x = _bq(x, bp, st)
		buf[off + i] += x * g

func _render(kind: String) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match kind:
		"pistol": _noise(b, .18, 1800, .7, .5); _tone(b, 180, 60, .12, .3, "triangle")
		"shotgun": _noise(b, .35, 900, .5, .8); _tone(b, 120, 40, .2, .45, "triangle")
		"rifle": _noise(b, .25, 2400, .8, .6); _tone(b, 220, 50, .15, .35, "triangle")
		"enemy": _noise(b, .16, 1400, .8, .25)
		"hit": _noise(b, .07, 500, 1, .18)
		"hurt": _tone(b, 140, 70, .18, .3, "square")
		"loot": _tone(b, 660, 660, .08, .14, "triangle"); _tone(b, 990, 990, .12, .14, "triangle", .08)
		"cash": _tone(b, 880, 880, .06, .1, "square"); _tone(b, 1320, 1320, .1, .1, "square", .06)
		"scream": _noise(b, .9, 2300, 3, .35); _tone(b, 700, 1350, .7, .07, "square"); _tone(b, 520, 900, .7, .05, "sawtooth")
		"pop": _noise(b, .6, 280, .6, .8, "lowpass"); _tone(b, 150, 45, .4, .3)
		"boom": _noise(b, 1.1, 200, .4, 1.2, "lowpass"); _tone(b, 80, 25, .8, .6)
		"bigboom": _noise(b, 2.2, 150, .3, 1.5, "lowpass"); _tone(b, 62, 16, 1.6, .75); _noise(b, .5, 1400, .6, .35); _noise(b, 1.4, 500, .4, .4, "lowpass", .15)
		"thump": _noise(b, .25, 300, .7, .5, "lowpass"); _noise(b, .3, 3000, 2, .12)
		"crash": _noise(b, 1.4, 400, .3, 1.2, "lowpass"); _noise(b, .8, 2000, .5, .4)
		"open": _noise(b, .16, 900, 1.2, .22); _tone(b, 210, 130, .14, .08, "triangle")
		"safe": _noise(b, .25, 1600, 2, .25); _tone(b, 320, 180, .2, .12, "square")
		"rare": _tone(b, 1320, 1320, .35, .08, "triangle"); _tone(b, 1760, 1760, .4, .07, "triangle", .07)
		"jackpot":
			var fs := [880, 1100, 1320, 1760]
			for i in 4: _tone(b, fs[i], fs[i], .3, .09, "triangle", i * .08)
		"smg": _noise(b, .07, 2100, .9, .32); _tone(b, 200, 80, .05, .15, "triangle")
		"rifle2": _noise(b, .16, 2300, .8, .5); _tone(b, 240, 55, .12, .3, "triangle")
		"shotgun2": _noise(b, .5, 650, .5, 1.1); _tone(b, 100, 32, .3, .55, "triangle")
		"bow": _noise(b, .12, 3200, 2, .14); _tone(b, 320, 190, .12, .08, "triangle")
		"jump": _noise(b, .14, 700, 1, .14)
		"land": _noise(b, .12, 260, .7, .3, "lowpass")
		"horde": _noise(b, 1.6, 180, .4, .8, "lowpass"); _tone(b, 90, 60, 1.4, .12, "sawtooth")
		"siphon": _noise(b, .35, 500, 3, .08)
		"caw":
			# crows taking off: soft whumps of wing beats from three birds, quickening
			# as they climb away and fading out (the key keeps its old name; it used to be a caw)
			for bird in 3:
				var t := bird * (0.05 + randf() * 0.05)
				var gap := 0.11 + randf() * 0.03
				var v := 0.045 - bird * 0.01
				for k in 7:
					_noise(b, .07, 420 + randf() * 160, .7, v, "bandpass", t)
					_noise(b, .05, 1500 + randf() * 400, 1.2, v * .25, "bandpass", t + .01)
					t += gap
					gap *= 0.9
					v *= 0.8
		"click": _tone(b, 1200, 900, .04, .06, "square")
		"swing": _noise(b, .14, 2600, 1.2, .25)
		"thunder": _noise(b, 2.4, 110, .3, 1.1, "lowpass"); _noise(b, .4, 900, .5, .3)
		"empty": _tone(b, 900, 700, .03, .08, "square")
		_:
			if kind.begins_with("groan"):
				var v := 0.06
				var f := 62.0 + randf() * 30.0
				var d := 0.9 + randf() * 0.5
				var bp := _coef("bandpass", 320 + randf() * 260, 2.5)
				_tone(b, f * 1.35, f, d, v, "triangle", 0.0, 5.0, 4.0 + randf() * 4.0, true, 0.18, bp)
				_noise(b, d * .8, 700, 1.5, v * .5)
			elif kind.begins_with("snarl"):
				var v := 0.12
				_noise(b, .55, 900, 2.2, v * 2.2); _tone(b, 190, 85, .5, v, "sawtooth")
			elif kind.begins_with("yell"):
				# a shouted "Hey!": buzzy voice through two vowel formants, pitch up then down
				var v := 0.14
				var f := 120.0   # each survivor's own pitch is applied when it plays (VOICE)
				# the three variants are full, medium and short: "Heyyy!", "Hey!", "Hy!"
				var d: float = [0.42, 0.3, 0.2][int(kind.substr(4)) % 3] + randf() * 0.06
				var f1 := _coef("bandpass", 480 + randf() * 100, 3.0)
				var f2 := _coef("bandpass", 1100 + randf() * 200, 4.0)
				_tone(b, f * 1.25, f * 0.8, d, v * 2.5, "sawtooth", 0.0, 4.0, 6.0, false, 0.05, f1)
				_tone(b, f * 1.25, f * 0.8, d, v * 1.5, "sawtooth", 0.0, 4.0, 6.0, false, 0.05, f2)
				_noise(b, minf(.12, d * .4), 1400, 1.5, v * .4)
			elif kind.begins_with("cry"):
				# thrown by a blast: a pained "Aagh!", open vowel, pitch breaking upward then falling away
				var v := 0.14
				var f := 170.0   # each survivor's own pitch is applied when it plays (VOICE)
				var d: float = [0.55, 0.42, 0.32][int(kind.substr(3)) % 3] + randf() * 0.08
				var f1 := _coef("bandpass", 750 + randf() * 120, 3.0)
				var f2 := _coef("bandpass", 1250 + randf() * 200, 4.0)
				_tone(b, f * 1.5, f * 0.7, d, v * 2.5, "sawtooth", 0.0, 3.0, 7.0, false, 0.02, f1)
				_tone(b, f * 1.5, f * 0.7, d, v * 1.5, "sawtooth", 0.0, 3.0, 7.0, false, 0.02, f2)
				_noise(b, minf(.15, d * .35), 1600, 1.5, v * .5)
			elif kind.begins_with("ugh"):
				# killed before they knew you were there: a short, choked "Ugh!", the breath
				# knocked out of them, pitch dropping as the vowel is cut off
				var v := 0.14
				var f := 120.0   # each survivor's own pitch is applied when it plays (VOICE)
				var d: float = [0.26, 0.2, 0.15][int(kind.substr(3)) % 3] + randf() * 0.04
				var f1 := _coef("bandpass", 600 + randf() * 80, 3.0)
				var f2 := _coef("bandpass", 1150 + randf() * 150, 4.0)
				_tone(b, f * 1.1, f * 0.65, d, v * 2.5, "sawtooth", 0.0, 0.0, 0.0, false, 0.015, f1)
				_tone(b, f * 1.1, f * 0.65, d, v * 1.5, "sawtooth", 0.0, 0.0, 0.0, false, 0.015, f2)
				_noise(b, d * .6, 900, 1.2, v * .6)
			elif kind.begins_with("heart"):
				var v := 0.2
				_tone(b, 58, 40, .14, v); _tone(b, 52, 36, .16, v * .8, "sine", .2)
	return b

func _to_stream(b: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		var s := int(clampf(b[i] * 0.6, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(FS)
	w.stereo = false
	w.data = data
	return w

const REF := {"groan": 0.06, "snarl": 0.12, "heart": 0.2, "yell": 0.14, "cry": 0.14, "ugh": 0.14}
# Each survivor gets a voice pitch at spawn ("voice", a playback pitch scale in this range) used
# for all their speech ("yell", "cry", "ugh"): about 105-135 Hz for the "Hey!", 150-190 Hz for the cry.
const VOICE := Vector2(0.875, 1.125)

## Play a sound. vv: volume for the REF sounds (their reference volume = as rendered);
## pitch: playback pitch scale (a survivor's voice).
func sfx(kind: String, vv: float = -1.0, pitch: float = 1.0) -> void:
	if not on: return
	var key := kind
	var vol_db := 0.0
	if REF.has(kind):
		key = kind + str(randi() % 3)
		if vv >= 0:
			if vv < 0.004 and kind == "groan": return
			vol_db = linear_to_db(maxf(0.0001, vv / REF[kind]))
	if not sounds.has(key):
		sounds[key] = _to_stream(_render(key))
	var p: AudioStreamPlayer = players[pi_]
	pi_ = (pi_ + 1) % players.size()
	p.bus = &"Master" if UNDUCKED.has(kind) else StringName(FX_BUS)
	p.stream = sounds[key]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

## Pre-render common sounds so the first gunshot does not hitch.
func warm() -> void:
	for k in ["pistol", "hit", "hurt", "loot", "open", "click", "thump", "enemy", "cash", "swing", "boom", "bigboom"]:
		if not sounds.has(k): sounds[k] = _to_stream(_render(k))
		await get_tree().process_frame

# ---------------- live bed: engine, wind, rain ----------------
func engine(thr: float, alt: float, active: bool) -> void:
	var base := 38.0 + thr * 62.0
	t_freq = base
	t_cut = 250.0 + thr * 900.0
	t_gain = (0.05 + thr * 0.09) if active else 0.0
	t_w = (0.008 + minf(1.0, alt / 100.0) * 0.022) if active else 0.0

func rain(k: float) -> void:
	t_r = k * 0.05 if k > 0.15 else 0.0

## Deafened by a blast close by (see Blasts.explode()): all other sounds drop to DEAF_VOL and
## the ears ring, then hearing comes back. Another blast while already deafened starts it
## over, keeping the ringing up if it already is.
func deafen() -> void:
	if deaf_on: deaf_t = minf(deaf_t, DEAF_RING_DELAY + DEAF_RING_IN)
	else:
		deaf_on = true
		deaf_t = 0.0
	_apply()

## Hearing back to normal at once (the player died).
func undeafen() -> void:
	deaf_on = false
	_apply()

func _process(dt: float) -> void:
	if deaf_on:
		deaf_t += dt
		if deaf_t >= DEAF_HOLD + DEAF_FADE: deaf_on = false
		_apply()
	if playback == null: return
	var a1 := 1.0 - exp(-dt / 0.1)
	var a2 := 1.0 - exp(-dt / 0.15)
	var a3 := 1.0 - exp(-dt / 0.3)
	var a4 := 1.0 - exp(-dt / 0.4)
	e_freq += (t_freq - e_freq) * a1
	e_cut += (t_cut - e_cut) * a1
	e_gain += (t_gain - e_gain) * a2
	w_gain += (t_w - w_gain) * a3
	r_gain += (t_r - r_gain) * a4
	var n := playback.get_frames_available()
	if n <= 0: return
	var co_e := _coef("lowpass", e_cut, 1.0)
	var f2 := e_freq * 0.5 + 1.3
	var silent := e_gain < 0.0005 and w_gain < 0.0005 and r_gain < 0.0005
	var buf := PackedVector2Array()
	buf.resize(n)
	var nb := noise_buf.size()
	var ni := randi() % nb
	for i in n:
		if silent:
			buf[i] = Vector2.ZERO
			continue
		ph1 = fmod(ph1 + e_freq / FS, 1.0)
		ph2 = fmod(ph2 + f2 / FS, 1.0)
		var x := (2.0 * ph1 - 1.0) + (1.0 if ph2 < 0.5 else -1.0)
		var s := _bq(x, co_e, bq_e) * e_gain
		var nz := noise_buf[(ni + i) % nb]
		s += _bq(nz, co_w, bq_w) * w_gain
		s += _bq(noise_buf[(ni + i * 7 + 3000) % nb], co_r, bq_r) * r_gain
		s *= 0.6
		buf[i] = Vector2(s, s)
	playback.push_buffer(buf)
