extends CanvasLayer
## Проигрыватель сюжетных кат-сцен.
## Сцена — список шагов из cine_scenes.gd: смена декорации с расстановкой актёров
## и «кадры» (движение камеры, реплики, позы, перемещения, эффекты, титры).
## 3D рисуется в отдельном мире (SubViewport с own_world_3d), поэтому кат-сцену
## можно запустить поверх убежища или боя — игра в это время на паузе.
## Пробел / клик / «ОК» — следующий кадр, Esc или кнопка — пропустить всё.

signal finished

const Scenes := preload("res://scripts/cine_scenes.gd")
const Actor := preload("res://scripts/cine_actor.gd")
const CSet := preload("res://scripts/cine_set.gd")
const T := preload("res://scripts/cine_toon.gd")
const Data := preload("res://scripts/data.gd")
const BossIntro := preload("res://scripts/boss_intro.gd")

var scene_id := ""
var steps: Array = []
var _i := -1
var _st := 0.0
var _dur := 0.0
var _shot := {}
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _set: Node3D
var actors := {}
var _moves: Array = []   # [актёр, от, до, длительность, t]
var _dissolve: Array = []
var _shake := 0.0
var _was_paused := false
var _done := false
var _fireworks := 0.0
var _post: ColorRect
var _impact := 0.0
var _glitch := 0.0
var _speed := 0.0
var _frame_t := 0.0

const ANIME_FPS := 12.0   # «на двойках», как в рисованном аниме

