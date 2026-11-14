extends Control
## Заставка при запуске в стиле 80-х: закатное солнце, неоновая сетка и три логотипа
## (хром + неон + полосатый треугольник): Godot, Claude, CPA4KA — под синтвейв.
## Любая клавиша, клик или касание — пропустить. Музыка — общий движок игры (audio.gd).

const RetroLogo := preload("res://scripts/retro_logo.gd")
const MENU := "res://menu.tscn"
const BPM := 96.0
const STAGES := [3.8, 3.8, 4.8]

static var shown := false
static var to_menu := false     # меню после заставки — зажигается неоном
static var handoff: Texture2D   # последний кадр заставки: меню растворяет его поверх себя
var _t := 0.0
var _all_t := 0.0
var _stage := -1
var _done := false
var _logo: Control
var _icon: TextureRect
var _flash := 0.0
var _stars: Array = []


func _ready() -> void:
	# Старые установки: выбросить из кэша скрипты, загруженные до подключения обновления
	preload("res://scripts/boot.gd").refresh()
	shown = true
	# Тёмный фон и между сценами — никакого серого кадра при переходе в меню
	RenderingServer.set_default_clear_color(Color(0, 0, 0))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 70:
		_stars.append(Vector3(randf(), randf() * 0.55, randf()))
	# Музыка — общим музыкальным движком игры: та же песня плавно продолжится в меню
	# и в убежище, а в бою перетечёт в боевую (мешап), не выключаясь.
	Sound.set_track("menu", true, Sound.SPLASH_SONG)
	_build_fx()
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
	if is_instance_valid(_refl) and _refl_tex != null:
		var rm: ShaderMaterial = _refl.material
		rm.set_shader_parameter("logo_tex", _refl_tex)
		rm.set_shader_parameter("t", _all_t)
		rm.set_shader_parameter("horizon", 0.62)
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
		var last := _stage >= STAGES.size() - 1
		if not last and _t >= dur - 0.45 and _logo.leaving < 0.0:
			_logo.leave()
		if _t >= dur and not _done:
			# последний логотип не гаснет: меню проступает прямо сквозь него
			if last:
				_finish()
			else:
				_next()
	queue_redraw()
	if is_instance_valid(_glints):
		_glints.queue_redraw()


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
	_logo.perspective = false      # ровно по центру экрана, без наклона
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_logo)
	_logo.pivot_offset = get_viewport_rect().size / 2.0
	var big := clampf(get_viewport_rect().size.x / 9.0, 70.0, 140.0)
	match _stage:
		0:
			_logo.setup("GODOT", "engine", int(big), true)
		1:
			_logo.setup("CLAUDE", "code", int(big * 1.05), true)
		2:
			_logo.setup("CPA4KA", "games", int(big * 1.2), true)
	_logo.play()
	_flash = 0.35
	_refl_tex = _logo.view_texture()


func _finish() -> void:
	if _done:
		return
	_done = true
	to_menu = true
	# Бесшовный переход: запомнить текущий кадр — меню откроется под ним
	# и растворит его неоновой волной от центра, без чёрного экрана.
	handoff = null
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		handoff = ImageTexture.create_from_image(img)
	get_tree().change_scene_to_file.call_deferred(MENU)


# ---------------- Синтвейв-фон ----------------
# Небо с закатом, полосатое солнце за логотипом, горы с неоновой кромкой,
# бегущая перспективная сетка и отражение логотипа в «мокром» полу.

const PALETTES := [
	# небо сверху, небо у горизонта, солнце сверху, солнце снизу, сетка
	[Color(0.01, 0.0, 0.08), Color(0.05, 0.25, 0.55), Color(0.55, 1.0, 1.0), Color(0.2, 0.45, 1.0), Color(0.3, 0.85, 1.0)],
	[Color(0.03, 0.0, 0.06), Color(0.45, 0.14, 0.18), Color(1.0, 0.85, 0.55), Color(1.0, 0.35, 0.25), Color(1.0, 0.5, 0.35)],
	[Color(0.02, 0.0, 0.07), Color(0.5, 0.05, 0.4), Color(1.0, 0.9, 0.35), Color(1.0, 0.15, 0.6), Color(1.0, 0.25, 0.85)],
]
var _pal: Array = PALETTES[2]
var _refl: TextureRect
var _refl_tex: Texture2D
var _glints: Control

