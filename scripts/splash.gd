extends Control
## Заставка при запуске в стиле 80-х: закатное солнце, неоновая сетка и три логотипа
## (хром + неон + полосатый треугольник): Godot, Claude, CPA4KA — под синтвейв.
## Любая клавиша, клик или касание — пропустить. Музыка синтезируется на лету.

const RetroLogo := preload("res://scripts/retro_logo.gd")
const MENU := "res://menu.tscn"
const BPM := 112.0
const STAGES := [3.8, 3.8, 4.8]

static var shown := false
var _t := 0.0
var _all_t := 0.0
var _stage := -1
var _done := false
var _logo: Control
var _icon: TextureRect
var _player: AudioStreamPlayer
var _flash := 0.0
var _stars: Array = []


func _ready() -> void:
	shown = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 70:
		_stars.append(Vector3(randf(), randf() * 0.55, randf()))
	_player = AudioStreamPlayer.new()
	_player.volume_db = linear_to_db(clampf(preload("res://scripts/data.gd").music_volume + 0.2, 0.05, 1.0)) - 3.0
	add_child(_player)
	_play(_synthwave())
	_next()


func _input(e: InputEvent) -> void:
	if _done or _all_t < 0.3:
		return
	if (e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed():
		_finish()


func _process(delta: float) -> void:
	_t += delta
	_all_t += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	if is_instance_valid(_logo):
		var dur: float = STAGES[_stage]
		_logo.modulate.a = clampf(_t / 0.2, 0.0, 1.0)
		# Лёгкое «дыхание» логотипа в такт
		var beat := fmod(_all_t * BPM / 60.0, 1.0)
		_logo.scale = Vector2.ONE * (1.0 + 0.012 * exp(-beat * 6.0))
		if is_instance_valid(_icon):
			_icon.modulate.a = _logo.modulate.a * clampf((dur - _t) / 0.4, 0.0, 1.0)
			var k := ease(clampf(_t / 0.7, 0.0, 1.0), 0.35)
			_icon.scale = Vector2(k, k)
			_icon.rotation = (1.0 - k) * -0.6
		if _stage == 2 and _t > 1.0 and _t - delta <= 1.0:
			_flash = 0.6
		if _t >= dur - 0.45 and _logo.leaving < 0.0:
			_logo.leave()
		if _t >= dur and not _done:
			_next()
	queue_redraw()


func _next() -> void:
	_stage += 1
	_t = 0.0
	if is_instance_valid(_logo):
		_logo.queue_free()
	if is_instance_valid(_icon):
		_icon.queue_free()
	if _stage >= STAGES.size():
		_finish()
		return
	_logo = RetroLogo.new()
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_logo)
	_logo.pivot_offset = get_viewport_rect().size / 2.0
	var big := clampf(get_viewport_rect().size.x / 9.0, 70.0, 140.0)
	match _stage:
		0:
			_logo.setup("GODOT", "engine", int(big), true)
			_icon = TextureRect.new()
			_icon.texture = load("res://assets/splash/godot_icon.svg")
			_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var s := big * 1.1
			_icon.size = Vector2(s, s)
			_icon.pivot_offset = Vector2(s, s) / 2.0
			var vs := get_viewport_rect().size
			_icon.position = Vector2(vs.x / 2.0 - s / 2.0, vs.y * 0.43 - big * 0.85 - s)
			add_child(_icon)
		1:
			_logo.setup("CLAUDE", "", int(big * 1.05), true)
		2:
			_logo.setup("CPA4KA", "", int(big * 1.2), true)
	_logo.play()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.4)
	tw.parallel().tween_property(_player, "volume_db", -40.0, 0.4)
	tw.tween_callback(func(): get_tree().change_scene_to_file(MENU))


# ---------------- Синтвейв-фон ----------------

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0))
	# Едва заметные звёзды и вспышка при появлении CPA4KA
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_all_t * 2.0 + st.z * 20.0)
		draw_rect(Rect2(Vector2(st.x * vs.x, st.y * vs.y / 0.55), Vector2(2, 2)), Color(0.8, 0.8, 1.0, 0.12 * tw * st.z))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.9, 1, _flash * 0.5))


# ---------------- Музыка ----------------
# Плавный синтвейв: тёплые пэды из расстроенных пил через фильтр, мягкий бас,
# колокольчики-арпеджио с эхом, мягкая бочка. Звуки синтезируются один раз и
# копируются (быстро), а объём дают эффекты шины: хорус, эхо, реверберация, фильтр.

const SR := 22050

