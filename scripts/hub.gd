extends Node
## «Неоновое убежище» — хаб между забегами в стиле HD-2D:
## 3D-мир с наклонной камерой, светом и тенями, а герои и жители — пиксельные спрайты.
## Здесь строятся и улучшаются здания, призываются жители, выбирается герой.

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const Meta := preload("res://scripts/meta.gd")
const Fx := preload("res://scripts/fx.gd")
const UiFocus := preload("res://scripts/ui_focus.gd")

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)
const PANEL_BG := Color(0.05, 0.03, 0.1, 0.92)
const SPRITE_PX := 0.045
const PORTAL_POS := Vector3(0, 0, -2.5)
const BOARD := Vector3(-3.6, 0, -1.0)   # доска заданий у портала
const Quests := preload("res://scripts/quests.gd")

var _vp: SubViewport
var _world: Node3D
var _camera: Camera3D
var _cam_target := Vector3.ZERO
var _cam_off := Vector3(0, 11.0, 12.5)
var _shake := 0.0

var _avatar: Node3D
var _av_base: Sprite3D
var _av_emit: Sprite3D
var _av_frames: Dictionary
var _av_t := 0.0
var _facing_left := false

var _buildings := {}
var _spinners: Array = []
var _bobbers: Array = []
var _villagers: Array = []
var _t := 0.0

# Интерфейс
var _hud: CanvasLayer
var _shards_label: Label
var _mats_label: Label
var _hero_label: Label
var _prompt: Label
var _panel_root: Control
var _panel_box: VBoxContainer
var _panel_scroll: ScrollContainer
var _panel_style: StyleBoxFlat


## Экран выше, чем шире (телефон вертикально)
func _portrait() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.y > vs.x


## Доступная ширина содержимого окна (экран минус поля окна).
func _avail() -> float:
	var vs := get_viewport().get_visible_rect().size
	return vs.x - (52.0 + 28.0 + 16.0 if _portrait() else 110.0 + 56.0 + 20.0)


## Сколько колонок шириной cell помещается в окно.
func _cols(cell: float) -> int:
	return maxi(1, int((_avail() + 10.0) / (cell + 10.0)))


## Окно никогда не выходит за экран: размер — по содержимому, но не больше экрана.
func _fit_panel() -> void:
	if _panel_scroll == null:
		return
	_panel_style.set_content_margin_all(14 if _portrait() else 28)
	var vs := get_viewport().get_visible_rect().size
	var want := _panel_box.get_combined_minimum_size()
	var lim := vs - (Vector2(52, 120) if _portrait() else Vector2(110, 100))
	_panel_scroll.custom_minimum_size = Vector2(minf(minf(want.x, lim.x), _avail()), minf(want.y, lim.y))
	# Прокрутка — только вертикальная: ширина содержимого всегда подогнана под экран
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
var _toast: Label
var _near := ""
var _panel_id := ""


func _ready() -> void:
	Meta.ensure_loaded()
	Data.coop = false
	Data.world_seed = 0
	if not Meta.hero_unlocked(Data.selected_character):
		Data.selected_character = "vega"
	if not Meta.hero_unlocked(Data.selected_character2):
		Data.selected_character2 = "vega"
	_build_viewport()
	_build_environment()
	_build_ground()
	_build_portal()
	_net_client = Net.mode == "client"
	for id in Meta.BUILDINGS:
		_buildings[id] = {"root": null}
		_rebuild_building(id)
	_build_places()
	_build_board()
	_build_decor()
	_build_avatar()
	_spawn_npcs()
	if _net_client:
		_avatar.position = Vector3(2.0, 0, 4.0)
		Net.send_profile()
	_build_post()
	_build_hud()
	Sound.set_track("hub")
	if not Meta.intro_seen and not _net_client:
		get_tree().create_timer(1.2).timeout.connect(func():
			if _panel_id == "":
				_open_panel("prologue"))
	if not Meta.last_reward.is_empty():
		_show_reward(Meta.last_reward)
		Meta.last_reward = {}
	if Meta.just_built != "":
		var bid := Meta.just_built
		Meta.just_built = ""
		get_tree().create_timer(2.5).timeout.connect(func():
			_toast_text("⚒ Стройка завершена: %s, ур. %d!" % [Meta.BUILDINGS[bid]["name"], Meta.level(bid)])
			Sound.play("evolve", -4.0))


# ================= Пиксельный пост-эффект: палитра + дизеринг =================