const REFLECT_SHADER := """
shader_type canvas_item;
uniform sampler2D logo_tex : filter_linear;
uniform float horizon = 0.62;
uniform float t = 0.0;
void fragment() {
	// Отражение: зеркалим логотип относительно линии горизонта, рябь и затухание
	float y = SCREEN_UV.y;
	float d = y - horizon;
	if (d < 0.0) { discard; }
	float wave = sin(y * 220.0 - t * 6.0) * 0.003 * smoothstep(0.0, 0.3, d);
	vec2 uv = vec2(SCREEN_UV.x + wave, horizon - d * 1.6);
	vec4 c = texture(logo_tex, uv);
	c.a *= 0.2 * smoothstep(0.25, 0.0, d);
	c.rgb *= vec3(0.9, 0.8, 1.1);
	COLOR = c;
}
"""


func _horizon() -> float:
	return get_viewport_rect().size.y * 0.62


func _draw() -> void:
	var vs := get_viewport_rect().size
	var target: Array = PALETTES[clampi(_stage, 0, 2)]
	var mix := clampf(_t / 0.6, 0.0, 1.0)
	var pal: Array = []
	for i in 5:
		pal.append((_pal[i] as Color).lerp(target[i], mix))
	if mix >= 1.0:
		_pal = target
	var hz := _horizon()
	# Небо
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, hz), Vector2(0, hz)]),
		PackedColorArray([pal[0], pal[0], pal[1], pal[1]]))
	# Звёзды
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_all_t * 2.0 + st.z * 20.0)
		draw_rect(Rect2(Vector2(st.x * vs.x, st.y * hz), Vector2(2, 2)), Color(0.9, 0.9, 1.0, 0.55 * tw * st.z))
	# Солнце: полосы, которые «уплывают» вниз
	var r := minf(vs.y * 0.27, vs.x * 0.34)
	var sc := Vector2(vs.x / 2.0, hz - r * 0.35)
	var y := sc.y - r
	while y < minf(sc.y + r, hz):
		var dy := y - sc.y
		var hw := sqrt(maxf(0.0, r * r - dy * dy))
		var k := (y - (sc.y - r)) / (2.0 * r)
		var gap := 0.0
		if k > 0.45:
			var band := fmod(y - sc.y + _all_t * 14.0, 16.0)
			gap = clampf((k - 0.45) * 26.0, 0.0, 9.0)
			if band < gap:
				y += 1.0
				continue
		draw_rect(Rect2(sc.x - hw, y, hw * 2.0, 1.2), (pal[2] as Color).lerp(pal[3], k))
		y += 1.0
	# Сияние солнца
	for i in 6:
		draw_circle(sc, r * (1.05 + i * 0.12), Color(pal[3], 0.05))
	# Горы с неоновой кромкой
	var grid_c: Color = pal[4]
	for layer in 2:
		var pts := PackedVector2Array()
		var amp := vs.y * (0.12 if layer == 0 else 0.07)
		pts.append(Vector2(0, hz))
		for i in 33:
			var x := vs.x * i / 32.0
			var n := absf(sin(i * 1.7 + layer * 3.0)) * 0.6 + absf(sin(i * 0.53 + layer)) * 0.4
			# Перед солнцем гор нет — силуэт расступается
			var gapk := clampf(absf(x - sc.x) / (r * 1.3), 0.0, 1.0)
			pts.append(Vector2(x, hz - amp * n * gapk))
		pts.append(Vector2(vs.x, hz))
		draw_colored_polygon(pts, Color(0.03, 0.0, 0.08) if layer == 0 else Color(0.07, 0.01, 0.14))
		var ridge := pts.slice(1, pts.size() - 1)
		draw_polyline(ridge, Color(grid_c, 0.55 if layer == 0 else 0.3), 2.0)
	# Пол и сетка
	draw_rect(Rect2(0, hz, vs.x, vs.y - hz), Color(0.02, 0.0, 0.06))
	var depth := vs.y - hz
	var scroll := fmod(_all_t * 0.9, 1.0)
	for i in 14:
		var z := (float(i) + scroll) / 14.0
		var yy := hz + depth * z * z
		var a := 0.15 + 0.85 * z
		draw_line(Vector2(0, yy), Vector2(vs.x, yy), Color(grid_c, 0.18 * a), 6.0)
		draw_line(Vector2(0, yy), Vector2(vs.x, yy), Color(grid_c, 0.9 * a), 1.6)
	for i in range(-16, 17):
		var xb := vs.x / 2.0 + i * vs.x / 12.0
		draw_line(Vector2(vs.x / 2.0 + i * 6.0, hz), Vector2(xb, vs.y), Color(grid_c, 0.16), 6.0)
		draw_line(Vector2(vs.x / 2.0 + i * 6.0, hz), Vector2(xb, vs.y), Color(grid_c, 0.75), 1.5)
	# Линия горизонта
	draw_line(Vector2(0, hz), Vector2(vs.x, hz), Color(1, 1, 1, 0.8), 2.0)
	draw_line(Vector2(0, hz), Vector2(vs.x, hz), Color(grid_c, 0.35), 10.0)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.9, 1, _flash * 0.5))


