extends Node2D
## Главный узел: мир, свет, пост-эффекты, герой, враги, интерфейс и ход игры.

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const GemScript := preload("res://scripts/gem.gd")
const GroundScript := preload("res://scripts/ground.gd")
const HudScript := preload("res://scripts/hud.gd")
const BossScript := preload("res://scripts/boss.gd")
const ChestScript := preload("res://scripts/chest.gd")
const PoiScript := preload("res://scripts/poi.gd")
const Meta := preload("res://scripts/meta.gd")

const MAX_ENEMIES := 320

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float aberration = 0.0012;
uniform float hurt = 0.0;
uniform float scan = 0.05;
uniform float vignette = 0.55;
uniform float flash = 0.0;
uniform float glitch = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = step(0.7, fract(sin(floor(uv.y * 40.0) * 91.7 + TIME * 30.0) * 43758.5));
	uv.x += (band - 0.5) * 0.03 * glitch;
	vec2 d = uv - 0.5;
	float ab = aberration + hurt * 0.006 + glitch * 0.01;
	vec3 col;
	col.r = texture(screen_tex, uv + d * ab * 2.0).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * ab * 2.0).b;
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159 * 0.66);
	col *= 1.0 - scan * line;
	float v = smoothstep(0.95, 0.25, length(d * vec2(1.0, 0.8)) * (1.0 + vignette * 0.5));
	col *= mix(0.35, 1.0, v);
	float edge = smoothstep(0.25, 0.75, length(d));
	col = mix(col, col * vec3(1.0, 0.25, 0.35) + vec3(0.3, 0.0, 0.05), hurt * edge);
	col += vec3(0.5, 0.7, 1.0) * flash;
	col = mix(col, col * vec3(0.6, 1.3, 0.8), glitch * 0.5);
	COLOR = vec4(col, 1.0);
}
"""

var player: Node2D          # Игрок 1 — ведущий: общий опыт и уровень
var players: Array = []      # все герои на экране (1 или 2)
var coop := false
var net_mode := ""           # "" | "host" | "client"
var attacker: Node2D         # чей удар сейчас наносится
var _choosers: Array = []    # кто выбирает улучшение (по очереди)
var _chooser: Node2D
var hud: CanvasLayer
var camera: Camera2D
var _cam_anchor: Node2D
var world: Node2D
var entities: Node2D
var gems_node: Node2D
var enemies_node: Node2D
var props_node: Node2D
var projectiles_node: Node2D
var fx_node: Node2D
var zones_node: Node2D

var time_alive := 0.0
var kills := 0
var game_over := false
var pending_level_ups := 0
var fx_numbers := 0
var burst_budget := 18     # всплесков частиц за кадр — при толпе лишние пропускаем
var _fps_s := 60.0
var fx_lights := 0
var status_fx_budget := 6
var flash_budget := 5
var explosion_budget := 2
var reactions_count := 0
var bosses_killed := 0
var reward := {}
var level: Dictionary
var level_index := 0
var _elite_i := 0
var _boss_i := 0
var _boss_warned := false
var boss: Node2D = null
var _boss_index := 0
var _reaction_text_t := 0.0
var _combo_t := 0.0
## Счётчики забега для заданий, мастерства и итогов (см. quests.gd / meta.gd)
var run := {}
var _streak := 0
var _streak_t := 0.0
var _nodmg_t := 0.0
var _last_hp := -1.0
var _run_sync_t := 0.0
const QuestsScript := preload("res://scripts/quests.gd")
const QuestPoiScript := preload("res://scripts/quest_poi.gd")
const EventsScript := preload("res://scripts/events.gd")
var events: Node
var active_quests: Array = []
var _combo_seen := {}

var _spawn_timer := 0.0
var _next_elite := 60.0
var _shake := 0.0
var _post: ShaderMaterial
var _wvp: SubViewport
var _view3d: Node3D
var _cam3d: Camera3D
var _plane: MeshInstance3D
var _cam_offset := Vector2.ZERO
var _look := Vector2.ZERO
var _bill_root: Node3D
var _mirror_root: Node3D
var return_after_size := false
var _nick_labels: Array = []
var _frame := 0
var _mirrors: Array = []
var _light_mirrors: Array = []
var ground_node: Node2D
var view_radius := 1200.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	run = {"hero": Data.selected_character, "kills": 0, "wkills": {}, "elites": 0, "altars": 0, "trials": 0,
		"caches": 0, "puzzles": 0, "beacons": 0, "events": 0, "reactions": 0, "boss": 0, "mat_scrap": 0,
		"mat_chips": 0, "mat_cores": 0, "scrap": 0, "nodmg": 0, "minutes": 0, "level": 1, "combo": 0, "fusions": 0}
	if not Data.coop and Net.mode == "":
		active_quests = QuestsScript.active(Data.selected_character)
	_vk = Settings.view_k()
	rng.randomize()
	level_index = clampi(Data.selected_level, 0, Data.LEVELS.size() - 1)
	level = Data.LEVELS[level_index]
	_setup_input()
	RenderingServer.set_default_clear_color(Color(0.03, 0.02, 0.06))
	_setup_view3d()

	world = Node2D.new()
	world.name = "World"
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wvp.add_child(world)

	var dark := CanvasModulate.new()
	dark.color = Color(0.4, 0.36, 0.58)
	_wvp.add_child(dark)

	var ground := GroundScript.new()
	ground.main = self
	ground_node = ground
	world.add_child(ground)

	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	world.add_child(entities)
	props_node = _make_layer("Props", entities, true)
	gems_node = _make_layer("Gems", entities, true)
	enemies_node = _make_layer("Enemies", entities, true)
	ground.props_parent = props_node

	coop = Data.coop
	player = PlayerScript.new()
	player.name = "Player"
	player.main = self
	player.setup(Data.selected_character)
	entities.add_child(player)
	players.append(player)
	if coop:
		var p2 = PlayerScript.new()
		p2.name = "Player2"
		p2.main = self
		p2.pid = 1
		if Net.in_game and Net.mode == "host":
			p2.profile = Net.peer_profile  # второй игрок играет со своей прокачкой
		p2.setup(Data.selected_character2)
		p2.position = Vector2(90, 0)
		player.position = Vector2(-90, 0)
		entities.add_child(p2)
		players.append(p2)
		net_mode = Net.mode if Net.in_game else ""
		if net_mode == "":
			var DevInput := preload("res://scripts/devinput.gd")
			player.input = DevInput.new(Data.coop_devices[0])
			p2.input = DevInput.new(Data.coop_devices[1])
		elif net_mode == "host":
			# Герой клиента считается у клиента; здесь — только показ по его данным
			p2.puppet = true
			p2.remote = true
			p2.net_pos = p2.position
		else:
			# Клиент: хост — показ, свой герой — полная локальная симуляция
			player.puppet = true
			player.net_pos = player.position
			_client_input = preload("res://scripts/devinput.gd").new(-1)
			p2.input = _client_input
	if net_mode != "":
		Net.main = self
		# Ники над героями в сетевой игре
		var me_i := 0 if net_mode == "host" else 1
		for i in players.size():
			var nk: String = Meta.nickname if i == me_i else (Net.peer_nick if Net.peer_nick != "" else "Игрок")
			var l := Label3D.new()
			l.text = nk
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 40
			l.outline_size = 10
			l.pixel_size = 0.004
			l.no_depth_test = true
			l.modulate = players[i].player_color()
			l.outline_modulate = Color(0.05, 0.02, 0.1)
			_mirror_root.add_child(l)
			_nick_labels.append([l, players[i]])
	attacker = player

	zones_node = _make_layer("Zones", world, false)
	zones_node.z_index = -12
	projectiles_node = _make_layer("Projectiles", world, false)
	projectiles_node.z_index = 5
	fx_node = _make_layer("Effects", world, false)
	events = EventsScript.new()
	events.main = self
	world.add_child(events)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	_cam_anchor = Node2D.new()
	world.add_child(_cam_anchor)
	_cam_anchor.position = center()
	_cam_anchor.add_child(camera)
	camera.make_current()
	_frame_camera()
	get_viewport().size_changed.connect(_frame_camera)

	_setup_weather()
	_setup_post()

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	Sound.set_track("battle", true)
	Fx.text_pop(self, player.position + Vector2(0, -40), "%d. %s" % [level_index + 1, level["name"]], Color(1.0, 0.9, 1.0), 30)
	Fx.portal(self, player.position, Color(0.3, 0.9, 1.0), 2.0)
	Fx.ring(self, player.position, 10.0, 160.0, Pixel.hdr(Color(0.3, 0.9, 1.0), 2.0), 0.8, 5.0)


## Центр между живыми героями — туда смотрит камера.
func center() -> Vector2:
	var sum := Vector2.ZERO
	for p in players:
		sum += p.position
	return sum / maxf(players.size(), 1)


## Куда смотрит камера: в сетевой игре — на своего героя (у каждого свой экран).
## Сколько врагов одновременно: на телефоне меньше (но они крепче — см. spawn_enemy)
func max_enemies() -> int:
	return Settings.mobile_enemy_cap() if Settings.is_mobile() else Settings.desktop_enemy_cap()


## Экран загрузки ждёт, пока эта функция не вернёт true: за это время под экраном
## один раз показываются враги, кристаллы и все виды эффектов — видеокарта заранее
## готовит их шейдеры, и в бою не будет рывков при их первом появлении.
var _pw_nodes: Array = []
var _pw_frame := -1
func loading_ready() -> bool:
	if _pw_frame == -1:
		_pw_frame = 0
		var c := view_center()
		var before := enemies_node.get_child_count()
		for k in ["imp", "bat", "ghoul", "wraith"]:
			if Data.ENEMIES.has(k):
				spawn_enemy(k, c + Vector2(rng.randf_range(-300, 300), rng.randf_range(-200, 200)))
		for i in range(before, enemies_node.get_child_count()):
			var en: Node = enemies_node.get_child(i)
			en.process_mode = Node.PROCESS_MODE_DISABLED
			_pw_nodes.append(en)
		var col := Color(0.4, 0.9, 1.0)
		Fx.burst(self, c, [col, Color.WHITE], 12, 120.0, 0.4, 3.0)
		Fx.sparks(self, c, col)
		Fx.ring(self, c, 10.0, 80.0, col, 0.3)
		Fx.explosion(self, c, col, Color(1.0, 0.4, 0.8), 60.0)
		Fx.lightning(self, c, 60.0)
		Fx.portal(self, c, col)
		Fx.glow_flash(self, c, col, 60.0, 0.3)
		Fx.light_flash(self, c, col, 1.0, 1.0, 0.3)
		Fx.chain(self, PackedVector2Array([c, c + Vector2(80, 30)]), col)
		Fx.slash(self, c, 0.0, 1.5, 80.0, col)
		Fx.beam(self, c, c + Vector2(120, 0), col)
		Fx.number(self, c, 12.0)
		Fx.text_pop(self, c, "", col)
		var g := GemScript.new()
		g.main = self
		g.player = player
		g.position = c + Vector2(60, 40)
		g.value = 1
		g.kind = "heal"
		g.process_mode = Node.PROCESS_MODE_DISABLED
		gems_node.add_child(g)
		_pw_nodes.append(g)
	_pw_frame += 1
	if _pw_frame < 6:
		return false
	for n in _pw_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_pw_nodes.clear()
	return true


func view_center() -> Vector2:
	if net_mode == "host":
		return players[0].position
	if net_mode == "client" and players.size() > 1:
		return players[1].position
	return center()


## Вокруг каких точек держать мир загруженным (хосту нужны оба героя).
func world_centers() -> Array:
	if net_mode == "host":
		return [players[0].position, players[1].position]
	return [view_center()]


## Около кого появляются враги: в сетевой игре — поочерёдно около каждого живого.
func _spawn_anchor() -> Vector2:
	if net_mode == "host":
		var alive: Array = players.filter(func(p): return not p._dead)
		if not alive.is_empty():
			return alive[rng.randi() % alive.size()].position
	return center()


func nearest_player(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var bd := INF
	for p in players:
		if p._dead:
			continue
		var d: float = p.position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best if best != null else player


## Кооператив: герои не могут разойтись дальше экрана.
func _leash() -> void:
	if players.size() < 2:
		return
	var a: Node2D = players[0]
	var b: Node2D = players[1]
	# Павший не двигается — живой не может уйти от него за край экрана
	var ka := 0.0 if a._dead else (1.0 if b._dead else 0.5)
	var kb := 1.0 - ka
	var lim := Vector2(820.0, 520.0)
	var d: Vector2 = b.position - a.position
	for ax in 2:
		var ex: float = absf(d[ax]) - lim[ax]
		if ex > 0.0:
			var sgn := signf(d[ax])
			a.position[ax] += sgn * ex * ka
			b.position[ax] -= sgn * ex * kb


func _make_layer(layer_name: String, parent: Node, ysort: bool) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.y_sort_enabled = ysort
	parent.add_child(n)
	return n


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"ability": [KEY_SPACE, KEY_SHIFT],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# ---------- 2.5D: 2D-мир боя рисуется в текстуру, лежащую на наклонной 3D-плоскости ----------

const PLANE_TEXEL := 0.01  # метров на пиксель мира
const VIEW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 fog_color : source_color = vec4(0.05, 0.02, 0.1, 1.0);
uniform float fog_start = 0.42;
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float far = smoothstep(fog_start, 0.0, UV.y);
	ALBEDO = mix(c, fog_color.rgb, far * 0.92);
}
"""


