extends Control
## Заставка при запуске в стиле 80-х: закатное солнце, неоновая сетка и три логотипа
## (хром + неон + полосатый треугольник): Godot, Claude, CPA4KA — под синтвейв.
## Любая клавиша, клик или касание — пропустить. Музыка синтезируется на лету.

const RetroLogo := preload("res://scripts/retro_logo.gd")
const MENU := "res://menu.tscn"
const RATE := 16000
const BPM := 112.0
const STAGES := [3.6, 3.6, 4.6]

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
		_logo.modulate.a = clampf(_t / 0.25, 0.0, 1.0) * clampf((dur - _t) / 0.45, 0.0, 1.0)
		# Лёгкое «дыхание» логотипа в такт
		var beat := fmod(_all_t * BPM / 60.0, 1.0)
		_logo.scale = Vector2.ONE * (1.0 + 0.012 * exp(-beat * 6.0))
		if is_instance_valid(_icon):
			_icon.modulate.a = _logo.modulate.a
			var k := ease(clampf(_t / 0.7, 0.0, 1.0), 0.35)
			_icon.scale = Vector2(k, k)
			_icon.rotation = (1.0 - k) * -0.6
		if _stage == 2 and _t > 1.0 and _t - delta <= 1.0:
			_flash = 0.6
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
			_icon.position = Vector2(vs.x / 2.0 - s / 2.0, vs.y * 0.38 - big * 0.8 - s)
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
	var hz := vs.y * 0.64
	# Небо: от чёрно-фиолетового к малиновому у горизонта
	var top := Color(0.02, 0.0, 0.06)
	var mid := Color(0.18, 0.02, 0.22)
	var low := Color(0.55, 0.08, 0.38)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, hz * 0.6), Vector2(0, hz * 0.6)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, hz * 0.6), Vector2(vs.x, hz * 0.6), Vector2(vs.x, hz), Vector2(0, hz)]), PackedColorArray([mid, mid, low, low]))
	for s in _stars:
		var tw := 0.5 + 0.5 * sin(_all_t * 3.0 + s.z * 20.0)
		draw_rect(Rect2(Vector2(s.x * vs.x, s.y * vs.y), Vector2(2, 2)), Color(1, 0.9, 1, 0.3 + 0.5 * tw * s.z))
	# Солнце с полосами
	var sr := minf(vs.x, vs.y) * 0.26
	var sc := Vector2(vs.x / 2.0, hz - sr * 0.35)
	var n := 48
	for i in n:
		var y0 := sc.y - sr + 2.0 * sr * float(i) / n
		var y1 := sc.y - sr + 2.0 * sr * float(i + 1) / n
		var k := float(i) / n
		if y1 > hz:
			break
		if k > 0.5 and fmod(k * 14.0 + _all_t * 0.6, 1.0) < 0.35 + (k - 0.5) * 0.6:
			continue
		var hw0 := sqrt(maxf(0.0, sr * sr - pow(y0 - sc.y, 2.0)))
		var hw1 := sqrt(maxf(0.0, sr * sr - pow(y1 - sc.y, 2.0)))
		var col := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.2, 0.6), k)
		draw_polygon(PackedVector2Array([Vector2(sc.x - hw0, y0), Vector2(sc.x + hw0, y0), Vector2(sc.x + hw1, y1), Vector2(sc.x - hw1, y1)]), PackedColorArray([col, col, col, col]))
	# Земля и неоновая сетка, бегущая на зрителя
	draw_rect(Rect2(Vector2(0, hz), Vector2(vs.x, vs.y - hz)), Color(0.03, 0.0, 0.07))
	var grid := Color(1.0, 0.25, 0.8, 0.8)
	draw_line(Vector2(0, hz), Vector2(vs.x, hz), Color(1.0, 0.5, 0.9), 2.0)
	for i in range(-14, 15):
		var x0 := vs.x / 2.0 + i * vs.x * 0.02
		var x1 := vs.x / 2.0 + i * vs.x * 0.16
		draw_line(Vector2(x0, hz), Vector2(x1, vs.y), Color(grid, 0.55), 1.5)
	var scroll := fmod(_all_t * 0.9, 1.0)
	for j in 12:
		var z := (float(j) + scroll) / 12.0
		var y := hz + (vs.y - hz) * pow(z, 2.2)
		draw_line(Vector2(0, y), Vector2(vs.x, y), Color(grid, 0.25 + 0.6 * z), 1.0 + 1.5 * z)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.9, 1, _flash))