## Отражение логотипа в полу и сканлайны — поверх фона, под логотипом.
func _build_fx() -> void:
	_refl = TextureRect.new()
	_refl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = REFLECT_SHADER
	_refl.material = m
	_refl.texture = PlaceholderTexture2D.new()
	add_child(_refl)
	var scan := ColorRect.new()
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type canvas_item;
void fragment() {
	float l = 0.5 + 0.5 * sin(SCREEN_UV.y * 900.0);
	vec2 d = SCREEN_UV - 0.5;
	float v = smoothstep(0.35, 0.85, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, l * 0.12 + v * 0.55);
}
"""
	scan.material = sm
	scan.z_index = 10
	add_child(scan)
	# Звёздочки-блики на краях хрома
	var gl := Control.new()
	gl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gl.z_index = 11
	gl.draw.connect(func():
		if not is_instance_valid(_logo) or _logo.t < 1.1 or _logo.leaving >= 0.0:
			return
		var rc: Rect2 = _logo.chrome_rect()
		var spots := [rc.position + Vector2(rc.size.x * 0.12, rc.size.y * 0.3), rc.position + Vector2(rc.size.x * 0.9, rc.size.y * 0.25),
			rc.position + Vector2(rc.size.x * 0.55, rc.size.y * 0.72)]
		for i in spots.size():
			var ph := fmod(_logo.t * 0.7 + i * 0.37, 1.6)
			if ph > 0.5:
				continue
			var k := sin(ph / 0.5 * PI)
			var c: Vector2 = spots[i]
			var L := 26.0 * k
			gl.draw_line(c - Vector2(L, 0), c + Vector2(L, 0), Color(1, 1, 1, 0.9 * k), 2.0)
			gl.draw_line(c - Vector2(0, L * 1.4), c + Vector2(0, L * 1.4), Color(1, 1, 1, 0.9 * k), 2.0)
			gl.draw_line(c - Vector2(L, L) * 0.4, c + Vector2(L, L) * 0.4, Color(0.8, 0.9, 1, 0.6 * k), 1.5)
			gl.draw_line(c - Vector2(L, -L) * 0.4, c + Vector2(L, -L) * 0.4, Color(0.8, 0.9, 1, 0.6 * k), 1.5)
			gl.draw_circle(c, 4.0 * k, Color(1, 1, 1, k)))
	add_child(gl)
	_glints = gl