func _setup_view3d() -> void:
	_wvp = SubViewport.new()
	_wvp.size = Vector2i(1600, 1200)
	_wvp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_wvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_wvp.canvas_cull_mask = 1  # слой 2 — спрайты, которые показываются стоя в 3D
	add_child(_wvp)

	_view3d = Node3D.new()
	add_child(_view3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.02, 0.1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# На телефоне при «мало эффектов» свечение выключено — это самый тяжёлый проход
	env.glow_enabled = Settings.glow_enabled()
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.45, 0.72)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_view3d.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40, 30, 0)
	moon.light_color = Color(0.55, 0.6, 1.0)
	moon.light_energy = 0.35
	# Тени от луны на объёмных постройках — по настройке качества теней
	moon.shadow_enabled = Settings.shadows > 0
	moon.directional_shadow_max_distance = 30.0
	_view3d.add_child(moon)
	_bill_root = Node3D.new()
	_view3d.add_child(_bill_root)
	# Корень «зеркал» мира: координаты детей — мировые, а сдвигается сам корень за камерой.
	# Так неподвижные объекты не нужно переставлять каждый кадр.
	_mirror_root = Node3D.new()
	_view3d.add_child(_mirror_root)

	_cam3d = Camera3D.new()
	_view3d.add_child(_cam3d)
	_orient_camera()
	_cam3d.make_current()
	Settings.orientation_changed.connect(_on_orientation)
	Settings.dyn_changed.connect(_on_dyn_changed)
	var late := Node.new()
	late.name = "LateSync"
	late.process_priority = 1000
	late.set_script(preload("res://scripts/late_sync.gd"))
	late.set("main", self)
	add_child(late)

	_plane = MeshInstance3D.new()
	_plane.mesh = PlaneMesh.new()
	var sh := Shader.new()
	sh.code = VIEW_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", _wvp.get_texture())
	_plane.material_override = m
	_view3d.add_child(_plane)


## Камера под положение экрана: горизонтально — привычный наклон; вертикально —
## держим ширину кадра и смотрим круче сверху, чтобы мир не уходил к горизонту.
func _orient_camera() -> void:
	var vs := get_viewport().get_visible_rect().size
	_cull_box = Vector3(800.0, 1700.0, 1000.0) if vs.y > vs.x else Vector3(1150.0, 1000.0, 720.0)
	if vs.y > vs.x:
		# Узкий угол обзора и камера дальше — перспектива как на ПК, без «рыбьего глаза»
		_cam3d.keep_aspect = Camera3D.KEEP_WIDTH
		_cam3d.fov = 30.0
		_cam3d.position = Vector3(0, 11.4, 9.2)
	else:
		_cam3d.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam3d.fov = 42.0
		_cam3d.position = Vector3(0, 6.6, 7.4)
	_cam3d.look_at(Vector3(0, 0, -0.4))


func _on_orientation(_p: bool) -> void:
	await get_tree().process_frame
	_orient_camera()
	_frame_camera()
	if hud and hud.has_method("relayout"):
		hud.relayout()


## Вертикальный экран (телефон)
func portrait() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.y > vs.x


## Подбирает размер плоскости и текстуры так, чтобы они покрывали весь кадр камеры.
func _frame_camera() -> void:
	if _cam3d == null or not _cam3d.is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(0, vs.y), Vector2(vs.x, vs.y)]:
		var o := _cam3d.project_ray_origin(c)
		var n := _cam3d.project_ray_normal(c)
		var tmax := 30.0 if vs.y > vs.x else 60.0
		var t := tmax
		if n.y < -0.01:
			t = minf(-o.y / n.y, tmax)
		var p := o + n * t
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(0.3, 0.3)
	hi += Vector2(0.3, 0.3)
	var size := hi - lo
	var px := Vector2i(clampi(int(size.x / PLANE_TEXEL), 256, 3200), clampi(int(size.y / PLANE_TEXEL), 256, 4000))
	size = Vector2(px) * PLANE_TEXEL
	# Чёткость текстур зависит от разрешения экрана: мир рисуется крупнее и сжимается
	var tk: float = Settings.tex_scale()
	if Settings.is_mobile():
		# Телефон: мир рисуется в уменьшенную текстуру — в 2–4 раза меньше пикселей
		tk = Settings.mobile_world_scale()
	_px = px
	_tk_base = tk
	tk *= _dyn_world_k()
	if absf(tk - 1.0) > 0.01:
		_wvp.size_2d_override = px
		_wvp.size_2d_override_stretch = true
		_wvp.size = Vector2i(int(px.x * tk), int(px.y * tk))
		return_after_size = true
	var center := (lo + hi) / 2.0
	(_plane.mesh as PlaneMesh).size = size
	_plane.position = Vector3(center.x, 0, center.y)
	if not return_after_size:
		_wvp.size = px
		_wvp.size_2d_override = Vector2i.ZERO
	return_after_size = false
	_cam_offset = center / PLANE_TEXEL
	view_radius = maxf(absf(lo.x), maxf(absf(hi.x), maxf(absf(lo.y), absf(hi.y)))) / PLANE_TEXEL


var _px := Vector2i.ZERO
var _tk_base := 1.0
var _tk_applied := 1.0


## Множитель текстуры мира от удержания кадров (Settings.dyn_k): 1.0 … 0.7
func _dyn_world_k() -> float:
	return lerpf(0.7, 1.0, (Settings.dyn_k - 0.5) / 0.5)


## Кадров не хватает — уменьшаем текстуру пола и спрайтов; запас вернулся — возвращаем.
func _on_dyn_changed(_k: float) -> void:
	if _px == Vector2i.ZERO:
		return
	var tk := _tk_base * _dyn_world_k()
	if absf(tk - _tk_applied) < 0.04:
		return
	_tk_applied = tk
	if absf(tk - 1.0) > 0.01:
		_wvp.size_2d_override = _px
		_wvp.size_2d_override_stretch = true
		_wvp.size = Vector2i(int(_px.x * tk), int(_px.y * tk))
	else:
		_wvp.size = _px
		_wvp.size_2d_override = Vector2i.ZERO


# ---------- Стоячие спрайты: 2D-логика, 3D-изображение ----------

## Показывать спрайт стоя в 3D. Сам 2D-спрайт перестаёт рисоваться на полу,
## но остаётся источником данных: текстура, кадр, отражение, цвет, масштаб.
func mirror(sprite: Sprite2D, anchor: Node2D, emissive: bool, is_static := false) -> void:
	sprite.visibility_layer = 2
	var s3 := Sprite3D.new()
	s3.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s3.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emissive:
		s3.shaded = false
		s3.render_priority = 1
		s3.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	else:
		s3.shaded = true
		s3.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s3.visible = false
	_mirror_root.add_child(s3)
	_mirrors.append([sprite, s3, anchor, emissive, is_static, false])


## Свет 2D-источника дублируется 3D-светом, чтобы освещать стоящие спрайты.
func mirror_light(light: PointLight2D, anchor: Node2D, height := 1.2) -> void:
	var l := OmniLight3D.new()
	l.light_color = light.color
	l.omni_range = light.texture_scale * 64.0 * PLANE_TEXEL * 0.9
	l.omni_attenuation = 1.4
	_mirror_root.add_child(l)
	_light_mirrors.append([light, l, anchor, height])


## Выталкивает круг из препятствий окружения (колонны, деревья, кристаллы...).
var _low_rows := {}


## Номер строки под самым нижним непрозрачным пикселем текстуры (кешируется).
func _lowest_row(t: Texture2D) -> float:
	var id := t.get_rid()
	if _low_rows.has(id):
		return _low_rows[id]
	var im := t.get_image()
	var low := float(t.get_height())
	if im:
		low = 0.0
		for y in range(im.get_height() - 1, -1, -1):
			var found := false
			for x in im.get_width():
				if im.get_pixel(x, y).a > 0.5:
					found = true
					break
			if found:
				low = float(y + 1)
				break
	_low_rows[id] = low
	return low


func push_out(pos: Vector2, r: float, iterations := 2) -> Vector2:
	return ground_node.push_out(pos, r, iterations) if ground_node else pos


func beam3d(points: PackedVector3Array, color: Color, width: float, duration: float, jitter := 0.0) -> void:
	if net_mode == "client" and not (Net.replaying or Net.local):
		return
	if net_mode == "client" and Net.local:
		Net.cfx("beam3d", [_to2dh(points), color, width, duration, jitter])
	if net_mode == "host" and not Net.replaying:
		Net.fx("beam3d", [_to2dh(points), color, width, duration, jitter])
	if not vfx_ok("vfx_beam", 28):
		return   # картинку пропускаем — урон уже посчитан тем, кто вызвал
	var b = preload("res://scripts/beam3d.gd").new()
	b.add_to_group("vfx_beam")
	b.camera = _cam3d
	b.points = points
	b.color = color
	b.width = width
	b.duration = duration
	b.jitter = jitter
	_bill_root.add_child(b)


func slash3d(pos: Vector2, angle: float, arc: float, radius_px: float, color: Color, anchor: Node2D) -> void:
	if net_mode == "client" and not (Net.replaying or Net.local):
		return
	if net_mode == "client" and Net.local:
		Net.cfx("slash3d", [pos, angle, arc, radius_px, color, players.find(anchor)])
	if net_mode == "host" and not Net.replaying:
		Net.fx("slash3d", [pos, angle, arc, radius_px, color, players.find(anchor)])
	if not vfx_ok("vfx_slash", 10):
		return
	var s = preload("res://scripts/slash3d.gd").new()
	s.add_to_group("vfx_slash")
	s.main = self
	s.center = pos
	s.anchor = anchor
	s.angle = angle
	s.arc = arc
	s.radius = radius_px * PLANE_TEXEL * 0.9
	s.color = color
	_bill_root.add_child(s)


## Позиция в корне зеркал (мировые координаты, без сдвига камеры).
## Точка экрана → точка мира (луч из 3D-камеры на плоскость пола).
func screen_to_world(sp: Vector2) -> Vector2:
	if _cam3d == null or _mirror_root == null:
		return Vector2.INF
	var o := _cam3d.project_ray_origin(sp)
	var n := _cam3d.project_ray_normal(sp)
	var py := _plane.global_position.y
	if absf(n.y) < 0.0001:
		return Vector2.INF
	var t := (py - o.y) / n.y
	if t < 0.0:
		return Vector2.INF
	var w := o + n * t - _mirror_root.global_position
	return Vector2(w.x, w.z) / PLANE_TEXEL


func _bl(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x * PLANE_TEXEL, height, p.y * PLANE_TEXEL)


## Лимит визуальных эффектов: сколько штук данного вида может быть на экране одновременно.
## Сам урон и логика от этого не зависят — пропускается только картинка.
func vfx_ok(group: String, cap: int) -> bool:
	var k := (1.0 if _fps_s > 45.0 else (0.6 if _fps_s > 30.0 else 0.35)) * Settings.fx_k()
	return get_tree().get_node_count_in_group(group) < maxi(2, int(cap * k))


func to3d(p: Vector2, height := 0.0) -> Vector3:
	var c := camera.get_screen_center_position()
	return _plane.position + Vector3((p.x - c.x) * PLANE_TEXEL, height, (p.y - c.y) * PLANE_TEXEL)


## Объёмные 3D-модели объектов поля: следуют за своей 2D-точкой мира.
var _props3d: Array = []   # [узел 3D, 2D-якорь, полуширина px, прозрачен?]
const Props3D := preload("res://scripts/props3d.gd")


func prop3d(kind: String, anchor: Node2D, rng: RandomNumberGenerator, rot := 0.0) -> Node3D:
	var n := Props3D.build(kind, rng)
	n.rotation.y = rot
	# Сразу ставим на место: иначе новый объект кадр висит в центре экрана (мелькание)
	n.position = _bl(anchor.global_position, 0.0) if anchor.is_inside_tree() else Vector3(0, -50, 0)
	n.visible = _on_view(anchor.global_position) if not _cull_c.is_empty() else true
	_mirror_root.add_child(n)
	var fr := Pixel.frames(kind)
	var half: float = fr["size"].x * Pixel.PX * 0.5 * n.scale.x
	# Повёрнутый объект шире по глубине — берём габарит с запасом
	half = maxf(half, absf(sin(rot)) * fr["size"].x * Pixel.PX * 0.5)
	_props3d.append([n, anchor, half, 0.0, fr["size"].y * Pixel.PX * Pixel.STAND])
	return n


func _sync_props3d() -> void:
	var i := _props3d.size() - 1
	while i >= 0:
		var e: Array = _props3d[i]
		var n: Node3D = e[0]
		var a = e[1]
		if not is_instance_valid(a) or not (a as Node).is_inside_tree():
			n.queue_free()
			_props3d.remove_at(i)
			i -= 1
			continue
		var gp: Vector2 = a.global_position
		# За пределами экрана — не показываем и не считаем
		if not _on_view(gp):
			n.visible = false
			i -= 1
			continue
		n.visible = true
		n.position = _bl(gp, 0.0)
		# Стоит между камерой и героем — плавно становится полупрозрачным.
		# Гистерезис: зона «скрыть» уже зоны «показать», чтобы не дрожало на границе.
		var cur: float = e[3]
		var want := 0.0
		for pp in players:
			var d: Vector2 = gp - pp.position
			var pad := 18.0 if cur > 0.3 else 0.0
			if d.y > 4.0 - pad and d.y < float(e[4]) * 1.35 + pad and absf(d.x) < float(e[2]) + 16.0 + pad:
				want = 0.7
				break
		var nxt := move_toward(cur, want, get_process_delta_time() * 3.0)
		if nxt != cur:
			e[3] = nxt
			for c in n.get_children():
				if c is GeometryInstance3D:
					(c as GeometryInstance3D).transparency = nxt
		i -= 1


## Точки, вокруг которых сейчас видно мир (камера и герои), — для отсечения невидимого.
var _cull_c: Array = []
var _vk := 1.0   # множитель дальности прорисовки (настройка телефона)
## Видимая область вокруг центра: x — вбок, y — вверх (вдаль), z — вниз.
## На вертикальном экране видно уже по бокам и дальше вверх-вниз.
var _cull_box := Vector3(1150.0, 1000.0, 720.0)
func _on_view(p: Vector2) -> bool:
	for c in _cull_c:
		var d: Vector2 = p - c
		if absf(d.x) < _cull_box.x * _vk and d.y > -_cull_box.y * _vk and d.y < _cull_box.z * _vk:
			return true
	return false