const POST := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float impact = 0.0;
uniform float glitch = 0.0;
uniform float speed = 0.0;
uniform float tt = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	if (glitch > 0.0) {
		float band = floor(uv.y * 22.0);
		float r = fract(sin(band * 12.9898 + floor(tt * 24.0) * 7.0) * 43758.5453);
		if (r < glitch * 0.7) {
			uv.x += (r - 0.35) * 0.12 * glitch;
		}
	}
	vec2 c = uv - 0.5;
	float ca = 0.004 + length(c) * 0.012 + glitch * 0.02;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ca).b;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 1.2);
	col = clamp((col - 0.5) * 1.1 + 0.52, 0.0, 1.0);
	if (speed > 0.0) {
		float a = atan(c.y, c.x);
		float s = step(0.82, fract(sin(floor(a * 70.0) * 91.345 + floor(tt * 12.0)) * 437.585));
		col = mix(col, vec3(1.0), s * smoothstep(0.28, 0.75, length(c)) * speed * 0.85);
	}
	if (impact > 0.0) {
		float b = step(0.42, l);
		vec3 imp = mix(vec3(0.02, 0.0, 0.04), vec3(1.0, 0.93, 0.04), b);
		col = mix(col, imp, impact);
	}
	float vig = smoothstep(0.5, 1.05, length(c) * 1.35);
	col *= 1.0 - vig * 0.6;
	COLOR = vec4(col, 1.0);
}
"""
var _fw_t := 0.0

var _bars: Array = []
var _fade: ColorRect
var _flash: ColorRect
var _sub_box: Control
var _sub_name: Label
var _sub_plate: Panel
var _sub_text: Label
var _cap: Label
var _title: Control
var _title_big: Label
var _title_small: Label
var _title_t := -1.0
var _skip: Button


## Запускает кат-сцену поверх сцены host. Возвращает узел (ждать сигнал finished).
static func play(host: Node, id: String) -> Node:
	var c: CanvasLayer = load("res://scripts/cutscene.gd").new()
	c.scene_id = id
	host.add_child(c)
	return c


static func exists(id: String) -> bool:
	return Scenes.SCENES.has(id)


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	steps = Scenes.SCENES.get(scene_id, [])
	_build_ui()
	_next()


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	var k := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.55, 1.8)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.handle_input_locally = false
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		_vp.msaa_3d = Viewport.MSAA_2X
	cont.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.05
	_cam.far = 400.0
	_world.add_child(_cam)
	_cam.make_current()

	# Аниме-плёнка: расслоение цвета к краям, сочный грейд, кадры-вспышки,
	# глитч на склейках, линии скорости, виньетка
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psm := ShaderMaterial.new()
	var psh := Shader.new()
	psh.code = POST
	psm.shader = psh
	_post.material = psm
	add_child(_post)

	# Кинополосы 2.35:1
	for i in 2:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_bars.append(r)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	# Закадровый текст
	_cap = Label.new()
	_cap.add_theme_font_override("font", BossIntro.font(k * 0.5))
	_cap.add_theme_font_size_override("font_size", int(26 * k))
	_cap.add_theme_color_override("font_color", Color(0.99, 0.93, 0.04))
	_cap.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.05))
	_cap.add_theme_constant_override("outline_size", int(6 * k))
	_cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_cap.add_theme_constant_override("shadow_offset_x", 2)
	_cap.add_theme_constant_override("shadow_offset_y", 2)
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cap)

	# Субтитры реплик: косая плашка с именем + текст
	_sub_box = Control.new()
	_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_box)
	_sub_plate = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.93, 0.04)
	sb.skew = Vector2(0.45, 0)
	sb.corner_radius_top_left = 2
	_sub_plate.add_theme_stylebox_override("panel", sb)
	_sub_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_box.add_child(_sub_plate)
	_sub_name = Label.new()
	_sub_name.add_theme_font_override("font", BossIntro.font(k * 0.5))
	_sub_name.add_theme_font_size_override("font_size", int(22 * k))
	_sub_name.add_theme_color_override("font_color", Color(0.06, 0.03, 0.1))
	_sub_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_plate.add_child(_sub_name)
	_sub_text = Label.new()
	_sub_text.add_theme_font_size_override("font_size", int(25 * k))
	_sub_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_sub_text.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.05))
	_sub_text.add_theme_constant_override("outline_size", int(6 * k))
	_sub_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_sub_text.add_theme_constant_override("shadow_offset_x", 2)
	_sub_text.add_theme_constant_override("shadow_offset_y", 2)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_box.add_child(_sub_text)

	# Титры глав
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	add_child(_title)
	var stripe := ColorRect.new()
	stripe.name = "stripe"
	stripe.color = Color(0.0, 0.94, 1.0)
	_title.add_child(stripe)
	_title_big = Label.new()
	_title_big.add_theme_font_override("font", BossIntro.font(k))
	_title_big.add_theme_font_size_override("font_size", int(68 * k))
	_title_big.add_theme_color_override("font_color", Color(1, 1, 1))
	_title_big.add_theme_color_override("font_color", Color(0.99, 0.93, 0.04))
	_title_big.add_theme_color_override("font_shadow_color", Color(1.0, 0.0, 0.35, 0.95))
	_title_big.add_theme_constant_override("shadow_offset_x", int(5 * k))
	_title_big.add_theme_constant_override("shadow_offset_y", int(4 * k))
	_title_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_child(_title_big)
	_title_small = Label.new()
	_title_small.add_theme_font_override("font", BossIntro.font(k * 0.5))
	_title_small.add_theme_font_size_override("font_size", int(24 * k))
	_title_small.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0))
	_title_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_child(_title_small)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

	_skip = Button.new()
	_skip.text = "ПРОПУСТИТЬ  ▶▶"
	_skip.flat = true
	_skip.add_theme_font_size_override("font_size", int(18 * k))
	_skip.add_theme_color_override("font_color", Color(0.99, 0.93, 0.04, 0.85))
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	add_child(_skip)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var k := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.55, 1.8)
	var bar_h := maxf(0.0, (vs.y - vs.x / 2.35) * 0.5)
	bar_h = maxf(bar_h, vs.y * 0.08)
	(_bars[0] as ColorRect).position = Vector2.ZERO
	(_bars[0] as ColorRect).size = Vector2(vs.x, bar_h)
	(_bars[1] as ColorRect).position = Vector2(0, vs.y - bar_h)
	(_bars[1] as ColorRect).size = Vector2(vs.x, bar_h)
	var tw := minf(vs.x * 0.8, 1000.0 * k)
	_cap.position = Vector2((vs.x - tw) * 0.5, vs.y - bar_h - 130 * k)
	_cap.size = Vector2(tw, 110 * k)
	_cap.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub_box.position = Vector2((vs.x - tw) * 0.5, vs.y - bar_h - 120 * k)
	_sub_box.size = Vector2(tw, 115 * k)
	_sub_plate.position = Vector2(0, 0)
	_sub_plate.size = Vector2(220 * k, 36 * k)
	_sub_name.size = _sub_plate.size
	_sub_text.position = Vector2(8 * k, 42 * k)
	_sub_text.size = Vector2(tw - 16 * k, 72 * k)
	var stripe: ColorRect = _title.get_node("stripe")
	_title.position = Vector2(0, vs.y * 0.38)
	_title.size = Vector2(vs.x, 160 * k)
	_title_big.position = Vector2(0, 0)
	_title_big.size = Vector2(vs.x, 90 * k)
	stripe.position = Vector2(vs.x * 0.25, 92 * k)
	stripe.size = Vector2(vs.x * 0.5, 5 * k)
	_title_small.position = Vector2(0, 104 * k)
	_title_small.size = Vector2(vs.x, 40 * k)
	_skip.position = Vector2(vs.x - 250 * k, bar_h * 0.5 - 18 * k)
	_skip.size = Vector2(230 * k, 36 * k)


# ---------- Шаги ----------

func _hero_key() -> String:
	var c: Dictionary = Data.CHARACTERS.get(Data.selected_character, Data.CHARACTERS["vega"])
	var spr: String = c["sprite"]
	return spr if Actor.Pixel.LOOKS.has(spr) else "hero"


func _hero_name() -> String:
	return Data.CHARACTERS.get(Data.selected_character, Data.CHARACTERS["vega"])["name"]


func _txt(v) -> String:
	if v is Dictionary:
		return str(v.get(Data.selected_character, v.get("_", "")))
	return str(v).replace("{HERO}", _hero_name())


func _next() -> void:
	_i += 1
	if _i >= steps.size():
		_end()
		return
	var s: Dictionary = steps[_i]
	if s.has("set"):
		_load_set(s)
		_next()
		return
	_start_shot(s)


func _load_set(s: Dictionary) -> void:
	if _set:
		_set.queue_free()
	for a in actors.values():
		(a as Node3D).queue_free()
	actors.clear()
	_moves.clear()
	_dissolve.clear()
	_set = CSet.make(str(s["set"]))
	_world.add_child(_set)
	for a in s.get("actors", []):
		var key: String = a[1]
		if key == "HERO":
			key = _hero_key()
		var node := Actor.make(key)
		_world.add_child(node)
		node.position = _v(a[2])
		node.rotation.y = deg_to_rad(float(a[3]) if a.size() > 3 else 0.0)
		node._last_pos = node.global_position
		actors[a[0]] = node
	_fade.color.a = 1.0
	_glitch = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.35)


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _start_shot(s: Dictionary) -> void:
	_shot = s
	_st = 0.0
	var text_len := 0
	_cap.text = ""
	_sub_box.visible = false
	if s.has("cap"):
		_cap.text = _txt(s["cap"])
		text_len = _cap.text.length()
	if s.has("line"):
		var ln: Array = s["line"]
		var who: String = ln[0]
		var nm := _txt(ln[1])
		if ln[1] == "HERO":
			nm = _hero_name()
		_sub_name.text = nm.to_upper()
		_sub_text.text = _txt(ln[2])
		var sb: StyleBoxFlat = _sub_plate.get_theme_stylebox("panel")
		sb.bg_color = Color(0.99, 0.93, 0.04) if who == "hero" else _who_color(who)
		_sub_box.visible = true
		text_len = _sub_text.text.length()
		if actors.has(who):
			actors[who].say(maxf(1.0, text_len * 0.05))
	_dur = float(s.get("t", maxf(3.0, 1.6 + text_len * 0.055)))
	for a in s.get("pose", {}):
		if actors.has(a):
			actors[a].set_mode(s["pose"][a])
	for a in s.get("look", {}):
		if actors.has(a):
			var tg = s["look"][a]
			if tg == null:
				actors[a].look_target = null
			elif tg is String and actors.has(tg):
				var other: Node3D = actors[tg]
				actors[a].look_target = other.global_position + Vector3(0, 1.6 * other.scale.y, 0)
			else:
				actors[a].look_target = _v(tg)
	for a in s.get("face", {}):
		if actors.has(a):
			var tg = s["face"][a]
			actors[a].face(actors[tg].global_position if (tg is String and actors.has(tg)) else _v(tg))
	for a in s.get("move", {}):
		if actors.has(a):
			var mv: Array = s["move"][a]
			var node: Node3D = actors[a]
			var to := _v(mv[0])
			node.face(to)
			_moves.append([node, node.position, to, float(mv[1]), 0.0])
	for a in s.get("dissolve", []):
		if actors.has(a):
			_dissolve.append([actors[a], 0.0, (actors[a] as Node3D).scale])
	_speed = 1.0 if (s.get("speed", false) or str(s.get("fx", "")) == "flash_shake") else 0.0
	match str(s.get("fx", "")):
		"flash":
			_impact = 1.0
			_flash.color = Color(1, 1, 1, 0.6)
		"shake":
			_shake = 0.25
			_glitch = 0.4
		"flash_shake":
			_impact = 1.0
			_flash.color = Color(1, 1, 1, 0.6)
			_shake = 0.3
		"fireworks":
			_fireworks = 999.0
	if s.has("title"):
		_title_big.text = _txt(s["title"][0])
		_title_small.text = _txt(s["title"][1]) if s["title"].size() > 1 else ""
		_title_t = 0.0
	if s.has("sound"):
		Sound.play(str(s["sound"]), -2.0)
	_cam_update(0.0)


func _who_color(who: String) -> Color:
	if actors.has(who):
		var sp: Dictionary = actors[who].spec
		if sp.has("neon"):
			return Color(sp["neon"]).lerp(Color.WHITE, 0.15)
	return Color(1.0, 0.6, 0.15)


func _cam_update(_d: float) -> void:
	if not _shot.has("cam"):
		return
	var c: Array = _shot["cam"]
	var k := clampf(_st / maxf(_dur, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var p0 := _v(c[0])
	var l0 := _v(c[1])
	var p1 := _v(c[2]) if c.size() > 2 else p0
	var l1 := _v(c[3]) if c.size() > 3 else l0
	var p := p0.lerp(p1, k)
	var l := l0.lerp(l1, k)
	# Лёгкая «ручная» камера
	var tt := Time.get_ticks_msec() / 1000.0
	p += Vector3(sin(tt * 0.7) * 0.02, sin(tt * 1.1) * 0.015, 0)
	if _shake > 0.0:
		p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.3
	if p.distance_to(l) > 0.01:
		_cam.look_at_from_position(p, l)
	_light_rig(p, l)
	var fv: Array = _shot.get("fov", [45.0, 45.0])
	_cam.fov = lerpf(float(fv[0]), float(fv[1] if fv.size() > 1 else fv[0]), k)


## «Свет» аниме-заливки: откуда падает ключ, цвета тени и каймы, костёр.
func _light_rig(p: Vector3, l: Vector3) -> void:
	if _set == null:
		return
	var fwd := l - p
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var side := -1.0 if bool(_shot.get("key_left", false)) else 1.0
	var kdir := (-fwd * 1.0 - right * 1.1 * side + Vector3.UP * 1.1).normalized()
	RenderingServer.global_shader_parameter_set("cine_key_dir", kdir)
	RenderingServer.global_shader_parameter_set("cine_key_col", _set.key_color)
	RenderingServer.global_shader_parameter_set("cine_shadow", _set.shadow_tint)
	RenderingServer.global_shader_parameter_set("cine_rim", Color(_set.rim_color, 1.0))
	RenderingServer.global_shader_parameter_set("cine_pt", _set.fire)
	RenderingServer.global_shader_parameter_set("cine_pt_col", _set.fire_color)


func _process(delta: float) -> void:
	if _done:
		return
	delta = minf(delta, 0.1)
	_st += delta
	_shake = maxf(0.0, _shake - delta * 0.5)
	# Картинка обновляется 12 раз в секунду — анимация «на двойках»
	_frame_t += delta
	if _frame_t >= 1.0 / ANIME_FPS:
		_frame_t = fmod(_frame_t, 1.0 / ANIME_FPS)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_impact = maxf(0.0, _impact - delta * 6.0)
	_glitch = maxf(0.0, _glitch - delta * 2.5)
	var pm: ShaderMaterial = _post.material
	pm.set_shader_parameter("impact", 1.0 if _impact > 0.5 else 0.0)
	pm.set_shader_parameter("glitch", _glitch)
	pm.set_shader_parameter("speed", _speed)
	pm.set_shader_parameter("tt", Time.get_ticks_msec() / 1000.0)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.6)
	_cam_update(delta)
	for m in _moves:
		m[4] = float(m[4]) + delta
		var k := clampf(float(m[4]) / float(m[3]), 0.0, 1.0)
		(m[0] as Node3D).position = (m[1] as Vector3).lerp(m[2], k)
	_moves = _moves.filter(func(m): return float(m[4]) < float(m[3]))
	for d in _dissolve:
		d[1] = float(d[1]) + delta
		var k := clampf(float(d[1]) / 2.5, 0.0, 1.0)
		var n: Node3D = d[0]
		n.scale = (d[2] as Vector3) * Vector3(1.0 - k * 0.6, 1.0 - k, 1.0 - k * 0.6)
		n.position.y += delta * 0.6
	if _fireworks > 0.0:
		_fw_t -= delta
		if _fw_t <= 0.0:
			_fw_t = randf_range(0.35, 0.8)
			_firework()
	if _title_t >= 0.0:
		_title_t += delta
		var a := clampf(_title_t / 0.5, 0.0, 1.0) * clampf((_dur - _st) / 0.5, 0.0, 1.0)
		_title.modulate.a = a
		_title.position.x = (1.0 - clampf(_title_t / 0.5, 0.0, 1.0)) * -80.0 + _title_t * 6.0
	if _st >= _dur:
		_title_t = -1.0
		_title.modulate.a = 0.0
		_next()


func _firework() -> void:
	var p := Vector3(randf_range(-12, 12), randf_range(9, 16), randf_range(-20, -10))
	var c: Color = [Color(1.0, 0.3, 0.7), Color(0.3, 0.95, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5)][randi() % 4]
	var em := CPUParticles3D.new()
	em.position = p
	em.one_shot = true
	em.explosiveness = 1.0
	em.amount = 60
	em.lifetime = 1.6
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.2
	em.direction = Vector3.UP
	em.spread = 180.0
	em.initial_velocity_min = 4.0
	em.initial_velocity_max = 6.0
	em.gravity = Vector3(0, -3, 0)
	em.damping_min = 2.0
	em.damping_max = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 4
	sm.rings = 2
	em.mesh = sm
	em.material_override = T.neon(c, 5.0)
	em.emitting = true
	_world.add_child(em)
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.light_energy = 3.0
	l.omni_range = 18.0
	_world.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
	get_tree().create_timer(2.0, true, false, true).timeout.connect(em.queue_free)
	Sound.play("boom", -14.0, randf_range(1.3, 1.8))


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		if _st > 0.35:
			_st = _dur
		get_viewport().set_input_as_handled()


func skip() -> void:
	_i = steps.size()
	_end()


func _end() -> void:
	if _done:
		return
	_done = true
	_sub_box.visible = false
	_cap.text = ""
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(func():
		get_tree().paused = _was_paused
		finished.emit()
		queue_free())