func _play(samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var peak := 0.001
	for i in samples.size():
		peak = maxf(peak, absf(samples[i]))
	var g := 0.85 / peak
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.data = data
	_player.stream = w
	_player.bus = _splash_bus()
	_player.play()


## Своя шина с эффектами: хорус расширяет пэды, эхо и реверб дают пространство,
## фильтр снимает резкость.
func _splash_bus() -> String:
	var name := "Splash"
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return name
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 7000.0
	AudioServer.add_bus_effect(idx, lp)
	var ch := AudioEffectChorus.new()
	ch.wet = 0.35
	AudioServer.add_bus_effect(idx, ch)
	var dl := AudioEffectDelay.new()
	dl.tap1_delay_ms = 400.0
	dl.tap1_level_db = -14.0
	dl.tap2_delay_ms = 800.0
	dl.tap2_level_db = -20.0
	dl.feedback_active = false
	AudioServer.add_bus_effect(idx, dl)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.damping = 0.45
	rv.wet = 0.32
	rv.dry = 0.85
	rv.spread = 0.9
	AudioServer.add_bus_effect(idx, rv)
	return name


var _snd := {}


## Звук (нота) — синтезируется один раз, дальше берётся из кэша.
func _voice(kind: String, freq: float, dur: float) -> PackedFloat32Array:
	var key := "%s_%.2f_%.2f" % [kind, freq, dur]
	if _snd.has(key):
		return _snd[key]
	var n := int(dur * SR)
	var b := PackedFloat32Array()
	b.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var lp := 0.0
	var df := freq / SR
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		match kind:
			"pad":
				# Три расстроенные пилы через плавно открывающийся фильтр
				p1 = fmod(p1 + df, 1.0)
				p2 = fmod(p2 + df * 1.0045, 1.0)
				p3 = fmod(p3 + df * 0.9958, 1.0)
				var raw := (p1 + p2 + p3) / 1.5 - 1.0
				var cut := 0.04 + 0.05 * minf(t / dur, 1.0)
				lp += (raw - lp) * cut
				var env := minf(t / 0.9, 1.0) * minf((dur - t) / 1.0, 1.0)
				v = lp * env
			"bass":
				p1 = fmod(p1 + df, 1.0)
				var raw2 := sin(TAU * p1) + 0.3 * (2.0 * p1 - 1.0)
				lp += (raw2 - lp) * 0.2
				v = lp * minf(t / 0.01, 1.0) * exp(-t * 2.2) * minf((dur - t) / 0.05, 1.0)
			"bell":
				v = (sin(TAU * freq * t) + 0.25 * sin(TAU * freq * 2.0 * t) * exp(-t * 6.0)) * exp(-t * 3.5) * minf(t / 0.004, 1.0)
			"kick":
				p1 += (45.0 + 70.0 * exp(-t * 28.0)) / SR
				v = sin(TAU * p1) * exp(-t * 7.0)
			"clap":
				v = (randf() * 2.0 - 1.0) * exp(-t * 22.0) * 0.6
			"swell":
				# Нарастающий «вжух» перед финальным логотипом
				var nz := randf() * 2.0 - 1.0
				lp += (nz - lp) * (0.02 + 0.2 * t / dur)
				v = lp * pow(t / dur, 2.0)
			"lead":
				p1 = fmod(p1 + df * (1.0 + 0.003 * sin(t * 33.0) * minf(t / 0.3, 1.0)), 1.0)
				var tri_w := 1.0 - 4.0 * absf(p1 - 0.5)
				v = tri_w * minf(t / 0.03, 1.0) * minf((dur - t) / 0.2, 1.0)
		b[i] = v
	_snd[key] = b
	return b


func _mix(out: PackedFloat32Array, start: float, src: PackedFloat32Array, vol: float) -> void:
	var s0 := int(start * SR)
	var n := mini(src.size(), out.size() - s0)
	for i in n:
		out[s0 + i] += src[i] * vol


func _synthwave() -> PackedFloat32Array:
	var total := 0.0
	for s in STAGES:
		total += s
	var out := PackedFloat32Array()
	out.resize(int((total + 1.5) * SR))
	var beat := 60.0 / 96.0
	var bar := beat * 4.0
	# Fmaj7 — Am7 — Dm7 — Cmaj7: мягкая «ночная» гармония
	var chords := [[174.61, 220.0, 261.63, 329.63], [220.0, 261.63, 329.63, 392.0], [146.83, 174.61, 220.0, 261.63], [130.81, 164.81, 196.0, 246.94]]
	var roots := [43.65, 55.0, 36.71, 32.70]
	var nbar := int(ceil(total / bar))
	var t3: float = STAGES[0] + STAGES[1]
	for bi in nbar:
		var t0 := bi * bar
		var ci := bi % 4
		for f in chords[ci]:
			_mix(out, t0, _voice("pad", f, bar + 0.8), 0.09)
		# Бас — с середины первого логотипа
		if t0 >= bar * 0.5:
			for e in 4:
				_mix(out, t0 + e * beat, _voice("bass", roots[ci] * 2.0, beat * 0.9), 0.22)
		# Мягкая бочка со второго такта, хлопок на 2 и 4 с третьего логотипа
		if bi >= 1:
			for q in 4:
				_mix(out, t0 + q * beat, _voice("kick", 0.0, 0.4), 0.45)
				if q % 2 == 1 and t0 + q * beat >= t3:
					_mix(out, t0 + q * beat, _voice("clap", 0.0, 0.25), 0.25)
		# Колокольчики восьмыми — лёгкое арпеджио
		for s in 8:
			var note: float = chords[ci][[0, 2, 1, 3, 2, 0, 3, 1][s]] * 2.0
			_mix(out, t0 + s * beat * 0.5, _voice("bell", note, 1.2), 0.05)
	# «Вжух» и мелодия на CPA4KA
	_mix(out, t3 + 0.1, _voice("swell", 0.0, 0.9), 0.35)
	var mel := [[659.25, 0.5], [783.99, 0.5], [880.0, 1.0], [783.99, 0.5], [659.25, 0.5], [587.33, 1.5]]
	var tm := t3 + 1.0
	for m in mel:
		_mix(out, tm, _voice("lead", m[0], beat * m[1] + 0.25), 0.12)
		tm += beat * m[1]
	_mix(out, t3 + 1.0, _voice("kick", 0.0, 0.4), 0.7)
	# Плавное затухание в конце
	var fade_n := int(1.4 * SR)
	for i in fade_n:
		var idx := out.size() - fade_n + i
		out[idx] *= 1.0 - float(i) / fade_n
	return out