func _sync_mirrors() -> void:
	if camera == null:
		return
	var cc := camera.get_screen_center_position()
	_mirror_root.position = _plane.position - Vector3(cc.x, 0.0, cc.y) * PLANE_TEXEL
	_frame += 1
	_cull_c = [cc]
	_cull_c.append_array(world_centers())
	for nl in _nick_labels:
		(nl[0] as Label3D).position = _bl((nl[1] as Node2D).position, 1.25)
	_sync_props3d()
	var toward_cam := (_cam3d.global_position - _plane.position).normalized() * 0.03
	var i := _mirrors.size() - 1
	while i >= 0:
		var m: Array = _mirrors[i]
		var sp = m[0]
		var s3: Sprite3D = m[1]
		if not is_instance_valid(sp) or not (sp as Node).is_inside_tree():
			s3.queue_free()
			_mirrors.remove_at(i)
			i -= 1
			continue
		var sprite: Sprite2D = sp
		var anc: Node2D = m[2]
		# Неподвижные объекты обновляем раз в 4 кадра (вразбивку), если уже настроены
		if m[4] and m[5] and (_frame + i) % 4 != 0:
			i -= 1
			continue
		if not _on_view(anc.global_position):
			s3.visible = false
			i -= 1
			continue
		m[5] = true
		var vis := sprite.is_visible_in_tree() and sprite.texture != null
		s3.visible = vis
		if vis:
			var anchor: Node2D = m[2]
			var gp := anchor.global_position
			var sgp := sprite.global_position
			var gs := sprite.global_scale
			var height := -(sgp.y - gp.y) / Pixel.STAND * PLANE_TEXEL
			s3.position = _bl(Vector2(sgp.x, gp.y), height)
			if m[3]:
				s3.position += toward_cam
			# Свойства меняем только при изменении: каждое присваивание перестраивает меш спрайта
			if s3.texture != sprite.texture:
				s3.texture = sprite.texture
			if s3.flip_h != sprite.flip_h:
				s3.flip_h = sprite.flip_h
			var px_size := PLANE_TEXEL * absf(gs.x)
			if not is_equal_approx(s3.pixel_size, px_size):
				s3.pixel_size = px_size
			var sc := Vector3(1.0, absf(gs.y / gs.x) / Pixel.STAND, 1.0)
			if not s3.scale.is_equal_approx(sc):
				s3.scale = sc
			var off := Vector2(sprite.offset.x, -sprite.offset.y)
			if s3.offset != off:
				s3.offset = off
			# Нижний непрозрачный пиксель спрайта не уходит под пол и не висит над ним
			var half_h: float = sprite.texture.get_height() / 2.0
			var low := _lowest_row(sprite.texture)
			var bottom: float = (half_h - low - sprite.offset.y) * s3.pixel_size * s3.scale.y
			if height + bottom < 0.0:
				s3.position.y += -(height + bottom)
			var mod := sprite.modulate * sprite.self_modulate
			var parent := sprite.get_parent() as CanvasItem
			while parent != null and parent != world:
				mod *= parent.modulate
				parent = parent.get_parent() as CanvasItem
			# Объект перед героем (ближе к камере) становится полупрозрачным, чтобы не загораживать
			if not (anchor in players):
				for pp in players:
					var d: Vector2 = gp - pp.position
					if d.y > 0.0 and d.y < 140.0 and absf(d.x) < 45.0 + absf(gs.x) * 6.0:
						mod.a *= 0.35
						break
			var ac := SpriteBase3D.ALPHA_CUT_DISABLED if (m[3] or mod.a < 0.99) else SpriteBase3D.ALPHA_CUT_DISCARD
			if s3.alpha_cut != ac:
				s3.alpha_cut = ac
			if s3.modulate != mod:
				s3.modulate = mod
		i -= 1
	i = _light_mirrors.size() - 1
	while i >= 0:
		var lm: Array = _light_mirrors[i]
		var l3: OmniLight3D = lm[1]
		if not is_instance_valid(lm[0]) or not (lm[0] as Node).is_inside_tree():
			l3.queue_free()
			_light_mirrors.remove_at(i)
			i -= 1
			continue
		var l2: PointLight2D = lm[0]
		l3.visible = l2.is_visible_in_tree() and _on_view(l2.global_position)
		l3.position = _bl(l2.global_position + Vector2(0, -l2.position.y), lm[3])
		l3.light_energy = l2.energy * 1.6
		i -= 1


func _particles3d(pos: Vector3, colors: Array, amount: int, extents: Vector3, gravity: Vector3,
		life: float, size: Vector2, vel := Vector2(0, 0), parent: Node3D = null, fixed_y := false) -> GPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if fixed_y:
		mm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mm.billboard_keep_scale = true
	q.material = mm
	p.mesh = q
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.gravity = gravity
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.color_ramp = Fx._ramp(colors)
	p.local_coords = true
	var g := Fx.gpu3d(p)   # считает видеокарта
	(parent if parent != null else _view3d).add_child(g)
	g.emitting = true
	return g


## Погода привязана к миру, а не к камере: поле разбито на клетки 4×4,
## каждая клетка — свой источник дождя; при движении клетки «переползают» вперёд.
const WEATHER_CELL := 900.0
var _weather_tiles: Array = []


func _setup_weather() -> void:
	if not Settings.weather_enabled():
		return   # телефон: погода выключена в настройках
	var half := WEATHER_CELL * PLANE_TEXEL * 0.5
	for ix in 4:
		for iy in 4:
			var root := Node3D.new()
			_view3d.add_child(root)
			# Неоновый дождь
			_particles3d(Vector3(0, 9, 0), [Color(0.4, 0.8, 1.0, 0.0), Color(0.5, 0.85, 1.0, 0.45), Color(0.9, 0.5, 1.0, 0.3)],
				60, Vector3(half, 0.5, half), Vector3(1.5, -40, 0), 0.6, Vector2(0.02, 0.35), Vector2.ZERO, root, true)
			# Брызги на земле
			_particles3d(Vector3(0, 0.05, 0), [Color(0.6, 0.85, 1.0, 0.0), Color(0.6, 0.85, 1.0, 0.4), Color(0.6, 0.85, 1.0, 0.0)],
				16, Vector3(half, 0.02, half), Vector3.ZERO, 0.25, Vector2(0.06, 0.03), Vector2.ZERO, root)
			# Светлячки-данные
			_particles3d(Vector3(0, 1.5, 0), [Color(1.0, 0.3, 0.8, 0.0), Color(1.4, 0.5, 1.6, 0.9), Color(0.4, 1.2, 1.6, 0.8), Color(0.3, 0.9, 1.0, 0.0)],
				6, Vector3(half, 1.5, half), Vector3(0, 0.15, 0), 5.0, Vector2(0.05, 0.05), Vector2(0.05, 0.3), root)
			_weather_tiles.append([root, ix, iy])
	_update_weather()


func _update_weather() -> void:
	if _weather_tiles.is_empty() or camera == null:
		return
	var c := camera.get_screen_center_position()
	var bx := floori(c.x / WEATHER_CELL)
	var by := floori(c.y / WEATHER_CELL)
	for t in _weather_tiles:
		# Клетка мира с тем же остатком по модулю 4 в окне [база-1 .. база+2]
		var cx: int = bx - 1 + posmod(int(t[1]) - (bx - 1), 4)
		var cy: int = by - 1 + posmod(int(t[2]) - (by - 1), 4)
		(t[0] as Node3D).position = to3d(Vector2(cx + 0.5, cy + 0.5) * WEATHER_CELL, 0.0)


func _setup_post() -> void:
	_post = ShaderMaterial.new()
	if DisplayServer.get_name() == "headless":
		return  # без видеокарты (автотесты) экранный шейдер не нужен
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POST_SHADER
	_post.shader = sh
	rect.material = _post
	layer.add_child(rect)


# ---------- Главный цикл ----------

func _process(delta: float) -> void:
	if net_mode == "":
		_leash()
	if _cam_anchor:
		_cam_anchor.position = view_center()
	_update_shake(delta)
	# Отражения в 3D, маяки — в «позднем» узле, после того как все сдвинулись и камера
	# обновилась: иначе пол и предметы рисуются со сдвигом в кадр и «шатаются».
	_update_weather()
	_update_music_intensity(delta)
	if Loader.busy:
		return  # мир уже рисуется под экраном загрузки, но время забега ещё не идёт
	status_fx_budget = 6
	flash_budget = 5
	explosion_budget = 2
	# При просадке кадров эффектов становится меньше
	_fps_s = lerpf(_fps_s, 1.0 / maxf(delta, 0.001), 0.05)
	burst_budget = int((18 if _fps_s > 50.0 else (10 if _fps_s > 35.0 else 5)) * Settings.fx_k())
	_reaction_text_t -= delta
	_combo_t -= delta
	if net_mode == "client":
		_net_client_tick(delta)
		return
	if net_mode == "host":
		_net_host_tick(delta)
	if game_over:
		return
	time_alive += delta
	_run_tick(delta)
	_handle_bosses()
	_handle_pois(delta)
	_handle_spawning(delta)
	_power_waves()
	_merge_gems(delta)
	# Телефон: раздвигаем толпу через кадр — заметно легче для процессора
	if not Settings.is_mobile() or Engine.get_process_frames() % 2 == 0:
		_separate_enemies()
	if endless:
		_endless_tick()
	elif time_alive >= level["time"]:
		if boss == null and _boss_i >= level["bosses"].size():
			if not _final_spawned:
				# Конец уровня: финальный босс (там, где босс уже был, — супер-босс)
				_final_spawned = true
				_spawn_boss(level.get("final", "lich"), not level["bosses"].is_empty())
			elif not _level_done:
				_level_done = true
				_offer_endless()
		elif not _boss_warned:
			_boss_warned = true
			Fx.text_pop(self, center() + Vector2(0, -60), "ПОБЕДИТЕ БОССА!", Pixel.hdr(Color(1.0, 0.4, 0.4), 1.4), 28)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not game_over and not hud.is_modal_open():
		hud.toggle_pause()


func shake(amount: float) -> void:
	if net_mode == "client" and not (Net.replaying or Net.local):
		return
	if net_mode == "host" and not Net.replaying:
		Net.fx("shake", [amount])
	_shake = maxf(_shake, amount)


func _update_shake(delta: float) -> void:
	_shake = clampf(move_toward(_shake, 0.0, delta * 40.0), 0.0, 30.0)
	# Защита: после долгого зависания плавная камера может «улететь» — возвращаем её
	if not camera.get_screen_center_position().is_finite():
		camera.reset_smoothing()
	# Взгляд: камера чуть смещается туда, куда смотрит герой
	var me: Node2D = players[1] if (net_mode == "client" and players.size() > 1) else players[0]
	var want: Vector2 = me.aim * 110.0 if (me.get("aim") != null and not coop) else Vector2.ZERO
	_look = _look.lerp(want, 1.0 - exp(-3.5 * get_process_delta_time()))
	camera.offset = _cam_offset + _look + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


## Красная вспышка экрана только у того, чьего героя ударили.
func hurt_flash_for(p: Node2D) -> void:
	if net_mode == "host" and p == players[1]:
		Net.fx("hurt", [])
		return
	hurt_flash()


func hurt_flash() -> void:
	var tw := create_tween()
	_post.set_shader_parameter("hurt", 1.0)
	tw.tween_method(func(v: float): _post.set_shader_parameter("hurt", v), 1.0, 0.0, 0.45)


func glitch_flash() -> void:
	if net_mode == "client" and not (Net.replaying or Net.local):
		return
	if net_mode == "host" and not Net.replaying:
		Net.fx("glitch", [])
	var tw := create_tween()
	tw.tween_method(func(v: float): _post.set_shader_parameter("glitch", v), 1.0, 0.0, 0.7)


func screen_flash(amount: float) -> void:
	if net_mode == "client" and not (Net.replaying or Net.local):
		return
	if net_mode == "host" and not Net.replaying:
		Net.fx("flash", [amount])
	var tw := create_tween()
	tw.tween_method(func(v: float): _post.set_shader_parameter("flash", v), amount, 0.0, 0.35)


# ---------- Враги ----------