# ---------------- Музыка: синтвейв ----------------
# Бочка на каждую долю, «гейтованный» малый барабан на 2 и 4, октавный бас восьмыми,
# арпеджио пилой и пэд. Аккорды: Am — F — C — G (по такту), в третьей части — удар и мелодия.

func _play(samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	_player.stream = w
	_player.play()


func _add(b: PackedFloat32Array, start: float, dur: float, freq: float, vol: float, kind: String) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	var ph2 := 0.0
	var df := freq / RATE
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			return
		var t := float(i) / RATE
		var v := 0.0
		match kind:
			"kick":
				var f := 50.0 + 110.0 * exp(-t * 30.0)
				ph += f / RATE
				v = sin(TAU * ph) * exp(-t * 9.0)
			"snare":
				v = (randf() * 2.0 - 1.0) * (exp(-t * 18.0) * 0.8 + (0.35 if t < 0.16 else 0.0)) + sin(TAU * 190.0 * t) * exp(-t * 25.0) * 0.4
			"hat":
				v = (randf() * 2.0 - 1.0) * exp(-t * 60.0)
			"bass":
				ph = fmod(ph + df, 1.0)
				v = (2.0 * ph - 1.0) * 0.6 + sin(TAU * ph) * 0.5
				v *= minf(t / 0.005, 1.0) * exp(-t * 5.0)
			"saw":
				ph = fmod(ph + df, 1.0)
				ph2 = fmod(ph2 + df * 1.006, 1.0)
				v = (ph + ph2 - 1.0) * minf(t / 0.004, 1.0) * exp(-t * 7.0)
			"pad":
				ph = fmod(ph + df, 1.0)
				ph2 = fmod(ph2 + df * 0.995, 1.0)
				v = (ph + ph2 - 1.0) * 0.5 * minf(t / 0.35, 1.0) * minf((dur - t) / 0.4, 1.0)
			"lead":
				ph = fmod(ph + df * (1.0 + 0.004 * sin(t * 30.0)), 1.0)
				v = (1.0 if ph < 0.5 else -1.0) * 0.5 * minf(t / 0.01, 1.0) * minf((dur - t) / 0.08, 1.0)
		b[idx] += v * vol


func _synthwave() -> PackedFloat32Array:
	var total := 0.0
	for s in STAGES:
		total += s
	var b := PackedFloat32Array()
	b.resize(int((total + 0.6) * RATE))
	var beat := 60.0 / BPM
	# Am F C G: корни баса и трезвучия
	var roots := [55.0, 43.65, 65.41, 49.0]
	var chords := [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
	var bars := int(total / (beat * 4.0)) + 1
	for bar in bars:
		var t0 := bar * beat * 4.0
		var ci := bar % 4
		var intro := bar == 0
		for f in chords[ci]:
			_add(b, t0, beat * 4.0, f, 0.05, "pad")
		for q in 4:
			var tb := t0 + q * beat
			if not intro:
				_add(b, tb, 0.35, 0.0, 0.55, "kick")
				if q % 2 == 1:
					_add(b, tb, 0.3, 0.0, 0.22, "snare")
			_add(b, tb + beat * 0.5, 0.05, 0.0, 0.05, "hat")
			for e in 2:
				_add(b, tb + e * beat * 0.5, beat * 0.45, roots[ci] * (2.0 if e == 1 else 1.0), 0.16, "bass")
			for s in 4:
				var note: float = chords[ci][(q * 4 + s) % 3] * (2.0 if s % 2 == 1 else 1.0)
				_add(b, tb + s * beat * 0.25, beat * 0.22, note, 0.05, "saw")
	# Мелодия и удар на появление CPA4KA
	var t3: float = STAGES[0] + STAGES[1]
	var mel := [659.25, 587.33, 523.25, 587.33, 659.25, 783.99, 659.25]
	for i in mel.size():
		_add(b, t3 + 1.0 + i * beat * 0.5, beat * (0.45 if i < mel.size() - 1 else 1.6), mel[i], 0.09, "lead")
	_add(b, t3 + 1.0, 0.5, 0.0, 0.8, "kick")
	_add(b, t3 + 1.0, 0.6, 0.0, 0.35, "snare")
	var fade_n := int(0.6 * RATE)
	for i in fade_n:
		var idx := b.size() - fade_n + i
		b[idx] *= 1.0 - float(i) / fade_n
	return b
