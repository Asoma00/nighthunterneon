extends Control
## Заставка при запуске: три стилизованные карточки под музыку.
##  1) Godot Engine — официальный значок движка (CC BY 4.0, Andrea Calabró);
##  2) «сделано вместе с Claude» — надпись набирается, как в терминале;
##  3) CPA4KA — неоновые буквы с глитчем и вспышкой.
## Любая клавиша, клик или касание — пропустить. Музыка синтезируется на лету.

const MENU := "res://menu.tscn"
const RATE := 22050
const BG := Color(0.02, 0.01, 0.04)

var _t := 0.0
var _stage := -1
var _done := false
var _card: Control
var _player: AudioStreamPlayer
var _font: Font
var _cursor: Label
var _typed: Label
var _studio: Array = []    # буквы CPA4KA
var _ghost_r: Label
var _ghost_b: Label
var _flash: ColorRect
var _scan: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_font = ThemeDB.fallback_font
	_player = AudioStreamPlayer.new()
	_player.volume_db = linear_to_db(clampf(preload("res://scripts/data.gd").music_volume + 0.2, 0.05, 1.0)) - 4.0
	add_child(_player)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan = ColorRect.new()
	_scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float line = step(0.5, fract(FRAGCOORD.y * 0.5));
	vec2 d = UV - 0.5;
	float vig = smoothstep(0.35, 0.95, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, line * 0.18 * amount + vig * 0.55);
}"""
	sm.shader = sh
	_scan.material = sm
	_next()


func _input(e: InputEvent) -> void:
	if _done or _t < 0.3:
		return
	if (e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed():
		_finish()


func _process(delta: float) -> void:
	_t += delta
	var dur: float = [3.0, 3.0, 4.2][maxi(_stage, 0)]
	match _stage:
		0:
			_anim_godot()
		1:
			_anim_claude()
		2:
			_anim_studio(delta)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 2.5)
	if _t >= dur and not _done:
		_next()


func _next() -> void:
	_stage += 1
	_t = 0.0
	if is_instance_valid(_card):
		_card.queue_free()
	if _stage > 2:
		_finish()
		return
	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.modulate.a = 0.0
	add_child(_card)
	if _flash.get_parent() == null:
		add_child(_flash)
	if _scan.get_parent() == null:
		add_child(_scan)
	move_child(_scan, -1)
	move_child(_flash, -1)
	match _stage:
		0:
			_build_godot()
			_play(_tune_pad())
		1:
			_build_claude()
			_play(_tune_bells())
		2:
			_build_studio()
			_play(_tune_hit())


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(MENU))


# ---------------- Карточки ----------------

func _center_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 18)
	_card.add_child(v)
	return v


func _text(s: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


var _logo: TextureRect


func _build_godot() -> void:
	var v := _center_box()
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/splash/godot_icon.svg")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.custom_minimum_size = Vector2(170, 170)
	_logo.pivot_offset = Vector2(85, 85)
	v.add_child(_logo)
	v.add_child(_text("СОЗДАНО НА", 18, Color(0.6, 0.65, 0.8)))
	v.add_child(_text("GODOT ENGINE", 46, Color(0.85, 0.92, 1.0)))


func _anim_godot() -> void:
	var a := clampf(_t / 0.6, 0.0, 1.0) * clampf((3.0 - _t) / 0.5, 0.0, 1.0)
	_card.modulate.a = a
	var s := 0.7 + 0.3 * ease(clampf(_t / 0.8, 0.0, 1.0), 0.3)
	_logo.scale = Vector2(s, s)
	_logo.rotation = (1.0 - clampf(_t / 0.8, 0.0, 1.0)) * -0.4
	(_scan.material as ShaderMaterial).set_shader_parameter("amount", 0.3)


func _build_claude() -> void:
	var v := _center_box()
	v.add_child(_text("сделано вместе с", 20, Color(0.75, 0.68, 0.62)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	_typed = _text("", 64, Color(0.96, 0.88, 0.8))
	row.add_child(_typed)
	_cursor = _text("▌", 64, Color(0.95, 0.6, 0.45))
	row.add_child(_cursor)


func _anim_claude() -> void:
	_card.modulate.a = clampf(_t / 0.4, 0.0, 1.0) * clampf((3.0 - _t) / 0.5, 0.0, 1.0)
	var word := "Claude"
	var n := clampi(int((_t - 0.35) / 0.12), 0, word.length())
	_typed.text = word.left(n)
	_cursor.visible = fmod(_t, 0.5) < 0.3 or n < word.length()
	(_scan.material as ShaderMaterial).set_shader_parameter("amount", 0.2)


func _build_studio() -> void:
	var word := "CPA4KA"
	_studio.clear()
	for i in word.length():
		var l := _text(word[i], 120, Color(1.0, 0.3, 0.75))
		l.size = Vector2(100, 150)
		l.add_theme_color_override("font_shadow_color", Color(0.3, 0.95, 1.0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 4)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.add_theme_constant_override("shadow_outline_size", 10)
		l.modulate.a = 0.0
		_card.add_child(l)
		_studio.append(l)
	var sub := _text("П Р Е Д С Т А В Л Я Е Т", 18, Color(0.7, 0.9, 1.0))
	sub.name = "Sub"
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.size = Vector2(500, 30)
	_card.add_child(sub)


func _anim_studio(_delta: float) -> void:
	_card.modulate.a = clampf((4.2 - _t) / 0.6, 0.0, 1.0)
	var vs := get_viewport_rect().size
	var lw := minf(100.0, (vs.x - 40.0) / float(_studio.size()))
	var x0 := (vs.x - lw * _studio.size()) / 2.0
	for i in _studio.size():
		(_studio[i] as Label).add_theme_font_size_override("font_size", int(lw * 1.2))
		(_studio[i] as Label).size = Vector2(lw, lw * 1.5)
		var l: Label = _studio[i]
		var t0 := 0.25 + i * 0.12
		var k := clampf((_t - t0) / 0.25, 0.0, 1.0)
		l.modulate.a = k
		# Буквы падают сверху и «защёлкиваются»; потом изредка глитчат
		var glitch := _t > 1.4 and randf() < 0.035
		l.position = Vector2(x0 + i * lw + (randf_range(-8, 8) if glitch else 0.0), vs.y / 2.0 - lw * 1.1 + (1.0 - ease(k, 0.25)) * -60.0)
		l.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0) if glitch else Color(1.0, 0.3, 0.75).lerp(Color(1, 1, 1), 0.25 * (0.5 + 0.5 * sin(_t * 9.0 + i))))
	if _t > 1.05 and _t - get_process_delta_time() <= 1.05:
		_flash.color.a = 0.55
	var sub := _card.find_child("Sub", true, false) as Label
	if sub:
		sub.modulate.a = clampf((_t - 1.3) / 0.6, 0.0, 1.0)
		sub.position = Vector2(vs.x / 2.0 - 250.0, vs.y / 2.0 + lw * 0.55)
	(_scan.material as ShaderMaterial).set_shader_parameter("amount", 1.0)


# ---------------- Музыка ----------------
# Короткие мотивы синтезируются в PCM: мягкий аккорд, колокольчики, удар с синтом.

func _play(samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_player.stream = w
	_player.play()


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


func _note(b: PackedFloat32Array, start: float, dur: float, freq: float, vol: float, kind := "pad") -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var env: float
		var v: float
		match kind:
			"bell":
				env = exp(-t * 4.0)
				v = sin(TAU * freq * t) + 0.4 * sin(TAU * freq * 2.76 * t) * exp(-t * 6.0)
			"bass":
				env = exp(-t * 3.0)
				v = sin(TAU * freq * t + 2.0 * sin(TAU * freq * 0.5 * t) * exp(-t * 8.0))
			"saw":
				env = minf(t / 0.02, 1.0) * exp(-t * 1.2)
				v = 0.0
				for h in range(1, 7):
					v += sin(TAU * freq * h * t) / h
				v *= 0.5
			_:
				env = minf(t / 0.5, 1.0) * minf((dur - t) / 0.8, 1.0)
				v = sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) + 0.15 * sin(TAU * freq * 1.005 * t)
		b[idx] += v * env * vol


func _tune_pad() -> PackedFloat32Array:
	var b := _buf(3.0)
	for f in [220.0, 277.18, 329.63, 440.0]:
		_note(b, 0.0, 2.9, f, 0.12)
	_note(b, 0.6, 1.6, 659.25, 0.12, "bell")
	return b


func _tune_bells() -> PackedFloat32Array:
	var b := _buf(3.0)
	var seq := [523.25, 659.25, 783.99, 1046.5, 783.99, 987.77]
	for i in seq.size():
		_note(b, 0.35 + i * 0.12, 1.4, seq[i], 0.16, "bell")
	for f in [261.63, 329.63, 392.0]:
		_note(b, 0.3, 2.6, f, 0.07)
	return b


func _tune_hit() -> PackedFloat32Array:
	var b := _buf(4.2)
	# Шум-«вжух» перед ударом
	for i in int(0.9 * RATE):
		var t := float(i) / RATE
		b[int(0.15 * RATE) + i] += randf_range(-1.0, 1.0) * 0.12 * (t / 0.9)
	_note(b, 1.05, 2.5, 55.0, 0.55, "bass")
	for f in [220.0, 261.63, 329.63, 392.0]:
		_note(b, 1.05, 3.0, f, 0.09, "saw")
	var arp := [880.0, 1046.5, 1318.5, 1567.98]
	for i in 8:
		_note(b, 1.3 + i * 0.1, 0.6, arp[i % 4], 0.08, "bell")
	return b