func _handle_spawning(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = maxf(0.16, 1.0 - time_alive / 160.0) * (2.0 if boss != null else 1.0) / float(level["rate"]) / (1.0 + 0.3 * endless_min)
		if events != null:
			_spawn_timer /= events.spawn_k
		var count := 1 + int(time_alive / 55.0) + endless_min
		if endless:
			# Адских меньше, но каждый опасен; с минутами их становится больше
			# Бесконечный режим: плотные толпы адских мобов, с каждой минутой гуще
			_spawn_timer = maxf(0.07, 0.36 - 0.045 * endless_min) * (1.5 if boss != null else 1.0)
			count = 4 + endless_min * 2
		for i in count:
			if enemies_node.get_child_count() >= max_enemies():
				break
			spawn_enemy(_pick_enemy_kind())
	var elites: Array = level["elites"]
	if _elite_i < elites.size() and time_alive >= elites[_elite_i]:
		_elite_i += 1
		spawn_enemy("brute")
		shake(6.0)
		Fx.text_pop(self, player.position + Vector2(0, -60), "РУННЫЙ ГОЛЕМ ПРИБЛИЖАЕТСЯ", Pixel.hdr(Color(1.0, 0.55, 0.1), 1.5), 22)


func _pick_enemy_kind() -> String:
	if endless:
		# Бесконечный режим — только адские мобы, с минутами добавляются сильнейшие
		var hp: Array = ["hell_imp", "hell_hound", "hell_bat"]
		if endless_min >= 2:
			hp.append("hell_wraith")
		if endless_min >= 3:
			hp.append("hell_knight")
		return hp[rng.randi_range(0, hp.size() - 1)]
	var pool: Array = level["enemies"]
	# В начале уровня — только первые два вида, остальные подключаются со временем
	var n := clampi(2 + int(time_alive / 45.0), 2, pool.size())
	return pool[rng.randi_range(0, n - 1)]


const HELL_OF := {"imp": "hell_imp", "bat": "hell_bat", "goblin": "hell_hound", "wraith": "hell_wraith",
	"knight": "hell_knight", "brute": "hell_brute", "ghoul": "hell_knight", "spider": "hell_hound",
	"caster": "hell_wraith", "bomber": "hell_bat", "slime": "hell_imp"}


func spawn_enemy(kind: String, at := Vector2.INF) -> void:
	# В бесконечном режиме любые обычные мобы (и свита боссов) приходят в адском облике
	if endless and HELL_OF.has(kind) and kind != "mob_altar":
		kind = HELL_OF[kind]
	var info: Dictionary = Data.ENEMIES[kind]
	var e := EnemyScript.new()
	e.main = self
	var anchor_pos := _spawn_anchor()
	e.player = nearest_player(at if at != Vector2.INF else anchor_pos)
	e.kind = kind
	# Со временем враги заметно крепнут: здоровье растёт быстрее чем линейно, урон — тоже
	var tm := time_alive
	var scale_hp := float(level["hp"]) * (1.0 + tm / 100.0 + pow(tm / 220.0, 2.0)) * (1.0 + 0.35 * endless_min)
	e.max_hp = info["hp"] * scale_hp
	e.speed = info["speed"] * rng.randf_range(0.9, 1.1) * (1.0 + minf(tm / 1200.0, 0.3))
	e.damage = info["damage"] * (1.0 + tm / 240.0) * (1.0 + 0.12 * endless_min)
	if info.get("hell", false):
		# Адские мобы крепнут с каждой минутой: здоровье, урон и скорость
		# Бесконечный режим: рост непрерывный (по долям минуты) и намного круче —
		# здоровье растёт почти квадратично, урон и скорость тоже заметно
		var em := maxf(0.0, (time_alive - float(level["time"])) / 60.0)
		e.max_hp = info["hp"] * float(level["hp"]) * (1.0 + 0.9 * em + 0.15 * em * em)
		e.damage = info["damage"] * (1.0 + 0.35 * em + 0.04 * em * em)
		e.speed = info["speed"] * minf(1.0 + 0.07 * em, 1.8) * rng.randf_range(0.95, 1.05)
		e.size_mult = 1.15
	e.radius = info["radius"]
	e.color = info["color"]
	e.xp_value = info["xp"]
	if (Settings.is_mobile() or Settings.crowd == 0) and kind != "mob_altar":
		# Телефон: врагов на экране меньше, но каждый крепче и даёт больше опыта —
		# сложность и темп прокачки как на ПК, а нагрузка на процессор ниже
		var fill := clampf(float(enemies_node.get_child_count()) / float(max_enemies()), 0.0, 1.0)
		var mk := 1.0 + 0.9 * fill
		e.max_hp *= mk
		e.xp_value = maxi(1, int(round(float(e.xp_value) * mk)))
	e.hp = e.max_hp
	e.is_elite = kind in ["brute", "hell_brute", "mob_altar"]
	# Усиления: чем дольше бой, тем чаще враги приходят с особыми свойствами
	if kind != "mob_altar" and kind != "slimelet" and kind != "spiderling":
		var chance := clampf((time_alive - 60.0) / 420.0, 0.0, 0.6) + 0.15 * endless_min
		if rng.randf() < chance:
			e.affixes.append(Data.AFFIXES.keys()[rng.randi() % Data.AFFIXES.size()])
			if time_alive > 300.0 and rng.randf() < 0.3:
				var a2: String = Data.AFFIXES.keys()[rng.randi() % Data.AFFIXES.size()]
				if not (a2 in e.affixes):
					e.affixes.append(a2)
	e.ai = info.get("ai", "chase")
	e.armor = info.get("armor", 0.0)
	e.split_kind = info.get("split", "")
	var angle := rng.randf() * TAU
	var dir := Vector2.RIGHT.rotated(angle)
	# Сверху кадр уходит вдаль — там враги появляются дальше, в тумане
	var far := maxf(0.0, -dir.y)
	var dist := lerpf(rng.randf_range(480.0, 640.0), rng.randf_range(760.0, 900.0), far)
	if portrait():
		# Вертикальный экран: по бокам видно меньше, вверх и вниз — больше
		dist = lerpf(rng.randf_range(430.0, 520.0), rng.randf_range(1250.0, 1450.0), far)
		if dir.y > 0.3:
			dist = maxf(dist, rng.randf_range(700.0, 820.0))
	e.position = anchor_pos + dir * dist if at == Vector2.INF else at
	enemies_node.add_child(e)


func get_enemies() -> Array[Node]:
	return enemies_node.get_children()


## aim — взгляд героя: враги по направлению взгляда в приоритете, сзади — в последнюю очередь.
func nearest_enemies_to(pos: Vector2, count: int, max_dist: float, exclude: Node, aim := Vector2.ZERO) -> Array:
	var list: Array = []
	var max_sq := max_dist * max_dist
	for e in enemies_node.get_children():
		if e == exclude or not e.can_be_hit():
			continue
		var d: float = pos.distance_squared_to(e.position)
		if d < max_sq:
			if aim != Vector2.ZERO and d > 1.0:
				var dot: float = aim.dot((e.position - pos) / sqrt(d))
				var w := 1.0 + 2.5 * (1.0 - dot)
				d *= w * w
			list.append([d, e])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array = []
	for i in mini(count, list.size()):
		result.append(list[i][1])
	return result


func damage_area(pos: Vector2, r: float, dmg: float, exclude: Node, status := "") -> void:
	for e in enemies_node.get_children():
		if e == exclude or not e.can_be_hit():
			continue
		var rr: float = r + e.radius
		if pos.distance_squared_to(e.position) < rr * rr:
			e.hit(dmg, pos, 120.0, status)


func spawn_shards(pos: Vector2, count: int, dmg: float) -> void:
	for i in count:
		var p = preload("res://scripts/projectile.gd").new()
		p.main = self
		p.style = "shard"
		p.position = pos
		p.velocity = Vector2.RIGHT.rotated(TAU * i / count + randf() * 0.3) * 420.0
		p.damage = dmg
		p.pierce = 2
		p.life = 0.6
		p.status = ""
		p.color = Color(0.6, 0.95, 1.0)
		p.can_ignite = false
		projectiles_node.add_child(p)


## Надпись о сработавшей связке (не чаще ~3 в секунду, новые — всегда).
func combo_pop(pos: Vector2, text: String, color: Color) -> void:
	var first := not _combo_seen.has(text)
	if not first and _combo_t > 0.0:
		return
	_combo_seen[text] = true
	_combo_t = 0.3
	Fx.text_pop(self, pos, text, Pixel.hdr(color, 1.5), 22 if first else 17)


## Поле одного оружия задевает предметы других: шары, лужи, туман, смерчи.
func energize(pos: Vector2, r: float, kind: String, element := "") -> void:
	for p in projectiles_node.get_children():
		if p.get("style") != "ball" or p.position.distance_to(pos) > r + p.zap_radius * 0.3:
			continue
		match kind:
			"light", "pulse":
				p.overcharge(1.0)
				combo_pop(p.position + Vector2(0, -60), "ПЕРЕЗАРЯДКА ШАРА", Color(0.6, 0.85, 1.0))
			"cut":
				p.split()
			"quake":
				var away: Vector2 = p.position - pos
				if away.length() > 1.0:
					p.velocity = away.normalized() * p.velocity.length()
	for z in zones_node.get_children():
		if z.position.distance_to(pos) < r + z.radius and kind in ["quake", "pulse"]:
			z.energize(kind)


func on_reaction(key: String, pos: Vector2) -> void:
	reactions_count += 1
	Sound.play("reaction", -6.0, 1.0, 0.1, 0.08)
	if _reaction_text_t <= 0.0:
		_reaction_text_t = 0.35
		var r: Dictionary = Data.REACTIONS[key]
		Fx.text_pop(self, pos + Vector2(0, 40), r["name"], Pixel.hdr(r["color"], 1.5), 20)


## Мягкое расталкивание врагов, чтобы толпа не слипалась в одну точку.
func _separate_enemies() -> void:
	var cells := {}
	for e in enemies_node.get_children():
		if e.dead or not e.vis:
			continue   # за кадром толпу не раздвигаем — её не видно
		var key := Vector2i(floori(e.position.x / 40.0), floori(e.position.y / 40.0))
		if cells.has(key):
			cells[key].append(e)
		else:
			cells[key] = [e]
	for key in cells:
		var arr: Array = cells[key]
		var n := mini(arr.size(), 10)
		for i in n:
			var a: Node2D = arr[i]
			for j in range(i + 1, n):
				var b: Node2D = arr[j]
				var d: Vector2 = a.position - b.position
				var dist := d.length()
				var min_d: float = (a.radius + b.radius) * 0.85
				if dist < min_d and dist > 0.01:
					var push := d / dist * (min_d - dist) * 0.5
					if not a.is_elite:
						a.position += push
					if not b.is_elite:
						b.position -= push


func on_enemy_killed(enemy: Node2D) -> void:
	kills += 1
	# Задания и мастерство: кем и чем убит враг, серия убийств, добыча материалов
	var src: String = str(enemy.get("last_src")) if enemy.get("last_src") != null else ""
	var wm: Dictionary = {}
	if src != "" and Data.WEAPONS.has(src):
		run["wkills"][src] = int(run["wkills"].get(src, 0)) + 1
		var kpw: Node2D = enemy._atk() if enemy.has_method("_atk") else player
		wm = kpw.wmods_for(src)
		if float(wm.get("leech", 0.0)) > 0.0 and not kpw._dead:
			kpw.heal(float(wm["leech"]), false)
	_streak = _streak + 1 if _streak_t > 0.0 else 1
	_streak_t = 2.0
	run["combo"] = maxi(int(run["combo"]), _streak)
	if enemy.has_meta("golden"):
		# Золотой гоблин: щедрая добыча
		drop_chest(enemy.position + Vector2(0, 50))
		drop_material(enemy.position, "scrap", 8)
		drop_material(enemy.position + Vector2(30, 0), "chips", 2)
		if rng.randf() < 0.4:
			drop_material(enemy.position + Vector2(-30, 0), "cores", 1)
		for i in 10:
			drop_gem_at(enemy.position + Vector2.RIGHT.rotated(TAU * i / 10.0) * 70.0, 6)
		combo_pop(enemy.position + Vector2(0, -90), "ЗОЛОТОЙ ГОБЛИН ПОЙМАН!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.6))
	if enemy.is_elite and not enemy.is_boss:
		run["elites"] = int(run["elites"]) + 1
		drop_material(enemy.position, "scrap", rng.randi_range(3, 5))
		if rng.randf() < 0.35:
			drop_material(enemy.position + Vector2(20, 10), "chips", 1)
	elif enemy.is_boss:
		drop_material(enemy.position, "cores", rng.randi_range(1, 2))
		drop_material(enemy.position + Vector2(-30, 10), "chips", 3)
		drop_material(enemy.position + Vector2(30, 10), "scrap", 8)
	elif rng.randf() < 0.035 * (1.0 + float(wm.get("salvage", 0.0))):
		drop_material(enemy.position, "scrap", 1 + int(rng.randf() < 0.3))
	var kp: Node2D = enemy._atk() if enemy.has_method("_atk") else player
	if kp.kill_heal > 0.0 and not kp._dead:
		kp.heal(kp.kill_heal, false)
	# Опыт выпадает случайно: иногда меньше, иногда больше, изредка крупный кристалл;
	# аптечки — редкость
	var heal_drop := rng.randf() < 0.005
	# Кристаллов меньше (≈55% врагов), но каждый ценнее — опыта в сумме примерно столько же
	if heal_drop or enemy.is_elite or rng.randf() > 0.45:
		var xv: float = float(enemy.xp_value) * rng.randf_range(0.8, 2.6) * (events.xp_k if events != null else 1.0)
		if rng.randf() < 0.06:
			xv *= 3.0
		_drop_gem(enemy.position, maxi(1, int(round(xv))), heal_drop)
	if enemy.kind == "mob_altar":
		drop_chest(enemy.position + Vector2(0, 40))
		for i in 5:
			drop_gem_at(enemy.position + Vector2.RIGHT.rotated(TAU * i / 5.0) * 80.0, 10)
		combo_pop(enemy.position + Vector2(0, -90), "АЛТАРЬ РАЗРУШЕН!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.4))
		shake(10.0)
		return
	# Усиленная волна: сундук один на всю волну — с последнего её врага
	if enemy.has_meta("wave"):
		var wid: int = enemy.get_meta("wave")
		_wave_left[wid] = int(_wave_left.get(wid, 1)) - 1
		if int(_wave_left[wid]) <= 0:
			_wave_left.erase(wid)
			drop_chest(enemy.position)
			combo_pop(enemy.position + Vector2(0, -90), "ВОЛНА ОТБИТА!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.4))
			shake(8.0)
		return
	if enemy.is_elite and not enemy.is_boss:
		if rng.randf() < 0.5 + Meta.run_mods()["chest"] + player.chest_bonus:
			drop_chest(enemy.position)
		for i in 3:
			_drop_gem(enemy.position + Vector2(rng.randf_range(-50, 50), rng.randf_range(-40, 40)), 10, false)
		shake(10.0)
		screen_flash(0.25)


var _gem_rr := 0
## Слияние кристаллов: несколько одинаковых рядом (и ещё не летящих к герою)
## превращаются в один кристалл следующей ступени: синие → зелёный → жёлтый → красный.
const GEM_MERGE_COUNT := 4
var _gem_merge_t := 0.0
func _merge_gems(delta: float) -> void:
	_gem_merge_t -= delta
	if _gem_merge_t > 0.0 or net_mode == "client":
		return
	_gem_merge_t = 0.4
	# Кристаллы по ступеням; мега-кристаллы сразу втягивают всё вокруг
	var by_tier := {0: [], 1: [], 2: [], 3: []}
	for g in gems_node.get_children():
		if g.get_script() != GemScript or g.kind != "xp" or g._attracted or g.is_queued_for_deletion():
			continue
		if g.tier >= 4:
			_absorb_into(g)
			continue
		by_tier[maxi(g.tier, 0)].append(g)
	# Слияние: рядом (в радиусе) лежит достаточно одинаковых — один кристалл ступенью выше
	for tr in by_tier:
		var arr: Array = by_tier[tr]
		var need := 3 if tr == 3 else GEM_MERGE_COUNT   # красных достаточно трёх
		var used := {}
		for g in arr:
			if used.has(g) or g.is_queued_for_deletion():
				continue
			var group: Array = [g]
			for h in arr:
				if h != g and not used.has(h) and not h.is_queued_for_deletion() and h.position.distance_to(g.position) < 140.0:
					group.append(h)
					if group.size() >= need:
						break
			if group.size() < need:
				continue
			for x in group:
				used[x] = true
			_merge_group(group)


func _merge_group(group: Array) -> void:
	var keep: Node2D = group[0]
	var sum := 0
	var c := Vector2.ZERO
	for g in group:
		sum += int(g.value)
		c += g.position
	c /= float(group.size())
	for g in group:
		if g != keep:
			Fx.burst(self, g.position + Vector2(0, -10), [Pixel.hdr(Color.WHITE, 1.6), Color(1, 1, 1, 0.0)], 3, 60.0, 0.25, 2.0)
			g.queue_free()
	keep.value = sum
	keep.tier = mini(int(keep.tier) + 1, 4)
	keep.position = c
	keep.refresh_look()
	Fx.ring(self, c, 4.0, 40.0, Pixel.hdr(keep._color, 1.8), 0.3, 2.0)
	if keep.tier == 4:
		_megas.append(keep)
		Fx.ring(self, c, 10.0, MEGA_RADIUS, Pixel.hdr(Color(1.0, 0.45, 0.3), 1.6), 0.6, 4.0)
		Fx.text_pop(self, c + Vector2(0, -40), "МЕГА-КРИСТАЛЛ", Pixel.hdr(Color(1.0, 0.5, 0.3), 1.6), 18)


## Мега-кристаллы (из нескольких красных): впитывают все кристаллы рядом,
## в том числе только что выпавшие, и копят весь их опыт.
const MEGA_RADIUS := 300.0
var _megas: Array = []


func _mega_near(pos: Vector2) -> Node2D:
	for m in _megas:
		if is_instance_valid(m) and not m.is_queued_for_deletion() and not m._attracted and m.position.distance_to(pos) < MEGA_RADIUS:
			return m
	return null


## Втянуть лежащие рядом кристаллы в мега-кристалл.
func _absorb_into(mega: Node2D) -> void:
	for g in gems_node.get_children():
		if g == mega or g.get_script() != GemScript or g.kind != "xp" or g._attracted or g.is_queued_for_deletion():
			continue
		if g.position.distance_to(mega.position) < MEGA_RADIUS:
			mega.value += int(g.value)
			mega.absorb_fx(g.position)
			g.queue_free()


func _drop_gem(pos: Vector2, value: int, heal: bool) -> void:
	_megas = _megas.filter(func(m): return is_instance_valid(m) and not m.is_queued_for_deletion())
	if not heal and net_mode != "client":
		var mega := _mega_near(pos)
		if mega:
			mega.value += value
			mega.absorb_fx(pos)
			return
	# Слишком много кристаллов на земле — самый дальний забытый кристалл переносим
	# к месту выпадения и прибавляем ему опыт: кристаллы всегда падают там, где убит враг
	if not heal and gems_node.get_child_count() > (70 if Settings.is_mobile() else 130):
		# Быстро: проверяем несколько кристаллов по кругу и берём самый дальний из них
		var far: Node2D = null
		var far_d := 0.0
		var n := gems_node.get_child_count()
		for k in 12:
			_gem_rr = (_gem_rr + 1) % n
			var g = gems_node.get_child(_gem_rr)
			if g.get_script() != GemScript or g.kind != "xp" or g._attracted or g.is_queued_for_deletion():
				continue
			var d: float = g.position.distance_squared_to(center())
			if d > far_d:
				far_d = d
				far = g
		if far:
			far.value += value
			far.position = pos
			far.refresh_look()
			return
	var gem := GemScript.new()
	gem.main = self
	gem.player = player
	gem.position = pos
	gem.value = value
	gem.kind = "heal" if heal else "xp"
	gems_node.add_child(gem)


# ---------- Боссы и сундуки ----------

# ---------- Точки интереса: алтари ----------

var pois: Array = []          # алтари на поле (и алтари мобов — они враги)
var _poi_t := 35.0


func pick_enemy_kind() -> String:
	return _pick_enemy_kind()


# ---------- Маяки: столбы света над точками интереса и сундуками ----------

var _beacons := {}   # anchor -> Node3D
var _beacon_t := 0.0


func _beacon_targets() -> Array:
	var out: Array = []
	for p in pois:
		if is_instance_valid(p) and p.get("state") != "done" and p.get("dead") != true:
			out.append([p, p.color() if p.has_method("color") else Color(1.0, 0.3, 0.35)])
	for c in get_tree().get_nodes_in_group("chests"):
		if is_instance_valid(c):
			out.append([c, Color(1.0, 0.78, 0.3)])
	return out


func _make_beacon(col: Color) -> Node3D:
	var root := Node3D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 1.0))
	grad.add_point(0.75, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_texture = gt
	m.albedo_color = Pixel.hdr(col, 1.6)
	var H := 9.0
	for k in 2:
		var cyl := CylinderMesh.new()
		cyl.height = H
		cyl.top_radius = 0.08 if k == 0 else 0.32
		cyl.bottom_radius = 0.14 if k == 0 else 0.42
		cyl.radial_segments = 10
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		var mk: StandardMaterial3D = m.duplicate()
		if k == 1:
			mk.albedo_color = Color(Pixel.hdr(col, 1.0), 0.45)
		mi.material_override = mk
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = H / 2.0
		root.add_child(mi)
	# Пульсирующее кольцо у земли
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.75
	tor.outer_radius = 0.9
	tor.rings = 24
	tor.ring_segments = 6
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(Pixel.hdr(col, 1.8), 0.8)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.05
	ring.name = "Ring"
	root.add_child(ring)
	return root


func _update_beacons(delta: float) -> void:
	if _mirror_root == null:
		return
	_beacon_t += delta
	var live := {}
	for t in _beacon_targets():
		var a: Node2D = t[0]
		live[a] = true
		var b: Node3D = _beacons.get(a)
		if b == null:
			b = _make_beacon(t[1])
			_mirror_root.add_child(b)
			_beacons[a] = b
		b.position = _bl(a.position, 0.0)
		var ring: Node3D = b.get_node("Ring")
		var k := fmod(_beacon_t * 0.8 + float(a.get_instance_id() % 7) * 0.13, 1.0)
		ring.scale = Vector3.ONE * (0.6 + k * 1.4)
		(ring as MeshInstance3D).transparency = k
	for a in _beacons.keys():
		if not live.has(a):
			var b: Node3D = _beacons[a]
			if is_instance_valid(b):
				b.queue_free()
			_beacons.erase(a)


func place3d(n: Node3D, pos: Vector2) -> void:
	n.position = _bl(pos, 0.0)
	_mirror_root.add_child(n)


func apply_buff(p: Node2D, kind: String, t: float) -> void:
	p.add_buff(kind, t)


var _qpoi_t := 22.0


## Места для заданий: тайники, рунные загадки, маяки. Нужные заданиям появляются чаще.
func _handle_quest_pois(delta: float) -> void:
	_qpoi_t -= delta
	if _qpoi_t > 0.0 or boss != null:
		return
	var have := {"cache": 0, "puzzle": 0, "beacons": 0}
	for p in pois:
		if is_instance_valid(p) and p.get_script() == QuestPoiScript:
			have[p.kind] += 1
	var weights := {"cache": 3.0 if quest_wants("caches") else 1.2, "puzzle": 3.0 if quest_wants("puzzles") else 0.6,
		"beacons": 3.0 if quest_wants("beacons") else 0.6}
	var cap := {"cache": 2, "puzzle": 1, "beacons": 1}
	var sum := 0.0
	for k in weights:
		if have[k] >= cap[k]:
			weights[k] = 0.0
		sum += weights[k]
	_qpoi_t = rng.randf_range(30.0, 50.0) * (0.7 if (quest_wants("caches") or quest_wants("puzzles") or quest_wants("beacons")) else 1.0)
	if sum <= 0.0:
		return
	var r := rng.randf() * sum
	var kind := "cache"
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			kind = k
			break
	var c := view_center()
	var pos := c
	var dist := rng.randf_range(900.0, 1300.0) if kind == "cache" else rng.randf_range(700.0, 1000.0)
	for tries in 10:
		pos = c + Vector2.RIGHT.rotated(rng.randf() * TAU) * dist
		if ground_node == null or ground_node.is_free(pos, 300.0 if kind == "puzzle" else 110.0):
			break
	var q := QuestPoiScript.new()
	q.main = self
	q.kind = kind
	q.position = pos
	enemies_node.get_parent().add_child(q)
	pois.append(q)


func _handle_pois(delta: float) -> void:
	pois = pois.filter(func(x): return is_instance_valid(x) and not (x.get("dead") == true))
	if net_mode != "client":
		_handle_quest_pois(delta)
	_poi_t -= delta
	if _poi_t > 0.0 or pois.size() >= 2 or boss != null:
		return
	_poi_t = rng.randf_range(40.0, 65.0)
	# Место: в стороне от героя, но недалеко, и не внутри построек
	var c := view_center()
	var pos := c
	for tries in 8:
		pos = c + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(650.0, 950.0)
		if ground_node == null or ground_node.is_free(pos, 110.0):
			break
	var roll := rng.randf()
	if roll < 0.3:
		_spawn_mob_altar(pos)
		return
	var poi := PoiScript.new()
	poi.main = self
	poi.kind = "power" if roll < 0.6 else ("trial" if roll < 0.85 else "spring")
	poi.position = pos
	enemies_node.get_parent().add_child(poi)
	pois.append(poi)


## Алтарь мобов: разрушаемый обелиск, призывает врагов, пока цел. За разрушение — сундук.
func _spawn_mob_altar(pos: Vector2) -> void:
	spawn_enemy("mob_altar", pos)
	var a: Node2D = enemies_node.get_child(enemies_node.get_child_count() - 1)
	a.max_hp = 260.0 * float(level["hp"]) * (1.0 + time_alive / 90.0) * (1.0 + 0.5 * endless_min)
	a.hp = a.max_hp
	pois.append(a)
	Fx.text_pop(self, pos + Vector2(0, -120), "✦ АЛТАРЬ МОБОВ — РАЗРУШЬТЕ ЕГО ✦", Pixel.hdr(Color(1.0, 0.25, 0.3), 1.5), 22)


func _handle_bosses() -> void:
	var list: Array = level["bosses"]
	if boss != null or _boss_i >= list.size():
		return
	if time_alive < list[_boss_i][0]:
		return
	var kind: String = list[_boss_i][1]
	_boss_i += 1
	_spawn_boss(kind)


func _spawn_boss(kind: String, is_super := false) -> void:
	var info: Dictionary = Data.BOSS_TYPES[kind]
	var b := BossScript.new()
	b.main = self
	b.player = player
	b.kind = kind
	b.boss_name = info["name"]
	# Боссы — настоящее испытание: очень плотные и крепнут вместе с боем
	b.max_hp = info["hp"] * 2.2 * (0.7 + 0.3 * float(level["hp"])) * (1.0 + time_alive / 300.0) * (1.0 + 0.35 * endless_min) * (3.0 if is_super else 1.0)
	b.is_super = is_super
	if is_super:
		b.boss_name = "★ СУПЕР-" + info["name"] + " ★"
		b.size_mult = 1.35
	b.hp = b.max_hp
	b.speed = info["speed"]
	b.damage = info["damage"] * 1.35 * (1.0 + time_alive / 600.0) * (1.4 if is_super else 1.0)
	b.radius = info["radius"] * (1.35 if is_super else 1.0)
	b.color = info["color"].lerp(Color(1.0, 0.85, 0.3), 0.35) if is_super else info["color"]
	b.xp_value = 60
	b.position = center() + Vector2.RIGHT.rotated(rng.randf() * TAU) * 380.0
	enemies_node.add_child(b)
	boss = b
	Sound.play("siren", 0.0)
	Sound.set_track("boss")
	shake(10.0)
	Fx.text_pop(self, center() + Vector2(0, -80), "⚠ " + b.boss_name + " ⚠", Pixel.hdr(b.color, 1.6), 34)
	hud.show_boss(b.boss_name, b.color)


func on_boss_killed(b: Node2D) -> void:
	boss = null
	bosses_killed += 1
	hud.hide_boss()
	drop_chest(b.position)
	for i in 12:
		_drop_gem(b.position + Vector2(rng.randf_range(-80, 80), rng.randf_range(-60, 60)), 5, i == 0)
	shake(16.0)
	screen_flash(0.5)
	Fx.text_pop(self, b.position + Vector2(0, -40), "БОСС ПОВЕРЖЕН", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.6), 34)
	Sound.set_track("battle")


## Материал для базы на земле (подбирается как кристалл).
func drop_material(pos: Vector2, kind: String, value: int) -> void:
	if net_mode == "client" or value <= 0:
		return
	var gem := GemScript.new()
	gem.main = self
	gem.player = player
	gem.position = pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-8, 8))
	gem.value = value
	gem.kind = kind
	gems_node.add_child(gem)