const PIXEL_POST := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float levels = 11.0;
uniform float px = 3.0;
const float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 d = SCREEN_UV - 0.5;
	c *= mix(0.65, 1.0, smoothstep(0.9, 0.35, length(d)));
	COLOR = vec4(c, 1.0);
}
"""


func _build_post() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = PIXEL_POST
	var m := ShaderMaterial.new()
	m.shader = sh
	var win := get_window()
	m.set_shader_parameter("px", 3.0 * maxf(1.0, win.content_scale_factor))
	rect.material = m
	layer.add_child(rect)


# ================= 3D-мир =================

const RENDER_H := 540  # высота 3D-картинки в пикселях — размер «пикселя» одинаков на любом мониторе
var _view_rect: TextureRect


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = [0, 1024, 2048, 4096][clampi(Settings.shadows, 0, 3)]
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_view_rect = TextureRect.new()
	_view_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view_rect.texture = _vp.get_texture()
	_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view_rect)
	_resize_view()
	get_viewport().size_changed.connect(_resize_view)
	_world = Node3D.new()
	_vp.add_child(_world)
	_camera = Camera3D.new()
	_camera.fov = 34.0
	_world.add_child(_camera)
	_resize_view()


var _title_l: Label
var _hint_l: Label


## Префикс подсказки у здания: «[E]  » / «[A]  »; на телефоне — кнопка «ВОЙТИ» на экране
func _pk() -> String:
	return "" if Settings.input_mode() == "touch" else "[%s]  " % Settings.key("interact")


## Нижняя подсказка управления в убежище — под текущее устройство
func _hint_text() -> String:
	match Settings.input_mode():
		"touch":
			return "Касание и сдвиг пальца — ходить   •   ВОЙТИ — войти / говорить   •   II — пауза"
		"pad":
			return "Левый стик — ходить   •   A — войти / говорить   •   START — пауза   •   B — назад"
	return "WASD — ходить   •   E — войти / говорить   •   ESC — пауза / назад"


func _on_input_mode(_m: String) -> void:
	if _hint_l:
		_hint_l.text = _hint_text()


## Верхние надписи: на вертикальном экране — под значками, по центру
var _safe_root: Control


func _layout_top() -> void:
	if _title_l == null:
		return
	if _safe_root:
		Settings.apply_safe(_safe_root)
	var p := _portrait()
	_title_l.offset_top = 140 if p else 14
	_title_l.add_theme_font_size_override("font_size", 26 if p else 30)
	if p:
		_hero_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hero_label.offset_left = -340
		_hero_label.offset_right = 340
		_hero_label.offset_top = 182
	else:
		_hero_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hero_label.offset_left = -420
		_hero_label.offset_right = -18
		_hero_label.offset_top = 18
	_hint_l.offset_left = -340 if p else -400
	_hint_l.offset_right = 340 if p else 400
	_hint_l.offset_top = -56 if p else -34


func _resize_view() -> void:
	_layout_top()
	var s := get_viewport().get_visible_rect().size
	var aspect := s.x / maxf(s.y, 1.0)
	# Высота картинки растёт с разрешением экрана (настройка чёткости текстур)
	var rh := int(RENDER_H * Settings.tex_scale())
	if Settings.pixel_art > 0:
		rh = int(Settings.PIXEL_TARGET[Settings.pixel_art])   # пиксельный 3D: такая же сетка, как в бою
	_vp.size = Vector2i(int(rh * aspect), rh)
	# Вертикальный экран: держим ширину кадра, камера чуть выше
	if _camera:
		if aspect < 1.0:
			_camera.keep_aspect = Camera3D.KEEP_WIDTH
			_camera.fov = 30.0
			_cam_off = Vector3(0, 16.0, 16.5)
		else:
			_camera.keep_aspect = Camera3D.KEEP_HEIGHT
			_camera.fov = 34.0
			_cam_off = Vector3(0, 11.0, 12.5)
	if _panel_id != "" and _panel_box:
		_fill_panel.call_deferred()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.02, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.26, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.08, 0.3)
	env.fog_density = 0.018
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 35, 0)
	moon.light_color = Color(0.55, 0.6, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = Settings.shadows > 0
	moon.directional_shadow_max_distance = 45.0
	moon.shadow_bias = 0.08
	moon.shadow_normal_bias = 2.5
	_world.add_child(moon)


func _mat(color: Color, rough := 0.8, metal := 0.2, surface := "panel", tile := 1.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.lightened(0.15)
	m.roughness = rough
	m.metallic = metal * 0.5
	if surface != "":
		# Пиксельная текстура, наложенная по мировым координатам на все грани
		m.albedo_texture = Pixel.surface(surface)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(tile, tile, tile)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _emat(color: Color, energy := 2.5, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


func _cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 8
	return t


func _light(parent: Node3D, pos: Vector3, color: Color, energy := 1.2, rng := 6.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
	return l


func _label3d(parent: Node3D, text: String, pos: Vector3, color: Color, size := 36) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_modulate = Color(0.04, 0.02, 0.08)
	l.no_depth_test = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	parent.add_child(l)
	return l


func _particles(parent: Node3D, pos: Vector3, color: Color, amount: int, extents: Vector3,
		gravity: Vector3, life: float, size := 0.08, one_shot := false, speed := 0.5) -> GPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.gravity = gravity
	p.direction = Vector3.UP
	p.spread = 60.0 if one_shot else 25.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(color, 0.0), Pixel.hdr(color, 1.6), Color(color, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	p.color_ramp = g
	# Частицы считает видеокарта
	var gp := Fx.gpu3d(p)
	parent.add_child(gp)
	gp.emitting = true
	if one_shot:
		get_tree().create_timer(life + 0.3).timeout.connect(gp.queue_free)
	return gp


func _build_ground() -> void:
	var g := Pixel.ground()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	var m := StandardMaterial3D.new()
	m.albedo_texture = g["base"]
	m.albedo_color = Color(0.85, 0.82, 0.95)
	m.uv1_scale = Vector3(22, 22, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.9
	_add(_world, plane, m, Vector3.ZERO)
	# Неоновые схемы — отдельный светящийся слой над землёй
	var em := StandardMaterial3D.new()
	em.albedo_texture = g["emit"]
	em.albedo_color = Color(1.4, 1.4, 1.4, 0.8)
	em.uv1_scale = Vector3(22, 22, 1)
	em.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_add(_world, plane, em, Vector3(0, 0.015, 0))

	# Центральная площадь с неоновым кругом
	_add(_world, _cyl(6.5, 6.5, 0.12, 48), _mat(Color(0.16, 0.14, 0.22), 0.6, 0.4, "tile", 0.8), Vector3(0, 0.06, 0))
	_add(_world, _torus(6.4, 6.6), _emat(CYAN, 2.0), Vector3(0, 0.13, 0))
	_add(_world, _torus(3.0, 3.12), _emat(MAGENTA, 1.6), Vector3(0, 0.13, 0))
	# Дорожки от площади к зданиям
	for id in Meta.BUILDINGS:
		var p: Vector3 = Meta.BUILDINGS[id]["pos"]
		var dir := Vector3(p.x, 0, p.z)
		var len := dir.length() - 6.0
		if len <= 0.5:
			continue
		var mid := dir.normalized() * (6.0 + len / 2.0)
		var path := _add(_world, _box(1.4, 0.06, len), _mat(Color(0.14, 0.12, 0.19), 0.7, 0.3, "tile", 1.4), Vector3(mid.x, 0.05, mid.z))
		path.rotation.y = atan2(dir.x, dir.z)


func _build_portal() -> void:
	var root := Node3D.new()
	root.position = PORTAL_POS
	_world.add_child(root)
	var stone := _mat(Color(0.22, 0.2, 0.3), 0.7, 0.2, "brick", 1.5)
	_add(root, _box(0.6, 3.6, 0.6), stone, Vector3(-1.8, 1.8, 0))
	_add(root, _box(0.6, 3.6, 0.6), stone, Vector3(1.8, 1.8, 0))
	_add(root, _box(4.4, 0.5, 0.7), stone, Vector3(0, 3.8, 0))
	_add(root, _box(0.1, 3.0, 0.62), _emat(MAGENTA, 3.0), Vector3(-1.5, 1.8, 0))
	_add(root, _box(0.1, 3.0, 0.62), _emat(MAGENTA, 3.0), Vector3(1.5, 1.8, 0))
	var ring := _add(root, _torus(1.25, 1.45), _emat(Color(0.7, 0.4, 1.0), 3.0), Vector3(0, 1.9, 0), Vector3(90, 0, 0))
	_spinners.append([ring, Vector3.FORWARD, 1.2])
	var disc := _add(root, _cyl(1.25, 1.25, 0.05, 32), _emat(Color(0.5, 0.2, 0.9), 1.5, 0.55), Vector3(0, 1.9, 0), Vector3(90, 0, 0))
	_spinners.append([disc, Vector3.UP, -2.0])
	_light(root, Vector3(0, 2.0, 1.2), Color(0.75, 0.4, 1.0), 2.5, 9.0)
	_particles(root, Vector3(0, 1.9, 0), Color(0.8, 0.5, 1.0), 40, Vector3(1.0, 1.0, 0.1), Vector3(0, 0.6, 0), 2.0, 0.07)
	_label3d(root, "ПОРТАЛ", Vector3(0, 4.6, 0), Color(1.0, 0.7, 1.0), 44)


# ================= Здания =================

func _rebuild_building(id: String) -> void:
	var info: Dictionary = Meta.BUILDINGS[id]
	var old: Node3D = _buildings[id]["root"]
	if old:
		_spinners = _spinners.filter(func(s): return is_instance_valid(s[0]) and not old.is_ancestor_of(s[0]))
		_bobbers = _bobbers.filter(func(b): return is_instance_valid(b[0]) and not old.is_ancestor_of(b[0]))
		old.queue_free()
	var root := Node3D.new()
	root.position = info["pos"]
	_world.add_child(root)
	_buildings[id]["root"] = root
	var lvl := _lvl(id)
	var col: Color = info["color"]
	var metal := _mat(Color(0.16, 0.15, 0.22), 0.6, 0.5)
	_add(root, _box(3.6, 0.3, 3.6), _mat(Color(0.12, 0.11, 0.17), 0.7, 0.3, "brick", 1.6), Vector3(0, 0.15, 0))
	_add(root, _box(3.65, 0.05, 3.65), _emat(col, 0.8), Vector3(0, 0.31, 0))

	if lvl == 0:
		# Стройплощадка: деревянные леса, доски, ящики и каркас-голограмма будущего здания
		var plank := _mat(Color(0.45, 0.33, 0.22), 0.9, 0.0, "wood", 1.4)
		var stone := _mat(Color(0.3, 0.28, 0.34), 0.85, 0.1, "brick", 1.2)
		for x in [-1.4, 1.4]:
			for z in [-1.4, 1.4]:
				_add(root, _box(0.14, 2.6, 0.14), plank, Vector3(x, 1.6, z))
		for y in [1.0, 2.0]:
			for z in [-1.4, 1.4]:
				_add(root, _box(2.95, 0.1, 0.18), plank, Vector3(0, y, z))
			for x in [-1.4, 1.4]:
				_add(root, _box(0.18, 0.1, 2.95), plank, Vector3(x, y, 0))
		# Начатая кладка нижнего этажа
		_add(root, _box(2.4, 0.6, 0.35), stone, Vector3(0, 0.6, -1.05))
		_add(root, _box(0.35, 0.6, 1.6), stone, Vector3(-1.05, 0.6, -0.3))
		_add(root, _box(0.9, 0.35, 0.35), stone, Vector3(0.7, 0.48, 0.9))
		# Каркас-голограмма: только светящиеся рёбра
		var holo := _emat(col, 1.6, 0.8)
		var hh := 2.4
		for x in [-1.1, 1.1]:
			for z in [-1.1, 1.1]:
				_add(root, _box(0.04, hh, 0.04), holo, Vector3(x, 0.35 + hh / 2.0, z))
		for z in [-1.1, 1.1]:
			_add(root, _box(2.24, 0.04, 0.04), holo, Vector3(0, 0.35 + hh, z))
		for x in [-1.1, 1.1]:
			_add(root, _box(0.04, 0.04, 2.24), holo, Vector3(x, 0.35 + hh, 0))
		# Ящики и брёвна рядом
		_add(root, _box(0.6, 0.6, 0.6), plank, Vector3(1.0, 0.65, 1.0), Vector3(0, 20, 0))
		_add(root, _cyl(0.12, 0.12, 1.6, 6), plank, Vector3(-0.6, 0.45, 1.1), Vector3(0, 0, 90))
		_add(root, _cyl(0.12, 0.12, 1.6, 6), plank, Vector3(-0.6, 0.68, 1.1), Vector3(0, 10, 90))
		_label3d(root, "%s\nПОСТРОИТЬ — %s" % [info["name"], Meta.cost_text(Meta.build_cost(id))] if id != "hall" else "%s\nОТКРЫТА — ИДЁТ РЕМОНТ" % info["name"], Vector3(0, 3.5, 0), Color(col, 0.9), 30)
		if id == "hall":
			# Таверна работает и во время стройки: временный вход под навесом
			_add(root, _box(2.2, 1.6, 1.6), _mat(Color(0.35, 0.25, 0.18), 0.9, 0.0, "wood", 1.4), Vector3(0, 1.1, 0.6))
			_door(root, 1.4, col)
		return

	var floors := mini(lvl, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var top := 0.3
	for i in floors:
		var w := 2.7 - 0.3 * i
		var h := 1.15
		_add(root, _box(w, h, w), metal, Vector3(0, top + h / 2.0, 0))
		_add(root, _box(w + 0.06, 0.07, w + 0.06), _emat(col, 1.6), Vector3(0, top + h - 0.09, 0))
		for j in 3:
			var lit := rng.randf() < 0.7
			var wc := Color(1.0, 0.8, 0.5) if rng.randf() < 0.5 else col
			if i == 0 and j == 1:
				continue  # здесь дверь
			_add(root, _box(0.32, 0.38, 0.05), _emat(wc, 1.3) if lit else _mat(Color(0.05, 0.05, 0.08)),
				Vector3(-0.7 + j * 0.7, top + h * 0.5, w / 2.0 + 0.02))
		if i == 0:
			_door(root, w / 2.0, col)
		top += h

	# Особая верхушка у каждого здания
	match id:
		"forge":
			_add(root, _cyl(0.28, 0.32, 1.4), metal, Vector3(0.6, top + 0.7, -0.4))
			_add(root, _cyl(0.22, 0.22, 0.1), _emat(Color(1.0, 0.5, 0.15), 4.0), Vector3(0.6, top + 1.42, -0.4))
			_particles(root, Vector3(0.6, top + 1.5, -0.4), Color(0.6, 0.5, 0.55), 20, Vector3(0.1, 0.05, 0.1), Vector3(0.2, 0.6, 0), 3.0, 0.18)
			_particles(root, Vector3(0.6, top + 1.5, -0.4), Color(1.0, 0.5, 0.15), 10, Vector3(0.1, 0.05, 0.1), Vector3(0, 1.0, 0), 1.0, 0.06)
			_add(root, _box(0.9, 0.35, 0.5), _mat(Color(0.3, 0.3, 0.35), 0.4, 0.8), Vector3(-1.6, 0.5, 1.2))
		"medbay":
			var cross := Node3D.new()
			cross.position = Vector3(0, top + 0.9, 0)
			root.add_child(cross)
			_add(cross, _box(1.0, 0.28, 0.14), _emat(Color(1.0, 0.25, 0.35), 3.5), Vector3.ZERO)
			_add(cross, _box(0.28, 1.0, 0.14), _emat(Color(1.0, 0.25, 0.35), 3.5), Vector3.ZERO)
			_spinners.append([cross, Vector3.UP, 0.8])
		"core":
			var orb := _add(root, _sphere(0.45), _emat(CYAN, 4.0), Vector3(0, top + 0.9, 0))
			_bobbers.append([orb, top + 0.9, 0.15])
			var r1 := _add(root, _torus(0.75, 0.85), _emat(CYAN, 2.0), Vector3(0, top + 0.9, 0), Vector3(70, 0, 0))
			_spinners.append([r1, Vector3.UP, 1.5])
		"magnet":
			_add(root, _cyl(0.18, 0.28, 2.4), metal, Vector3(0, top + 1.2, 0))
			var r2 := _add(root, _torus(0.55, 0.68), _emat(Color(0.7, 0.4, 1.0), 2.5), Vector3(0, top + 1.8, 0))
			_spinners.append([r2, Vector3.RIGHT, 2.0])
			_add(root, _sphere(0.2), _emat(Color(0.8, 0.5, 1.0), 4.0), Vector3(0, top + 2.5, 0))
		"hall":
			var roof := _add(root, _cyl(0.0, 1.95, 1.3, 4), _mat(Color(0.7, 0.55, 0.25), 0.4, 0.8, "brick", 2.2), Vector3(0, top + 0.65, 0), Vector3(0, 45, 0))
			roof.rotation_degrees = Vector3(0, 45, 0)
			_add(root, _sphere(0.18), _emat(GOLD, 4.0), Vector3(0, top + 1.4, 0))
			for k in 4:
				var hero_ids := ["vega", "rin", "bram", "kira"]
				var unlocked := Meta.hero_unlocked(hero_ids[k])
				_add(root, _box(0.3, 0.5, 0.05), _emat(Data.CHARACTERS[hero_ids[k]]["color"], 2.5) if unlocked else _mat(Color(0.1, 0.1, 0.12)),
					Vector3(-0.9 + k * 0.6, 0.9, 1.37))
		"shrine":
			var crystal := Node3D.new()
			crystal.position = Vector3(0, top + 1.0, 0)
			root.add_child(crystal)
			_add(crystal, _cyl(0.0, 0.45, 0.7, 6), _emat(MAGENTA, 3.0), Vector3(0, 0.35, 0))
			_add(crystal, _cyl(0.45, 0.0, 0.7, 6), _emat(MAGENTA, 3.0), Vector3(0, -0.35, 0))
			_spinners.append([crystal, Vector3.UP, 1.0])
			_bobbers.append([crystal, top + 1.0, 0.2])
		"academy":
			var roof2 := _add(root, _cyl(0.0, 1.9, 1.1, 4), _mat(Color(0.3, 0.6, 0.55), 0.5, 0.5, "brick", 2.0), Vector3(0, top + 0.55, 0))
			roof2.rotation_degrees = Vector3(0, 45, 0)
			var book := _add(root, _box(0.9, 0.12, 0.65), _emat(Color(0.5, 1.0, 0.8), 2.5), Vector3(0, top + 1.6, 0), Vector3(20, 0, 0))
			_bobbers.append([book, top + 1.6, 0.12])
			_spinners.append([book, Vector3.UP, 0.7])
		"arsenal":
			for i in 3:
				var sw := _add(root, _box(0.12, 1.6, 0.05), _emat(Color(1.0, 0.45, 0.3), 2.0), Vector3(-0.7 + i * 0.7, top + 0.8, 0))
				sw.rotation_degrees.z = -15 + i * 15
			_add(root, _box(2.0, 0.25, 0.5), metal, Vector3(0, top + 0.12, 0))
		"lab":
			for i in 3:
				var tube := _add(root, _cyl(0.22, 0.22, 1.4, 10), _emat([Color(0.4, 0.85, 1.0), Color(0.6, 1.0, 0.3), Color(1.0, 0.4, 0.7)][i], 1.2, 0.55), Vector3(-0.8 + i * 0.8, top + 0.7, 0))
				_bobbers.append([tube, top + 0.7, 0.03])
			_particles(root, Vector3(0, top + 1.5, 0), Color(0.5, 1.0, 0.8), 14, Vector3(1.0, 0.1, 0.3), Vector3(0, 0.5, 0), 2.0, 0.08)
		"beacon":
			_add(root, _cyl(0.1, 0.16, 3.2), metal, Vector3(0, top + 1.6, 0))
			var tip := _add(root, _sphere(0.3), _emat(Color(0.4, 1.0, 0.5), 4.0), Vector3(0, top + 3.3, 0))
			_bobbers.append([tip, top + 3.3, 0.08])
			if lvl >= 2:
				_add(root, _cyl(0.25, 0.6, 12.0, 12), _emat(Color(0.4, 1.0, 0.5), 1.0, 0.12), Vector3(0, top + 9.0, 0))

	if lvl >= 3:
		for x in [-1.0, 1.0]:
			_add(root, _cyl(0.03, 0.03, 1.0, 4), metal, Vector3(x, top + 0.5, -0.9))
			_add(root, _sphere(0.08), _emat(Color(1.0, 0.2, 0.2), 4.0), Vector3(x, top + 1.0, -0.9))
	if lvl >= info["max"]:
		var halo := _add(root, _torus(1.6, 1.68), _emat(GOLD, 1.2), Vector3(0, top + 0.3, 0))
		_spinners.append([halo, Vector3.UP, 0.6])

	_light(root, Vector3(0, 1.8, 2.4), col, 0.8, 6.0)
	var stars := "◆".repeat(lvl) + "◇".repeat(int(info["max"]) - lvl)
	if Meta.building_busy(id) and lvl > 0:
		# Идёт стройка следующего уровня: леса вокруг и табличка
		var plank := _mat(Color(0.45, 0.33, 0.22), 0.9, 0.0, "wood", 1.4)
		for x in [-1.75, 1.75]:
			for z in [-1.75, 1.75]:
				_add(root, _box(0.1, top + 0.6, 0.1), plank, Vector3(x, (top + 0.6) / 2.0, z))
		for z in [-1.75, 1.75]:
			_add(root, _box(3.6, 0.08, 0.14), plank, Vector3(0, top * 0.6, z))
		_add(root, _box(0.5, 0.5, 0.5), _emat(Color(1.0, 0.7, 0.2), 1.6), Vector3(1.2, top + 0.9, 1.2))
		stars += "\n⚒ стройка ур. %d — ещё %d выл." % [int(Meta.construct["lvl"]), int(Meta.construct["left"])]
	_label3d(root, "%s\n%s" % [info["name"], stars], Vector3(0, top + 3.0 if id != "beacon" else top + 4.4, 0), col.lightened(0.3), 30)


## Дверь на фасаде: створка, рама, неоновая подсветка и фонарь.
func _door(root: Node3D, z: float, col: Color) -> void:
	_add(root, _box(0.62, 0.95, 0.06), _mat(Color(0.3, 0.2, 0.14), 0.9, 0.0, "wood", 2.0), Vector3(0, 0.78, z + 0.03))
	_add(root, _box(0.74, 0.08, 0.1), _emat(col, 2.0), Vector3(0, 1.3, z + 0.04))
	for s in [-1.0, 1.0]:
		_add(root, _box(0.06, 1.0, 0.1), _mat(Color(0.12, 0.1, 0.1), 0.6, 0.5), Vector3(s * 0.36, 0.8, z + 0.04))
	_add(root, _sphere(0.05), _emat(GOLD, 3.0), Vector3(0.2, 0.78, z + 0.08))
	_add(root, _box(0.9, 0.04, 0.5), _mat(Color(0.25, 0.22, 0.3), 0.6, 0.4), Vector3(0, 0.33, z + 0.3))


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var stone := _mat(Color(0.24, 0.22, 0.3), 0.85, 0.1, "brick", 1.4)
	var dark := _mat(Color(0.16, 0.14, 0.2), 0.8, 0.2, "panel", 1.2)
	var wood := _mat(Color(0.32, 0.22, 0.18), 0.9, 0.0, "wood", 1.2)
	var metal := _mat(Color(0.2, 0.2, 0.27), 0.5, 0.7)

	# ---- Неоновые фонари вокруг площади, между ними провода с огоньками ----
	var lamp_tops: Array = []
	for i in 10:
		var a := TAU * i / 10.0 + 0.15
		var p := Vector3(cos(a) * 7.4, 0, sin(a) * 7.4)
		if absf(p.x) < 1.6 and p.z < 0.0:
			continue  # не загораживаем портал
		var col := CYAN if i % 2 == 0 else MAGENTA
		_add(_world, _cyl(0.06, 0.1, 2.4, 6), metal, p + Vector3(0, 1.2, 0))
		_add(_world, _box(0.5, 0.06, 0.06), metal, p + Vector3(0, 2.35, 0))
		var bulb := _add(_world, _sphere(0.17), _emat(col, 2.2), p + Vector3(0, 2.5, 0))
		_flicker.append([bulb.material_override, 2.2, rng.randf() * 10.0])
		_light(_world, p + Vector3(0, 2.4, 0), col, 0.55, 4.5)
		lamp_tops.append(p + Vector3(0, 2.4, 0))
	for i in lamp_tops.size():
		var a: Vector3 = lamp_tops[i]
		var b: Vector3 = lamp_tops[(i + 1) % lamp_tops.size()]
		if a.distance_to(b) > 6.0:
			continue
		for k in 6:
			var t := (k + 0.5) / 6.0
			var q := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.5, 0)
			var bulb := _add(_world, _sphere(0.06), _emat([GOLD, CYAN, MAGENTA][k % 3], 2.5), q)
			_flicker.append([bulb.material_override, 2.5, rng.randf() * 10.0])

	# ---- Крепостная стена с башнями по кругу (ворота у портала и сзади) ----
	var wall_r := 24.0
	for i in 48:
		var a := TAU * i / 48.0
		var p := Vector3(cos(a) * wall_r, 0, sin(a) * wall_r)
		if (absf(p.x) < 4.0 and p.z < 0.0) or (absf(p.x) < 4.0 and p.z > 0.0):
			continue
		var seg := _add(_world, _box(3.3, 2.2, 0.9), stone, p + Vector3(0, 1.1, 0))
		seg.rotation.y = -a + PI / 2.0
		if i % 2 == 0:
			var merlon := _add(_world, _box(1.0, 0.5, 0.95), stone, p + Vector3(0, 2.45, 0))
			merlon.rotation.y = -a + PI / 2.0
		if i % 6 == 0:
			# Башня с неоновым поясом, флагом и огнём на верхушке
			_add(_world, _cyl(1.3, 1.5, 5.0, 10), stone, p + Vector3(0, 2.5, 0))
			_add(_world, _cyl(1.55, 1.55, 0.6, 10), dark, p + Vector3(0, 5.2, 0))
			var col := [CYAN, MAGENTA, GOLD][(i / 6) % 3] as Color
			_add(_world, _torus(1.35, 1.48), _emat(col, 2.2), p + Vector3(0, 3.6, 0))
			_add(_world, _cyl(0.0, 1.4, 1.6, 10), _mat(Color(0.35, 0.16, 0.22), 0.8, 0.1, "wood", 1.0), p + Vector3(0, 6.3, 0))
			_add(_world, _cyl(0.04, 0.04, 1.6, 4), metal, p + Vector3(0, 7.6, 0))
			var flag := _add(_world, _box(0.9, 0.5, 0.03), _emat(col, 1.2), p + Vector3(0.45, 8.0, 0))
			_sway.append([flag, rng.randf() * 6.0, 0.25])
			_light(_world, p + Vector3(0, 5.8, 0), col, 0.9, 7.0)
			_obstacles.append([p, 1.6])

	# ---- Домики жителей: каменный низ, дощатый верх, неоновые окна и вывески ----
	var spots: Array = []
	for i in 200:
		var a := rng.randf() * TAU
		var d := rng.randf_range(13.0, 20.5)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_building(p, 3.2) or absf(p.x) < 3.6 or _near_any(spots, p, 4.6) or p.distance_to(CAMPFIRE) < 5.0 or not _free(p, 2.0):
			continue
		spots.append(p)
		if spots.size() >= 12:
			break
	# Дома — те же 3D-модели с пиксельными текстурами, что и в бою, фасадом к площади
	for i in spots.size():
		var p: Vector3 = spots[i]
		var kind: String = ["house0", "house1", "house2", "house0", "house1", "manor0"][i % 6]
		if kind == "manor0" and (_near_building(p, 7.0) or _near_any(spots.slice(0, i), p, 7.0)):
			kind = "house2"
		_prop(kind, p, atan2(-p.x, -p.z), 0.75)

	# ---- Рыночные лавки: на свободных местах, подальше от зданий ----
	var stalls := STALLS
	for i in stalls.size():
		_stall(stalls[i], [CYAN, MAGENTA, GOLD, Color(0.4, 1.0, 0.5)][i] as Color, rng)

	# ---- Деревья: тёмные ели со светящимися шишками и кибер-деревья ----
	for i in 60:
		var a := rng.randf() * TAU
		var d := rng.randf_range(12.0, 22.5)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_building(p, 4.0) or _near_any(spots, p, 2.6) or absf(p.x) < 2.6:
			continue
		if rng.randf() < 0.65:
			_pine(p, rng)
		else:
			_cyber_tree(p, rng)
	# Деревья и скалы за стеной — силуэт леса
	for i in 70:
		var a := rng.randf() * TAU
		var d := rng.randf_range(26.0, 38.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		_pine(p, rng, rng.randf_range(1.3, 2.2))

	# ---- Детали из боя: ящики, бочки, телеги, вывески, знамёна, заборы, камни ----
	var det := ["crate0", "crate1", "barrel0", "barrel1", "cart0", "sign0", "sign1", "banner0", "banner1",
		"fence0", "rock0", "rock1", "lantern0", "crate0", "barrel0", "bush0", "bush1", "mushroom0", "mushroom1"]
	var placed := 0
	for i in 260:
		if placed >= 70:
			break
		var a := rng.randf() * TAU
		var d := rng.randf_range(8.0, 22.5)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_building(p, 3.4) or absf(p.x) < 2.4 or p.distance_to(CAMPFIRE) < 3.5 or not _free(p, 1.1):
			continue
		var kind: String = det[rng.randi() % det.size()]
		_prop(kind, p, rng.randf() * TAU, 1.0, not kind.begins_with("bush") and not kind.begins_with("mushroom"))
		placed += 1
	# Фонари вдоль главных дорожек
	for i in 12:
		var a := TAU * i / 12.0 + 0.26
		var p := Vector3(cos(a) * 11.0, 0, sin(a) * 11.0)
		if _near_building(p, 3.0) or absf(p.x) < 2.4 or not _free(p, 0.8):
			continue
		_prop(["lamp0", "lamp1"][i % 2], p, -a, 1.0)
	for i in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(8.5, 21.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_building(p, 3.6) or absf(p.x) < 2.0 or not _free(p, 0.9):
			continue
		match rng.randi_range(2, 3):
			0:
				var s := rng.randf_range(0.45, 0.7)
				_add(_world, _box(s, s, s), wood, p + Vector3(0, s / 2.0, 0), Vector3(0, rng.randf() * 90.0, 0))
				_add(_world, _box(s * 0.7, s * 0.7, s * 0.7), wood, p + Vector3(0.1, s + s * 0.35, 0.05), Vector3(0, rng.randf() * 90.0, 0))
			1:
				_add(_world, _cyl(0.32, 0.32, 0.8, 10), wood, p + Vector3(0, 0.4, 0))
				_add(_world, _torus(0.3, 0.34), _emat(CYAN, 1.2), p + Vector3(0, 0.6, 0))
			2:
				var bench := _add(_world, _box(1.4, 0.12, 0.4), wood, p + Vector3(0, 0.45, 0))
				bench.rotation.y = rng.randf() * TAU
			3:
				_add(_world, _cyl(rng.randf_range(0.6, 1.2), rng.randf_range(0.6, 1.2), 0.02, 14),
					_emat(Color(0.25, 0.5, 0.9), 0.5, 0.45), p + Vector3(0, 0.03, 0))
	for i in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(9.0, 23.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		_add(_world, _cyl(rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.4), 0.03, 10),
			_mat(Color(0.12, 0.22, 0.14), 1.0, 0.0), p + Vector3(0, 0.02, 0))

	# ---- Кристаллы-руны на окраинах ----
	for i in 16:
		var a := rng.randf() * TAU
		var d := rng.randf_range(12.0, 23.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_building(p, 4.0):
			continue
		var col := [CYAN, MAGENTA, Color(0.7, 0.4, 1.0)][rng.randi_range(0, 2)] as Color
		var h := rng.randf_range(0.8, 2.0)
		var cr := _add(_world, _cyl(0.0, rng.randf_range(0.2, 0.4), h, 5), _emat(col, 2.0), p + Vector3(0, h / 2.0, 0),
			Vector3(rng.randf_range(-12, 12), rng.randf() * 360.0, rng.randf_range(-12, 12)))
		_flicker.append([cr.material_override, 2.0, rng.randf() * 10.0])

	# ---- Ветряк-турбина с неоновыми лопастями ----
	var tp := Vector3(-16.0, 0, -9.0)
	_add(_world, _cyl(0.25, 0.45, 7.0, 8), stone, tp + Vector3(0, 3.5, 0))
	var hubn := Node3D.new()
	hubn.position = tp + Vector3(0, 7.0, 0.5)
	_world.add_child(hubn)
	for k in 3:
		var blade := _add(hubn, _box(0.25, 3.0, 0.06), _emat(CYAN, 1.4), Vector3(0, 1.5, 0))
		var piv := Node3D.new()
		piv.rotation.z = TAU * k / 3.0
		hubn.add_child(piv)
		blade.reparent(piv)
	_spinners.append([hubn, Vector3.FORWARD, 0.8])
	_obstacles.append([tp, 0.8])

	# ---- Дроны-патрульные кружат над посёлком ----
	for i in 4:
		var dr := Node3D.new()
		_world.add_child(dr)
		_add(dr, _box(0.5, 0.12, 0.5), metal, Vector3.ZERO)
		var eye := _add(dr, _sphere(0.1), _emat([CYAN, MAGENTA][i % 2] as Color, 3.0), Vector3(0, -0.08, 0.2))
		_light(dr, Vector3(0, -0.3, 0), [CYAN, MAGENTA][i % 2] as Color, 0.8, 4.0)
		_drones.append([dr, rng.randf_range(8.0, 18.0), rng.randf_range(0.15, 0.35) * (1 if i % 2 == 0 else -1), rng.randf() * TAU, rng.randf_range(5.0, 7.5)])
		eye.visible = true

	# ---- Светлячки, искры и лёгкий дождь ----
	_particles(_world, Vector3(0, 3, 2), Color(1.0, 0.5, 1.0), 90, Vector3(20, 3, 18), Vector3(0, 0.1, 0), 6.0, 0.07)
	_particles(_world, Vector3(0, 1.2, 2), Color(0.5, 1.0, 0.6), 60, Vector3(22, 1, 20), Vector3(0, 0.15, 0), 5.0, 0.05)
	_particles(_world, Vector3(0, 12, 2), Color(0.5, 0.8, 1.0), 320, Vector3(26, 0.5, 24), Vector3(0, -30, 0), 0.8, 0.04, false, 0.0)


# ---- Части декора ----

var _obstacles: Array = []
var _flicker: Array = []   # [материал, базовая яркость, фаза]
var _sway: Array = []      # [узел, фаза, сила]
var _drones: Array = []    # [узел, радиус, скорость, угол, высота]


## Модель из боя (Props3D) в убежище: тот же меш и текстуры, масштаб под рост жителей,
## препятствия — по форме модели.
const HUB_K := 1.45


func _prop(kind: String, p: Vector3, rot := 0.0, k := 1.0, solid := true) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(p.x, p.z))
	var n := Props3D.build(kind, rng)
	n.scale *= HUB_K * k
	n.position = p
	n.rotation.y = rot
	_world.add_child(n)
	if solid:
		var s := n.scale.x
		for sh in Props3D.shapes(kind):
			var wo := (Vector2(sh[1], sh[2]) * s).rotated(-rot)
			var c := p + Vector3(wo.x, 0, wo.y)
			if sh[0] == "r":
				_obstacles.append([c, Vector2(sh[3], sh[4]) * s, rot])
			else:
				_obstacles.append([c, float(sh[3]) * s])
	return n


## Место свободно: в радиусе r нет препятствий.
func _free(p: Vector3, r: float) -> bool:
	return _collide(p, r).distance_to(p) < 0.01


func _near_building(p: Vector3, r: float) -> bool:
	for q in _reserved:
		if Vector2(p.x - q.x, p.z - q.z).length() < r + 3.0:
			return true
	if Vector2(p.x - PORTAL_POS.x, p.z - PORTAL_POS.z).length() < r + 1.0:
		return true
	if Vector2(p.x, p.z).length() < 9.0:
		return true
	for id in Meta.BUILDINGS:
		var b: Vector3 = Meta.BUILDINGS[id]["pos"]
		if Vector2(p.x - b.x, p.z - b.z).length() < r:
			return true
		# дорожка от площади к зданию
		var dir := Vector2(b.x, b.z)
		var t := clampf(Vector2(p.x, p.z).dot(dir.normalized()), 0.0, dir.length())
		if (Vector2(p.x, p.z) - dir.normalized() * t).length() < 1.8:
			return true
	return false


func _near_any(list: Array, p: Vector3, r: float) -> bool:
	for q in list:
		if (q as Vector3).distance_to(p) < r:
			return true
	return false


func _house(p: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = atan2(-p.x, -p.z) + rng.randf_range(-0.3, 0.3)  # фасадом к площади
	_world.add_child(root)
	var w := rng.randf_range(2.4, 3.4)
	var d := rng.randf_range(2.2, 2.8)
	var h1 := rng.randf_range(1.4, 1.8)
	var h2 := rng.randf_range(1.0, 1.4)
	_add(root, _box(w, h1, d), _mat(Color(0.26, 0.24, 0.3), 0.85, 0.1, "brick", 1.3), Vector3(0, h1 / 2.0, 0))
	_add(root, _box(w + 0.15, h2, d + 0.15), _mat(Color(0.42, 0.34, 0.3), 0.9, 0.0, "wood", 1.2), Vector3(0, h1 + h2 / 2.0, 0))
	# Двускатная крыша из двух наклонных плит
	var roof := _mat([Color(0.45, 0.16, 0.2), Color(0.2, 0.18, 0.4), Color(0.18, 0.3, 0.32)][rng.randi_range(0, 2)] as Color, 0.8, 0.1, "wood", 1.0)
	var prism := PrismMesh.new()
	prism.size = Vector3(d + 0.5, 1.2, w + 0.5)
	_add(root, prism, roof, Vector3(0, h1 + h2 + 0.6, 0), Vector3(0, 90, 0))
	# Труба с дымом
	var cx := rng.randf_range(-w * 0.3, w * 0.3)
	_add(root, _box(0.35, 1.0, 0.35), _mat(Color(0.24, 0.22, 0.28), 0.9, 0.1, "brick", 1.0), Vector3(cx, h1 + h2 + 0.9, -d * 0.2))
	_particles(root, Vector3(cx, h1 + h2 + 1.5, -d * 0.2), Color(0.28, 0.25, 0.36), 10, Vector3(0.08, 0.05, 0.08), Vector3(0.15, 0.5, 0), 2.6, 0.12)
	# Окна и дверь светятся
	var wc := [GOLD, CYAN, MAGENTA][rng.randi_range(0, 2)] as Color
	for k in 2:
		var x := (k - 0.5) * w * 0.5
		var win := _add(root, _box(0.45, 0.4, 0.05), _emat(wc, 1.8), Vector3(x, h1 + h2 * 0.5, d / 2.0 + 0.09))
		_flicker.append([win.material_override, 1.8, rng.randf() * 10.0])
	_add(root, _box(0.6, 1.1, 0.05), _mat(Color(0.2, 0.14, 0.12), 0.9, 0.0, "wood", 1.0), Vector3(0, 0.55, d / 2.0 + 0.03))
	_light(root, Vector3(0, h1 + h2 * 0.5, d / 2.0 + 0.6), wc, 0.45, 3.5)
	# Неоновая вывеска над дверью у некоторых домов
	if rng.randf() < 0.6:
		var sc := [CYAN, MAGENTA, Color(0.4, 1.0, 0.5)][rng.randi_range(0, 2)] as Color
		var sign := _add(root, _box(0.9, 0.3, 0.05), _emat(sc, 2.4), Vector3(0, h1 + 0.15, d / 2.0 + 0.12))
		_flicker.append([sign.material_override, 2.4, rng.randf() * 10.0])
	_obstacles.append([p, Vector2(w / 2.0 + 0.1, d / 2.0 + 0.1), root.rotation.y])


func _stall(p: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = atan2(-p.x, -p.z)
	_world.add_child(root)
	var wood := _mat(Color(0.34, 0.24, 0.18), 0.9, 0.0, "wood", 1.0)
	_add(root, _box(1.8, 0.8, 0.8), wood, Vector3(0, 0.4, 0))
	for x in [-0.8, 0.8]:
		_add(root, _cyl(0.04, 0.04, 2.0, 4), wood, Vector3(x, 1.0, -0.35))
		_add(root, _cyl(0.04, 0.04, 1.6, 4), wood, Vector3(x, 0.8, 0.4))
	var awn := _add(root, _box(2.1, 0.06, 1.3), _emat(col, 0.6), Vector3(0, 1.85, 0.05))
	awn.rotation.x = deg_to_rad(-14.0)
	# Товар: светящиеся склянки и кристаллы
	for k in 5:
		var gc := [CYAN, MAGENTA, GOLD, Color(0.4, 1.0, 0.5)][rng.randi_range(0, 3)] as Color
		_add(root, _cyl(0.07, 0.09, 0.22, 6), _emat(gc, 2.2), Vector3(-0.7 + k * 0.35, 0.92, rng.randf_range(-0.2, 0.2)))
	# Голограмма-вывеска крутится над прилавком
	var holo := _add(root, _box(0.7, 0.4, 0.02), _emat(col, 1.6, 0.6), Vector3(0, 2.4, 0))
	_spinners.append([holo, Vector3.UP, 1.2])
	_light(root, Vector3(0, 1.6, 0.6), col, 0.6, 4.0)
	_obstacles.append([p, Vector2(1.0, 0.55), root.rotation.y])


## Деревья — те же объёмные пиксельные (воксельные) деревья, что и в бою.
func _pine(p: Vector3, rng: RandomNumberGenerator, scale := 1.0) -> void:
	_prop(["pine0", "pine0", "pine1", "pine2"][rng.randi_range(0, 3)], p, rng.randf() * TAU, scale * rng.randf_range(0.9, 1.2), scale <= 1.0)


func _pine_old(p: Vector3, rng: RandomNumberGenerator, scale := 1.0) -> void:
	var root := Node3D.new()
	root.position = p
	root.scale = Vector3.ONE * scale * rng.randf_range(0.8, 1.25)
	_world.add_child(root)
	_add(root, _cyl(0.12, 0.18, 1.0, 6), _mat(Color(0.25, 0.17, 0.14), 0.9, 0.0), Vector3(0, 0.5, 0))
	var leaf := _mat(Color(0.1, 0.2 + rng.randf() * 0.08, 0.2), 0.9, 0.0)
	for k in 3:
		_add(root, _cyl(0.0, 1.1 - k * 0.28, 1.2, 7), leaf, Vector3(0, 1.1 + k * 0.7, 0))
	if rng.randf() < 0.5:
		var c := [CYAN, MAGENTA, Color(0.4, 1.0, 0.5)][rng.randi_range(0, 2)] as Color
		_add(root, _sphere(0.09), _emat(c, 3.0), Vector3(0, 3.0, 0))
	if scale <= 1.0:
		_obstacles.append([p, 0.6])


func _cyber_tree(p: Vector3, rng: RandomNumberGenerator) -> void:
	_prop(["tree0", "tree1", "tree2", "tree3"][rng.randi_range(0, 3)], p, rng.randf() * TAU, rng.randf_range(0.9, 1.15))


func _cyber_tree_old(p: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = p
	_world.add_child(root)
	_add(root, _cyl(0.1, 0.2, 2.0, 6), _mat(Color(0.22, 0.2, 0.28), 0.6, 0.5), Vector3(0, 1.0, 0))
	var c := [CYAN, MAGENTA, Color(0.7, 0.4, 1.0)][rng.randi_range(0, 2)] as Color
	var crown := _add(root, _sphere(0.9), _emat(c.darkened(0.55), 0.8), Vector3(0, 2.4, 0))
	crown.scale = Vector3(1.0, 0.75, 1.0)
	_add(root, _torus(0.85, 0.92), _emat(c, 2.0), Vector3(0, 2.3, 0))
	_bobbers.append([crown, 2.4, 0.06])
	_light(root, Vector3(0, 2.2, 0), c, 0.4, 3.5)
	_obstacles.append([p, 0.6])


## Анимация декора: мерцание неона, флаги, патрульные дроны.
func _animate_decor(delta: float) -> void:
	for f in _flicker:
		var m: StandardMaterial3D = f[0]
		var k := 0.85 + 0.15 * sin(_t * 3.0 + f[2])
		if fmod(_t + f[2], 7.0) < 0.12:
			k = 0.3  # короткий «сбой» вывески
		m.emission_energy_multiplier = f[1] * k
	for s in _sway:
		(s[0] as Node3D).rotation.y = sin(_t * 2.2 + s[1]) * s[2]
	for d in _drones:
		d[3] += d[2] * delta
		var n: Node3D = d[0]
		n.position = Vector3(cos(d[3]) * d[1], d[4] + sin(_t * 1.5 + d[1]) * 0.3, sin(d[3]) * d[1] + 2.0)
		n.rotation.y = -d[3] + (PI if d[2] > 0 else 0.0)


# ================= Персонажи =================

func _sprite_pair(parent: Node3D, frames: Dictionary) -> Array:
	var base := Sprite3D.new()
	base.texture = frames["base"][0]
	var px_size: float = SPRITE_PX * float(frames.get("k", 1.0))
	base.pixel_size = px_size
	base.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	base.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	base.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var h: float = frames["size"].y * px_size
	base.position.y = h / 2.0
	parent.add_child(base)
	var emit := Sprite3D.new()
	emit.texture = frames["emit"][0]
	emit.pixel_size = px_size
	emit.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	emit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	emit.shaded = false
	emit.render_priority = 1
	emit.modulate = Pixel.hdr(Color.WHITE, 1.5)
	emit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emit.position = base.position + Vector3(0, 0, 0.01)
	parent.add_child(emit)
	return [base, emit]


func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.position = Vector3(0, 0, 3.5)
	_world.add_child(_avatar)
	_set_avatar_sprites()
	var l := _light(_avatar, Vector3(0, 1.6, 0.8), Color(0.8, 0.85, 1.0), 0.9, 5.0)
	l.shadow_enabled = false


func _set_avatar_sprites() -> void:
	if _av_base:
		_av_base.queue_free()
		_av_emit.queue_free()
	var c: Dictionary = Data.CHARACTERS[Data.selected_character]
	_av_frames = Pixel.frames(c["sprite"])
	var pair := _sprite_pair(_avatar, _av_frames)
	_av_base = pair[0]
	_av_emit = pair[1]


# ================= Цикл =================

var _focus := {}


func _process(delta: float) -> void:
	_t += delta
	if _panel_root.visible:
		UiFocus.keep(_panel_root, _focus)
	for s in _spinners:
		if is_instance_valid(s[0]):
			(s[0] as Node3D).rotate(s[1], s[2] * delta)
	for b in _bobbers:
		if is_instance_valid(b[0]):
			(b[0] as Node3D).position.y = b[1] + sin(_t * 2.0) * b[2]
	_animate_decor(delta)
	_animate_places()
	_update_avatar(delta)
	_update_chats(delta)
	_update_villagers(delta)
	_update_marks()
	_update_thanks()
	if _inside == "hall":
		_update_tavern(delta)
	_update_camera(delta)
	_update_interaction()
	_shards_label.text = str(Meta.shards)
	_mats_label.text = "   ⚙ %d   ▣ %d   ✶ %d" % [int(Meta.materials.get("scrap", 0)), int(Meta.materials.get("chips", 0)), int(Meta.materials.get("cores", 0))]
	_net_tick(delta)


func _update_avatar(delta: float) -> void:
	var dir := Vector2.ZERO
	if _panel_id == "":
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := dir != Vector2.ZERO
	var pos := _avatar.position + Vector3(dir.x, 0, dir.y) * 6.0 * delta
	pos = _collide(pos, 0.5)
	var flat := Vector2(pos.x, pos.z)
	if _inside != "":
		var ri: Dictionary = INTERIORS[_inside]
		var ro: Vector3 = ri["o"]
		flat.x = clampf(flat.x, ro.x - float(ri["w"]) / 2.0 + 0.45, ro.x + float(ri["w"]) / 2.0 - 0.45)
		var front := ro.z + float(ri["d"]) / 2.0 - (0.2 if absf(flat.x - ro.x) < 1.1 else 0.45)
		flat.y = clampf(flat.y, ro.z - float(ri["d"]) / 2.0 + 0.45, front)
	elif flat.length() > 22.0:
		flat = flat.normalized() * 22.0
	_avatar.position = Vector3(flat.x, 0, flat.y)
	if absf(dir.x) > 0.1:
		_facing_left = dir.x < 0.0
	_av_t += delta
	var f := Pixel.hero_frame(_av_frames, "run" if moving else "idle", _av_t)
	_av_base.texture = _av_frames["base"][f]
	_av_emit.texture = _av_frames["emit"][f]
	_av_base.flip_h = _facing_left
	_av_emit.flip_h = _facing_left


func _collide(pos: Vector3, r: float) -> Vector3:
	var obstacles: Array = [[PORTAL_POS + Vector3(-1.8, 0, 0), 0.6], [PORTAL_POS + Vector3(1.8, 0, 0), 0.6]]
	for id in Meta.BUILDINGS:
		# Здание стоит на квадратном фундаменте 3.6 × 3.6
		obstacles.append([Meta.BUILDINGS[id]["pos"], Vector2(1.85, 1.85), 0.0])
	obstacles.append_array(_obstacles)
	for o in obstacles:
		var c: Vector3 = o[0]
		if o.size() == 3:
			# Прямоугольник (повёрнутый): ближайшая точка на нём
			var half: Vector2 = o[1]
			var ang: float = o[2]
			var lp := Vector2(pos.x - c.x, pos.z - c.z).rotated(ang)
			var q := Vector2(clampf(lp.x, -half.x, half.x), clampf(lp.y, -half.y, half.y))
			var dd := lp - q
			if dd.length() < r:
				if dd.length() > 0.001:
					lp = q + dd.normalized() * r
				else:
					var px := half.x + r - absf(lp.x)
					var pz := half.y + r - absf(lp.y)
					if px < pz:
						lp.x = (half.x + r) * signf(lp.x if lp.x != 0.0 else 1.0)
					else:
						lp.y = (half.y + r) * signf(lp.y if lp.y != 0.0 else 1.0)
				var wp := lp.rotated(-ang)
				pos = Vector3(c.x + wp.x, pos.y, c.z + wp.y)
			continue
		var d := Vector2(pos.x - c.x, pos.z - c.z)
		var min_d: float = o[1] + r
		if d.length() < min_d and d.length() > 0.001:
			d = d.normalized() * min_d
			pos = Vector3(c.x + d.x, pos.y, c.z + d.y)
	return pos


func _update_camera(delta: float) -> void:
	_cam_target = _cam_target.lerp(_avatar.position, minf(1.0, delta * 4.0))
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.15
	_camera.position = _cam_target + _cam_off + jitter
	_camera.look_at(_cam_target + Vector3(0, 0.8, 0) + jitter)


func _update_interaction() -> void:
	if _panel_id != "":
		_prompt.visible = false
		return
	if _inside != "":
		_near = _interior_interaction()
		_prompt.visible = _near != ""
		return
	var ti := _talk_target()
	if ti >= 0 and not _net_client:
		var tv: Dictionary = _villagers[ti]
		_near = "talk:%d" % ti
		_prompt.text = _pk() + "Поговорить: %s, %s" % [tv["profile"]["name"], tv["profile"]["title"]]
		_prompt.visible = true
		return
	var best := ""
	var best_d := 999.0
	var p := _avatar.position
	var dp := Vector2(p.x - PORTAL_POS.x, p.z - PORTAL_POS.z).length()
	if dp < 3.6:
		best = "portal"
		best_d = dp
	var dl := Vector2(p.x - LIBRARY.x, p.z - LIBRARY.z).length()
	if dl < 3.6 and dl < best_d:
		best = "library"
		best_d = dl
	var db := Vector2(p.x - BOARD.x, p.z - BOARD.z).length()
	if db < 2.2 and db < best_d:
		best = "board"
		best_d = db
	for id in Meta.BUILDINGS:
		var bp: Vector3 = Meta.BUILDINGS[id]["pos"]
		var d := Vector2(p.x - bp.x, p.z - bp.z).length()
		if d < 3.4 and d < best_d:
			best = id
			best_d = d
	_near = best
	_prompt.visible = best != ""
	if best == "portal":
		_prompt.text = _pk() + "Портал — начать вылазку"
	elif best == "library":
		_prompt.text = _pk() + "Библиотека — всё об открытом"
	elif best == "board":
		_prompt.text = _pk() + "Доска заданий"

	elif best != "":
		var lvl := _lvl(best)
		if (lvl > 0 or best == "hall") and not _net_client:
			_prompt.text = _pk() + "Войти: %s%s" % [Meta.BUILDINGS[best]["name"], "" if lvl == 0 else "  (ур. %d)" % lvl]
			_near = "enter:" + best
		else:
			_prompt.text = _pk() + "%s  %s" % [Meta.BUILDINGS[best]["name"], ("— построить" if lvl == 0 else "(ур. %d)" % lvl)]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if _panel_id == "" and _near != "":
			if _inside != "":
				_interior_act(_near)
			elif _near.begins_with("enter:"):
				_enter_building(_near.substr(6))
			else:
				_open_panel(_near)
	elif event.is_action_pressed("pause") or (event.is_action_pressed("ui_cancel") and _panel_id != ""):
		get_viewport().set_input_as_handled()
		if _panel_id != "":
			_close_panel()
		else:
			_open_panel("pause")


# ================= Интерфейс =================

func _label(text: String, size: int, color := Color.WHITE, glow := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	l.add_theme_constant_override("outline_size", 6)
	if glow.a > 0.0:
		l.add_theme_color_override("font_shadow_color", glow)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.add_theme_constant_override("shadow_outline_size", 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sbox(border: Color, bg := PANEL_BG, width := 2, glow := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(border, 0.45)
	s.shadow_size = glow
	s.set_content_margin_all(10)
	return s


func _button(text: String, accent: Color, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(minf(380, _avail()), 48)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_stylebox_override("normal", _sbox(accent.darkened(0.35), PANEL_BG, 2, 4))
	b.add_theme_stylebox_override("hover", _sbox(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 14))
	b.add_theme_stylebox_override("pressed", _sbox(Color.WHITE, Color(0.15, 0.08, 0.25, 0.95), 3, 18))
	b.add_theme_stylebox_override("focus", _sbox(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 14))
	b.add_theme_stylebox_override("disabled", _sbox(Color(0.3, 0.3, 0.35), Color(0.05, 0.04, 0.08, 0.9), 1, 0))
	b.disabled = not enabled
	b.mouse_entered.connect(func(): Sound.play("hover", -10.0))
	return b


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_safe_root = root

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _sbox(GOLD, PANEL_BG, 2, 8))
	top.position = Vector2(16, 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	top.add_child(h)
	var gem := TextureRect.new()
	gem.texture = Pixel.frames("gem5")["base"][0]
	gem.custom_minimum_size = Vector2(minf(30, _avail()), 34)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.add_child(gem)
	_shards_label = _label("0", 28, GOLD, Color(GOLD, 0.6))
	h.add_child(_shards_label)
	h.add_child(_label("осколков", 16, Color(0.85, 0.8, 0.7)))
	_mats_label = _label("", 18, Color(0.85, 0.9, 1.0))
	h.add_child(_mats_label)

	# Значок профиля: аватар героя и ник; по клику — страница профиля
	var badge := Button.new()
	badge.position = Vector2(16, 76)
	badge.custom_minimum_size = Vector2(minf(240, _avail()), 60)
	badge.focus_mode = Control.FOCUS_NONE
	badge.add_theme_stylebox_override("normal", _sbox(GOLD.darkened(0.3), PANEL_BG, 2, 6))
	badge.add_theme_stylebox_override("hover", _sbox(GOLD, PANEL_BG, 2, 12))
	badge.add_theme_stylebox_override("pressed", _sbox(Color.WHITE, PANEL_BG, 2, 12))
	badge.pressed.connect(func():
		if Net.mode != "":
			_toast_text("Профиль открывается из главного меню")
			return
		Sound.play("click")
		Meta.save()
		Data.menu_page = "profile"
		Data.menu_return = "hub"
		Loader.go("res://menu.tscn"))
	root.add_child(badge)
	var bh := HBoxContainer.new()
	bh.position = Vector2(8, 5)
	bh.add_theme_constant_override("separation", 10)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(bh)
	_badge_pic = _pic(Pixel.portrait(Data.CHARACTERS[Data.selected_character]["sprite"]), 2.0)
	_badge_pic.custom_minimum_size = Vector2(minf(50, _avail()), 50)
	_badge_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bh.add_child(_badge_pic)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(bv)
	var nl := _label(Meta.nickname, 19, Color(1.0, 0.9, 0.6))
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(nl)
	var pl := _label("профиль", 13, Color(0.7, 0.7, 0.85))
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(pl)

	var title := _label("НЕОНОВОЕ УБЕЖИЩЕ", 30, Color(1.0, 0.95, 1.0), Color(MAGENTA, 0.8))
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 14
	root.add_child(title)
	_title_l = title

	_hero_label = _label("", 18, CYAN)
	_hero_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hero_label.offset_left = -420
	_hero_label.offset_right = -18
	_hero_label.offset_top = 18
	root.add_child(_hero_label)
	_update_hero_label()

	var hint := _label(_hint_text(), 15, Color(0.75, 0.75, 0.9))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_left = -400
	hint.offset_right = 400
	hint.offset_top = -34
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)
	_hint_l = hint
	Settings.input_mode_changed.connect(_on_input_mode)
	_layout_top()

	_prompt = _label("", 22, Color.WHITE, Color(CYAN, 0.7))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.offset_left = 16
	_prompt.offset_right = -16
	_prompt.offset_top = -110
	_prompt.offset_bottom = -40
	root.add_child(_prompt)

	_toast = _label("", 20, GOLD, Color(GOLD, 0.6))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.offset_left = 16
	_toast.offset_right = -16
	_toast.offset_top = 255 if _portrait() else 64
	_toast.offset_bottom = 311 if _portrait() else 120
	root.add_child(_toast)

	_panel_root = Control.new()
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.visible = false
	_hud.add_child(_panel_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(center)
	var panel := PanelContainer.new()
	var pb := _sbox(CYAN, PANEL_BG, 3, 22)
	pb.set_content_margin_all(14 if _portrait() else 28)
	_panel_style = pb
	panel.add_theme_stylebox_override("panel", pb)
	center.add_child(panel)
	# Содержимое окна прокручивается, если не помещается в экран
	_panel_scroll = ScrollContainer.new()
	panel.add_child(_panel_scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 12)
	_panel_scroll.add_child(_panel_box)


var _badge_pic: TextureRect


func _update_hero_label() -> void:
	if _badge_pic:
		_badge_pic.texture = Pixel.portrait(Data.CHARACTERS[Data.selected_character]["sprite"])
	var c: Dictionary = Data.CHARACTERS[Data.selected_character]
	var who := "%s  •  Герой: %s, %s" % [Meta.nickname, c["name"], c["title"].to_lower()]
	_hero_label.text = "%s\nВылазок: %d   •   Рекорд: %02d:%02d" % [
		who, Meta.total_runs, int(Meta.best_time) / 60, int(Meta.best_time) % 60]


func _toast_text(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 1.0)


func _show_reward(r: Dictionary) -> void:
	var t := "Вылазка завершена: +%d ◆" % r["total"]
	var mats: Dictionary = r.get("materials", {})
	for m in mats:
		t += "  +%d %s" % [int(mats[m]), Meta.MATERIALS[m]["icon"]]
	var qs: Array = r.get("quests", [])
	if not qs.is_empty():
		t += "   •   заданий выполнено: %d" % qs.size()
	_toast_text(t)


func _open_panel(id: String) -> void:
	_panel_id = id
	_focus = {}
	Sound.play("click")
	_fill_panel()
	_panel_root.visible = true


func _close_panel() -> void:
	if _panel_id == "settings":
		Settings.save_settings()
	_panel_id = ""
	_panel_root.visible = false


func _fill_panel() -> void:
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()
	_fit_panel.call_deferred()
	var id := _panel_id
	if id == "pause":
		_panel_box.add_child(_centered(_label("ПАУЗА", 40, Color.WHITE, Color(CYAN, 0.8))))
		var cont := _button("ПРОДОЛЖИТЬ", CYAN)
		cont.pressed.connect(func():
			Sound.play("click")
			_close_panel())
		_panel_box.add_child(_centered(cont))
		var sett := _button("НАСТРОЙКИ", GOLD)
		sett.pressed.connect(func():
			Sound.play("click")
			_panel_id = "settings"
			_fill_panel())
		_panel_box.add_child(_centered(sett))
		var menu := _button("ПОКИНУТЬ СЕТЕВУЮ ИГРУ" if Net.mode != "" else "В ГЛАВНОЕ МЕНЮ", MAGENTA)
		menu.pressed.connect(func():
			Sound.play("click")
			Meta.save()
			if Net.mode != "":
				Net.leave()
				Data.menu_page = "net"
			Loader.go("res://menu.tscn"))
		_panel_box.add_child(_centered(menu))
		return
	if id == "settings":
		var sp = preload("res://scripts/settings_panel.gd").new()
		sp.on_back = func():
			_panel_id = "pause"
			_fill_panel()
		_panel_box.add_child(_centered(sp))
		return
	if _net_client and id != "hall" and id != "library":
		_fill_client_panel(id)
		return
	if _net_client and id == "hall":
		_fill_client_hall()
		return
	if id == "portal":
		_fill_portal()
		return
	if id == "library":
		_fill_library()
		return
	if id == "board":
		_fill_board()
		return
	if id.begins_with("hire:"):
		_fill_hire(id.substr(5))
		return
	if id.begins_with("talk:"):
		_fill_talk(int(id.substr(5)))
		return
	if id == "story":
		_fill_story()
		return
	if id == "prologue":
		_fill_prologue()
		return
	if id in ["forge", "shrine", "lab"] and Meta.level(id) > 0:
		_fill_tree_panel(id)
		return

	var info: Dictionary = Meta.BUILDINGS[id]
	var lvl := Meta.level(id)
	var col: Color = info["color"]
	_panel_box.add_child(_centered(_label(info["name"], 34, Color.WHITE, Color(col, 0.8))))
	_panel_box.add_child(_centered(_label("◆".repeat(lvl) + "◇".repeat(int(info["max"]) - lvl), 22, col)))
	var desc := _label(info["desc"], 17, Color(0.85, 0.85, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(minf(460, _avail()), 0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(desc)
	if Meta.building_busy(id):
		_panel_box.add_child(_centered(_label("⚒ Идёт стройка уровня %d — завершится через %d вылаз." % [int(Meta.construct["lvl"]), int(Meta.construct["left"])], 18, GOLD)))
	elif lvl < info["max"]:
		_panel_box.add_child(_centered(_build_cost_row(id)))
		var cost_t := Meta.cost_text(Meta.build_cost(id))
		var text := ("ПОСТРОИТЬ — " if lvl == 0 else "УЛУЧШИТЬ ДО УР. %d — " % (lvl + 1)) + cost_t
		var up := _button(text, col, Meta.can_upgrade(id))
		up.custom_minimum_size.x = 520 if not _portrait() else 440
		up.pressed.connect(func(): _do_upgrade(id))
		_panel_box.add_child(_centered(up))
		var why := Meta.upgrade_block(id)
		if why != "":
			_panel_box.add_child(_centered(_label("⊘ " + why, 15, Color(1.0, 0.6, 0.6))))
	else:
		_panel_box.add_child(_centered(_label("МАКСИМАЛЬНЫЙ УРОВЕНЬ", 18, GOLD)))

	if id == "hall" and _inside == "hall":
		_fill_contracts()
	elif id == "hall":
		_panel_box.add_child(_centered(_label("ГЕРОИ", 22, GOLD)))
		var hint := _label("Вега доступна сразу. Остальных героев откройте: выполните условие и заплатите осколками.", 14, Color(0.75, 0.75, 0.9))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(minf(600 if _portrait() else 900, _avail()), 0)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_box.add_child(_centered(hint))
		var row := GridContainer.new()
		row.columns = _cols(206 if _portrait() else 180)
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		for hid in Meta.HERO_ORDER:
			if not Data.CHARACTERS.has(hid):
				continue
			row.add_child(_hero_card(hid))
		_panel_box.add_child(_centered(row))
	_add_close()


## Карточка героя в Зале: выбрать (открыт) / открыть (условие выполнено) / условие.
func _hero_card(hid: String) -> Control:
	var hc: Dictionary = Data.CHARACTERS[hid]
	var st := Meta.hero_state(hid)
	var col: Color = hc["color"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sbox(col if st == "owned" else col.darkened(0.55), PANEL_BG, 2, 6 if hid == Data.selected_character else 0))
	card.custom_minimum_size = Vector2(minf(196 if _portrait() else 170, _avail()), 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var pic := _pic(Pixel.portrait(hc["sprite"], st != "owned"), 2.2)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	var nm := _label(("✓ " if hid == Data.selected_character else "") + hc["name"], 16, col.lightened(0.2) if st == "owned" else Color(0.7, 0.7, 0.8))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var tt := _label(hc["title"], 12, Color(0.75, 0.75, 0.9))
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tt)
	card.tooltip_text = Data.HERO_LORE.get(hid, "")
	var u: Dictionary = Meta.HERO_UNLOCK.get(hid, {"cost": 0, "conds": []})
	if st != "owned" and st != "open" and st != "expensive":
		# Что именно нужно для найма — тайна: игрок узнаёт сам
		var ql := _label("«Я пока не готов идти с тобой…»", 11, Color(0.75, 0.7, 0.85))
		ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ql.custom_minimum_size = Vector2(minf(150, _avail()), 0)
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ql)
	var b: Button
	match st:
		"owned":
			b = _button("ВЫБРАН" if hid == Data.selected_character else "ВЫБРАТЬ", col, hid != Data.selected_character)
			b.pressed.connect(func():
				if _inside == "hall":
					_close_panel()
					_take_hero(hid)
					return
				Data.selected_character = hid
				_set_avatar_sprites()
				_update_hero_label()
				Sound.play("levelup", -6.0)
				_fill_panel())
		"open":
			b = _button("ОТКРЫТЬ — %d ◆" % int(u["cost"]), GOLD)
			b.pressed.connect(func():
				if Meta.unlock_hero(hid):
					Sound.play("levelup", -2.0)
					_particles(_world, _avatar.position + Vector3(0, 2.0, 0), col, 40, Vector3(1, 1, 1), Vector3(0, 2, 0), 1.2, 0.1, true, 3.0)
					_toast_text("Нанят герой: %s — %s! Подойдите к нему, чтобы взять в бой." % [hc["name"], hc["title"]])
					if _inside == "hall":
						_rebuild_tavern_heroes()
				_fill_panel())
		"expensive":
			b = _button("%d ◆ — мало" % int(u["cost"]), GOLD.darkened(0.4), false)
		"lost":
			b = _button("⊘ не найден", Color(0.5, 0.5, 0.6), false)
		"parts":
			b = _button("⊘ не готов", Color(0.5, 0.5, 0.6), false)
		_:
			b = _button("⊘ не готов", Color(0.5, 0.5, 0.6), false)
	b.custom_minimum_size = Vector2(minf(150, _avail()), 40)
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	return card


## Пиксельная картинка, увеличенная в k раз без размытия.
func _pic(t: Texture2D, k: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.custom_minimum_size = t.get_size() * k * (0.5 if t.has_meta("icon2x") else 1.0)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _centered(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c


func _add_close() -> void:
	var close := _button(Settings.with_key("ЗАКРЫТЬ", "back"), Color(0.6, 0.6, 0.75))
	close.pressed.connect(func():
		Sound.play("click")
		_close_panel())
	_panel_box.add_child(_centered(close))


## Что нужно для следующего уровня здания: ресурсы (есть / нужно), условие и время стройки.
func _build_cost_row(id: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var cost := Meta.build_cost(id)
	var parts: Array = []
	var ok_s := Meta.shards >= int(cost["shards"])
	parts.append("%s ◆ %d / %d" % ["✓" if ok_s else "✗", Meta.shards, int(cost["shards"])])
	for m in Meta.MATERIALS:
		var need := int(cost.get(m, 0))
		if need <= 0:
			continue
		var have := int(Meta.materials.get(m, 0))
		parts.append("%s %s %s %d / %d" % ["✓" if have >= need else "✗", Meta.MATERIALS[m]["icon"], Meta.MATERIALS[m]["name"], have, need])
	var l := _label(("\n" if _portrait() else "   ").join(parts), 15, Color(0.9, 0.9, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_centered(l))
	var L := Meta.level(id) + 1
	var runs: int = Meta.BUILD_RUNS[mini(L, 5)]
	var req := Meta.build_req(id)
	var info := "Стройка: " + ("сразу" if runs <= 0 else "%d вылаз. после начала" % runs)
	if req > 0:
		info += "   •   нужно пройти уровней главы: %d (%d)" % [req, Meta.levels_cleared]
	var il := _label(info, 14, Color(0.75, 0.75, 0.9))
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.custom_minimum_size = Vector2(minf(440 if _portrait() else 640, _avail()), 0)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_centered(il))
	var hint := _label("Материалы (⚙ лом, ▣ микросхемы, ✶ ядра) добываются только в бою: элита, боссы, тайники, загадки, события и задания.", 13, Color(0.65, 0.65, 0.8))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(minf(440 if _portrait() else 640, _avail()), 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_centered(hint))
	return v


func _do_upgrade(id: String) -> void:
	var was := Meta.level(id)
	if not Meta.upgrade(id):
		return
	if Meta.building_busy(id):
		_toast_text("Стройка началась: %s, ур. %d — завершится через %d вылаз." % [Meta.BUILDINGS[id]["name"], int(Meta.construct["lvl"]), int(Meta.construct["left"])])
	Sound.play("evolve" if was == 0 else "chest", -2.0)
	_shake = 1.0
	_rebuild_building(id)
	Net.push_hub()
	var bp: Vector3 = Meta.BUILDINGS[id]["pos"]
	_particles(_world, bp + Vector3(0, 1.5, 0), Meta.BUILDINGS[id]["color"], 60, Vector3(1.5, 1.5, 1.5), Vector3(0, 2, 0), 1.2, 0.12, true, 4.0)
	_particles(_world, bp + Vector3(0, 0.5, 0), Color(0.6, 0.55, 0.65), 30, Vector3(1.8, 0.2, 1.8), Vector3(0, 0.5, 0), 1.5, 0.25, true, 1.5)
	if id == "hall":
		_toast_text("Новый герой ждёт вас в таверне!")
	_fill_panel()


func _start_run() -> void:
	Sound.play("ability", 0.0)
	_close_panel()
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color", Color(0.3, 0.1, 0.5, 1.0), 0.5)
	tw.tween_callback(func(): Loader.go("res://main.tscn"))


# ================= Портал: выбор уровня главы =================

var _portal_ch := -1


func _fill_portal() -> void:
	var c: Dictionary = Data.CHARACTERS[Data.selected_character]
	var cur_ch := Data.chapter_of(mini(Meta.levels_cleared, Data.LEVELS.size() - 1))
	if _portal_ch < 0 or _portal_ch > cur_ch:
		_portal_ch = cur_ch
	# Вкладки глав: открываются по мере прохождения
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 6)
	tabs.custom_minimum_size = Vector2(minf(760, _avail()), 0)
	for ci in Story.CHAPTERS.size():
		var open := ci <= cur_ch
		var tb := _button(("Глава %s" % ["I", "II", "III"][ci]) if open else "Глава %s  🔒" % ["I", "II", "III"][ci], MAGENTA if ci == _portal_ch else MAGENTA.darkened(0.55), open)
		tb.custom_minimum_size = Vector2(150, 40)
		tb.add_theme_font_size_override("font_size", 15)
		var cc := ci
		tb.pressed.connect(func():
			_portal_ch = cc
			Sound.play("click")
			_fill_panel())
		tabs.add_child(tb)
	_panel_box.add_child(_centered(tabs))
	_panel_box.add_child(_centered(_label(str(Story.CHAPTERS[_portal_ch]["name"]).to_upper(), 28, Color.WHITE, Color(MAGENTA, 0.8))))
	var intro := _label(Story.CHAPTERS[_portal_ch]["intro"], 14, Color(0.82, 0.8, 0.95))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size = Vector2(minf(700, _avail()), 0)
	_panel_box.add_child(_centered(intro))
	_panel_box.add_child(_centered(_label(("Герой: %s — %s\nпройдено %d / %d" if _portrait() else "Герой: %s — %s   •   пройдено %d / %d") % [c["name"], c["title"], Meta.levels_cleared, Data.LEVELS.size()], 17, c["color"])))
	if Net.mode == "host":
		var ok: bool = Net.lobby.get("client", false)
		var hc: Dictionary = Data.CHARACTERS.get(Net.peer_hero, Data.CHARACTERS["vega"])
		var t := ("Сетевая вылазка вдвоём  •  Игрок 2: %s — %s" % [hc["name"], hc["title"]]) if ok else "Ждём второго игрока — он должен подключиться к вашей игре"
		_panel_box.add_child(_centered(_label(t, 17, Color(1.0, 0.45, 0.8) if ok else Color(0.7, 0.7, 0.85))))
	var grid := GridContainer.new()
	grid.columns = _cols(220)   # вертикальный экран: уровни в две колонки, ничего не вылезает
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in range(_portal_ch * Data.LEVELS_PER_CHAPTER, mini((_portal_ch + 1) * Data.LEVELS_PER_CHAPTER, Data.LEVELS.size())):
		var lv: Dictionary = Data.LEVELS[i]
		var unlocked := i <= Meta.levels_cleared
		var cleared := i < Meta.levels_cleared
		var boss_mark := "  ☠" if not lv["bosses"].is_empty() else ""
		var status_txt := "закрыт"
		if cleared:
			status_txt = "✓ пройден"
		elif unlocked:
			status_txt = "%d:%02d" % [int(lv["time"]) / 60, int(lv["time"]) % 60]
		var accent := GOLD if cleared else (MAGENTA if unlocked else Color(0.35, 0.35, 0.4))
		var b := _button("%d. %s%s\n%s" % [i + 1, lv["name"], boss_mark, status_txt], accent, unlocked and (Net.mode != "host" or Net.lobby.get("client", false)))
		b.custom_minimum_size = Vector2(minf(210, _avail()), 64)
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = Story.LEVEL_STORY[i]["brief"] if i < Story.LEVEL_STORY.size() else lv["desc"]
		var idx := i
		b.pressed.connect(func():
			Data.selected_level = idx
			if Net.mode == "host":
				Sound.play("ability", 0.0)
				Net.start_run(idx)
			else:
				_start_run())
		grid.add_child(b)
	_panel_box.add_child(_centered(grid))
	var m := Meta.run_mods()
	var bonus := ("Бонусы убежища:\nурон ×%.2f   шанс сундука +%d%%" if _portrait() else "Бонусы убежища:  урон ×%.2f   шанс сундука +%d%%") % [m["damage"], int(m["chest"] * 100.0)]
	_panel_box.add_child(_centered(_label(bonus, 14, Color(0.8, 0.8, 0.95))))
	_add_close()


# ================= Академия / Арсенал / Лаборатория: деревья =================

var _tree_tab := ""


func _fill_tree_panel(id: String) -> void:
	var info: Dictionary = Meta.BUILDINGS[id]
	var col: Color = info["color"]
	var lvl := Meta.level(id)
	var narrow := _portrait()
	var tl := _label("%s   %s" % [info["name"], "◆".repeat(lvl) + "◇".repeat(int(info["max"]) - lvl)], 26, Color.WHITE, Color(col, 0.8))
	_panel_box.add_child(_centered(tl))
	var prefix: String = {"shrine": "c:", "forge": "w:", "lab": "m:"}[id]
	var source: Dictionary = {"shrine": Data.CHARACTERS, "forge": Data.WEAPONS, "lab": Data.PASSIVES}[id]
	if _tree_tab == "" or not _tree_tab.begins_with(prefix):
		_tree_tab = prefix + str(source.keys()[0])
	# Вертикальный экран: список — полосой сверху; горизонтальный — колонкой слева
	var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if narrow else 16)
	_panel_box.add_child(row)
	var list: Container
	if narrow:
		# Вертикальный экран: кнопки переносятся по строкам — без горизонтальной прокрутки
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.custom_minimum_size = Vector2(_avail(), 0)
		row.add_child(flow)
		list = flow
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(minf(240, _avail()), 470)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		row.add_child(scroll)
		scroll.add_child(vb)
		list = vb
	for key in source:
		var tk: String = prefix + str(key)
		var name_txt: String = source[key]["name"]
		var owned: int = Meta.trees.get(tk, []).size()
		var total: int = Meta.tree_nodes(tk).size()
		var locked: bool = id == "shrine" and not Meta.hero_unlocked(key)
		var b := _button("%s %d/%d" % [name_txt, owned, total] if not locked else "%s ⊘" % name_txt, col if tk == _tree_tab else col.darkened(0.5), not locked)
		b.custom_minimum_size = Vector2(minf(150 if narrow else 222, _avail()), 52 if narrow else (50 if id == "shrine" else 36))
		b.add_theme_font_size_override("font_size", 13 if narrow else 14)
		b.clip_text = true
		if id == "shrine":
			b.icon = Pixel.portrait(source[key]["sprite"], locked)
		else:
			b.icon = Pixel.icon(str(key))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 30 if id == "shrine" else 26)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_tree_tab = tk
			Sound.play("click")
			_fill_panel())
		list.add_child(b)
	# Само дерево
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var key_name: String = _tree_tab.substr(2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	right.add_child(head)
	var src: Dictionary = source[key_name]
	if id == "shrine":
		head.add_child(_pic(Pixel.portrait(src["sprite"]), 2.0))
	else:
		head.add_child(_pic(Pixel.icon(key_name), 2.4))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(_label(src["name"] + (("  —  " + src["title"]) if src.has("title") else ""), 20, col.lightened(0.3)))
	var desc: String = src.get("desc", src.get("trait", ""))
	if id == "shrine":
		desc = "%s  •  «%s»: %s" % [src["trait"], src["active"], src["active_desc"]]
	var dl := _label(desc, 13, Color(0.8, 0.8, 0.95))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(minf(500 if narrow else 720, _avail() - (90.0 if narrow else 350.0)), 0)
	hv.add_child(dl)
	var tv = preload("res://scripts/tree_view.gd").new()
	right.add_child(tv)
	tv.setup(_tree_tab, col, narrow, _avail() if narrow else _avail() - 260.0)
	tv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Подробности узла (наведение / касание): эффект, цена, условия
	var info_l := _label("Наведите на узел или коснитесь его — здесь появятся эффект и условия открытия.", 13, Color(0.9, 0.85, 1.0))
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(minf(tv.custom_minimum_size.x, _avail()), 36)
	right.add_child(info_l)
	tv.info.connect(func(t: String): info_l.text = t)
	tv.bought.connect(func():
		_particles(_world, Meta.BUILDINGS[id]["pos"] + Vector3(0, 2.0, 0), col, 30, Vector3(1, 1, 1), Vector3(0, 2, 0), 1.0, 0.1, true, 3.0)
		_fill_panel.call_deferred())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 14)
	_panel_box.add_child(foot)
	if Meta.building_busy(id):
		foot.add_child(_label("⚒ стройка ур. %d — ещё %d выл." % [int(Meta.construct["lvl"]), int(Meta.construct["left"])], 16, GOLD))
	elif lvl < int(info["max"]):
		var up := _button("ЗДАНИЕ УР. %d — %s" % [lvl + 1, Meta.cost_text(Meta.build_cost(id))], col, Meta.can_upgrade(id))
		up.custom_minimum_size.x = 320 if narrow else 420
		up.add_theme_font_size_override("font_size", 16)
		up.pressed.connect(func(): _do_upgrade(id))
		foot.add_child(up)
		var why := Meta.upgrade_block(id)
		if why != "":
			up.tooltip_text = why
			_panel_box.add_child(_centered(_label("Здание: ⊘ " + why + "   •   у вас ⚙ %d  ▣ %d  ✶ %d" % [int(Meta.materials["scrap"]), int(Meta.materials["chips"]), int(Meta.materials["cores"])], 13, Color(1.0, 0.65, 0.65))))
	var close := _button("ЗАКРЫТЬ" if narrow else Settings.with_key("ЗАКРЫТЬ", "back"), Color(0.6, 0.6, 0.75))
	close.custom_minimum_size.x = 220 if narrow else 260
	close.pressed.connect(func():
		Sound.play("click")
		_close_panel())
	foot.add_child(close)



# ================= Сетевая игра: убежище хоста =================

var _net_client := false
var _buddy: Node3D
var _bd_base: Sprite3D
var _bd_emit: Sprite3D
var _bd_frames: Dictionary
var _bd_hero := ""
var _bd_t := 0.0
var _bd_label: Label3D
var _net_label: Label
var _net_send_t := 0.0
var _was_net := false


## Уровень здания: у клиента — как в убежище хоста.
func _lvl(id: String) -> int:
	if _net_client:
		return int(Net.host_hub.get("buildings", {}).get(id, 0))
	return Meta.level(id)


func _net_tick(delta: float) -> void:
	if Net.mode == "":
		if _was_net:
			# Связь пропала — назад в меню сетевой игры
			_was_net = false
			Data.menu_page = "net"
			Loader.go("res://menu.tscn")
		if _net_label:
			_net_label.visible = false
		return
	_was_net = true
	if _net_label == null:
		_net_label = _label("", 16, Color(0.4, 1.0, 0.6), Color(0.2, 0.8, 0.4, 0.5))
		_net_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_net_label.offset_left = -620
		_net_label.offset_right = -16
		_net_label.offset_top = 18
		_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud.add_child(_net_label)
	if Net.mode == "host":
		_net_label.text = ("СЕТЬ: Игрок 2 в убежище" if Net.lobby.get("client", false) else "СЕТЬ: ждём игрока 2...  IP: " + _local_ips())
	else:
		_net_label.text = "СЕТЬ: вы в убежище хоста  •  вылазку начинает хост"
	# Свой аватар — напарнику
	_net_send_t -= delta
	if _net_send_t <= 0.0:
		_net_send_t = 1.0 / 15.0
		var moving := Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO and _panel_id == ""
		Net.send_hub_pos(_avatar.position, _facing_left, moving, Data.selected_character)
	# Аватар напарника
	var b: Dictionary = Net.buddy
	if b.is_empty() or Time.get_ticks_msec() - int(b.get("t", 0)) > 4000:
		if _buddy:
			_buddy.visible = false
		return
	if _buddy == null:
		_buddy = Node3D.new()
		_buddy.position = b["pos"]
		_world.add_child(_buddy)
		var col := Color(1.0, 0.4, 0.75) if not _net_client else Color(0.3, 0.95, 1.0)
		_bd_label = _label3d(_buddy, "ИГРОК 2" if not _net_client else "ХОСТ", Vector3(0, 1.9, 0), col, 36)
	_buddy.visible = true
	var bn: String = b.get("nick", "")
	if bn != "" and _bd_label.text != bn:
		_bd_label.text = bn
	if b["hero"] != _bd_hero:
		_bd_hero = b["hero"]
		if _bd_base:
			_bd_base.queue_free()
			_bd_emit.queue_free()
		_bd_frames = Pixel.frames(Data.CHARACTERS.get(_bd_hero, Data.CHARACTERS["vega"])["sprite"])
		var pair := _sprite_pair(_buddy, _bd_frames)
		_bd_base = pair[0]
		_bd_emit = pair[1]
	_buddy.position = _buddy.position.lerp(b["pos"], 1.0 - exp(-12.0 * delta))
	_bd_t += delta
	var f := Pixel.hero_frame(_bd_frames, "run" if b["moving"] else "idle", _bd_t)
	_bd_base.texture = _bd_frames["base"][f]
	_bd_emit.texture = _bd_frames["emit"][f]
	_bd_base.flip_h = b["left"]
	_bd_emit.flip_h = b["left"]


func _local_ips() -> String:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return ", ".join(out)


## Клиент: здания хоста только для просмотра.
func _fill_client_panel(id: String) -> void:
	if id == "portal":
		var c: Dictionary = Data.CHARACTERS[Data.selected_character]
		_panel_box.add_child(_centered(_label("ПОРТАЛ", 34, Color.WHITE, Color(MAGENTA, 0.8))))
		_panel_box.add_child(_centered(_label("Вылазку и уровень выбирает хост.", 19, Color(0.85, 0.85, 1.0))))
		_panel_box.add_child(_centered(_label("Ваш герой: %s — %s" % [c["name"], c["title"]], 18, c["color"])))
		_panel_box.add_child(_centered(_label("Сменить героя можно в таверне.", 15, Color(0.7, 0.7, 0.85))))
	else:
		var info: Dictionary = Meta.BUILDINGS[id]
		var lvl := _lvl(id)
		_panel_box.add_child(_centered(_label(info["name"], 34, Color.WHITE, Color(info["color"], 0.8))))
		_panel_box.add_child(_centered(_label("◆".repeat(lvl) + "◇".repeat(int(info["max"]) - lvl), 22, info["color"])))
		var d := _label("Это убежище хоста — улучшать его здания может только он.\nВаши улучшения из своего убежища действуют в сетевой вылазке.", 16, Color(0.85, 0.85, 1.0))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(minf(520, _avail()), 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_box.add_child(d)
	_add_close()


## Клиент: Зал героев — выбор из СВОИХ открытых героев.
func _fill_client_hall() -> void:
	_panel_box.add_child(_centered(_label("ВАШИ ГЕРОИ", 30, GOLD, Color(GOLD, 0.6))))
	_panel_box.add_child(_centered(_label("Открыты по вашему сохранению", 15, Color(0.75, 0.75, 0.9))))
	var row := GridContainer.new()
	row.columns = _cols(206 if _portrait() else 180)
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	for hid in Data.CHARACTERS:
		var hc: Dictionary = Data.CHARACTERS[hid]
		var unlocked := Meta.hero_unlocked(hid)
		var txt: String = ("%s\n%s" % [hc["name"], hc["title"]]) if unlocked else "%s\n(закрыт)" % hc["name"]
		if hid == Data.selected_character:
			txt = "✓ " + txt
		var hb := _button(txt, hc["color"], unlocked)
		hb.custom_minimum_size = Vector2(minf(150, _avail()), 58)
		hb.add_theme_font_size_override("font_size", 14)
		hb.pressed.connect(func():
			Data.selected_character = hid
			_set_avatar_sprites()
			_update_hero_label()
			Sound.play("levelup", -6.0)
			Net.send_profile()
			_fill_panel())
		row.add_child(hb)
	_panel_box.add_child(row)
	_add_close()


# ================= Жители убежища: разные NPC со своими ролями =================

## Особые места убежища (их обходит декор): костёр, тренировочный плац, колодец, сад.
const CAMPFIRE := Vector3(0, 0, -13)
const TRAINING := Vector3(-15, 0, 3)
const WELL := Vector3(14, 0, 4)
const GARDEN := Vector3(0, 0, 17)
const LIBRARY := Vector3(14, 0, -8)
const STALLS := [Vector3(-4.6, 0, -8.2), Vector3(4.6, 0, -8.2), Vector3(-12.5, 0, 13.0), Vector3(12.5, 0, 13.0)]

const NPC_PHRASES := {
	"merchant": ["Свежие кристаллы!", "Склянки со светом — два осколка!", "Подходи, не стесняйся!", "Лучшие руны в посаде!"],
	"guard": ["Всё спокойно.", "Стена держится.", "Слышал вой за воротами...", "Не отходи далеко от огня."],
	"kid": ["Догони!", "Я быстрее!", "Хи-хи!", "Смотри, дрон!"],
	"smith": ["Ещё один клинок...", "Горн горячий!", "Тук-тук-тук!", "Руна легла ровно."],
	"monk": ["Портал дышит.", "Тише... слушай неон.", "Сила в равновесии.", "Код и магия — одно."],
	"musician": ["♪ Ночь длинна... ♪", "♪ Неон и сталь ♪", "Подпевай!", "♪ ла-ла-ла ♪"],
	"elder": ["В мои годы неона не было...", "Береги себя, охотник.", "Огонь греет кости.", "Помню первую ночь..."],
	"walker": ["Неон греет душу.", "Удачной вылазки!", "Пахнет озоном.", "Здесь безопасно.", "Кузня опять дымит.", "Видел Лича? Жуть..."],
	"gardener": ["Светоцвет подрос!", "Полить бы...", "Эти грибы светятся к дождю.", "Не топчи грядки!"],
	"robot": ["БИП. Уборка.", "БУП-БИП.", "Сканирую...", "Заряд 87%."],
	"trainee": ["Хэй-я!", "Ещё удар!", "Устал... но не сдамся!", "Смотри, как я могу!"],
}
const NPC_NAMES := ["Мира", "Тим", "Ольга", "Сэм", "Варя", "Ким", "Лекс", "Нико", "Ада", "Рей", "Зоя", "Ян",
	"Фил", "Эла", "Гор", "Ива", "Дар", "Лин", "Бо", "Тая", "Арс", "Нэд", "Юна", "Макс"]
const NPC_TITLES := {"merchant": "торговка", "guard": "стражник", "kid": "ребёнок", "smith": "подмастерье",
	"monk": "кибер-монах", "musician": "музыкант", "elder": "старейшина", "walker": "житель",
	"gardener": "садовница", "robot": "робот-уборщик", "trainee": "новобранец",
	"barkeep": "трактирщик", "blacksmith": "кузнец", "priestess": "жрица", "engineer": "инженер", "commander": "командир"}


func _spawn_npcs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var add := _add_npc
	# Торговцы за прилавками
	for p in STALLS:
		var d := Vector3(-p.x, 0, -p.z).normalized()
		add.call("merchant", p - d * 1.1, {"home": p - d * 1.1})
	# Стража обходит стену
	for i in 3:
		add.call("guard", Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 20.0, {"ang": i * 2.1, "dir": 1.0 if i % 2 == 0 else -1.0})
	# Дети носятся по площади
	for i in 3:
		add.call("kid", Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(2, 6)))
	# Подмастерье у кузни, монах у портала, музыкант и старейшины у костра
	var fp: Vector3 = Meta.BUILDINGS["forge"]["pos"]
	add.call("smith", fp + Vector3(2.4, 0, 1.2), {"home": fp + Vector3(2.4, 0, 1.2)})
	add.call("monk", PORTAL_POS + Vector3(-2.6, 0, 1.4), {"home": PORTAL_POS + Vector3(-2.6, 0, 1.4)})
	add.call("musician", CAMPFIRE + Vector3(0, 0, 2.0), {"home": CAMPFIRE + Vector3(0, 0, 2.0)})
	for i in 3:
		var a := PI + i * 0.9 - 0.9
		var sp := CAMPFIRE + Vector3(cos(a), 0, sin(a)) * 2.0
		add.call("elder", sp, {"home": sp})
	# Новобранцы на плацу, садовница, робот-уборщики и просто жители
	for i in 2:
		add.call("trainee", TRAINING + Vector3(1.4, 0, -1.0 + i * 2.0), {"home": TRAINING + Vector3(1.4, 0, -1.0 + i * 2.0)})
	add.call("gardener", GARDEN + Vector3(1.5, 0, 0))
	# Командир Ворон у доски заданий — ведёт сюжет
	add.call("commander", COMMANDER_POS, {"home": COMMANDER_POS})
	for i in 2:
		add.call("robot", Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-2, 8)))
	for i in 6:
		var a := rng.randf() * TAU
		add.call("walker", Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 12.0))


var _npc_n := 0


func _add_npc(role: String, pos: Vector3, extra := {}) -> void:
	var v := _make_npc(role, pos, 100 + _npc_n * 7, NPC_NAMES[_npc_n % NPC_NAMES.size()])
	for k in extra:
		v[k] = extra[k]
	_apply_profile(v, _profile_for(role))
	# Стартовая точка и «рабочее место» — не внутри моделей
	(v["node"] as Node3D).position = _collide((v["node"] as Node3D).position, 0.5)
	v["home"] = _collide(v["home"], 0.5)
	_npc_n += 1


func _make_npc(role: String, pos: Vector3, seed: int, nm: String) -> Dictionary:
	var node := Node3D.new()
	node.position = pos
	_world.add_child(node)
	var frames: Dictionary
	if role == "robot":
		frames = Pixel.frames("drone")
	else:
		frames = Pixel.frames("villager_%d" % seed)
	var pair := _sprite_pair(node, frames)
	if role == "kid":
		node.scale = Vector3.ONE * 0.75
	if role == "robot":
		node.scale = Vector3.ONE * 0.8
		_light(node, Vector3(0, 0.6, 0.3), CYAN, 0.5, 2.5)
	var name_l := _label3d(node, "%s, %s" % [nm, NPC_TITLES[role]] if role != "robot" else "Б-%d" % (seed % 100), Vector3(0, 1.55, 0), Color(0.85, 0.85, 1.0, 0.95), 30)
	name_l.visible = false
	var bubble := _label3d(node, "", Vector3(0, 2.0, 0), Color(1, 1, 1), 32)
	bubble.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var speed := {"kid": 3.6, "guard": 1.4, "robot": 1.8, "walker": 1.6, "gardener": 1.0}.get(role, 1.2) as float
	var v := {"node": node, "base": pair[0], "emit": pair[1], "frames": frames, "role": role,
		"target": pos, "wait": rng.randf_range(0.5, 3.0), "t": rng.randf() * 5.0, "home": pos,
		"bubble": bubble, "bubble_t": rng.randf_range(3.0, 14.0), "name": name_l, "speed": speed, "fx_t": rng.randf() * 2.0}
	_villagers.append(v)
	return v


## Любимые места жителей — куда они ходят по своим делам.
const HAUNTS := {
	"Мира": ["gate", "gate", "campfire"], "Лекс": ["lab", "board", "portal"], "Ада": ["shrine", "hall", "campfire"],
	"Нико": ["board", "portal", "gate"], "Рей": ["lab", "forge", "well"], "Зоя": ["gate", "board", "hall"],
}


func _place(id: String) -> Vector3:
	match id:
		"gate":
			return Vector3(randf_range(-1.5, 1.5), 0, 20.5)
		"board":
			return BOARD + Vector3(randf_range(-1.0, 1.0), 0, 1.6)
		"portal":
			return PORTAL_POS + Vector3(randf_range(-2.0, 2.0), 0, 2.4)
		"campfire":
			return CAMPFIRE + Vector3(randf_range(-2.5, 2.5), 0, 2.8)
		"well":
			return WELL + Vector3(randf_range(-1.2, 1.2), 0, 1.8)
		"market":
			return STALLS[randi() % STALLS.size()] + Vector3(0, 0, 1.6)
	if Meta.BUILDINGS.has(id):
		return Meta.BUILDINGS[id]["pos"] + Vector3(randf_range(-1.2, 1.2), 0, 2.7)
	return Vector3.ZERO


## Шаг в обход препятствий: прямо, иначе пробуем отклониться в «свою» сторону,
## потом в другую. Плюс лёгкое расталкивание с соседями.
func _steer(pos: Vector3, dir: Vector3, step: float, v: Dictionary) -> Vector3:
	var side: float = v.get("side", 1.0 if randf() < 0.5 else -1.0)
	for a in [0.0, 35.0, 70.0, 105.0, 140.0]:
		for s in ([1.0] if a == 0.0 else [side, -side]):
			var d := dir.rotated(Vector3.UP, deg_to_rad(a * s))
			var cand := pos + d * step
			var c := _collide(cand, 0.35)
			if c.distance_to(cand) < step * 0.35:
				if a > 0.0:
					v["side"] = s
				return _separate(c, v)
	return _separate(_collide(pos + dir * step, 0.35), v)


func _separate(p: Vector3, v: Dictionary) -> Vector3:
	for o in _villagers:
		if o == v or o.has("chat") and o["chat"]["with"] == v:
			continue
		var op: Vector3 = (o["node"] as Node3D).position
		var d := Vector3(p.x - op.x, 0, p.z - op.z)
		var l := d.length()
		if l < 0.55 and l > 0.001:
			p += d / l * (0.55 - l) * 0.5
	return p


func _unstick(v: Dictionary) -> void:
	var node: Node3D = v["node"]
	var role: String = v["role"]
	if role in ["merchant", "smith", "monk", "musician", "elder", "trainee", "barkeep", "blacksmith", "priestess", "engineer", "commander"]:
		# Стоят на своём месте: если место занято моделью — переносим «дом» рядом
		v["home"] = _collide(v["home"], 0.5)
		node.position = _collide(node.position, 0.5)
		return
	v.erase("chat")
	var a := randf() * TAU
	v["target"] = _collide(node.position + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 4.0), 0.5)
	v["wait"] = 0.3
	v["side"] = -float(v.get("side", 1.0))


## Поведение NPC по ролям.
func _update_villagers(delta: float) -> void:
	for v in _villagers:
		var node: Node3D = v["node"]
		v["t"] += delta
		var role: String = v["role"]
		match role:
			"guard":
				# Обход вдоль стены
				v["ang"] = float(v["ang"]) + float(v["dir"]) * delta * 0.07
				v["target"] = Vector3(cos(v["ang"]), 0, sin(v["ang"])) * 20.0
			"kid":
				# Бегают за друг другом и по площади
				if node.position.distance_to(v["target"]) < 0.4:
					var a := randf() * TAU
					v["target"] = Vector3(cos(a), 0, sin(a) + 0.6) * randf_range(1.0, 5.5)
			"merchant", "smith", "monk", "musician", "elder", "trainee", "barkeep", "blacksmith", "priestess", "engineer", "commander":
				v["target"] = v["home"]
				_npc_work(v, delta)
			"robot":
				if node.position.distance_to(v["target"]) < 0.4:
					v["wait"] = float(v["wait"]) - delta
					if v["wait"] <= 0.0:
						v["wait"] = randf_range(1.0, 3.0)
						var a := randf() * TAU
						v["target"] = Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 12.0)
			"gardener":
				if node.position.distance_to(v["target"]) < 0.4:
					v["wait"] = float(v["wait"]) - delta
					if v["wait"] <= 0.0:
						v["wait"] = randf_range(2.0, 4.0)
						v["target"] = GARDEN + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-1.5, 1.5))
						_particles(_world, node.position + Vector3(0, 0.3, 0), Color(0.3, 0.6, 1.0), 6, Vector3(0.3, 0.1, 0.3), Vector3(0, -2, 0), 0.6, 0.05, true, 0.8)
			_:  # житель гуляет между зданиями, лавками и площадью
				if node.position.distance_to(v["target"]) < 0.4:
					v["wait"] = float(v["wait"]) - delta
					if v["wait"] <= 0.0:
						v["wait"] = randf_range(2.0, 6.0)
						var r := randf()
						var haunts: Array = HAUNTS.get(v.get("profile", {}).get("name", ""), [])
						if not haunts.is_empty() and randf() < 0.65:
							# У каждого жителя свои дела: лекарка — у алтаря, механик — у лаборатории…
							v["target"] = _place(haunts[randi() % haunts.size()])
						elif r < 0.4:
							var ids := Meta.BUILDINGS.keys()
							var bp: Vector3 = Meta.BUILDINGS[ids[randi() % ids.size()]]["pos"]
							v["target"] = bp + Vector3(randf_range(-1.5, 1.5), 0, 2.6)
						elif r < 0.6:
							v["target"] = CAMPFIRE + Vector3(randf_range(-3, 3), 0, randf_range(2.5, 3.5))
						elif r < 0.75:
							v["target"] = WELL + Vector3(randf_range(-1.5, 1.5), 0, 1.8)
						else:
							var a := randf() * TAU
							v["target"] = Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 6.0)
		# Цель внутри стены или модели — сдвигаем к ближайшему свободному месту
		if v.get("tchk", Vector3.INF) != v["target"]:
			v["target"] = _collide(v["target"], 0.45)
			v["tchk"] = v["target"]
		var to: Vector3 = v["target"] - node.position
		to.y = 0
		var moving := to.length() > 0.2
		if moving:
			var step := minf(to.length(), float(v["speed"]) * delta)
			var before := node.position
			node.position = _steer(node.position, to.normalized(), step, v)
			var mv := node.position - before
			if absf(mv.x) > 0.002:
				(v["base"] as Sprite3D).flip_h = mv.x < 0.0
				(v["emit"] as Sprite3D).flip_h = mv.x < 0.0
			# Застрял: за 2 с почти не приблизился к цели — ищет другой путь
			v["st"] = float(v.get("st", 0.0)) + delta
			if float(v["st"]) > 2.0:
				var d_now := to.length()
				if float(v.get("st_d", 999.0)) - d_now < 0.4:
					_unstick(v)
				v["st_d"] = d_now
				v["st"] = 0.0
		else:
			v["st"] = 0.0
			v["st_d"] = 999.0
		var fr: Dictionary = v["frames"]
		var f: int
		if role == "robot":
			f = int(v["t"] * 8.0) % 4
			node.position.y = 0.25 + sin(float(v["t"]) * 4.0) * 0.06
		else:
			f = (4 + int(v["t"] * (12.0 if role == "kid" else 9.0)) % 4) if moving else int(v["t"] * 3.0) % 4
		(v["base"] as Sprite3D).texture = fr["base"][f % fr["base"].size()]
		(v["emit"] as Sprite3D).texture = fr["emit"][f % fr["emit"].size()]
		# Имя — когда герой рядом
		(v["name"] as Label3D).visible = node.position.distance_to(_avatar.position) < 3.5
		# Реплики по роли
		v["bubble_t"] = float(v["bubble_t"]) - delta
		var bubble: Label3D = v["bubble"]
		if v["bubble_t"] <= 0.0:
			if bubble.visible:
				bubble.visible = false
				v["bubble_t"] = randf_range(7.0, 16.0)
			else:
				var ph: Array = v["profile"]["lines"] if v.has("profile") and randf() < 0.6 else NPC_PHRASES.get(role, HOST_PHRASES.get(role, NPC_PHRASES["walker"]))
				bubble.text = ph[randi() % ph.size()]
				bubble.visible = true
				v["bubble_t"] = 3.0


## Работа на месте: искры у подмастерья, руны у монаха, ноты у музыканта...
func _npc_work(v: Dictionary, delta: float) -> void:
	v["fx_t"] = float(v["fx_t"]) - delta
	if v["fx_t"] > 0.0:
		return
	var node: Node3D = v["node"]
	var p := node.position + Vector3(0, 0.9, 0)
	match v["role"]:
		"smith", "blacksmith":
			v["fx_t"] = 0.9
			_particles(_world, p + Vector3(0.4, -0.3, 0.2), Color(1.0, 0.6, 0.2), 10, Vector3(0.1, 0.1, 0.1), Vector3(0, -6, 0), 0.5, 0.05, true, 3.0)
		"monk", "priestess":
			v["fx_t"] = 1.6
			_particles(_world, p + Vector3(0, 0.6, 0), Color(0.75, 0.45, 1.0), 6, Vector3(0.4, 0.1, 0.4), Vector3(0, 0.8, 0), 1.4, 0.06, true, 0.4)
		"musician":
			v["fx_t"] = 0.7
			_particles(_world, p + Vector3(0.2, 0.4, 0), GOLD, 2, Vector3(0.1, 0.1, 0.1), Vector3(0.3, 1.0, 0), 1.6, 0.09, true, 0.6)
		"trainee":
			v["fx_t"] = 0.8
			_particles(_world, p + Vector3(-0.6, -0.1, 0), Color(1.0, 0.95, 0.8), 5, Vector3(0.1, 0.2, 0.1), Vector3(0, -3, 0), 0.3, 0.05, true, 2.0)
			(v["base"] as Sprite3D).flip_h = true
			(v["emit"] as Sprite3D).flip_h = true
		"engineer":
			v["fx_t"] = 1.1
			_particles(_world, p + Vector3(0.4, -0.2, 0.2), CYAN, 6, Vector3(0.1, 0.1, 0.1), Vector3(0, -4, 0), 0.4, 0.04, true, 2.5)
		"merchant", "barkeep":
			v["fx_t"] = 3.0
		_:
			v["fx_t"] = 2.0


# ---- Новые места: костёр, тренировочный плац, колодец, сад ----

func _build_places() -> void:
	_reserved = [CAMPFIRE, TRAINING, WELL, GARDEN, PORTAL_POS + Vector3(3.6, 0, 1.5), LIBRARY]
	_reserved.append_array(STALLS)
	_build_library()
	var stone := _mat(Color(0.26, 0.24, 0.32), 0.85, 0.1, "brick", 1.4)
	var wood := _mat(Color(0.34, 0.24, 0.18), 0.9, 0.0, "wood", 1.0)
	# Костёр со скамьями и гирляндой
	_add(_world, _cyl(3.6, 3.6, 0.08, 24), _mat(Color(0.18, 0.15, 0.2), 0.9, 0.1, "tile", 1.0), CAMPFIRE + Vector3(0, 0.04, 0))
	for k in 8:
		var a := TAU * k / 8.0
		_add(_world, _sphere(0.22), stone, CAMPFIRE + Vector3(cos(a) * 0.8, 0.12, sin(a) * 0.8))
	for k in 3:
		var lg := _add(_world, _cyl(0.1, 0.1, 1.1, 6), wood, CAMPFIRE + Vector3(0, 0.15, 0), Vector3(90, k * 60.0, 0))
		lg.scale = Vector3.ONE
	var fire := _add(_world, _cyl(0.0, 0.5, 1.0, 8), _emat(Color(1.0, 0.5, 0.15), 3.5, 0.85), CAMPFIRE + Vector3(0, 0.6, 0))
	_flicker.append([fire.material_override, 3.5, 0.0])
	_bobbers.append([fire, 0.6, 0.08])
	var fl := _light(_world, CAMPFIRE + Vector3(0, 1.2, 0), Color(1.0, 0.6, 0.25), 2.2, 9.0)
	_fire_lights.append(fl)
	_particles(_world, CAMPFIRE + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 40, Vector3(0.3, 0.2, 0.3), Vector3(0, 2.0, 0), 1.4, 0.07)
	_particles(_world, CAMPFIRE + Vector3(0, 2.0, 0), Color(0.3, 0.28, 0.35), 16, Vector3(0.2, 0.2, 0.2), Vector3(0.2, 0.7, 0), 3.0, 0.14)
	for k in 4:
		var a := PI * 0.15 + k * PI * 0.45
		var b := _add(_world, _box(1.6, 0.25, 0.45), wood, CAMPFIRE + Vector3(cos(a), 0.22, sin(a)) * 2.7)
		b.rotation.y = -a + PI / 2.0
		_obstacles.append([CAMPFIRE + Vector3(cos(a), 0, sin(a)) * 2.7, 0.6])
	_obstacles.append([CAMPFIRE, 1.0])
	_label3d(_world, "КОСТЁР", CAMPFIRE + Vector3(0, 3.0, 0), Color(1.0, 0.75, 0.4), 30)

	# Тренировочный плац: манекены и стойка с оружием
	_add(_world, _box(5.0, 0.06, 5.0), _mat(Color(0.3, 0.24, 0.2), 0.95, 0.0, "wood", 0.8), TRAINING + Vector3(0, 0.03, 0))
	for k in 3:
		var dp := TRAINING + Vector3(-1.0, 0, -1.6 + k * 1.6)
		_add(_world, _cyl(0.06, 0.06, 1.6, 6), wood, dp + Vector3(0, 0.8, 0))
		var body := _add(_world, _cyl(0.3, 0.32, 0.8, 8), _mat(Color(0.6, 0.5, 0.3), 0.95, 0.0), dp + Vector3(0, 1.2, 0))
		_sway.append([body, k * 1.3, 0.12])
		_add(_world, _sphere(0.22), _mat(Color(0.6, 0.5, 0.3), 0.95, 0.0), dp + Vector3(0, 1.8, 0))
		_add(_world, _box(0.7, 0.08, 0.08), wood, dp + Vector3(0, 1.35, 0))
		_add(_world, _torus(0.28, 0.33), _emat(MAGENTA, 1.5), dp + Vector3(0, 1.2, 0.25), Vector3(90, 0, 0))
		_obstacles.append([dp, 0.5])
	var rack := TRAINING + Vector3(-2.2, 0, 0)
	_add(_world, _box(0.2, 1.4, 2.0), wood, rack + Vector3(0, 0.7, 0))
	for k in 4:
		_add(_world, _box(0.05, 1.3, 0.05), _emat([CYAN, MAGENTA, GOLD, CYAN][k] as Color, 1.6), rack + Vector3(0.15, 0.9, -0.7 + k * 0.45), Vector3(0, 0, 10))
	_label3d(_world, "ПЛАЦ", TRAINING + Vector3(0, 2.6, 0), Color(1.0, 0.6, 0.8), 30)

	# Колодец с неоновой водой
	_add(_world, _cyl(1.0, 1.1, 0.9, 12), stone, WELL + Vector3(0, 0.45, 0))
	var water := _add(_world, _cyl(0.85, 0.85, 0.05, 12), _emat(Color(0.2, 0.6, 1.0), 1.8, 0.85), WELL + Vector3(0, 0.88, 0))
	_flicker.append([water.material_override, 1.8, 3.0])
	for x in [-0.9, 0.9]:
		_add(_world, _cyl(0.06, 0.06, 1.6, 6), wood, WELL + Vector3(x, 1.3, 0))
	_add(_world, _box(2.0, 0.1, 0.1), wood, WELL + Vector3(0, 2.1, 0))
	var roofw := PrismMesh.new()
	roofw.size = Vector3(2.4, 0.7, 1.4)
	_add(_world, roofw, _mat(Color(0.4, 0.18, 0.22), 0.8, 0.1, "wood", 1.0), WELL + Vector3(0, 2.5, 0))
	_light(_world, WELL + Vector3(0, 1.2, 0), Color(0.3, 0.6, 1.0), 0.8, 4.0)
	_obstacles.append([WELL, 1.2])

	# Сад светоцветов: грядки, светящиеся растения и грибы
	for r in 3:
		var bed := GARDEN + Vector3(0, 0, -1.4 + r * 1.4)
		_add(_world, _box(5.0, 0.2, 0.8), _mat(Color(0.22, 0.15, 0.12), 1.0, 0.0), bed + Vector3(0, 0.1, 0))
		for k in 8:
			var c := [Color(0.4, 1.0, 0.5), CYAN, MAGENTA, GOLD][(k + r) % 4] as Color
			var pp := bed + Vector3(-2.1 + k * 0.6, 0.35, randf_range(-0.15, 0.15))
			_add(_world, _cyl(0.02, 0.02, 0.3, 4), _mat(Color(0.2, 0.5, 0.25), 1.0, 0.0), pp)
			var bloom := _add(_world, _sphere(0.09), _emat(c, 2.4), pp + Vector3(0, 0.18, 0))
			_flicker.append([bloom.material_override, 2.4, randf() * 10.0])
	for k in 6:
		var mp := GARDEN + Vector3(randf_range(-3.5, 3.5), 0, randf_range(2.0, 3.0))
		_add(_world, _cyl(0.04, 0.05, 0.25, 5), _mat(Color(0.8, 0.8, 0.75), 1.0, 0.0), mp + Vector3(0, 0.12, 0))
		_add(_world, _sphere(0.16), _emat(Color(0.7, 0.4, 1.0), 1.6), mp + Vector3(0, 0.28, 0))
	_particles(_world, GARDEN + Vector3(0, 0.8, 0), Color(0.5, 1.0, 0.6), 30, Vector3(2.6, 0.5, 2.0), Vector3(0, 0.15, 0), 4.0, 0.05)
	_label3d(_world, "САД СВЕТОЦВЕТОВ", GARDEN + Vector3(0, 2.0, 0), Color(0.6, 1.0, 0.7), 28)
	_obstacles.append([GARDEN, 2.4])

	# Доска объявлений у портала
	var nb := PORTAL_POS + Vector3(3.6, 0, 1.5)
	for x in [-0.6, 0.6]:
		_add(_world, _cyl(0.05, 0.05, 1.8, 5), wood, nb + Vector3(x, 0.9, 0))
	_add(_world, _box(1.5, 1.0, 0.08), wood, nb + Vector3(0, 1.5, 0))
	for k in 4:
		var paper := _add(_world, _box(0.3, 0.35, 0.02), _emat([GOLD, CYAN, Color(1, 1, 1), MAGENTA][k] as Color, 0.6), nb + Vector3(-0.45 + k * 0.3, 1.5 + (0.12 if k % 2 == 0 else -0.12), 0.05))
		paper.rotation.z = randf_range(-0.15, 0.15)
	_obstacles.append([nb, 0.6])


var _fire_lights: Array = []
var _reserved: Array = []


func _animate_places() -> void:
	for l in _fire_lights:
		(l as OmniLight3D).light_energy = 2.0 + 0.5 * sin(_t * 9.0) + 0.3 * sin(_t * 23.0)



# ================= Библиотека: всё об открытом =================

func _build_library() -> void:
	var stone := _mat(Color(0.28, 0.25, 0.36), 0.85, 0.1, "brick", 1.4)
	var wood := _mat(Color(0.32, 0.22, 0.17), 0.9, 0.0, "wood", 1.0)
	var roofm := _mat(Color(0.26, 0.14, 0.32), 0.8, 0.1, "wood", 1.0)
	var root := Node3D.new()
	root.position = LIBRARY
	root.rotation.y = atan2(-LIBRARY.x, -LIBRARY.z)   # фасадом к площади
	_world.add_child(root)
	# Корпус и крыша
	_add(root, _box(4.2, 3.0, 3.0), stone, Vector3(0, 1.5, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(4.6, 1.6, 3.4)
	_add(root, roof, roofm, Vector3(0, 3.8, 0))
	# Круглая башенка-обсерватория сбоку
	_add(root, _cyl(0.9, 1.0, 4.6, 12), stone, Vector3(2.2, 2.3, -0.4))
	_add(root, _cyl(0.0, 1.15, 1.4, 12), roofm, Vector3(2.2, 5.3, -0.4))
	_add(root, _torus(0.92, 1.02), _emat(Color(0.7, 0.4, 1.0), 2.2), Vector3(2.2, 3.6, -0.4))
	# Фасад: дверь, круглое окно-роза, полки с книгами за стеклом
	_add(root, _box(1.0, 1.7, 0.1), wood, Vector3(0, 0.85, 1.52))
	_add(root, _cyl(0.55, 0.55, 0.08, 16), _emat(Color(0.95, 0.75, 0.35), 1.6), Vector3(0, 2.45, 1.52), Vector3(90, 0, 0))
	for side in [-1.0, 1.0]:
		var shelf := Vector3(side * 1.45, 1.35, 1.52)
		_add(root, _box(1.0, 1.6, 0.08), wood, shelf)
		for r in 3:
			for k in 5:
				var col := [CYAN, MAGENTA, GOLD, Color(0.5, 1.0, 0.6), Color(0.7, 0.5, 1.0)][(k + r * 2) % 5] as Color
				var spine := _add(root, _box(0.13, 0.36, 0.06), _emat(col, 1.4), shelf + Vector3(-0.36 + k * 0.18, -0.5 + r * 0.5, 0.06))
				_flicker.append([spine.material_override, 1.4, randf() * 10.0])
	# Парящая раскрытая книга над входом
	var book := Node3D.new()
	book.position = Vector3(0, 4.9, 1.0)
	root.add_child(book)
	for side in [-1.0, 1.0]:
		_add(book, _box(0.7, 0.05, 0.9), _emat(Color(0.95, 0.9, 0.8), 1.2), Vector3(side * 0.36, 0, 0), Vector3(0, 0, side * -12.0))
	_add(book, _box(0.08, 0.1, 0.92), _mat(Color(0.4, 0.15, 0.4)), Vector3.ZERO)
	_bobbers.append([book, 4.9, 0.18])
	_particles(root, Vector3(0, 5.2, 1.0), Color(0.6, 0.8, 1.0), 18, Vector3(0.4, 0.2, 0.4), Vector3(0, 0.6, 0), 2.0, 0.05)
	_light(root, Vector3(0, 2.4, 2.4), Color(0.95, 0.75, 0.4), 1.4, 6.0)
	_light(root, Vector3(0, 5.0, 1.2), Color(0.6, 0.7, 1.0), 0.9, 4.0)
	_label3d(_world, "БИБЛИОТЕКА", LIBRARY + Vector3(0, 6.4, 0), Color(0.8, 0.7, 1.0), 32)
	_obstacles.append([LIBRARY, 2.4])
	_obstacles.append([LIBRARY + Vector3(2.2, 0, -0.4).rotated(Vector3.UP, root.rotation.y), 1.1])


## Доска заданий: столб с досками и светящимися листками.
func _build_board() -> void:
	var root := Node3D.new()
	root.position = BOARD
	root.rotation.y = deg_to_rad(20.0)
	_world.add_child(root)
	var wood := _mat(Color(0.42, 0.3, 0.2), 0.9, 0.0, "wood", 1.4)
	for x in [-0.8, 0.8]:
		_add(root, _box(0.14, 2.2, 0.14), wood, Vector3(x, 1.1, 0))
	_add(root, _box(1.9, 1.15, 0.08), wood, Vector3(0, 1.45, 0.02))
	_add(root, _box(2.1, 0.12, 0.3), wood, Vector3(0, 2.15, 0.05))
	var cols := [GOLD, CYAN, MAGENTA, Color(0.5, 1.0, 0.6)]
	for i in 4:
		var paper := _add(root, _box(0.36, 0.44, 0.02), _emat(cols[i], 1.3), Vector3(-0.62 + i * 0.41, 1.45 + (0.12 if i % 2 == 0 else -0.08), 0.08), Vector3(0, 0, (i - 1.5) * 5.0))
		_flicker.append([paper.material_override, 1.3, randf() * 10.0])
	_light(root, Vector3(0, 2.2, 0.8), GOLD, 0.9, 4.0)
	_label3d(_world, "ДОСКА ЗАДАНИЙ", BOARD + Vector3(0, 2.9, 0), GOLD.lightened(0.2), 28)
	_obstacles.append([BOARD, 0.9])


func _fill_board() -> void:
	_panel_box.add_child(_centered(_label("ДОСКА ЗАДАНИЙ", 34, Color.WHITE, Color(GOLD, 0.8))))
	var info := _label("Задание нужно ВЗЯТЬ — тогда оно пойдёт с вами в бой. Выполняется за ОДНУ вылазку. Выполненное сменяется новым, с каждым разом сложнее и щедрее.", 15, Color(0.8, 0.8, 0.95))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(minf(460 if _portrait() else 760, _avail()), 0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(_centered(info))
	if Net.mode != "":
		_panel_box.add_child(_centered(_label("В сетевой игре задания не засчитываются", 15, Color(1.0, 0.6, 0.6))))
	var grid := GridContainer.new()
	grid.columns = mini(3, _cols(450 if _portrait() else 262))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var b := Quests.board()
	for i in b.size():
		grid.add_child(_quest_card(b[i], i))
	_panel_box.add_child(_centered(grid))
	# Личное задание выбранного героя
	var hc: Dictionary = Data.CHARACTERS[Data.selected_character]
	var hq := Quests.hero_quest(Data.selected_character)
	var steps: int = Quests.HERO_QUESTS.get(Data.selected_character, []).size()
	_panel_box.add_child(_centered(_label("ЛИЧНОЕ ЗАДАНИЕ: %s — %s" % [hc["name"].to_upper(), hc["title"]], 20, hc["color"])))
	if hq.is_empty():
		_panel_box.add_child(_centered(_label("Вся история героя пройдена ★★★", 16, GOLD)))
	else:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sbox(hc["color"], PANEL_BG, 2, 6))
		var v := VBoxContainer.new()
		card.add_child(v)
		var t := _label("Шаг %d / %d:  «%s»" % [int(hq["step"]) + 1, steps, hq["title"]], 18, Color.WHITE)
		v.add_child(t)
		var lore := _label(hq["lore"], 15, Color(0.85, 0.8, 0.95))
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore.custom_minimum_size = Vector2(minf(440 if _portrait() else 720, _avail()), 0)
		v.add_child(lore)
		v.add_child(_label("Цель: " + Quests.desc(hq) + "  (только этим героем)", 16, GOLD))
		v.add_child(_label("Награда: " + Quests.reward_text(Quests.reward(hq)) + "  •  открывает узлы дерева героя", 14, Color(0.7, 1.0, 0.75)))
		var hid: String = Data.selected_character
		var tk := Quests.hero_taken(hid)
		var hb := _button("✓ Взято — отказаться" if tk else "ВЗЯТЬ", Color(0.6, 1.0, 0.7) if tk else GOLD)
		hb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hb.pressed.connect(func():
			Quests.set_hero_taken(hid, not tk)
			Meta.save()
			Sound.play("click")
			_fill_panel())
		v.add_child(hb)
		_panel_box.add_child(_centered(card))
	_add_close()


func _quest_card(q: Dictionary, i: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sbox(GOLD.darkened(0.2), PANEL_BG, 2, 4))
	card.custom_minimum_size = Vector2(minf(440 if _portrait() else 250, _avail()), 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(_label(Quests.title(q), 19, GOLD))
	var d := _label(Quests.desc(q), 15, Color(0.92, 0.92, 1.0))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(minf(220, _avail()), 0)
	v.add_child(d)
	v.add_child(_label("Сложность: " + "★".repeat(int(q.get("tier", 0)) + 1), 13, Color(0.75, 0.75, 0.9)))
	v.add_child(_label("Награда: " + Quests.reward_text(Quests.reward(q)), 14, Color(0.6, 1.0, 0.7)))
	var tk: bool = q.get("taken", false)
	var take := _button("✓ Взято — отказаться" if tk else "ВЗЯТЬ", Color(0.6, 1.0, 0.7) if tk else GOLD)
	take.custom_minimum_size = Vector2(minf(200, _avail()), 38)
	take.add_theme_font_size_override("font_size", 14)
	take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	take.pressed.connect(func():
		Meta.quests[i]["taken"] = not tk
		Meta.save()
		Sound.play("levelup" if not tk else "click", -6.0)
		_fill_panel())
	v.add_child(take)
	var swap := _button("Заменить — 15 ◆", Color(0.6, 0.6, 0.75), Meta.shards >= 15 and not tk)
	swap.custom_minimum_size = Vector2(minf(200, _avail()), 38)
	swap.add_theme_font_size_override("font_size", 14)
	swap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swap.pressed.connect(func():
		if Meta.shards < 15:
			return
		Meta.shards -= 15
		var ex: Array = []
		for qq in Meta.quests:
			ex.append(qq["k"])
		Meta.quests[i] = Quests.make(ex)
		Meta.save()
		Sound.play("click")
		_fill_panel())
	v.add_child(swap)
	return card


const LIB_TABS := [["chronicle", "Летопись"], ["bestiary", "Бестиарий"], ["heroes", "Герои"], ["abilities", "Способности"], ["weapons", "Оружие"],
	["modules", "Модули"], ["aspects", "Аспекты"], ["statuses", "Эффекты"], ["reactions", "Реакции"]]
var _lib_tab := "chronicle"
var _lib_sel := ""


## Список записей вкладки: [ключ, имя, иконка, открыто?]
func _lib_entries(tab: String) -> Array:
	var out: Array = []
	match tab:
		"chronicle":
			out.append(["prologue", "Слияние и Ночь Врат", Pixel.icon("book"), true])
			for c in Story.CHAPTERS.size():
				out.append(["ch%d" % c, Story.CHAPTERS[c]["short"], Pixel.icon("book"), Meta.levels_cleared >= c * Data.LEVELS_PER_CHAPTER])
		"bestiary":
			for e in Story.ENEMY_INFO:
				var spr: String = Data.ENEMIES.get(e, {}).get("sprite", e)
				out.append([e, Story.ENEMY_INFO[e]["name"], Pixel.frames(spr)["base"][0], Meta.discovered("e:" + e)])
		"heroes":
			for h in Data.CHARACTERS:
				var c: Dictionary = Data.CHARACTERS[h]
				var ok := Meta.hero_unlocked(h)
				out.append([h, c["name"], Pixel.portrait(c["sprite"], not ok), ok])
		"abilities":
			for h in Data.CHARACTERS:
				var c: Dictionary = Data.CHARACTERS[h]
				out.append([h, c["active"], Pixel.icon("ab_" + h), Meta.hero_unlocked(h)])
		"weapons":
			for w in Data.WEAPONS:
				out.append([w, Data.WEAPONS[w]["name"], Pixel.icon(w), _weapon_known(w)])
		"modules":
			for m in Data.PASSIVES:
				out.append([m, Data.PASSIVES[m]["name"], Pixel.icon(m), Meta.discovered("m:" + m)])
		"aspects":
			for a in Data.ASPECTS:
				out.append([a, Data.ASPECTS[a]["name"], Pixel.icon(a), Meta.discovered("a:" + a)])
		"statuses":
			for st in Data.STATUSES:
				out.append([st, Data.STATUSES[st]["name"], Pixel.icon("st_" + st), Meta.discovered("s:" + st) or not Data.STATUSES[st].get("derived", false)])
		"reactions":
			for r in Data.REACTIONS:
				var pair: PackedStringArray = (r as String).split("+")
				out.append([r, Data.REACTIONS[r]["name"].capitalize(), Pixel.icon("st_" + pair[0]), Meta.discovered("r:" + r)])
	return out


func _weapon_known(w: String) -> bool:
	if Meta.discovered("w:" + w):
		return true
	for h in Data.CHARACTERS:
		if Data.CHARACTERS[h]["weapon"] == w and Meta.hero_unlocked(h):
			return true
	return false


func _fill_library() -> void:
	var accent := Color(0.75, 0.6, 1.0)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	title.add_child(_pic(Pixel.icon("book"), 2.4))
	title.add_child(_label("БИБЛИОТЕКА УБЕЖИЩА", 30, Color.WHITE, Color(accent, 0.8)))
	_panel_box.add_child(_centered(title))
	# Вкладки
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 5)
	tabs.add_theme_constant_override("v_separation", 5)
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.custom_minimum_size = Vector2(minf(600 if _portrait() else 940, _avail()), 0)
	for t in LIB_TABS:
		var entries := _lib_entries(t[0])
		var known := entries.filter(func(e): return e[3]).size()
		var tb := _button("%s  %d/%d" % [t[1], known, entries.size()], accent if t[0] == _lib_tab else accent.darkened(0.55))
		tb.add_theme_font_size_override("font_size", 14)
		tb.custom_minimum_size = Vector2(0, 38)
		var tid: String = t[0]
		tb.pressed.connect(func():
			Sound.play("click")
			_lib_tab = tid
			_lib_sel = ""
			_fill_panel())
		tabs.add_child(tb)
	_panel_box.add_child(_centered(tabs))
	var entries := _lib_entries(_lib_tab)
	if _lib_sel == "" or not entries.any(func(e): return e[0] == _lib_sel):
		_lib_sel = entries[0][0]
		for e in entries:
			if e[3]:
				_lib_sel = e[0]
				break
	var row: BoxContainer = VBoxContainer.new() if _portrait() else HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel_box.add_child(row)
	# Список слева
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(600, _avail()), 220) if _portrait() else Vector2(250, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var sel_entry: Array = entries[0]
	for e in entries:
		var known: bool = e[3]
		var b := _button(e[1] if known else "???", accent if e[0] == _lib_sel else accent.darkened(0.6))
		b.custom_minimum_size = Vector2(minf(232, _avail()), 42)
		b.add_theme_font_size_override("font_size", 15)
		b.icon = e[2]
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 32)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not known:
			b.modulate = Color(0.55, 0.55, 0.65)
		var key: String = e[0]
		b.pressed.connect(func():
			Sound.play("click")
			_lib_sel = key
			_fill_panel())
		list.add_child(b)
		if e[0] == _lib_sel:
			sel_entry = e
			b.call_deferred("grab_focus")
	# Статья справа
	var art_scroll := ScrollContainer.new()
	art_scroll.custom_minimum_size = Vector2(minf(600, _avail()), 620) if _portrait() else Vector2(minf(680, _avail() - 270.0), 430)
	art_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(art_scroll)
	var art := VBoxContainer.new()
	art.add_theme_constant_override("separation", 10)
	art.custom_minimum_size = Vector2(minf(580 if _portrait() else 660, _avail() - (20.0 if _portrait() else 290.0)), 0)
	art_scroll.add_child(art)
	if sel_entry[3]:
		_lib_article(art, _lib_tab, sel_entry[0])
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 18)
		var pic := _pic(sel_entry[2], 4.0)
		pic.modulate = Color(0.1, 0.08, 0.15)
		head.add_child(pic)
		head.add_child(_label("Ещё не открыто", 26, Color(0.7, 0.7, 0.8)))
		art.add_child(head)
		var hint := "Говорят, этого героя видели где-то в пустошах…" if _lib_tab in ["heroes", "abilities"] else "Встретьте это в бою — запись появится здесь."
		art.add_child(_para(hint))
	_add_close()


func _para(text: String, color := Color(0.86, 0.86, 1.0), size := 16) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(570 if _portrait() else 640, _avail()), 0)
	return l


func _section(art: VBoxContainer, title: String) -> void:
	art.add_child(_label(title, 19, GOLD, Color(GOLD, 0.4)))


## Строка: маленькая картинка + текст.
func _icon_line(art: VBoxContainer, tex: Texture2D, text: String, color := Color(0.86, 0.86, 1.0)) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_pic(tex, 1.6))
	var l := _label(text, 16, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(520 if _portrait() else 600, _avail()), 0)
	h.add_child(l)
	art.add_child(h)


func _lib_head(art: VBoxContainer, tex: Texture2D, k: float, title: String, sub: String, col: Color) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sbox(col, Color(0.03, 0.02, 0.07, 0.95), 2, 10))
	frame.add_child(_pic(tex, k))
	head.add_child(frame)
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(_label(title, 30, Color.WHITE, Color(col, 0.8)))
	if sub != "":
		var sl := _label(sub, 17, col.lightened(0.3))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(minf(460, _avail()), 0)
		v.add_child(sl)
	head.add_child(v)
	art.add_child(head)


func _reactions_of(st: String) -> Array:
	var out: Array = []
	for key in Data.REACTIONS:
		var pair: PackedStringArray = (key as String).split("+")
		if st in pair:
			out.append(key)
	return out


func _lib_article(art: VBoxContainer, tab: String, key: String) -> void:
	match tab:
		"chronicle":
			if key == "prologue":
				_lib_head(art, Pixel.icon("book"), 3.0, "Летопись Слияния", "как всё началось", Color(0.75, 0.6, 1.0))
				for para in Story.PROLOGUE:
					art.add_child(_para(para, Color(0.9, 0.88, 1.0), 15))
			else:
				var c := int(key.substr(2))
				_lib_head(art, Pixel.icon("book"), 3.0, Story.CHAPTERS[c]["name"], "", Color(0.75, 0.6, 1.0))
				art.add_child(_para(Story.CHAPTERS[c]["intro"], Color(0.9, 0.88, 1.0), 15))
				for i in range(c * Data.LEVELS_PER_CHAPTER, (c + 1) * Data.LEVELS_PER_CHAPTER):
					if i < Meta.levels_cleared:
						_section(art, "%d. %s" % [i + 1, Data.LEVELS[i]["name"]])
						art.add_child(_para(Story.LEVEL_STORY[i]["after"], Color(0.85, 0.85, 0.98), 14))
		"bestiary":
			var info: Dictionary = Story.ENEMY_INFO[key]
			var ed: Dictionary = Data.ENEMIES.get(key, {})
			var col: Color = ed.get("color", Color.WHITE)
			_lib_head(art, Pixel.frames(ed.get("sprite", key))["base"][0], 3.0, info["name"], "тварь из орды Врат", col)
			art.add_child(_para(info["lore"], Color(0.9, 0.88, 1.0), 15))
			if not ed.is_empty():
				_section(art, "Повадки")
				art.add_child(_para("Здоровье: %d   •   скорость: %d   •   урон: %d" % [int(ed["hp"]), int(ed["speed"]), int(ed["damage"])], Color(0.8, 0.8, 0.95), 14))
			var barks: Array = info.get("barks", [])
			if not barks.is_empty():
				_section(art, "Что бормочет в бою")
				art.add_child(_para("«" + "»   «".join(barks) + "»", Color(1.0, 0.9, 0.75), 14))
		"heroes":
			var c: Dictionary = Data.CHARACTERS[key]
			_lib_head(art, Pixel.portrait(c["sprite"]), 5.0, c["name"], c["title"], c["color"])
			_section(art, "История")
			art.add_child(_para(Data.HERO_LORE.get(key, ""), Color(0.9, 0.85, 1.0), 15))
			var steps: Array = Quests.HERO_QUESTS.get(key, [])
			var done_n := Quests.hero_step(key)
			for i in steps.size():
				if i < done_n:
					art.add_child(_para("✓ «%s» — %s" % [steps[i][2], steps[i][3]], GOLD, 14))
				elif i == done_n:
					art.add_child(_para("• Личное задание «%s»: %s (только этим героем, доска заданий)" % [steps[i][2], Quests.desc({"k": steps[i][0], "g": steps[i][1]})], Color(0.7, 0.9, 1.0), 14))
			_section(art, "Характеристики")
			_icon_line(art, Pixel.icon("hp"), "Здоровье: %d" % int(c["hp"]))
			_icon_line(art, Pixel.icon("speed"), "Скорость: %d" % int(c["speed"]))
			_icon_line(art, Pixel.icon(c["weapon"]), "Стартовое оружие: %s — %s" % [Data.WEAPONS[c["weapon"]]["name"], Data.WEAPONS[c["weapon"]]["desc"]])
			_section(art, "Врождённая черта")
			art.add_child(_para(c["trait"]))
			_section(art, "Способность")
			_icon_line(art, Pixel.icon("ab_" + key), "«%s» — %s Перезарядка %.0f с." % [c["active"], c["active_desc"], float(c["active_cd"])])
			var el: String = Data.ABILITY_ELEMENT.get(key, "")
			if el != "":
				_icon_line(art, Pixel.icon("st_" + el), "Стихия способности: %s. После неё все удары героя 4 с кладут эту стихию." % Data.STATUSES[el]["name"], Data.STATUSES[el]["color"])
			_section(art, "Прокачка в Алтаре героев")
			var owned: Array = Meta.trees.get("c:" + key, [])
			for n in Meta.HERO_TREE:
				var has: bool = n["id"] in owned
				art.add_child(_para(("✓ " if has else "•  ") + "%s — %s" % [n["name"], n["desc"]], GOLD if has else Color(0.7, 0.7, 0.85), 15))
		"abilities":
			var c: Dictionary = Data.CHARACTERS[key]
			_lib_head(art, Pixel.icon("ab_" + key), 5.0, c["active"], "Способность героя: %s, %s" % [c["name"], c["title"].to_lower()], c["color"])
			art.add_child(_para(c["active_desc"]))
			_icon_line(art, Pixel.icon("cooldown"), "Перезарядка: %.0f с (уменьшают «Фокус» в алтаре и модули перезарядки героя)." % float(c["active_cd"]))
			var el: String = Data.ABILITY_ELEMENT.get(key, "")
			if el != "":
				_section(art, "Стихия и связки")
				_icon_line(art, Pixel.icon("st_" + el), Data.synergy_text(el), Data.STATUSES[el]["color"])
			_section(art, "Как применять")
			art.add_child(_para("Пробел / A на геймпаде. Способность также перезаряжает оружие, подпитывает поля и на 4 секунды даёт стихию героя всем ударам — так проще собирать реакции."))
			_icon_line(art, Pixel.portrait(c["sprite"]), "Владелец: %s — %s" % [c["name"], c["title"]], c["color"])
		"weapons":
			var w: Dictionary = Data.WEAPONS[key]
			var st: String = w["status"]
			_lib_head(art, Pixel.icon(key), 5.0, w["name"], w["desc"], Data.STATUSES[st]["color"])
			_section(art, "Стихия")
			_icon_line(art, Pixel.icon("st_" + st), "Удары кладут «%s».  %s" % [Data.STATUSES[st]["name"], Data.synergy_text(st)], Data.STATUSES[st]["color"])
			if Data.CATALYSTS.has(key):
				_section(art, "Катализатор — связка с другим оружием")
				var cat: Array = Data.CATALYSTS[key]
				_icon_line(art, Pixel.icon("st_" + cat[0]), Data.catalyst_text(key), Data.STATUSES[cat[0]]["color"])
			_section(art, "Рост по уровням")
			var s1 := Data.weapon_stats(key, 1)
			var s10 := Data.weapon_stats(key, 10)
			var names := {"damage": "урон", "cooldown": "перезарядка, с", "count": "количество", "pierce": "пробивание",
				"radius": "радиус", "range": "дальность", "length": "длина", "strikes": "удары", "beams": "лучи", "interval": "интервал, с"}
			for k in names:
				if s1.has(k) and s10.has(k):
					art.add_child(_para("•  %s: %s  →  %s (ур. 10)" % [names[k], _num(s1[k]), _num(s10[k])], Color(0.8, 0.85, 1.0), 15))
			_section(art, "Аспекты")
			art.add_child(_para("На 6 уровне оружие получает свой единственный аспект — выбор из трёх, по модулям оружия, которые у вас есть. Аспект, взятый одним оружием, другому уже не достанется (пока оружие не сольют). Например: «%s», «%s»." % [Data.evo_name(key, "damage"), Data.evo_name(key, "crit")]))
			_section(art, "Эволюция")
			art.add_child(_para("Как только два оружия достигают 10 уровня, они сливаются в одно — до двух слияний за бой. Вы выбираете основу: например, «Плазменная искра» + «Голо-клинки» станут «Голо-искрами» или «Плазмо-клинками». Характеристики обоих складываются и делятся пополам, аспекты и стихии суммируются, а их аспекты освобождаются для других оружий. Новое оружие атакует как основа, а каждый её удар выпускает атаку второго оружия из точки попадания. У каждого слияния своя иконка, занимает один слот."))
			var who: Array = []
			for h in Data.CHARACTERS:
				if Data.CHARACTERS[h]["weapon"] == key:
					who.append(Data.CHARACTERS[h]["name"])
			if not who.is_empty():
				_icon_line(art, Pixel.portrait(Data.CHARACTERS[Data.CHARACTERS.keys().filter(func(h): return Data.CHARACTERS[h]["weapon"] == key)[0]]["sprite"]), "Стартовое оружие: " + ", ".join(who))
			var owned: Array = Meta.trees.get("w:" + key, [])
			_section(art, "Прокачка в Рунной кузнице  (%d/%d)" % [owned.size(), Meta.WEAPON_TREE.size()])
			for n in Meta.WEAPON_TREE:
				var has: bool = n["id"] in owned
				art.add_child(_para(("✓ " if has else "•  ") + "%s — %s" % [n["name"], n["desc"]], GOLD if has else Color(0.7, 0.7, 0.85), 15))
		"modules":
			var p: Dictionary = Data.PASSIVES[key]
			var hero_kind: bool = p["kind"] == "hero"
			_lib_head(art, Pixel.icon(key), 5.0, p["name"], "Модуль героя" if hero_kind else "Модуль оружия", Color(0.5, 1.0, 0.7) if hero_kind else Color(1.0, 0.6, 0.3))
			art.add_child(_para(p["desc"] + " за каждый уровень (до 10)."))
			art.add_child(_para("Действует только на героя." if hero_kind else "Действует на все ваши оружия.", Color(0.75, 0.75, 0.9), 15))
			if Data.ASPECTS.has(key) and not hero_kind:
				var a: Dictionary = Data.ASPECTS[key]
				_section(art, "Аспект оружия")
				_icon_line(art, Pixel.icon(key), "«%s»: %s" % [a["name"], a["desc"]], a["color"])
			_section(art, "Ограничения")
			art.add_child(_para("В бою можно носить не больше %d оружия и %d модулей: %d модуля оружия и %d модуля героя. Аспект оружия (один, на 6 уровне) предлагается, только если в этот момент есть свободный модуль оружия, — иначе он пропускается." % [Data.MAX_WEAPONS, Data.MAX_PASSIVES, Data.MAX_WEAPON_MODULES, Data.MAX_HERO_MODULES]))
			var owned: Array = Meta.trees.get("m:" + key, [])
			_section(art, "Прокачка в Лаборатории  (%d/%d)" % [owned.size(), Meta.MODULE_TREE.size()])
			for n in Meta.MODULE_TREE:
				var has: bool = n["id"] in owned
				art.add_child(_para(("✓ " if has else "•  ") + "%s — %s" % [n["name"], n["desc"]], GOLD if has else Color(0.7, 0.7, 0.85), 15))
		"aspects":
			var a: Dictionary = Data.ASPECTS[key]
			_lib_head(art, Pixel.icon(key), 5.0, a["name"], "Аспект модуля «%s»" % Data.PASSIVES[key]["name"], a["color"])
			art.add_child(_para("Оружие с этим аспектом: " + a["desc"] + "."))
			_section(art, "Как получить")
			art.add_child(_para("Носите модуль «%s» и доведите оружие до 6 уровня — аспект появится среди вариантов (если его не занял другое оружие)." % Data.PASSIVES[key]["name"]))
			_section(art, "Названия оружия с аспектом")
			var shown := 0
			for w in Data.WEAPONS:
				if _weapon_known(w) and shown < 6:
					_icon_line(art, Pixel.icon(w), Data.evo_name(w, key), a["color"])
					shown += 1
		"statuses":
			var s: Dictionary = Data.STATUSES[key]
			_lib_head(art, Pixel.icon("st_" + key), 5.0, s["name"], "Эффект на враге, длится %.0f с" % float(s["time"]), s["color"])
			var what := {
				"burn": "Враг горит и получает урон каждую секунду.",
				"shock": "Ток бьёт врага и соседей; на мокрых — гораздо сильнее.",
				"chill": "Враг замедлен; лёд делает его хрупким для молота и стрел.",
				"bleed": "Кровь теряется со временем; кровоточащих добивают катана и круг.",
				"poison": "Яд медленно, но долго разъедает здоровье.",
				"wet": "Появляется, когда лёд тает от огня. Мокрый враг замедлен и уязвим к току и холоду.",
			}
			art.add_child(_para(what.get(key, "")))
			var src: Array = []
			for w in Data.WEAPONS:
				if Data.WEAPONS[w]["status"] == key and _weapon_known(w):
					src.append(w)
			if not src.is_empty():
				_section(art, "Кладут оружия")
				for w in src:
					_icon_line(art, Pixel.icon(w), Data.WEAPONS[w]["name"])
			_section(art, "Реакции")
			for r in _reactions_of(key):
				var pair: PackedStringArray = (r as String).split("+")
				var other: String = pair[0] if pair[1] == key else pair[1]
				var rr: Dictionary = Data.REACTIONS[r]
				var known := Meta.discovered("r:" + r)
				_icon_line(art, Pixel.icon("st_" + other), ("+ %s → %s: %s" % [Data.STATUSES[other]["name"], rr["name"], rr["desc"]]) if known else "+ %s → ??? (ещё не видели)" % Data.STATUSES[other]["name"], rr["color"] if known else Color(0.6, 0.6, 0.7))
		"reactions":
			var r: Dictionary = Data.REACTIONS[key]
			var pair: PackedStringArray = (key as String).split("+")
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", 10)
			head.add_child(_pic(Pixel.icon("st_" + pair[0]), 4.0))
			head.add_child(_label("+", 36, Color.WHITE))
			head.add_child(_pic(Pixel.icon("st_" + pair[1]), 4.0))
			var v := VBoxContainer.new()
			v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			v.add_child(_label(r["name"], 30, Color.WHITE, Color(r["color"], 0.8)))
			v.add_child(_label("%s + %s" % [Data.STATUSES[pair[0]]["name"], Data.STATUSES[pair[1]]["name"]], 17, r["color"]))
			head.add_child(v)
			art.add_child(head)
			art.add_child(_para("Когда на враге встречаются эти два эффекта: %s." % r["desc"]))
			_section(art, "Чем собрать")
			for st in pair:
				var ws: Array = []
				for w in Data.WEAPONS:
					if Data.WEAPONS[w]["status"] == st and _weapon_known(w):
						ws.append(Data.WEAPONS[w]["name"])
				if st == "wet":
					ws.append("реакция «Мокрый» (огонь + холод)")
				_icon_line(art, Pixel.icon("st_" + st), "%s: %s" % [Data.STATUSES[st]["name"], ", ".join(ws) if not ws.is_empty() else "способности героев"], Data.STATUSES[st]["color"])


func _num(v) -> String:
	if v is float:
		return ("%.2f" % v).rstrip("0").rstrip(".")
	return str(v)


# ================= Интерьеры зданий =================
# Каждое здание — комната далеко за пределами площади. Вход — через дверь здания,
# внутри работает «хозяин»: кузнец, жрица, инженер, трактирщик. Разговор с ним
# открывает панель здания. В таверне гуляют открытые герои (подойти — взять в бой),
# у стойки сидят наёмники (нанять), трактирщик даёт контракты.

const INTERIORS := {
	"hall": {"o": Vector3(130, 0, 0), "w": 17.0, "d": 11.0, "floor": Color(0.38, 0.26, 0.17), "wall": Color(0.3, 0.2, 0.15), "lamp": Color(1.0, 0.68, 0.38),
		"npc": ["barkeep", "Бруно"], "npc_pos": Vector3(-3.0, 0, -4.2)},
	"forge": {"o": Vector3(130, 0, 40), "w": 13.0, "d": 9.5, "floor": Color(0.24, 0.22, 0.25), "wall": Color(0.26, 0.2, 0.18), "lamp": Color(1.0, 0.5, 0.2),
		"npc": ["blacksmith", "Горн"], "npc_pos": Vector3(0.6, 0, -2.4)},
	"shrine": {"o": Vector3(170, 0, 0), "w": 12.0, "d": 10.0, "floor": Color(0.22, 0.2, 0.3), "wall": Color(0.2, 0.17, 0.28), "lamp": Color(1.0, 0.4, 0.85),
		"npc": ["priestess", "Селена"], "npc_pos": Vector3(0, 0, -2.6)},
	"lab": {"o": Vector3(170, 0, 40), "w": 13.0, "d": 9.5, "floor": Color(0.18, 0.22, 0.27), "wall": Color(0.16, 0.2, 0.26), "lamp": Color(0.4, 0.85, 1.0),
		"npc": ["engineer", "Дэкс"], "npc_pos": Vector3(1.5, 0, -2.6)},
}
const HOST_PHRASES := {
	"barkeep": ["Кружку неонового эля?", "Есть работёнка — для смелых.", "Герои отдыхают — не буди.", "Контракты платят вдвое!", "За стойкой — наёмники. Платишь — идут с тобой."],
	"blacksmith": ["Тук! Тук!", "Клинок без руны — просто железо.", "Принёс лом? Давай сюда.", "Горн любит чипы.", "Каждому стволу — своё дерево."],
	"priestess": ["Свет помнит каждого героя.", "Сядь, помолчи с нами.", "Алтарь слышит твои шаги.", "Сила героя — в его истории."],
	"engineer": ["Модуль сгорел? Бывает.", "Не трогай синюю колбу!", "Ядра — это энергия. Береги.", "Калибрую... калибрую...", "Пайка — это искусство."],
}
const HOST_TITLES := {"barkeep": "трактирщик", "blacksmith": "кузнец", "priestess": "жрица", "engineer": "инженер"}
const HOST_TASK := {"hall": "контракты и стройка", "forge": "прокачка оружия", "shrine": "прокачка героев", "lab": "прокачка модулей"}

var _inside := ""
var _rooms := {}           # id -> {"root", "npc"}
var _tav_heroes: Array = []
var _fade_rect: ColorRect


func _room(id: String) -> Dictionary:
	if not _rooms.has(id):
		_build_room(id)
	return _rooms[id]


func _build_room(id: String) -> void:
	var info: Dictionary = INTERIORS[id]
	var o: Vector3 = info["o"]
	var w: float = info["w"]
	var d: float = info["d"]
	var root := Node3D.new()
	root.position = o
	_world.add_child(root)
	var col: Color = Meta.BUILDINGS[id]["color"]
	var wood := _mat(Color(0.42, 0.3, 0.2), 0.9, 0.0, "wood", 1.4)
	var dark := _mat(Color(0.18, 0.13, 0.1), 0.9, 0.0, "wood", 1.0)
	var wallm := _mat(info["wall"], 0.9, 0.05, "brick", 1.3)
	# Пол, стены, балки
	_add(root, _box(w, 0.2, d), _mat(info["floor"], 0.85, 0.05, "wood" if id in ["hall", "shrine"] else "tile", 1.2), Vector3(0, -0.1, 0))
	_add(root, _box(w + 0.8, 4.6, 0.4), wallm, Vector3(0, 2.3, -d / 2.0 - 0.2))
	for s in [-1.0, 1.0]:
		_add(root, _box(0.4, 4.6, d + 0.4), wallm, Vector3(s * (w / 2.0 + 0.2), 2.3, 0))
		# Низкая передняя стенка по бокам от двери — камера смотрит поверх
		var seg := w / 2.0 - 1.3
		_add(root, _box(seg, 0.9, 0.3), wallm, Vector3(s * (1.3 + seg / 2.0), 0.45, d / 2.0 + 0.15))
		# Невысокие столбы двери с фонарями — не закрывают комнату от камеры
		_add(root, _box(0.26, 1.3, 0.34), dark, Vector3(s * 1.3, 0.65, d / 2.0 + 0.15))
		_add(root, _sphere(0.12), _emat(Color(0.5, 1.0, 0.6), 2.5), Vector3(s * 1.3, 1.42, d / 2.0 + 0.15))
	_label3d(root, "ВЫХОД", Vector3(0, 1.1, d / 2.0 + 0.3), Color(0.6, 1.0, 0.7), 22)
	_add(root, _box(2.0, 0.03, 0.9), _emat(Color(0.4, 0.9, 0.5), 0.35, 0.22), Vector3(0, 0.02, d / 2.0 - 0.45))
	for x in range(-int(w / 2.0) + 1, int(w / 2.0), 3):
		_add(root, _box(0.25, 4.4, 0.25), dark, Vector3(x, 2.2, -d / 2.0 + 0.05))
	_add(root, _box(w, 0.3, 0.3), dark, Vector3(0, 4.3, -d / 2.0 + 0.1))
	# Неоновая полоса на задней стене — цвет здания
	_add(root, _box(w * 0.8, 0.06, 0.05), _emat(col, 1.6), Vector3(0, 3.7, -d / 2.0 + 0.02))
	_label3d(root, Meta.BUILDINGS[id]["name"].to_upper(), Vector3(0, 4.9, -d / 2.0), col.lightened(0.3), 40)
	# Свет
	var lamp: Color = info["lamp"]
	_light(root, Vector3(0, 3.6, 0), lamp, 1.6, w * 0.9)
	for s in [-1.0, 1.0]:
		var ln := _light(root, Vector3(s * (w / 2.0 - 0.6), 2.6, -d / 2.0 + 0.8), lamp, 1.1, 6.0)
		ln.shadow_enabled = false
		_add(root, _sphere(0.14), _emat(lamp, 3.0), Vector3(s * (w / 2.0 - 0.3), 2.6, -d / 2.0 + 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"hall":
			_furnish_tavern(root, o, w, d, wood, dark, rng)
		"forge":
			_furnish_forge(root, o, w, d, wood, dark)
		"shrine":
			_furnish_shrine(root, o, w, d, dark)
		"lab":
			_furnish_lab(root, o, w, d, dark)
	# Хозяин
	var role: String = info["npc"][0]
	var npc := _make_npc(role, o + info["npc_pos"], 900 + absi(hash(role)) % 50, info["npc"][1])
	npc["home"] = o + info["npc_pos"]
	_rooms[id] = {"root": root, "npc": npc}


## Прямоугольное препятствие в комнате (координаты — относительно начала комнаты).
func _rob(o: Vector3, p: Vector3, hx: float, hz: float) -> void:
	_obstacles.append([o + p, Vector2(hx, hz), 0.0])


func _furnish_tavern(root: Node3D, o: Vector3, w: float, d: float, wood: Material, dark: Material, rng: RandomNumberGenerator) -> void:
	# Стойка с бочками и полками бутылок
	_add(root, _box(6.4, 1.1, 0.8), wood, Vector3(-3.0, 0.55, -2.9))
	_add(root, _box(6.6, 0.1, 1.0), dark, Vector3(-3.0, 1.12, -2.9))
	_rob(o, Vector3(-3.0, 0, -2.9), 3.3, 0.5)
	for i in 3:
		_add(root, _box(5.6, 0.08, 0.35), dark, Vector3(-3.0, 1.7 + i * 0.6, -d / 2.0 + 0.25))
		for j in 9:
			var bc: Color = [Color(0.3, 0.9, 0.5), Color(0.9, 0.4, 0.2), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.3)][(i + j) % 4]
			_add(root, _cyl(0.05, 0.07, 0.32, 6), _emat(bc, 0.9), Vector3(-5.5 + j * 0.62, 1.92 + i * 0.6, -d / 2.0 + 0.25))
	for i in 3:
		_add(root, _cyl(0.42, 0.42, 0.9, 10), wood, Vector3(-7.2, 0.45, -1.4 + i * 0.95))
		_add(root, _torus(0.4, 0.44), dark, Vector3(-7.2, 0.7, -1.4 + i * 0.95))
	_rob(o, Vector3(-7.2, 0, -0.45), 0.5, 1.5)
	# Камин справа
	_add(root, _box(2.4, 2.2, 0.9), _mat(Color(0.3, 0.28, 0.3), 0.9, 0.1, "brick", 1.4), Vector3(5.2, 1.1, -d / 2.0 + 0.45))
	_add(root, _box(1.2, 0.9, 0.3), _emat(Color(1.0, 0.45, 0.12), 2.4), Vector3(5.2, 0.55, -d / 2.0 + 0.85))
	var fl := _light(root, Vector3(5.2, 1.0, -d / 2.0 + 1.6), Color(1.0, 0.5, 0.2), 1.8, 6.0)
	_fire_lights.append(fl)
	_particles(root, Vector3(5.2, 0.8, -d / 2.0 + 0.9), Color(1.0, 0.55, 0.15), 14, Vector3(0.4, 0.1, 0.1), Vector3(0, 1.2, 0), 0.9, 0.07)
	_rob(o, Vector3(5.2, 0, -d / 2.0 + 0.45), 1.25, 0.5)
	# Столы со стульями: справа — стол наёмников
	for t in [Vector3(-3.5, 0, 1.0), Vector3(0.8, 0, 2.2), Vector3(4.6, 0, 0.6)]:
		_add(root, _cyl(0.75, 0.75, 0.08, 12), wood, t + Vector3(0, 0.78, 0))
		_add(root, _cyl(0.1, 0.18, 0.75, 6), dark, t + Vector3(0, 0.38, 0))
		_add(root, _cyl(0.07, 0.07, 0.12, 6), _emat(Color(1.0, 0.8, 0.4), 1.6), t + Vector3(0.2, 0.88, 0.1))
		for a in 4:
			var s: Vector3 = t + Vector3(cos(a * PI / 2.0 + 0.4), 0, sin(a * PI / 2.0 + 0.4)) * 1.15
			_add(root, _cyl(0.24, 0.24, 0.45, 8), dark, s + Vector3(0, 0.22, 0))
		_obstacles.append([o + t, 0.85])
	# Ковёр, люстра
	_add(root, _box(5.0, 0.02, 3.0), _mat(Color(0.45, 0.12, 0.16), 1.0, 0.0, "", 1.0), Vector3(0.4, 0.01, 1.4))
	_add(root, _torus(0.8, 0.95), dark, Vector3(0.5, 3.4, 0.8))
	for a in 6:
		_add(root, _sphere(0.08), _emat(Color(1.0, 0.75, 0.4), 3.0), Vector3(0.5 + cos(a * TAU / 6.0) * 0.88, 3.5, 0.8 + sin(a * TAU / 6.0) * 0.88))
	_label3d(root, "ДОСКА КОНТРАКТОВ — У ТРАКТИРЩИКА", Vector3(-3.0, 3.9, -d / 2.0 + 0.3), GOLD, 22)
	_label3d(root, "НАЁМНИКИ", Vector3(4.6, 2.6, 0.6), Color(1.0, 0.6, 0.5), 24)


func _furnish_forge(root: Node3D, o: Vector3, w: float, d: float, wood: Material, dark: Material) -> void:
	var iron := _mat(Color(0.25, 0.25, 0.3), 0.4, 0.8)
	# Горн с огнём
	_add(root, _box(2.6, 1.6, 1.6), _mat(Color(0.32, 0.27, 0.27), 0.9, 0.1, "brick", 1.4), Vector3(-3.6, 0.8, -d / 2.0 + 1.0))
	_add(root, _box(1.6, 0.5, 1.0), _emat(Color(1.0, 0.4, 0.1), 3.0), Vector3(-3.6, 1.45, -d / 2.0 + 1.1))
	_add(root, _cyl(0.5, 0.8, 2.8, 8), _mat(Color(0.3, 0.26, 0.26), 0.9, 0.1, "brick", 1.4), Vector3(-3.6, 3.0, -d / 2.0 + 0.8))
	var fl := _light(root, Vector3(-3.6, 2.0, -d / 2.0 + 2.2), Color(1.0, 0.45, 0.15), 2.4, 7.0)
	_fire_lights.append(fl)
	_particles(root, Vector3(-3.6, 1.7, -d / 2.0 + 1.1), Color(1.0, 0.6, 0.2), 18, Vector3(0.6, 0.1, 0.3), Vector3(0, 1.5, 0), 1.0, 0.06)
	_rob(o, Vector3(-3.6, 0, -d / 2.0 + 1.0), 1.35, 0.85)
	# Наковальня
	_add(root, _box(0.5, 0.6, 0.4), iron, Vector3(-0.6, 0.3, -2.4))
	_add(root, _box(1.1, 0.25, 0.45), iron, Vector3(-0.6, 0.72, -2.4))
	_obstacles.append([o + Vector3(-0.6, 0, -2.4), 0.6])
	# Стойки с оружием по правой стене
	for i in 4:
		var x := 2.2 + i * 1.0
		_add(root, _box(0.08, 1.8, 0.08), wood, Vector3(x, 0.9, -d / 2.0 + 0.4))
		_add(root, _box(0.12, 1.3, 0.04), iron, Vector3(x + 0.25, 1.3, -d / 2.0 + 0.45), Vector3(0, 0, 12))
		_add(root, _box(0.05, 0.05, 0.05), _emat(Meta.BUILDINGS["forge"]["color"], 2.0), Vector3(x + 0.25, 1.9, -d / 2.0 + 0.48))
	_add(root, _box(4.4, 0.15, 0.5), wood, Vector3(3.7, 1.8, -d / 2.0 + 0.4))
	# Бочка с водой, ящики лома
	_add(root, _cyl(0.5, 0.5, 0.8, 10), wood, Vector3(4.8, 0.4, 1.8))
	_add(root, _cyl(0.45, 0.45, 0.02, 10), _emat(Color(0.3, 0.6, 1.0), 0.6), Vector3(4.8, 0.81, 1.8))
	_obstacles.append([o + Vector3(4.8, 0, 1.8), 0.55])
	for i in 3:
		_add(root, _box(0.8, 0.7, 0.8), wood, Vector3(-5.2 + (i % 2) * 0.3, 0.35 + (i / 2) * 0.7, 1.4 + (i % 2) * 0.85))
	_rob(o, Vector3(-5.1, 0, 1.8), 0.6, 0.9)


func _furnish_shrine(root: Node3D, o: Vector3, w: float, d: float, dark: Material) -> void:
	var stone := _mat(Color(0.35, 0.32, 0.42), 0.8, 0.1, "brick", 1.0)
	var col: Color = Meta.BUILDINGS["shrine"]["color"]
	# Алтарь со светящейся сферой
	_add(root, _box(3.2, 0.3, 1.6), stone, Vector3(0, 0.15, -d / 2.0 + 1.4))
	_add(root, _box(1.8, 0.9, 1.0), stone, Vector3(0, 0.75, -d / 2.0 + 1.3))
	var orb := _add(root, _sphere(0.35), _emat(col, 2.5), Vector3(0, 1.75, -d / 2.0 + 1.3))
	_bobbers.append([orb, 1.75, 0.12])
	_add(root, _torus(0.5, 0.58), _emat(col, 1.8), Vector3(0, 1.75, -d / 2.0 + 1.3), Vector3(90, 0, 0))
	_light(root, Vector3(0, 2.0, -d / 2.0 + 2.0), col, 2.0, 7.0)
	_rob(o, Vector3(0, 0, -d / 2.0 + 1.35), 1.6, 0.85)
	# Статуи героев по бокам, свечи, скамьи
	for s in [-1.0, 1.0]:
		_add(root, _box(0.8, 0.5, 0.8), stone, Vector3(s * 4.2, 0.25, -d / 2.0 + 1.0))
		_add(root, _cyl(0.22, 0.32, 1.6, 8), stone, Vector3(s * 4.2, 1.3, -d / 2.0 + 1.0))
		_add(root, _sphere(0.26), stone, Vector3(s * 4.2, 2.3, -d / 2.0 + 1.0))
		_obstacles.append([o + Vector3(s * 4.2, 0, -d / 2.0 + 1.0), 0.55])
		for i in 2:
			_add(root, _box(3.0, 0.4, 0.6), dark, Vector3(s * 2.6, 0.2, 0.6 + i * 1.8))
			_rob(o, Vector3(s * 2.6, 0, 0.6 + i * 1.8), 1.5, 0.3)
		for i in 5:
			var cp := Vector3(s * (1.2 + i * 0.35), 0.0, -d / 2.0 + 2.4 + (i % 2) * 0.2)
			_add(root, _cyl(0.04, 0.04, 0.25 + (i % 3) * 0.1, 6), _mat(Color(0.95, 0.9, 0.8), 0.9, 0.0, ""), cp + Vector3(0, 0.14, 0))
			var fm := _add(root, _sphere(0.04), _emat(Color(1.0, 0.75, 0.4), 4.0), cp + Vector3(0, 0.33 + (i % 3) * 0.1, 0))
			_flicker.append([fm.material_override, 4.0, randf() * 10.0])
	_particles(root, Vector3(0, 1.8, -d / 2.0 + 1.3), col, 10, Vector3(1.4, 0.4, 0.4), Vector3(0, 0.5, 0), 2.0, 0.05)


func _furnish_lab(root: Node3D, o: Vector3, w: float, d: float, dark: Material) -> void:
	var metal := _mat(Color(0.2, 0.22, 0.28), 0.4, 0.7)
	var col: Color = Meta.BUILDINGS["lab"]["color"]
	# Консоли вдоль задней стены
	for i in 3:
		var x := -4.0 + i * 2.2
		_add(root, _box(1.8, 1.0, 0.8), metal, Vector3(x, 0.5, -d / 2.0 + 0.6))
		var scr := _add(root, _box(1.4, 0.8, 0.06), _emat([col, Color(0.4, 1.0, 0.6), MAGENTA][i], 1.4), Vector3(x, 1.6, -d / 2.0 + 0.3), Vector3(-10, 0, 0))
		_flicker.append([scr.material_override, 1.4, randf() * 10.0])
	_rob(o, Vector3(-1.8, 0, -d / 2.0 + 0.6), 3.2, 0.5)
	# Колбы с жидкостью
	for i in 3:
		var p := Vector3(3.6 + i * 1.0, 0, -d / 2.0 + 0.9)
		_add(root, _cyl(0.32, 0.32, 0.2, 10), metal, p + Vector3(0, 0.1, 0))
		_add(root, _cyl(0.28, 0.28, 1.7, 10), _emat([Color(0.3, 1.0, 0.5), col, Color(1.0, 0.5, 0.9)][i], 0.9, 0.45), p + Vector3(0, 1.05, 0))
		_add(root, _cyl(0.32, 0.32, 0.2, 10), metal, p + Vector3(0, 2.0, 0))
		_particles(root, p + Vector3(0, 0.4, 0), Color(0.8, 1.0, 1.0), 5, Vector3(0.15, 0.1, 0.15), Vector3(0, 1.0, 0), 1.6, 0.04)
	_rob(o, Vector3(4.6, 0, -d / 2.0 + 0.9), 1.6, 0.45)
	# Верстак с голограммой модуля
	_add(root, _box(2.4, 0.9, 1.1), metal, Vector3(-2.2, 0.45, 1.4))
	var holo := _add(root, _box(0.5, 0.5, 0.5), _emat(col, 2.0, 0.5), Vector3(-2.2, 1.55, 1.4))
	_spinners.append([holo, Vector3.UP, 1.2])
	_add(root, _cyl(0.3, 0.3, 0.04, 12), _emat(col, 2.0), Vector3(-2.2, 0.93, 1.4))
	_light(root, Vector3(-2.2, 1.8, 1.8), col, 1.2, 4.0)
	_rob(o, Vector3(-2.2, 0, 1.4), 1.25, 0.6)
	# Кабели по полу
	for i in 4:
		_add(root, _cyl(0.04, 0.04, 3.0, 6), dark, Vector3(2.0 + i * 0.3, 0.04, 0.6), Vector3(90, 20 * i, 0))


# ---- Герои и наёмники в таверне ----

const TAV_SEATS := [Vector3(5.66, 0, 1.05), Vector3(4.15, 0, 1.66), Vector3(3.54, 0, 0.15), Vector3(5.05, 0, -0.46),
	Vector3(1.86, 0, 2.66), Vector3(0.35, 0, 3.27), Vector3(-0.26, 0, 1.76), Vector3(1.25, 0, 1.15), Vector3(6.6, 0, 2.6), Vector3(6.6, 0, -1.6)]


func _rebuild_tavern_heroes(prev_pos := Vector3.INF) -> void:
	for h in _tav_heroes:
		(h["node"] as Node3D).queue_free()
	_tav_heroes.clear()
	var o: Vector3 = INTERIORS["hall"]["o"]
	var seat := 0
	var walk_i := 0
	for hid in Meta.HERO_ORDER:
		if not Data.CHARACTERS.has(hid) or hid == Data.selected_character or not Meta.hero_rescued(hid):
			continue   # не спасённых героев в таверне нет
		var c: Dictionary = Data.CHARACTERS[hid]
		var owned := Meta.hero_unlocked(hid)
		var pos: Vector3
		if owned:
			pos = o + Vector3(-4.5 + walk_i * 1.6, 0, 3.2 - (walk_i % 2) * 1.0)
			walk_i += 1
		else:
			pos = o + TAV_SEATS[seat % TAV_SEATS.size()]
			seat += 1
		var node := Node3D.new()
		node.position = pos
		_world.add_child(node)
		var fr := Pixel.frames(c["sprite"])
		var pair := _sprite_pair(node, fr)
		var lbl_text: String = c["name"] if owned else "Наёмник %s" % c["name"]
		var lbl := _label3d(node, lbl_text, Vector3(0, 2.2, 0), (c["color"] as Color).lightened(0.25) if owned else Color(1.0, 0.75, 0.6), 26)
		lbl.visible = false
		if not owned:
			# Наёмник — приглушён, ждёт найма
			(pair[0] as Sprite3D).modulate = Color(0.62, 0.58, 0.68)
			(pair[1] as Sprite3D).modulate = Pixel.hdr(Color.WHITE, 0.6)
		_tav_heroes.append({"node": node, "base": pair[0], "emit": pair[1], "frames": fr, "hid": hid, "owned": owned,
			"target": pos, "wait": randf_range(0.5, 3.0), "t": randf() * 5.0, "label": lbl})
	if prev_pos != Vector3.INF:
		for h in _tav_heroes:
			if h["hid"] == _tav_prev:
				(h["node"] as Node3D).position = prev_pos
				h["target"] = prev_pos


var _tav_prev := ""


func _update_tavern(delta: float) -> void:
	var info: Dictionary = INTERIORS["hall"]
	var o: Vector3 = info["o"]
	var hw: float = info["w"] / 2.0 - 0.8
	var hd: float = info["d"] / 2.0 - 0.8
	for h in _tav_heroes:
		var node: Node3D = h["node"]
		h["t"] = float(h["t"]) + delta
		var moving := false
		if h["owned"]:
			var to: Vector3 = h["target"] - node.position
			to.y = 0
			if to.length() < 0.25:
				h["wait"] = float(h["wait"]) - delta
				if h["wait"] <= 0.0:
					h["wait"] = randf_range(2.0, 6.0)
					h["target"] = o + Vector3(randf_range(-hw, hw * 0.6), 0, randf_range(-0.8, hd))
			else:
				moving = true
				var np := node.position + to.normalized() * minf(to.length(), 1.5 * delta)
				node.position = _collide(np, 0.35)
				(h["base"] as Sprite3D).flip_h = to.x < 0.0
				(h["emit"] as Sprite3D).flip_h = to.x < 0.0
		var fr: Dictionary = h["frames"]
		var f := Pixel.hero_frame(fr, "run" if moving else "idle", float(h["t"]))
		(h["base"] as Sprite3D).texture = fr["base"][f]
		(h["emit"] as Sprite3D).texture = fr["emit"][f]
		(h["label"] as Label3D).visible = node.position.distance_to(_avatar.position) < 3.2


# ---- Вход / выход ----

func _fade() -> void:
	if not _fade_rect:
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0.02, 0.01, 0.04)
		_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(_fade_rect)
		_hud.move_child(_fade_rect, 0)
	_fade_rect.modulate.a = 1.0
	create_tween().tween_property(_fade_rect, "modulate:a", 0.0, 0.45)


func _enter_building(id: String) -> void:
	var room := _room(id)
	var info: Dictionary = INTERIORS[id]
	_inside = id
	if id == "hall":
		_rebuild_tavern_heroes()
	_avatar.position = info["o"] + Vector3(0, 0, float(info["d"]) / 2.0 - 1.3)
	_facing_left = false
	_cam_target = _avatar.position
	_fade()
	Sound.play("click")
	_toast_text(Meta.BUILDINGS[id]["name"])
	var npc: Dictionary = room["npc"]
	var bubble: Label3D = npc["bubble"]
	var ph: Array = HOST_PHRASES[npc["role"]]
	bubble.text = ph[randi() % ph.size()]
	bubble.visible = true
	npc["bubble_t"] = 3.5


func _exit_building() -> void:
	var id := _inside
	_inside = ""
	for h in _tav_heroes:
		(h["node"] as Node3D).queue_free()
	_tav_heroes.clear()
	var bp: Vector3 = Meta.BUILDINGS[id]["pos"]
	_avatar.position = _collide(bp + Vector3(0, 0, 2.9), 0.5)
	_cam_target = _avatar.position
	_fade()
	Sound.play("click")


## Взаимодействие внутри здания: дверь, хозяин, герои / наёмники.
func _interior_interaction() -> String:
	var info: Dictionary = INTERIORS[_inside]
	var o: Vector3 = info["o"]
	var p := _avatar.position
	var best := ""
	var best_d := 999.0
	var door := o + Vector3(0, 0, float(info["d"]) / 2.0 - 0.6)
	var dd := Vector2(p.x - door.x, p.z - door.z).length()
	if dd < 1.6:
		best = "exit"
		best_d = dd
	var npc: Dictionary = _rooms[_inside]["npc"]
	var nd := (npc["node"] as Node3D).position.distance_to(p)
	if nd < 2.6 and nd < best_d:
		best = "host"
		best_d = nd
	for h in _tav_heroes:
		var hd := (h["node"] as Node3D).position.distance_to(p)
		if hd < 1.7 and hd < best_d:
			best = ("take:" if h["owned"] else "hire:") + str(h["hid"])
			best_d = hd
	if best == "exit":
		_prompt.text = _pk() + "Выйти на площадь"
	elif best == "host":
		_prompt.text = _pk() + "%s, %s — %s" % [INTERIORS[_inside]["npc"][1], HOST_TITLES[npc["role"]], HOST_TASK[_inside]]
	elif best.begins_with("take:"):
		var c: Dictionary = Data.CHARACTERS[best.substr(5)]
		_prompt.text = _pk() + "Взять в бой: %s — %s" % [c["name"], c["title"]]
	elif best.begins_with("hire:"):
		var c2: Dictionary = Data.CHARACTERS[best.substr(5)]
		_prompt.text = _pk() + "Наёмник %s — условия найма" % c2["name"]
	return best


func _interior_act(what: String) -> void:
	if what == "exit":
		_exit_building()
	elif what == "host":
		var npc: Dictionary = _rooms[_inside]["npc"]
		var bubble: Label3D = npc["bubble"]
		var ph: Array = HOST_PHRASES[npc["role"]]
		bubble.text = ph[randi() % ph.size()]
		bubble.visible = true
		npc["bubble_t"] = 3.0
		_open_panel(_inside)
	elif what.begins_with("take:"):
		_take_hero(what.substr(5))
	elif what.begins_with("hire:"):
		_open_panel(what)


func _take_hero(hid: String) -> void:
	if not Meta.hero_unlocked(hid):
		return
	var pos := _avatar.position
	var h_node_pos := pos
	for h in _tav_heroes:
		if h["hid"] == hid:
			h_node_pos = (h["node"] as Node3D).position
	_tav_prev = Data.selected_character
	Data.selected_character = hid
	Meta.save()
	_set_avatar_sprites()
	_update_hero_label()
	_avatar.position = h_node_pos
	_cam_target = _avatar.position
	_rebuild_tavern_heroes(pos)
	var c: Dictionary = Data.CHARACTERS[hid]
	_particles(_world, h_node_pos + Vector3(0, 1.0, 0), c["color"], 30, Vector3(0.5, 0.8, 0.5), Vector3(0, 2, 0), 1.0, 0.08, true, 2.0)
	Sound.play("levelup", -6.0)
	_toast_text("В бой идёт: %s — %s" % [c["name"], c["title"]])


## Панель найма: карточка героя, условия и лор.
func _fill_hire(hid: String) -> void:
	var hc: Dictionary = Data.CHARACTERS[hid]
	_panel_box.add_child(_centered(_label("НАЁМНИК", 30, Color.WHITE, Color(hc["color"], 0.8))))
	var lore := _label(Data.HERO_LORE.get(hid, ""), 15, Color(0.85, 0.82, 0.95))
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.custom_minimum_size = Vector2(minf(440 if _portrait() else 640, _avail()), 0)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(_centered(lore))
	_panel_box.add_child(_centered(_hero_card(hid)))
	_add_close()


## Контракты трактирщика.
func _fill_contracts() -> void:
	_panel_box.add_child(_centered(_label("КОНТРАКТЫ", 24, GOLD)))
	var slots := Quests.contract_slots()
	var info := _label("Трудные заказы для одной вылазки — цель больше, награда почти вдвое щедрее. Действуют, пока не выполните. Мест: %d / %d%s" % [Meta.contracts.size(), slots, "" if slots > 1 else " (2 — с 3-го уровня таверны)"], 14, Color(0.8, 0.8, 0.95))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(minf(440 if _portrait() else 760, _avail()), 0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(_centered(info))
	var grid := GridContainer.new()
	grid.columns = mini(3, _cols(450 if _portrait() else 262))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for i in Meta.contracts.size():
		grid.add_child(_contract_card(Meta.contracts[i], i, true))
	var o := Quests.offers()
	for i in o.size():
		grid.add_child(_contract_card(o[i], i, false))
	_panel_box.add_child(_centered(grid))


func _contract_card(q: Dictionary, i: int, taken: bool) -> Control:
	var col := Color(0.5, 1.0, 0.6) if taken else GOLD
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sbox(col.darkened(0.15), PANEL_BG, 2, 6 if taken else 2))
	card.custom_minimum_size = Vector2(minf(440 if _portrait() else 250, _avail()), 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(_label(("✓ ВЗЯТ  " if taken else "") + Quests.title(q), 17, col))
	var d := _label(Quests.desc(q), 15, Color(0.92, 0.92, 1.0))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(minf(220, _avail()), 0)
	v.add_child(d)
	v.add_child(_label("Сложность: " + "★".repeat(int(q.get("tier", 0)) + 1), 13, Color(0.75, 0.75, 0.9)))
	v.add_child(_label("Награда: " + Quests.reward_text(Quests.reward(q)), 14, Color(0.6, 1.0, 0.7)))
	var b: Button
	if taken:
		b = _button("Отказаться", Color(1.0, 0.5, 0.5))
		b.pressed.connect(func():
			Quests.drop_contract(i)
			Sound.play("click")
			_fill_panel())
	else:
		var can := Meta.contracts.size() < Quests.contract_slots()
		b = _button("ВЗЯТЬ" if can else "Нет мест", GOLD, can)
		b.pressed.connect(func():
			if Quests.take_contract(i):
				Sound.play("levelup", -6.0)
				_toast_text("Контракт взят: " + Quests.title(q))
			_fill_panel())
	b.custom_minimum_size = Vector2(minf(200, _avail()), 38)
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	return card


# ================= Сюжет и жители =================
# Командир Ворон ведёт главную линию; у каждого жителя есть имя, история и просьба.
# Жители не бродят «болванчиками»: работают на своих местах, сходятся поболтать,
# благодарят за выполненные просьбы. Над теми, у кого есть дело к охотнику, — «!».

const Props3D := preload("res://scripts/props3d.gd")
const Story := preload("res://scripts/story.gd")
const COMMANDER_POS := Vector3(-5.6, 0, 0.4)
var _role_n := {}
var _chat_t := 6.0


## Анкета жителя по роли (по порядку появления).
func _profile_for(role: String) -> Dictionary:
	var list: Array = Story.VILLAGERS.get(role, [])
	if list.is_empty():
		return {}
	var i := int(_role_n.get(role, 0))
	_role_n[role] = i + 1
	return list[i % list.size()]


func _apply_profile(v: Dictionary, prof: Dictionary) -> void:
	if prof.is_empty():
		return
	v["profile"] = prof
	(v["name"] as Label3D).text = "%s, %s" % [prof["name"], prof["title"]]
	var mark := _label3d(v["node"], "!", Vector3(0, 2.35, 0), GOLD, 56)
	mark.visible = false
	v["mark"] = mark


## Предложение жителя: его просьба, если он сейчас ничего не ждёт.
func _npc_offer(v: Dictionary) -> Dictionary:
	var prof: Dictionary = v.get("profile", {})
	if prof.is_empty() or not prof.has("quest"):
		return {}
	var nm: String = prof["name"]
	if Meta.story_step < int(Story.NPC_UNLOCK.get(nm, 0)):
		return {}   # пока не доверяет — просьбы откроются по ходу сюжета
	for q in Meta.npc_quests:
		if str(q.get("giver", "")) == nm:
			return {}
	if Meta.total_runs < int(Meta.npc_cd.get(nm, 0)):
		return {}
	var k: String = prof["quest"]
	var t := Quests.tier()
	return {"k": k, "g": int(Quests.POOL[k]["g"][t]), "tier": t, "giver": nm}


func _npc_active(v: Dictionary) -> Dictionary:
	var nm: String = v.get("profile", {}).get("name", "")
	for q in Meta.npc_quests:
		if str(q.get("giver", "")) == nm:
			return q
	return {}


## Метки над головами: «!» — есть просьба или сюжет, «?» — пора доложить.
func _update_marks() -> void:
	# Подписи: только у ближайшего жителя — чтобы имена не наезжали друг на друга
	var nearest: Dictionary = {}
	var nd := 3.0
	for v in _villagers:
		var d := (v["node"] as Node3D).position.distance_to(_avatar.position)
		(v["name"] as Label3D).visible = false
		if d < nd:
			nd = d
			nearest = v
	if not nearest.is_empty():
		(nearest["name"] as Label3D).visible = true
	for v in _villagers:
		if not v.has("mark"):
			continue
		var mk: Label3D = v["mark"]
		var txt := ""
		if v.get("profile", {}).get("name", "") == "Ворон":
			txt = "?" if Meta.story_ready() else ("!" if not Meta.story_cur().is_empty() and not Meta.story_taken else "")
		elif not _npc_offer(v).is_empty() and Meta.npc_quests.size() < 3:
			txt = "!"
		mk.text = txt
		mk.visible = txt != "" and not v.has("chat")
		mk.position.y = 2.35 + sin(float(v["t"]) * 3.0) * 0.06


## Ближайший житель с историей, с которым можно поговорить.
func _talk_target() -> int:
	var best := -1
	var bd := 1.5
	for i in _villagers.size():
		var v: Dictionary = _villagers[i]
		if not v.has("profile"):
			continue
		var d := (v["node"] as Node3D).position.distance_to(_avatar.position)
		if d < bd:
			bd = d
			best = i
	return best


## Болтовня: житель подходит к соседу, и они обмениваются репликами.
func _update_chats(delta: float) -> void:
	_chat_t -= delta
	if _chat_t <= 0.0:
		_chat_t = randf_range(9.0, 16.0)
		var walkers: Array = []
		var free: Array = []
		for v in _villagers:
			if v.has("profile") and not v.has("chat") and v["role"] in ["walker", "elder", "trainee", "gardener", "merchant", "musician"]:
				free.append(v)
				if v["role"] == "walker":
					walkers.append(v)
		if not walkers.is_empty() and free.size() >= 2:
			var a: Dictionary = walkers[randi() % walkers.size()]
			var b: Dictionary = a
			var bd := 999.0
			for o in free:
				if o != a:
					var d := (o["node"] as Node3D).position.distance_to((a["node"] as Node3D).position)
					if d < bd:
						bd = d
						b = o
			if b != a and bd < 14.0:
				var pair: Array = Story.CHATS[randi() % Story.CHATS.size()]
				a["chat"] = {"with": b, "line": pair[0], "lead": true, "t": 0.0}
				b["chat"] = {"with": a, "line": pair[1], "lead": false, "t": 0.0}
	for v in _villagers:
		if not v.has("chat"):
			continue
		var c: Dictionary = v["chat"]
		var o: Dictionary = c["with"]
		var op: Vector3 = (o["node"] as Node3D).position
		var me: Vector3 = (v["node"] as Node3D).position
		if me.distance_to(op) > 1.5 and float(c["t"]) <= 0.0:
			v["target"] = op + (me - op).normalized() * 1.1
			v["wait"] = 1.0
			c["far"] = float(c.get("far", 0.0)) + delta
			if float(c["far"]) > 14.0 or not o.has("chat"):
				v.erase("chat")
			continue
		v["target"] = me
		v["wait"] = 1.0
		(v["base"] as Sprite3D).flip_h = op.x < me.x
		(v["emit"] as Sprite3D).flip_h = op.x < me.x
		c["t"] = float(c["t"]) + delta
		var start := 0.4 if c["lead"] else 3.0
		var bubble: Label3D = v["bubble"]
		if float(c["t"]) > start and float(c["t"]) < start + 2.6:
			bubble.text = c["line"]
			bubble.visible = true
			v["bubble_t"] = 3.0
		elif float(c["t"]) >= 6.0:
			bubble.visible = false
			v.erase("chat")
			v["wait"] = randf_range(2.0, 5.0)


## Благодарность за выполненную просьбу — когда охотник проходит рядом.
func _update_thanks() -> void:
	if Meta.npc_thanks.is_empty():
		return
	for v in _villagers:
		var nm: String = v.get("profile", {}).get("name", "")
		if nm != "" and nm in Meta.npc_thanks and (v["node"] as Node3D).position.distance_to(_avatar.position) < 3.0:
			Meta.npc_thanks.erase(nm)
			var bubble: Label3D = v["bubble"]
			bubble.text = ["Спасибо, охотник! Я не забуду.", "Ты сдержал слово!", "Вот это да! Спасибо!"][randi() % 3]
			bubble.visible = true
			v["bubble_t"] = 4.0
			_particles(_world, (v["node"] as Node3D).position + Vector3(0, 1.6, 0), GOLD, 16, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.5, 0), 0.8, 0.06, true, 1.5)
			Meta.save()
			return


# ---- Панели: разговор, сюжет, пролог ----

func _story_w() -> float:
	return minf(640.0, _avail())


func _fill_talk(i: int) -> void:
	if i < 0 or i >= _villagers.size():
		_add_close()
		return
	var v: Dictionary = _villagers[i]
	var prof: Dictionary = v["profile"]
	if prof["name"] == "Ворон":
		_fill_story()
		return
	_panel_box.add_child(_centered(_label(str(prof["name"]).to_upper(), 30, Color.WHITE, Color(CYAN, 0.7))))
	_panel_box.add_child(_centered(_label(prof["title"], 16, Color(0.75, 0.8, 1.0))))
	var lines: Array = prof["lines"]
	var quote := _label("«%s»" % lines[randi() % lines.size()], 17, Color(1.0, 0.92, 0.75))
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.custom_minimum_size = Vector2(_story_w(), 0)
	_panel_box.add_child(_centered(quote))
	var story := _label(prof["story"], 15, Color(0.85, 0.85, 0.98))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(_story_w(), 0)
	_panel_box.add_child(_centered(story))
	var act := _npc_active(v)
	var offer := _npc_offer(v)
	if not act.is_empty():
		_panel_box.add_child(_centered(_label("Вы обещали помочь:", 15, GOLD)))
		_panel_box.add_child(_centered(_label(Quests.desc(act) + "  •  награда: " + Quests.reward_text(Quests.reward(act)), 15, Color(0.92, 0.92, 1.0))))
		var drop := _button("Не смогу — отказаться", Color(1.0, 0.5, 0.5))
		drop.pressed.connect(func():
			Meta.npc_quests.erase(act)
			Meta.save()
			_fill_panel())
		_panel_box.add_child(_centered(drop))
	elif not offer.is_empty():
		_panel_box.add_child(_centered(_label("Просьба:", 15, GOLD)))
		var d := _label(Quests.desc(offer) + "  •  награда: " + Quests.reward_text(Quests.reward(offer)), 15, Color(0.92, 0.92, 1.0))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size = Vector2(_story_w(), 0)
		_panel_box.add_child(_centered(d))
		var can := Meta.npc_quests.size() < 3
		var take := _button("ПОМОГУ" if can else "Слишком много обещаний (3)", GOLD, can)
		take.pressed.connect(func():
			Meta.npc_quests.append(offer)
			Meta.save()
			Sound.play("levelup", -6.0)
			_toast_text("%s: «Спасибо! Я буду ждать.»" % prof["name"])
			_close_panel())
		_panel_box.add_child(_centered(take))
	_add_close()


func _fill_story() -> void:
	var ch := Data.chapter_of(Meta.levels_cleared if Meta.levels_cleared < Data.LEVELS.size() else Data.LEVELS.size() - 1)
	_panel_box.add_child(_centered(_label("КОМАНДИР ВОРОН", 30, Color.WHITE, Color(GOLD, 0.7))))
	_panel_box.add_child(_centered(_label(Story.CHAPTERS[ch]["name"], 18, Color(0.85, 0.75, 1.0))))
	var intro := _label(Story.CHAPTERS[ch]["intro"], 15, Color(0.82, 0.82, 0.95))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(_story_w(), 0)
	_panel_box.add_child(_centered(intro))
	var st := Meta.story_cur()
	if st.is_empty():
		var fin := _label("«Первые Врата закрыты. Но я слышу, как где-то тлеют малые… Отдыхай, охотник. Пока.»", 17, Color(1.0, 0.92, 0.75))
		fin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fin.custom_minimum_size = Vector2(_story_w(), 0)
		_panel_box.add_child(_centered(fin))
	else:
		_panel_box.add_child(_centered(_label("Задание: «%s»" % st["title"], 20, GOLD)))
		var t := _label("«%s»" % st["text"], 16, Color(1.0, 0.92, 0.75))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(_story_w(), 0)
		_panel_box.add_child(_centered(t))
		var p := Meta.story_progress(st)
		_panel_box.add_child(_centered(_label("Цель: %s  —  %d / %d" % [Meta.story_goal_text(st), int(p[0]), int(p[1])], 15, Color(0.6, 1.0, 0.7) if Meta.story_ready() else Color(0.9, 0.9, 1.0))))
		_panel_box.add_child(_centered(_label("Награда: " + Meta.cost_text(st["reward"]), 14, Color(0.75, 0.75, 0.9))))
		if not Meta.story_taken:
			var acc := _button("ПРИНЯТЬ ЗАДАНИЕ", GOLD)
			acc.pressed.connect(func():
				Meta.story_taken = true
				Meta.save()
				Sound.play("levelup", -6.0)
				_toast_text("Сюжетное задание: «%s»" % st["title"])
				_fill_panel())
			_panel_box.add_child(_centered(acc))
		elif Meta.story_ready():
			var b := _button("ДОЛОЖИТЬ", GOLD)
			b.pressed.connect(func():
				var r := Meta.story_claim()
				Sound.play("evolve", -2.0)
				_toast_text("Сюжет продвинулся! Награда: " + Meta.cost_text(r))
				_fill_panel())
			_panel_box.add_child(_centered(b))
	var pro := _button("Летопись: как всё началось", Color(0.75, 0.6, 1.0))
	pro.pressed.connect(func():
		_panel_id = "prologue"
		_fill_panel())
	_panel_box.add_child(_centered(pro))
	_add_close()


func _fill_prologue() -> void:
	_panel_box.add_child(_centered(_label("ЛЕТОПИСЬ СЛИЯНИЯ", 30, Color.WHITE, Color(Color(0.75, 0.6, 1.0), 0.8))))
	for para in Story.PROLOGUE:
		var l := _label(para, 16, Color(0.9, 0.88, 1.0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(_story_w(), 0)
		_panel_box.add_child(_centered(l))
	var go := _button("К КОМАНДИРУ ВОРОНУ", GOLD)
	go.pressed.connect(func():
		Meta.intro_seen = true
		Meta.save()
		_panel_id = "story"
		_fill_panel())
	_panel_box.add_child(_centered(go))
	_add_close()