func add_material(kind: String, value: int, at: Vector2) -> void:
	run["mat_" + kind] = int(run.get("mat_" + kind, 0)) + value
	if kind == "scrap":
		run["scrap"] = int(run["scrap"]) + value
	var m: Dictionary = Meta.MATERIALS[kind]
	Fx.text_pop(self, at + Vector2(0, -26), "+%d %s %s" % [value, m["icon"], m["name"]], Pixel.hdr(m["color"], 1.3), 15)
	Sound.play("gem", -6.0, 1.3)
	if net_mode == "host":
		Net.fx("mat", [kind, value])


## Счётчики забега, которые считаются по ходу (раз в полсекунды) — для заданий и подсказок.
func _run_tick(delta: float) -> void:
	_streak_t -= delta
	var me: Node2D = player
	if _last_hp >= 0.0 and me.hp < _last_hp - 0.01:
		_nodmg_t = 0.0
	_last_hp = me.hp
	_nodmg_t += delta
	run["nodmg"] = maxi(int(run["nodmg"]), int(_nodmg_t))
	_run_sync_t -= delta
	if _run_sync_t > 0.0:
		return
	_run_sync_t = 0.5
	run["kills"] = kills
	run["reactions"] = reactions_count
	run["boss"] = bosses_killed
	run["minutes"] = int(time_alive / 60.0)
	run["level"] = int(player.level)
	run["fusions"] = player.fusions.size()
	_check_quests()


var _quest_done := {}


## Задание выполнено прямо в бою — сообщаем сразу (награда — по итогам вылазки).
func _check_quests() -> void:
	for i in active_quests.size():
		var q: Dictionary = active_quests[i]
		if _quest_done.has(i):
			continue
		if QuestsScript.done(q, run):
			_quest_done[i] = true
			Sound.play("levelup", -2.0, 1.2)
			screen_flash(0.15)
			Fx.text_pop(self, player.position + Vector2(0, -120), "ЗАДАНИЕ ВЫПОЛНЕНО: " + QuestsScript.title(q).to_upper(), Pixel.hdr(Color(1.0, 0.85, 0.3), 1.6), 24)


## Нужно ли заданиям это место на карте — тогда оно появляется чаще и раньше.
func quest_wants(k: String) -> bool:
	for q in active_quests:
		if q["k"] == k and not QuestsScript.done(q, run):
			return true
	return false


func run_for_meta() -> Dictionary:
	var r := run.duplicate(true)
	r["weapons"] = player.weapons.keys()
	r["modules"] = player.passives.keys()
	return r


func drop_chest(pos: Vector2) -> void:
	if net_mode == "client":
		return
	var c := ChestScript.new()
	c.main = self
	c.player = player
	c.position = pos
	gems_node.add_child(c)


func drop_gem_at(pos: Vector2, value: int) -> void:
	if net_mode == "client":
		return   # кристаллы и сундуки появляются только у хоста
	_drop_gem(pos, value, false)


## Аспект оружия (один раз, на 6 уровне): до трёх вариантов — модули оружия игрока,
## которые не заняты аспектом другого оружия.
func _evo_choices(player: Node2D) -> Array:
	while not player.aspect_due.is_empty():
		var id: String = player.aspect_due[0]
		var mods: Array = player.aspect_options(id)
		if mods.is_empty() or not player.evolved.get(id, []).is_empty():
			player.aspect_due.pop_front()  # нет свободных модулей — аспект пропускается насовсем
			continue
		var out: Array = []
		for m in mods:
			out.append({"type": "evo", "id": id, "module": m, "new": true, "level": 0,
				"title": "Аспект «%s»" % Data.ASPECTS[m]["name"], "desc": Data.ASPECTS[m]["desc"],
				"hint": "%s ур. %d — единственный аспект оружия\nот модуля «%s» • другому оружию он уже не достанется" % [Data.WEAPONS[id]["name"], player.weapons[id], Data.PASSIVES[m]["name"]]})
		return out
	return []


## Слияние: как только два оружия достигли 10 уровня — выбор, каким будет новое оружие.
func _fusion_choices(player: Node2D) -> Array:
	var pairs: Array = player.fusion_pairs()
	if pairs.is_empty():
		return []
	var a: String = pairs[0][0]
	var b: String = pairs[0][1]
	var out: Array = []
	for pr in [[a, b], [b, a]]:
		var base: String = pr[0]
		var other: String = pr[1]
		out.append({"type": "fusion", "id": base, "partner": other, "new": true, "level": 0,
			"title": Data.fused_name(base, other),
			"desc": "Атакует как «%s», а её удары выпускают атаку «%s» прямо из точки попадания.\nХарактеристики обоих складываются и делятся пополам, аспекты и стихии суммируются." % [Data.WEAPONS[base]["name"], Data.WEAPONS[other]["name"]],
			"hint": "Стихии: %s + %s  •  занимает один слот  •  слияние %d из %d" % [Data.STATUSES[Data.WEAPONS[base]["status"]]["name"], Data.STATUSES[Data.WEAPONS[other]["status"]]["name"], player.fusions.size() + 1, Data.MAX_FUSIONS]})
	return out


func open_chest(opener: Node2D = null) -> void:
	var player: Node2D = opener if opener != null else self.player
	Sound.play("chest", 0.0)
	var rewards: Array = []
	# Аспекты теперь выбираются при повышении уровня оружия, не в сундуке
	var evo: Array = []
	if not evo.is_empty():
		Sound.play("evolve", 0.0)
		get_tree().paused = true
		_chooser = player
		var et: String = _who(player) + "АСПЕКТ ОРУЖИЯ: " + Data.WEAPONS[evo[0]["id"]]["name"].to_upper()
		if net_mode == "host":
			get_tree().paused = false
			_net_show_offer(player, evo, et, "выберите аспект — он усилит это оружие")
			return
		hud.show_level_up(evo, et, "выберите аспект — он усилит это оружие")
		return
	# 2) иначе — до трёх улучшений того, что уже есть
	if rewards.is_empty():
		var pool: Array = []
		for id in player.weapons:
			if player.weapons[id] < Data.MAX_WEAPON_LEVEL:
				pool.append(["weapon", id])
		for id in player.passives:
			if player.passives[id] < Data.MAX_PASSIVE_LEVEL:
				pool.append(["passive", id])
		pool.shuffle()
		var n := mini(pool.size(), rng.randi_range(1, 3))
		for i in n:
			var t: String = pool[i][0]
			var id: String = pool[i][1]
			if t == "weapon":
				player.add_weapon(id)
				rewards.append({"type": "weapon", "id": id, "title": Data.WEAPONS[id]["name"], "desc": "Уровень %d" % player.weapons[id]})
			else:
				player.add_passive(id)
				rewards.append({"type": "passive", "id": id, "title": Data.PASSIVES[id]["name"], "desc": "Уровень %d" % player.passives[id]})
	if rewards.is_empty():
		player.heal(50.0)
		rewards.append({"type": "heal", "id": "heal", "title": "Нано-аптечка", "desc": "+50 здоровья"})
	if net_mode == "host":
		# Сетевая игра: окно сундука только у того, кто открыл, мир не останавливается
		if player == players[1]:
			Net.event("chest", rewards)
			_net_next_offer(player)
		else:
			hud.show_chest(rewards)
		return
	get_tree().paused = true
	hud.show_chest(rewards)


func close_chest() -> void:
	hud.hide_chest()
	if net_mode == "host":
		_net_next_offer(players[0])
		return
	if net_mode != "":
		return
	if true:
		_show_next_level_up()
	else:
		get_tree().paused = false


# ---------- Уровни ----------

func _who(p: Node2D) -> String:
	if not coop:
		return ""
	return "ИГРОК %d — " % (p.pid + 1)


func queue_level_up(p: Node2D = null) -> void:
	if p == null:
		p = player
	Sound.play("levelup", -2.0)
	Fx.text_pop(self, p.position, _who(p) + "УРОВЕНЬ %d" % p.level, Pixel.hdr(Color(1.0, 0.85, 0.3), 1.6), 30)
	Fx.ring(self, p.position, 10.0, 220.0, Pixel.hdr(Color(1.0, 0.8, 0.3), 2.0), 0.6, 6.0)
	if net_mode == "host":
		# Сетевая игра: мир не останавливается, выбирающий герой неуязвим
		p.pending_lv += 1
		_net_next_offer(p)
		return
	pending_level_ups += 1
	_choosers.append(p)
	Fx.burst(self, p.position, [Pixel.hdr(Color(1.0, 0.9, 0.4), 2.0), Pixel.hdr(Color(1.0, 0.4, 0.8), 1.5), Color(0.5, 0.2, 1.0, 0.0)],
		40, 380.0, 0.9, 4.0)
	screen_flash(0.2)
	if not get_tree().paused and not hud.is_modal_open():
		_show_next_level_up()


func _show_next_level_up() -> void:
	# Сначала — положенный аспект оружия (6 уровень) и слияние (два оружия 10 уровня)
	for p in players:
		var asp := _evo_choices(p)
		if not asp.is_empty():
			get_tree().paused = true
			_chooser = p
			hud.show_level_up(asp, _who(p) + "АСПЕКТ ОРУЖИЯ: " + Data.WEAPONS[asp[0]["id"]]["name"].to_upper(), "один аспект на оружие — выбранный модуль другому оружию уже не достанется")
			return
		var fu := _fusion_choices(p)
		if not fu.is_empty():
			get_tree().paused = true
			_chooser = p
			hud.show_level_up(fu, _who(p) + "СЛИЯНИЕ ОРУЖИЯ", "выберите, каким станет новое оружие")
			return
	if _choosers.is_empty():
		pending_level_ups = 0
		get_tree().paused = false
		return
	get_tree().paused = true
	_chooser = _choosers[0]
	var ch := _build_choices(_chooser)
	var title := _who(_chooser) + "ПОВЫШЕНИЕ УРОВНЯ"
	var sub := ("выберите улучшение  •  " + Settings.key("pick") if not coop else "выбирает игрок %d" % (_chooser.pid + 1))
	if net_mode == "host":
		_net_offer(ch, title, sub)
		return
	hud.show_level_up(ch, title, sub)


const STAT_NAMES := {"damage": "Урон", "cooldown": "Перезарядка, с", "count": "Количество", "pierce": "Пробивание",
	"radius": "Радиус", "range": "Дальность", "length": "Длина", "strikes": "Удары", "beams": "Лучи",
	"interval": "Интервал, с", "duration": "Длительность, с", "tick": "Такт, с", "speed": "Скорость снаряда"}


func _fmt_stat(v) -> String:
	if v is int:
		return str(v)
	var f := float(v)
	if f >= 20.0:
		return str(int(round(f)))
	return ("%.1f" % f) if absf(f * 10.0 - round(f * 10.0)) < 0.01 else ("%.2f" % f)


## Краткие характеристики нового оружия для карточки.
func _weapon_stat_line(id: String) -> String:
	var s := Data.weapon_stats(id, 1, false)
	var parts: Array = []
	for k in STAT_NAMES:
		if s.has(k) and (s[k] is float or s[k] is int) and float(s[k]) > 0.0 and parts.size() < 4:
			parts.append("%s: %s" % [STAT_NAMES[k], _fmt_stat(s[k])])
	return "\n".join(parts)


## Что улучшится при переходе оружия на следующий уровень.
func _weapon_upgrade_text(id: String, from: int, to: int) -> String:
	var a := Data.weapon_stats(id, from, false)
	var b := Data.weapon_stats(id, to, false)
	var lines: Array = []
	for k in STAT_NAMES:
		if a.has(k) and b.has(k) and (a[k] is float or a[k] is int):
			if absf(float(b[k]) - float(a[k])) > 0.001:
				lines.append("%s: %s → %s" % [STAT_NAMES[k], _fmt_stat(a[k]), _fmt_stat(b[k])])
	for k in b:
		if not a.has(k) or (b[k] is bool and b[k] != a.get(k)):
			if b[k] is bool and b[k]:
				lines.append("+ новый эффект")
	if lines.is_empty():
		return "Усиление уровня"
	return "\n".join(lines)


func _build_choices(player: Node2D) -> Array:
	var pool: Array = []
	var full: bool = player.weapon_slots() >= Data.MAX_WEAPONS
	for id in Data.WEAPONS:
		var lvl: int = player.weapons.get(id, 0)
		if lvl == 0 and full:
			continue
		if lvl < Data.MAX_WEAPON_LEVEL:
			var w: Dictionary = Data.WEAPONS[id]
			var evo_p: String = Data.PASSIVES[w["evo_with"]]["name"]
			if lvl == 0:
				# Первое появление: что это за оружие, его характеристики и эффекты
				pool.append({"type": "weapon", "id": id, "new": true, "level": 1,
					"title": w["name"], "desc": w["desc"] + "\n\n" + _weapon_stat_line(id),
					"hint": Data.catalyst_text(id) + "\nСтихия: " + Data.STATUSES[w["status"]]["name"] + "  •  аспект на ур. 6"})
			else:
				# Дальше — только то, что улучшится
				var up := _weapon_upgrade_text(id, lvl, lvl + 1)
				var hint := ""
				if lvl + 1 == Data.ASPECT_LEVEL and player.evolved.get(id, []).is_empty() and player.has_aspect_module(id):
					hint = "+ выбор аспекта (один на оружие)"
				elif lvl + 1 == Data.MAX_WEAPON_LEVEL:
					hint = "10 ур.: сольётся с другим оружием 10 ур."
				pool.append({"type": "weapon", "id": id, "new": false, "level": lvl + 1,
					"title": w["name"], "desc": up, "hint": hint})
	for id in Data.PASSIVES:
		var lvl: int = player.passives.get(id, 0)
		var pk: String = Data.PASSIVES[id]["kind"]
		if lvl == 0 and player.module_count(pk) >= Data.module_cap(pk):
			continue
		if lvl < Data.MAX_PASSIVE_LEVEL:
			var p: Dictionary = Data.PASSIVES[id]
			var evo_for := ""
			for wid in Data.WEAPONS:
				if Data.WEAPONS[wid]["evo_with"] == id:
					evo_for = Data.WEAPONS[wid]["name"]
			pool.append({"type": "passive", "id": id, "new": lvl == 0, "level": lvl + 1,
				"title": p["name"], "desc": p["desc"],
				"hint": "Действует только на героя" if p["kind"] == "hero" else "Только на оружие  •  аспект «%s»" % Data.ASPECTS[id]["name"]})
	# Взвешенный случайный порядок: модули с узлом «Знакомый сигнал» выпадают вдвое чаще
	for c in pool:
		var w := 2.0 if (c["type"] == "passive" and Meta.has_node("m:" + str(c["id"]), "favor")) else 1.0
		c["_k"] = pow(randf(), 1.0 / w)
	pool.sort_custom(func(a, b): return a["_k"] > b["_k"])
	for c in pool:
		c.erase("_k")
	var choices := pool.slice(0, 3)
	if choices.is_empty():
		choices.append({"type": "heal", "id": "heal", "new": false, "level": 0,
			"title": "Нано-аптечка", "desc": "Восстанавливает 40 здоровья", "hint": ""})
	return choices


func apply_choice(choice: Dictionary) -> void:
	if net_mode == "client":
		Net.choose(_client_choices.find(choice))
		hud.hide_level_up()
		return
	if net_mode == "host":
		_net_apply_offer(players[0], choice)
		return
	var player: Node2D = _chooser if _chooser != null and is_instance_valid(_chooser) else self.player
	match choice["type"]:
		"weapon":
			player.add_weapon(choice["id"])
		"passive":
			player.add_passive(choice["id"])
		"evo":
			player.evolve(choice["id"], choice["module"])
			Fx.text_pop(self, player.position + Vector2(0, -90), (Data.WEAPONS[choice["id"]]["name"] + ": " + choice["title"]).to_upper(), Pixel.hdr(Data.ASPECTS[choice["module"]]["color"], 1.6), 26)
			hud.hide_level_up()
			_show_next_level_up()
			return
		"fusion":
			player.fuse(choice["id"], choice["partner"])
			hud.hide_level_up()
			_show_next_level_up()
			return
		"heal":
			player.heal(40.0)
	if not _choosers.is_empty():
		_choosers.pop_front()
	pending_level_ups = _choosers.size()
	hud.hide_level_up()
	_show_next_level_up()


# ---------- Конец игры ----------

## Кооператив: один герой пал. Игра заканчивается, когда пали оба.
func on_player_down(p: Node2D) -> void:
	Sound.play("boom", 0.0, 0.8)
	shake(10.0)
	if net_mode == "client":
		return   # исход забега решает хост
	for q in players:
		if not q._dead:
			Fx.text_pop(self, p.position + Vector2(0, -70), "ИГРОК %d ПАЛ — ВСТАНЬТЕ РЯДОМ!" % (p.pid + 1), Pixel.hdr(p.player_color(), 1.5), 22)
			return
	on_player_died()


# ---------- Бесконечный режим ----------

var _final_spawned := false
var endless := false
var endless_min := 0
var _level_done := false


## Уровень пройден: завершить или остаться в бесконечном режиме.
func _offer_endless() -> void:
	Sound.play("evolve", 0.0)
	screen_flash(0.3)
	if net_mode == "client":
		return
	get_tree().paused = true
	if net_mode == "host":
		Net.event("wait", "Уровень пройден! Хост решает: завершить или продолжить...")
	hud.show_endless_choice()


func finish_level() -> void:
	hud.hide_endless_choice()
	get_tree().paused = false
	_end_game(true)


func continue_endless() -> void:
	hud.hide_endless_choice()
	endless = true
	endless_min = 0
	get_tree().paused = false
	if net_mode == "host":
		Net.event("wait_end")
	Sound.play("siren", -2.0)
	Fx.text_pop(self, view_center() + Vector2(0, -80), "∞ БЕСКОНЕЧНЫЙ РЕЖИМ ∞  •  ИДУТ АДСКИЕ МОБЫ", Pixel.hdr(Color(1.0, 0.35, 0.3), 1.6), 32)
	# Обычные мобы сгорают — дальше только адские
	for e in enemies_node.get_children():
		if not e.is_boss and not Data.ENEMIES.get(e.kind, {}).get("hell", false) and not e.dead:
			Fx.burst(self, e.position + Vector2(0, -15), [Pixel.hdr(Color(1.0, 0.5, 0.2), 2.0), Color(0.6, 0.1, 0.05, 0.0)], 4, 90.0, 0.5, 3.0)
			e.queue_free()
	screen_flash(0.3)
	shake(10.0)


## Усиленная волна каждые 2 минуты: кольцо крепких врагов со свойствами,
## с каждой волной больше и сильнее.
var _power_wave_n := 0
var _wave_left := {}   # номер волны -> сколько её врагов ещё живо
func _power_waves() -> void:
	if endless:
		return
	var due := int(time_alive / 120.0)
	if due <= _power_wave_n:
		return
	_power_wave_n = due
	var k := _power_wave_n
	var n := 18 + 6 * k
	var c := view_center()
	var kinds: Array = level["enemies"]
	var spawned: Array = []
	var before := enemies_node.get_child_count()
	for i in n:
		if enemies_node.get_child_count() >= max_enemies() + 40:
			break
		var kind: String = kinds[i % kinds.size()]
		spawn_enemy(kind, c + Vector2.RIGHT.rotated(TAU * i / n) * (Vector2(560.0, 420.0) if not portrait() else Vector2(380.0, 700.0)))
	for i in range(before, enemies_node.get_child_count()):
		var e: Node2D = enemies_node.get_child(i)
		e.max_hp *= 1.5 + 0.35 * k
		e.hp = e.max_hp
		e.damage *= 1.2 + 0.1 * k
		e.set_meta("wave", k)
		if e.affixes.is_empty():
			e.affixes.append(Data.AFFIXES.keys()[rng.randi() % Data.AFFIXES.size()])
		spawned.append(e)
	_wave_left[k] = spawned.size()
	Fx.text_pop(self, c + Vector2(0, -90), "УСИЛЕННАЯ ВОЛНА %d!" % k, Pixel.hdr(Color(1.0, 0.3, 0.5), 1.7), 32)
	Fx.ring(self, c, 40.0, 700.0, Pixel.hdr(Color(1.0, 0.3, 0.5), 1.6), 0.8, 6.0)
	Sound.play("siren", -6.0, 1.1)
	shake(8.0)


var _wave_t := 15.0
func _endless_tick() -> void:
	# Каждые 20 секунд — волна: кольцо адских мобов вокруг героя
	_wave_t -= get_process_delta_time()
	if _wave_t <= 0.0:
		_wave_t = 20.0
		var n := 20 + endless_min * 6
		var c := view_center()
		for i in n:
			if enemies_node.get_child_count() >= max_enemies():
				break
			var kinds: Array = ["hell_imp", "hell_hound", "hell_bat"]
			spawn_enemy(kinds[i % kinds.size()], c + Vector2.RIGHT.rotated(TAU * i / n) * Vector2(620.0, 480.0))
		Fx.text_pop(self, c + Vector2(0, -80), "ВОЛНА!", Pixel.hdr(Color(1.0, 0.35, 0.2), 1.6), 30)
		Sound.play("siren", -8.0, 1.3)
	var m := int((time_alive - float(level["time"])) / 60.0) + 1
	if m != endless_min:
		endless_min = m
		shake(6.0)
		Fx.text_pop(self, view_center() + Vector2(0, -80), "МИНУТА %d: адские мобы сильнее и быстрее" % m, Pixel.hdr(Color(1.0, 0.45, 0.3), 1.5), 26)
		# Каждую минуту — элитный голем, каждые 3 минуты — ещё и босс главы
		for i in mini(m, 4):
			spawn_enemy("hell_brute")
		if m % 3 == 0 and boss == null:
			var kinds: Array = Data.BOSS_TYPES.keys()
			_spawn_boss(kinds[(m / 3 - 1) % kinds.size()])


func on_player_died() -> void:
	Sound.play("boom", 2.0, 0.6)
	Fx.death(self, player.position, Color(0.3, 0.9, 1.0), true)
	Fx.death(self, player.position, Color(1.0, 0.3, 0.8), true)
	shake(14.0)
	_end_game(false)


func _end_game(victory: bool) -> void:
	if game_over:
		return
	game_over = true
	if _level_done:
		victory = true  # уровень уже пройден — гибель в бесконечном режиме не отменяет победу
	Meta.note_run(reactions_count, player.level, Data.selected_character)
	reward = Meta.finish_run(kills, time_alive, bosses_killed, victory, level_index, int(level["reward"]), endless_min, run_for_meta())
	if net_mode == "host":
		Net.event("over", [victory, time_alive, kills, player.level, reactions_count, bosses_killed])
	Sound.set_track("menu")
	if victory:
		screen_flash(0.6)
		Sound.play("evolve", 0.0)
	hud.hide_level_up()
	# Небольшая пауза, чтобы увидеть взрыв, затем экран итогов
	get_tree().create_timer(0.8).timeout.connect(func():
		get_tree().paused = true
		hud.show_game_over(victory, time_alive, kills, player.level, reactions_count))


func restart() -> void:
	if net_mode != "":
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	Loader.go("res://menu.tscn")


## Выход из забега через паузу: награда начисляется как за поражение.
func on_player_died_quit() -> void:
	if net_mode == "client":
		Net.leave()
		Data.menu_page = "net"
		to_menu()
		return
	if net_mode == "host" and not game_over:
		_end_game(false)
		return
	if not game_over:
		game_over = true
		Meta.note_run(reactions_count, player.level, Data.selected_character)
		reward = Meta.finish_run(kills, time_alive, bosses_killed, false, level_index, 0, 0, run_for_meta())
	to_hub()


func to_hub() -> void:
	if net_mode != "":
		Net.back_to_lobby()
		return
	if coop:
		Data.menu_page = "coop"
		to_menu()
		return
	get_tree().paused = false
	Loader.go("res://hub.tscn")



# ================= Сетевая игра =================

const NET_DT := 1.0 / 30.0
var _client_input
var _snap_t := 0.0
var _inv_t := 0.0
var _remote_choices: Array = []
var _client_choices: Array = []
var _puppets := {"e": {}, "p": {}, "g": {}, "z": {}, "cp": {}, "cz": {}}
var _cstate_t := 0.0


## Хост: у каждого игрока свои предложения улучшений (мир не стоит).
var _offers := [[], []]


func _net_offer(ch: Array, title: String, sub: String) -> void:
	_net_show_offer(_chooser if _chooser != null else player, ch, title, sub)


func _net_next_offer(p: Node2D) -> void:
	if not _offers[p.pid].is_empty():
		return
	var asp := _evo_choices(p)
	if not asp.is_empty():
		_net_show_offer(p, asp, "АСПЕКТ ОРУЖИЯ: " + Data.WEAPONS[asp[0]["id"]]["name"].to_upper(), "один аспект на оружие")
		return
	var fu := _fusion_choices(p)
	if not fu.is_empty():
		_net_show_offer(p, fu, "СЛИЯНИЕ ОРУЖИЯ", "выберите, каким станет новое оружие")
		return
	if p.pending_lv <= 0:
		p.choosing = false
		return
	_net_show_offer(p, _build_choices(p), "ПОВЫШЕНИЕ УРОВНЯ %d" % p.level, "выберите улучшение  •  герой неуязвим, пока вы выбираете")


func _net_show_offer(p: Node2D, ch: Array, title: String, sub: String) -> void:
	_offers[p.pid] = ch
	p.choosing = true
	if p.pid == 0:
		hud.show_level_up(ch, title, sub)
	else:
		Net.event("choices", [ch, title, sub])


func _net_apply_offer(p: Node2D, choice: Dictionary) -> void:
	match choice["type"]:
		"weapon":
			p.add_weapon(choice["id"])
		"passive":
			p.add_passive(choice["id"])
		"evo":
			p.evolve(choice["id"], choice["module"])
			Fx.text_pop(self, p.position + Vector2(0, -90), (Data.WEAPONS[choice["id"]]["name"] + ": " + choice["title"]).to_upper(), Pixel.hdr(Data.ASPECTS[choice["module"]]["color"], 1.6), 26)
		"fusion":
			p.fuse(choice["id"], choice["partner"])
		"heal":
			p.heal(40.0)
	if choice["type"] != "evo" and choice["type"] != "fusion":
		p.pending_lv = maxi(0, p.pending_lv - 1)
	_offers[p.pid] = []
	if p.pid == 0:
		hud.hide_level_up()
	p.choosing = false
	_net_next_offer(p)


func net_remote_choice(index: int) -> void:
	var off: Array = _offers[1]
	if index < 0 or index >= off.size():
		return
	_net_apply_offer(players[1], off[index])


## Хост: попадания героя клиента — урон уже посчитан у него, здесь только применяем.
func net_client_hits(h: Array) -> void:
	if players.size() < 2 or game_over:
		return
	var p2: Node2D = players[1]
	var prev_att: Node2D = attacker
	attacker = p2
	for row in h:
		var obj = instance_from_id(int(row[0]))
		if obj == null or not is_instance_valid(obj) or obj.get_parent() != enemies_node or obj.dead:
			continue
		var e: Node2D = obj
		e.last_pl = p2
		e.last_src = row[4]
		p2._src = row[4]
		var amount: float = row[1]
		if amount > 0.0 and e.can_be_hit():
			e._net_quiet = true
			e._take(amount, Color(1.0, 0.5, 0.3) if row[3] else Color(1.0, 0.95, 0.6), 18 if amount >= 30.0 else 14)
			e._net_quiet = false
		if row[2] != "" and not e.dead:
			e.apply_status(row[2])
	p2._src = ""
	attacker = prev_att


## Клиент: событие от хоста.
func net_event(kind: String, data: Variant) -> void:
	match kind:
		"p_dmg", "p_heal", "p_buff", "p_inv":
			if players.size() < 2:
				return
			var me: Node2D = players[1]
			Net.local = true
			match kind:
				"p_dmg":
					me.take_damage(float(data))
				"p_heal":
					me.heal(float(data))
				"p_buff":
					me.add_buff(data[0], float(data[1]))
				"p_inv":
					me.give_invuln(float(data))
			Net.local = false
		"choices":
			_client_choices = data[0]
			hud.hide_wait()
			hud.show_level_up(data[0], data[1], data[2])
		"wait":
			hud.show_wait(str(data))
		"wait_end":
			hud.hide_wait()
		"chest":
			hud.show_chest(data)
		"over":
			if game_over:
				return
			game_over = true
			Meta.note_run(int(data[4]), int(data[3]), Net.my_hero if Net.my_hero != "" else Data.selected_character)
			reward = Meta.finish_run(int(data[2]), float(data[1]), int(data[5]), bool(data[0]), level_index, int(level["reward"]), endless_min, run_for_meta())
			hud.hide_level_up()
			hud.hide_wait()
			hud.show_game_over(bool(data[0]), float(data[1]), int(data[2]), int(data[3]), int(data[4]))


## Связь потеряна посреди забега.
func net_lost(reason: String) -> void:
	net_mode = ""
	hud.show_wait(reason + ". Возврат в меню...")
	get_tree().paused = false
	var t := get_tree().create_timer(2.5, true)
	t.timeout.connect(func():
		Data.menu_page = "net"
		Loader.go("res://menu.tscn"))


func _net_host_tick(delta: float) -> void:
	# Состояние героя клиента: позиция, здоровье, его снаряды, зоны и эффекты
	var cs: Dictionary = Net.take_cstate()
	if not cs.is_empty() and players.size() > 1:
		var p2: Node2D = players[1]
		Net.replaying = true
		if cs.has("pl"):
			p2.net_state(cs["pl"], true)
		if cs.has("p"):
			_apply_projectiles(cs["p"], "cp", p2)
		if cs.has("z"):
			_apply_zones(cs["z"], "cz")
		for f in cs.get("fx", []):
			_replay(f[0], f[1])
		Net.replaying = false
	# Касания врагов и пули по герою клиента считаем здесь (враги настоящие тут)
	if players.size() > 1 and not players[1]._dead and not game_over:
		players[1]._check_contact()
	_snap_t -= delta
	if _snap_t > 0.0:
		return
	_snap_t = NET_DT
	Net.send_snapshot(_build_snapshot())


func _build_snapshot() -> Dictionary:
	var s := {}
	s["hud"] = [time_alive, kills, player.level, player.xp, player.xp_to_next, endless, endless_min]
	var pl: Array = []
	for p in players:
		pl.append(p.net_row())
	s["pl"] = pl
	_inv_t -= NET_DT
	if _inv_t <= 0.0:
		_inv_t = 0.5
		var inv: Array = []
		for p in players:
			inv.append([p.weapons, p.passives, p.evolved, p.fusions])
		s["inv"] = inv
	# Враги
	var e_id := PackedInt64Array()
	var e_k := PackedStringArray()
	var e_xy := PackedVector2Array()
	var e_hp := PackedFloat32Array()
	var e_st := PackedByteArray()
	for e in enemies_node.get_children():
		if e.dead:
			continue
		e_id.append(e.get_instance_id())
		e_k.append(e.kind)
		e_xy.append(e.position)
		e_hp.append(clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0))
		e_st.append(e.net_bits() | (64 if e.is_elite else 0) | (128 if e.is_boss else 0))
	s["e"] = [e_id, e_k, e_xy, e_hp, e_st]
	if boss != null and is_instance_valid(boss):
		s["boss"] = [boss.get_instance_id(), boss.boss_name, boss.hp, boss.max_hp, boss.color]
	# Снаряды (и пули врагов)
	var p_id := PackedInt64Array()
	var p_s := PackedStringArray()
	var p_xy := PackedVector2Array()
	var p_v := PackedVector2Array()
	var p_c := PackedColorArray()
	var p_r := PackedFloat32Array()
	for p in projectiles_node.get_children():
		if p.is_queued_for_deletion() or p.get("puppet") == true:
			continue   # снаряды клиента у него и так есть
		var st = p.get("style")
		p_id.append(p.get_instance_id())
		p_s.append(st if st != null else "eb")
		p_xy.append(p.position)
		p_v.append(p.velocity)
		p_c.append(p.color)
		p_r.append(p.zap_radius if st != null else p.radius)
	s["p"] = [p_id, p_s, p_xy, p_v, p_c, p_r]
	# Кристаллы и сундуки
	var g_id := PackedInt64Array()
	var g_k := PackedByteArray()
	var g_v := PackedInt32Array()
	var g_xy := PackedVector2Array()
	for g in gems_node.get_children():
		if g.is_queued_for_deletion():
			continue
		g_id.append(g.get_instance_id())
		if g.get_script() == ChestScript:
			g_k.append(2)
			g_v.append(0)
		else:
			g_k.append({"heal": 1, "scrap": 3, "chips": 4, "cores": 5}.get(g.kind, 0))
			g_v.append(g.value)
		g_xy.append(g.position)
	s["g"] = [g_id, g_k, g_v, g_xy]
	# Зоны
	var z: Array = []
	for zz in zones_node.get_children():
		if zz.is_queued_for_deletion() or zz.puppet:
			continue
		z.append([zz.get_instance_id(), zz.position, zz.radius, zz.color, 1 if zz.flask else (2 if zz.cloud else 0)])
	s["z"] = z
	s["fx"] = Net.take_fx()
	return s


func _net_client_tick(delta: float) -> void:
	var snap: Dictionary = Net.take_snapshot()
	if not snap.is_empty():
		Net.replaying = true
		net_apply(snap)
		Net.replaying = false
	# Своё состояние хосту: герой, его снаряды и зоны, эффекты (попадания уходят отдельно)
	_cstate_t -= delta
	if _cstate_t <= 0.0 and players.size() > 1:
		_cstate_t = NET_DT
		var me: Node2D = players[1]
		var p_id := PackedInt64Array()
		var p_s := PackedStringArray()
		var p_xy := PackedVector2Array()
		var p_v := PackedVector2Array()
		var p_c := PackedColorArray()
		var p_r := PackedFloat32Array()
		for p in projectiles_node.get_children():
			if p.puppet or p.is_queued_for_deletion() or p.get("style") == null:
				continue
			p_id.append(p.get_instance_id())
			p_s.append(p.style)
			p_xy.append(p.position)
			p_v.append(p.velocity)
			p_c.append(p.color)
			p_r.append(p.zap_radius)
		var z: Array = []
		for zz in zones_node.get_children():
			if zz.puppet or zz.is_queued_for_deletion():
				continue
			z.append([zz.get_instance_id(), zz.position, zz.radius, zz.color, 1 if zz.flask else (2 if zz.cloud else 0)])
		Net.send_client_state({"pl": me.net_row(), "p": [p_id, p_s, p_xy, p_v, p_c, p_r], "z": z})


## Клиент: применить снимок мира от хоста.
func net_apply(s: Dictionary) -> void:
	if net_mode != "client":
		return
	var h: Array = s["hud"]
	time_alive = h[0]
	kills = h[1]
	endless = h[5]
	endless_min = h[6]
	player.level = h[2]
	player.xp = h[3]
	player.xp_to_next = h[4]
	for i in mini(players.size(), s["pl"].size()):
		if i == 1:
			players[i].net_progress(s["pl"][i])   # свой герой: только опыт и уровень от хоста
		else:
			players[i].net_state(s["pl"][i])
	if s.has("inv"):
		for i in mini(players.size(), s["inv"].size()):
			var inv: Array = s["inv"][i]
			if i == 1:
				Net.replaying = false
				players[i].sync_owned_inventory(inv[0], inv[1], inv[2], inv[3] if inv.size() > 3 else [])
				Net.replaying = true
			else:
				players[i].net_inventory(inv[0], inv[1], inv[2])
	_apply_enemies(s["e"])
	if s.has("boss"):
		var b: Array = s["boss"]
		var node = _puppets["e"].get(b[0])
		if node != null and is_instance_valid(node):
			if boss != node:
				boss = node
				hud.show_boss(b[1], b[4])
			node.hp = b[2]
			node.max_hp = b[3]
	elif boss != null:
		boss = null
		hud.hide_boss()
	_apply_projectiles(s["p"])
	_apply_gems(s["g"])
	_apply_zones(s["z"])
	Net.replaying = true
	for f in s["fx"]:
		_replay(f[0], f[1])
	Net.replaying = false


func _sync_set(key: String, ids: Variant) -> Dictionary:
	# Удаляем то, чего больше нет у хоста
	var keep := {}
	for id in ids:
		keep[id] = true
	var d: Dictionary = _puppets[key]
	for id in d.keys():
		if not keep.has(id):
			var n = d[id]
			if is_instance_valid(n):
				n.queue_free()
			d.erase(id)
	return d


func _apply_enemies(e: Array) -> void:
	var d := _sync_set("e", e[0])
	for i in e[0].size():
		var id: int = e[0][i]
		var n = d.get(id)
		if n == null or not is_instance_valid(n):
			var kind: String = e[1][i]
			var flags: int = e[4][i]
			if flags & 128:
				n = BossScript.new()
				var bi: Dictionary = Data.BOSS_TYPES.get(kind, {})
				n.boss_name = bi.get("name", "")
				n.color = bi.get("color", Color.WHITE)
				n.radius = bi.get("radius", 40.0)
			else:
				n = EnemyScript.new()
				var info: Dictionary = Data.ENEMIES.get(kind, {})
				n.color = info.get("color", Color.WHITE)
				n.radius = info.get("radius", 12.0)
			n.max_hp = 1.0
			n.main = self
			n.kind = kind
			n.puppet = true
			n.is_elite = (flags & 64) != 0
			n.player = player
			n.hp = 1.0
			n.net_id = id
			n.position = e[2][i]
			n.net_pos = e[2][i]
			enemies_node.add_child(n)
			d[id] = n
		if n.is_boss:
			n.net_pos = e[2][i]
		else:
			n.net_state(e[2][i], e[3][i], e[4][i])


func _apply_projectiles(p: Array, key := "p", owner: Node2D = null) -> void:
	var d := _sync_set(key, p[0])
	for i in p[0].size():
		var id: int = p[0][i]
		var n = d.get(id)
		if n == null or not is_instance_valid(n):
			var st: String = p[1][i]
			if st == "eb":
				n = preload("res://scripts/enemy_bullet.gd").new()
				n.radius = p[5][i]
			else:
				n = preload("res://scripts/projectile.gd").new()
				n.style = st
				n.owner_pl = owner if owner != null else player
				n.zap_radius = p[5][i]
			n.main = self
			n.puppet = true
			n.color = p[4][i]
			n.velocity = p[3][i]
			n.position = p[2][i]
			n.net_pos = p[2][i]
			projectiles_node.add_child(n)
			d[id] = n
		n.net_pos = p[2][i]
		n.velocity = p[3][i]
		if n.get("style") == "ball":
			n.zap_radius = p[5][i]


func _apply_gems(g: Array) -> void:
	var d := _sync_set("g", g[0])
	for i in g[0].size():
		var id: int = g[0][i]
		var n = d.get(id)
		var k: int = g[1][i]
		if n == null or not is_instance_valid(n):
			if k == 2:
				n = ChestScript.new()
			else:
				n = GemScript.new()
				n.kind = {1: "heal", 3: "scrap", 4: "chips", 5: "cores"}.get(k, "xp")
				n.value = g[2][i]
				n.net_pos = g[3][i]
			n.player = player
			n.main = self
			n.puppet = true
			n.position = g[3][i]
			gems_node.add_child(n)
			d[id] = n
		if k != 2:
			n.net_pos = g[3][i]


func _apply_zones(z: Array, key := "z") -> void:
	var ids: Array = []
	for row in z:
		ids.append(row[0])
	var d := _sync_set(key, ids)
	for row in z:
		var n = d.get(row[0])
		if n == null or not is_instance_valid(n):
			n = preload("res://scripts/zone.gd").new()
			n.main = self
			n.puppet = true
			n.duration = 99999.0
			n.position = row[1]
			n.radius = row[2]
			n.color = row[3]
			n.flask = row.size() > 4 and row[4] == 1
			n.cloud = row.size() > 4 and row[4] == 2
			zones_node.add_child(n)
			d[row[0]] = n
		n.net_pos = row[1]
		n.radius = row[2]
		n.color = row[3]


## Клиент: проиграть эффект хоста.
func _replay(kind: String, a: Array) -> void:
	match kind:
		"burst":
			Fx.burst(self, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
		"number":
			Fx.number(self, a[0], a[1], a[2], a[3])
		"text_pop":
			Fx.text_pop(self, a[0], a[1], a[2], a[3])
		"ring":
			Fx.ring(self, a[0], a[1], a[2], a[3], a[4], a[5])
		"portal":
			Fx.portal(self, a[0], a[1], a[2])
		"glow_flash":
			Fx.glow_flash(self, a[0], a[1], a[2], a[3])
		"light_flash":
			Fx.light_flash(self, a[0], a[1], a[2], a[3], a[4])
		"beam3d":
			var pts := PackedVector3Array()
			for v in a[0]:
				pts.append(to3d(Vector2(v.x, v.y), v.z))
			beam3d(pts, a[1], a[2], a[3], a[4])
		"slash3d":
			var anchor: Node2D = players[a[5]] if a[5] >= 0 and a[5] < players.size() else null
			slash3d(a[0], a[1], a[2], a[3], a[4], anchor)
		"sunray":
			if a[0] < players.size():
				players[a[0]].net_sunray(a[1], a[2], a[3], a[4])
		"shake":
			shake(a[0])
		"mat":
			# Сетевая игра: материалы общие — у клиента тоже копятся
			run["mat_" + str(a[0])] = int(run.get("mat_" + str(a[0]), 0)) + int(a[1])
		"flash":
			screen_flash(a[0])
		"glitch":
			glitch_flash()
		"hurt":
			hurt_flash()
		"snd":
			Sound.play(a[0], a[1], a[2], a[3], a[4])
		"track":
			Sound.set_track(a[0], a[1] if a.size() > 1 else false, a[2] if a.size() > 2 else -1)


## 3D-точки → (x, y на земле, высота), чтобы клиент пересчитал под свою камеру.
func _to2dh(points: PackedVector3Array) -> Array:
	var c := camera.get_screen_center_position()
	var out: Array = []
	for p in points:
		out.append(Vector3((p.x - _plane.position.x) / PLANE_TEXEL + c.x, (p.z - _plane.position.z) / PLANE_TEXEL + c.y, p.y - _plane.position.y))
	return out


## Накал боя для музыки: число врагов рядом с героями, босс, мало здоровья.
var _mus_t := 0.0
func _update_music_intensity(delta: float) -> void:
	_mus_t -= delta
	if _mus_t > 0.0 or enemies_node == null:
		return
	_mus_t = 0.5
	var near := 0
	var hp_k := 1.0
	for e in enemies_node.get_children():
		for p in players:
			if is_instance_valid(p) and (e as Node2D).position.distance_squared_to(p.position) < 700.0 * 700.0:
				near += 1
				break
	for p in players:
		if is_instance_valid(p) and p.max_hp > 0.0:
			hp_k = minf(hp_k, p.hp / p.max_hp)
	var k := clampf(near / 60.0, 0.0, 0.75)
	if boss != null and is_instance_valid(boss):
		k += 0.35
	k += (1.0 - hp_k) * 0.25
	k += clampf(endless_min * 0.04, 0.0, 0.2)
	Sound.intensity_target = clampf(k, 0.0, 1.0)
