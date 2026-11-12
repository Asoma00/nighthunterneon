extends Node3D
## Декорации кат-сцен: стилизованные локации Слияния — город, где замки срослись
## с небоскрёбами, поле Врат, Неоновое убежище у костра, вершина башни Академии,
## пепельная плавильня и Цитадель Первых Врат. Своё небо, туман, свет и «живые»
## детали (огонь мерцает, кольца вращаются, порталы закручиваются).

const T := preload("res://scripts/cine_toon.gd")

var set_id := ""
var flames: Array = []      # [узел, свет, фаза]
var spinners: Array = []    # [узел, ось, скорость]
var bobbers: Array = []     # [узел, базовая высота, фаза]
var flashes: Array = []     # молнии: [свет]
var env: Environment
var key_color := Color(1.0, 0.86, 0.72)
var rim_color := Color(0.5, 0.8, 1.0)
var fill_color := Color(0.5, 0.58, 1.0)
var _t := 0.0
var _rng := RandomNumberGenerator.new()


static func make(n: String) -> Node3D:
	var s: Node3D = load("res://scripts/cine_set.gd").new()
	s.set_id = n
	s._build()
	return s


func _build() -> void:
	_rng.seed = hash(set_id)
	match set_id:
		"fusion":
			_sky(Color(0.05, 0.03, 0.14), Color(0.42, 0.18, 0.45), Color(1.0, 0.35, 0.65), 1.0, Color(0.16, 0.1, 0.25), 0.012)
			_moon(Vector3(-40, 60, -30), Color(0.75, 0.75, 1.0), 1.1)
			_ground(Color(0.2, 0.18, 0.28))
			_city(Vector3(0, 0, -30), 26, 60.0, 34.0)
			for i in 6:
				_castle(Vector3(-30 + i * 12 + _rng.randf_range(-3, 3), 0, -22 - _rng.randf_range(0, 18)), _rng.randf_range(0.8, 1.5))
			for i in 7:
				_island(Vector3(_rng.randf_range(-35, 35), _rng.randf_range(14, 26), _rng.randf_range(-60, -25)), _rng.randf_range(1.5, 3.5))
			_rim(Vector3(20, 10, -40), Color(1.0, 0.3, 0.7), 2.0)
			rim_color = Color(1.0, 0.45, 0.8)
		"gate":
			_sky(Color(0.06, 0.02, 0.1), Color(0.4, 0.1, 0.3), Color(1.0, 0.25, 0.5), 0.6, Color(0.22, 0.08, 0.2), 0.02)
			_moon(Vector3(30, 40, -30), Color(1.0, 0.6, 0.8), 0.7)
			_ground(Color(0.22, 0.16, 0.22))
			_gate(Vector3(0, 0, -16), 7.0, Color(0.6, 0.2, 1.0), Color(1.0, 0.3, 0.7))
			rim_color = Color(0.85, 0.4, 1.0)
			for i in 14:
				var a := _rng.randf_range(-1.2, 1.2)
				_rock(Vector3(sin(a) * _rng.randf_range(8, 22), 0, -16 + cos(a) * _rng.randf_range(4, 14)), _rng.randf_range(0.6, 2.0))
			_city(Vector3(0, 0, -45), 14, 70.0, 10.0, true)
		"camp":
			_sky(Color(0.03, 0.03, 0.1), Color(0.18, 0.14, 0.32), Color(0.35, 0.6, 1.0), 0.0, Color(0.1, 0.08, 0.18), 0.018)
			_moon(Vector3(-20, 50, -40), Color(0.6, 0.7, 1.0), 0.75)
			_ground(Color(0.2, 0.24, 0.22))
			_fire(Vector3(0, 0, 0))
			key_color = Color(1.0, 0.68, 0.42)
			rim_color = Color(0.45, 0.75, 1.0)
			_wall(Vector3(0, 0, -11), 26.0)
			for i in 5:
				_house(Vector3(-12 + i * 6 + _rng.randf_range(-1, 1), 0, -6.5 - _rng.randf_range(0, 2)), _rng.randf_range(0.9, 1.3))
			for i in 10:
				var side := -1.0 if i % 2 == 0 else 1.0
				_tree(Vector3(side * _rng.randf_range(9, 18), 0, _rng.randf_range(-10, 3)), _rng.randf_range(0.8, 1.3))
			for i in 6:
				_lantern(Vector3(-7 + i * 2.8, 0, -3.5))
			_gate(Vector3(10, 0, -24), 3.0, Color(0.6, 0.2, 1.0), Color(1.0, 0.3, 0.7))
			_city(Vector3(0, 0, -50), 10, 80.0, 6.0, true)
		"tower":
			_sky(Color(0.03, 0.05, 0.1), Color(0.15, 0.3, 0.4), Color(0.3, 1.0, 0.9), 0.5, Color(0.08, 0.14, 0.2), 0.01)
			_moon(Vector3(10, 30, -40), Color(0.7, 0.95, 1.0), 0.9)
			_platform(Color(0.2, 0.22, 0.3), Color(0.3, 1.0, 0.9))
			key_color = Color(0.85, 0.92, 1.0)
			rim_color = Color(0.3, 1.0, 0.9)
			for i in 3:
				var r := _node(Vector3(0, 9 + i * 3.0, -5))
				T.mi(T.torus(9.0 + i * 3.5, 9.15 + i * 3.5), T.neon(Color(0.3, 1.0, 0.9), 0.9), r, Vector3.ZERO, Vector3.ONE, Vector3(0.35 * (i - 1), 0, 0.2 * i))
				spinners.append([r, Vector3.UP, 0.08 * (1 + i) * (-1.0 if i % 2 else 1.0)])
			var lf := OmniLight3D.new()
			lf.position = Vector3(0, 20, -10)
			lf.light_color = Color(0.7, 0.9, 1.0)
			lf.light_energy = 0.0
			lf.omni_range = 80.0
			add_child(lf)
			flashes.append(lf)
			_city(Vector3(0, -30, -60), 22, 120.0, 20.0, true)
		"foundry":
			_sky(Color(0.06, 0.02, 0.02), Color(0.5, 0.18, 0.05), Color(1.0, 0.45, 0.1), 0.0, Color(0.3, 0.1, 0.05), 0.03)
			_moon(Vector3(0, 30, -40), Color(1.0, 0.6, 0.35), 0.6)
			_ground(Color(0.2, 0.15, 0.13))
			key_color = Color(1.0, 0.6, 0.35)
			rim_color = Color(1.0, 0.4, 0.15)
			fill_color = Color(0.4, 0.45, 0.8)
			for i in 4:
				var lv := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(_rng.randf_range(4, 8), _rng.randf_range(3, 6))
				lv.mesh = pm
				lv.material_override = T.lava()
				lv.position = Vector3(-10 + i * 7, 0.03, -6 - _rng.randf_range(0, 8))
				add_child(lv)
				var ol := OmniLight3D.new()
				ol.position = lv.position + Vector3(0, 1.0, 0)
				ol.light_color = Color(1.0, 0.45, 0.1)
				ol.light_energy = 2.5
				ol.omni_range = 9.0
				add_child(ol)
			for i in 6:
				_chimney(Vector3(-18 + i * 7, 0, -20 - _rng.randf_range(0, 8)))
			for i in 8:
				var ch := _node(Vector3(_rng.randf_range(-12, 12), 14, _rng.randf_range(-14, -2)))
				for j in 12:
					T.mi(T.torus(0.12, 0.2), T.mat(Color(0.3, 0.28, 0.3), 0.0, 0.6), ch, Vector3(0, -j * 0.36, 0), Vector3.ONE, Vector3(0, (j % 2) * PI / 2.0, PI / 2.0))
			_embers(Vector3(0, 0, -4), Color(1.0, 0.55, 0.15))
		"citadel":
			_sky(Color(0.02, 0.02, 0.06), Color(0.2, 0.35, 0.5), Color(0.7, 0.95, 1.0), 1.0, Color(0.12, 0.16, 0.24), 0.012)
			_moon(Vector3(0, 50, -40), Color(0.85, 0.95, 1.0), 1.0)
			_platform(Color(0.45, 0.48, 0.58), Color(0.6, 0.95, 1.0))
			key_color = Color(0.95, 0.95, 1.0)
			rim_color = Color(1.0, 0.55, 0.9)
			_gate(Vector3(0, 0, -13), 9.0, Color(0.5, 0.9, 1.0), Color(1.0, 0.5, 0.9))
			for i in 10:
				var a := TAU * i / 10.0
				_crystal(Vector3(cos(a) * 18, -2, -8 + sin(a) * 14), _rng.randf_range(2.0, 5.0))
			_city(Vector3(0, -30, -70), 22, 140.0, 24.0, true)


func _node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


# ---------- Небо, свет, земля ----------

func _sky(top: Color, hor: Color, glowc: Color, rift: float, fog: Color, fog_d: float) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = T.shader("sky")
	sm.set_shader_parameter("top", Vector3(top.r, top.g, top.b))
	sm.set_shader_parameter("hor", Vector3(hor.r, hor.g, hor.b))
	sm.set_shader_parameter("glowc", Vector3(glowc.r, glowc.g, glowc.b))
	sm.set_shader_parameter("rift", rift)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = hor.lerp(Color(0.5, 0.5, 0.7), 0.5)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = fog
	env.fog_density = fog_d
	env.fog_sky_affect = 0.15
	# Объём как в роликах: затенение в складках, переотражённый свет, лучи в дымке.
	# В вебе (Compatibility) эти эффекты недоступны — остаётся обычный туман.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 2.2
		env.ssao_detail = 0.6
		env.ssil_enabled = true
		env.ssil_intensity = 0.8
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_min_cell_size = 0.15
		env.sdfgi_energy = 0.8
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = fog_d * 1.6
		env.volumetric_fog_albedo = fog.lightened(0.5)
		env.volumetric_fog_emission = fog * 0.4
		env.volumetric_fog_anisotropy = 0.5
		env.volumetric_fog_length = 80.0
		env.fog_density = fog_d * 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.06
	we.environment = env
	add_child(we)


func _moon(pos: Vector3, c: Color, e: float) -> void:
	var d := DirectionalLight3D.new()
	d.light_color = c
	d.light_energy = e
	d.shadow_enabled = true
	d.directional_shadow_max_distance = 40.0
	d.light_volumetric_fog_energy = 2.0
	add_child(d)
	d.look_at_from_position(pos, Vector3.ZERO)
	# Тёплая заливка снизу-спереди, чтобы лица не проваливались в тень
	var f := DirectionalLight3D.new()
	f.light_color = Color(1.0, 0.8, 0.7)
	f.light_energy = 0.25
	add_child(f)
	f.look_at_from_position(Vector3(10, 4, 20), Vector3.ZERO)


func _rim(pos: Vector3, c: Color, e: float) -> void:
	var d := DirectionalLight3D.new()
	d.light_color = c
	d.light_energy = e * 0.4
	add_child(d)
	d.look_at_from_position(pos, Vector3.ZERO)


func _ground(c: Color) -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	g.mesh = pm
	g.material_override = T.mat(c, 0.0, 0.05, 0.0)
	add_child(g)
	# Россыпь камней и травы для фактуры
	for i in 60:
		var p := Vector3(_rng.randf_range(-25, 25), 0, _rng.randf_range(-25, 12))
		if p.length() < 3.0:
			continue
		T.mi(T.sphere(_rng.randf_range(0.08, 0.25), 6), T.mat(c.lightened(_rng.randf_range(0.05, 0.2))), self, p, Vector3(1, 0.5, 1))


# ---------- Постройки ----------

func _city(at: Vector3, n: int, width: float, depth: float, dark := false) -> void:
	for i in n:
		var w := _rng.randf_range(2.0, 4.5)
		var h := _rng.randf_range(6.0, 24.0)
		var p := at + Vector3(_rng.randf_range(-width * 0.5, width * 0.5), h * 0.5, _rng.randf_range(-depth * 0.5, depth * 0.5))
		var wall := Color(0.16, 0.15, 0.26) if not dark else Color(0.1, 0.08, 0.15)
		var lit: Color = [Color(1.0, 0.7, 0.3), Color(1.0, 0.45, 0.7), Color(0.4, 0.85, 1.0)][i % 3]
		var b := T.mi(T.box(w, h, w), T.windows(wall, lit, float(i) * 3.7, 0.3), self, p)
		# Неоновая вывеска на части домов
		if i % 3 == 0:
			var sc: Color = [Color(1.0, 0.3, 0.75), Color(0.3, 0.95, 1.0), Color(1.0, 0.85, 0.3)][(i / 3) % 3]
			T.mi(T.box(0.15, h * 0.3, 0.9), T.neon(sc, 3.0), b, Vector3(w * 0.5 + 0.1, h * 0.15, 0))
		# Антенны и шпили
		if i % 4 == 1:
			T.mi(T.cyl(0.03, 0.06, 3.0, 6), T.mat(Color(0.4, 0.4, 0.5)), b, Vector3(0, h * 0.5 + 1.5, 0))
			T.mi(T.sphere(0.12), T.neon(Color(1.0, 0.2, 0.3), 4.0), b, Vector3(0, h * 0.5 + 3.0, 0))


func _castle(p: Vector3, s: float) -> void:
	var stone := Color(0.42, 0.4, 0.5)
	var root := _node(p)
	root.scale = Vector3.ONE * s
	var h := _rng.randf_range(8, 14)
	T.mi(T.cyl(1.4, 1.6, h, 14), T.mat(stone), root, Vector3(0, h * 0.5, 0))
	for i in 8:
		var a := TAU * i / 8.0
		T.mi(T.box(0.5, 0.6, 0.5), T.mat(stone), root, Vector3(cos(a) * 1.45, h + 0.3, sin(a) * 1.45))
	T.mi(T.cyl(0.0, 1.8, 3.5, 14), T.mat(Color(0.35, 0.2, 0.5)), root, Vector3(0, h + 2.3, 0))
	T.mi(T.box(0.5, 0.9, 0.1), T.neon(Color(1.0, 0.75, 0.35), 2.5), root, Vector3(0, h * 0.7, 1.55))
	# Кабели и неоновые кольца — замок «сросся» с машинами
	T.mi(T.torus(1.6, 1.75), T.neon(Color(0.3, 0.95, 1.0), 2.0), root, Vector3(0, h * 0.45, 0))
	T.mi(T.box(0.2, h * 0.6, 0.2), T.mat(Color(0.25, 0.26, 0.32)), root, Vector3(1.55, h * 0.4, 0.4))


func _island(p: Vector3, s: float) -> void:
	var n := _node(p)
	T.mi(T.cyl(s, 0.2, s * 2.2, 9), T.mat(Color(0.35, 0.28, 0.32)), n, Vector3(0, -s * 1.1, 0))
	T.mi(T.cyl(s * 1.05, s, 0.4, 9), T.mat(Color(0.3, 0.5, 0.35)), n, Vector3(0, 0.1, 0))
	_tree(p + Vector3(s * 0.3, 0.2, 0), s * 0.5)
	bobbers.append([n, p.y, _rng.randf() * TAU])


func _rock(p: Vector3, s: float) -> void:
	T.mi(T.sphere(s, 7), T.mat(Color(0.3, 0.26, 0.33), 0.0, 0.1), self, p, Vector3(1.0, 0.7, 0.9), Vector3(0, _rng.randf() * TAU, 0))
	if _rng.randf() < 0.4:
		T.mi(T.sphere(s * 0.3, 4), T.neon(Color(0.8, 0.3, 1.0), 2.5), self, p + Vector3(0, s * 0.6, 0), Vector3(0.6, 1.6, 0.6))


func _tree(p: Vector3, s: float) -> void:
	var n := _node(p)
	n.scale = Vector3.ONE * s
	T.mi(T.cyl(0.15, 0.25, 2.2, 8), T.mat(Color(0.4, 0.27, 0.2)), n, Vector3(0, 1.1, 0))
	var leaf := Color(0.18, 0.42, 0.35).lerp(Color(0.35, 0.25, 0.45), _rng.randf() * 0.4)
	T.mi(T.sphere(1.2, 12), T.mat(leaf), n, Vector3(0, 2.6, 0))
	T.mi(T.sphere(0.9, 12), T.mat(leaf.lightened(0.1)), n, Vector3(0.6, 3.2, 0.2))
	T.mi(T.sphere(0.8, 12), T.mat(leaf.darkened(0.1)), n, Vector3(-0.6, 3.0, -0.2))
	if _rng.randf() < 0.5:
		T.mi(T.sphere(0.08), T.neon(Color(0.4, 1.0, 0.8), 3.0), n, Vector3(0.9, 2.5, 0.8))


func _house(p: Vector3, s: float) -> void:
	var n := _node(p)
	n.scale = Vector3.ONE * s
	T.mi(T.box(3.0, 2.2, 2.6), T.mat(Color(0.5, 0.42, 0.36)), n, Vector3(0, 1.1, 0))
	T.mi(T.prism(3.4, 1.4, 2.9), T.mat(Color(0.45, 0.22, 0.25)), n, Vector3(0, 2.9, 0))
	T.mi(T.box(0.7, 1.2, 0.08), T.mat(Color(0.3, 0.2, 0.15)), n, Vector3(0, 0.6, 1.31))
	T.mi(T.box(0.6, 0.5, 0.06), T.neon(Color(1.0, 0.75, 0.35), 2.5), n, Vector3(0.9, 1.4, 1.31))
	T.mi(T.box(3.0, 0.06, 0.06), T.neon(Color(0.3, 0.9, 1.0), 2.0), n, Vector3(0, 2.2, 1.32))


func _wall(p: Vector3, w: float) -> void:
	var n := _node(p)
	var cnt := int(w / 1.6)
	for i in cnt:
		var x := -w * 0.5 + i * 1.6
		T.mi(T.box(1.5, 3.4, 0.9), T.mat(Color(0.4, 0.42, 0.5)), n, Vector3(x, 1.7, 0))
		T.mi(T.box(1.5, 0.08, 0.1), T.neon(Color(0.4, 0.9, 1.0), 2.0), n, Vector3(x, 2.4, 0.46))
		if i % 4 == 0:
			T.mi(T.cyl(0.4, 0.5, 4.6, 8), T.mat(Color(0.35, 0.36, 0.44)), n, Vector3(x, 2.3, 0.1))
			T.mi(T.sphere(0.25), T.neon(Color(1.0, 0.6, 0.25), 3.0), n, Vector3(x, 4.8, 0.1))


func _lantern(p: Vector3) -> void:
	var n := _node(p)
	T.mi(T.cyl(0.04, 0.05, 2.2, 6), T.mat(Color(0.25, 0.22, 0.25)), n, Vector3(0, 1.1, 0))
	T.mi(T.sphere(0.16), T.neon(Color(1.0, 0.75, 0.35), 3.0), n, Vector3(0, 2.25, 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 2.2, 0)
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 0.8
	l.omni_range = 4.0
	n.add_child(l)


func _fire(p: Vector3) -> void:
	var n := _node(p)
	for i in 5:
		var a := TAU * i / 5.0
		T.mi(T.cyl(0.08, 0.08, 1.1, 6), T.mat(Color(0.35, 0.22, 0.15)), n, Vector3(cos(a) * 0.25, 0.12, sin(a) * 0.25), Vector3.ONE, Vector3(PI / 2.0 - 0.3, -a, 0))
	for i in 8:
		var a := TAU * i / 8.0
		T.mi(T.sphere(0.18, 6), T.mat(Color(0.4, 0.38, 0.42)), n, Vector3(cos(a) * 0.7, 0.08, sin(a) * 0.7))
	var fl := _node(p + Vector3(0, 0.15, 0))
	T.mi(T.cyl(0.0, 0.35, 1.0, 8), T.neon(Color(1.0, 0.45, 0.1), 3.0), fl, Vector3(0, 0.45, 0))
	T.mi(T.cyl(0.0, 0.22, 0.75, 8), T.neon(Color(1.0, 0.85, 0.35), 3.5), fl, Vector3(0.05, 0.38, 0.03))
	T.mi(T.sphere(0.9), T.halo(Color(1.0, 0.5, 0.15, 0.55), 1.5), fl, Vector3(0, 0.5, 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.0, 0)
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.6
	l.omni_range = 7.0
	l.shadow_enabled = true
	fl.add_child(l)
	flames.append([fl, l, 0.0])
	_embers(p, Color(1.0, 0.6, 0.2))


func _embers(p: Vector3, c: Color) -> void:
	var em := CPUParticles3D.new()
	em.position = p + Vector3(0, 0.6, 0)
	em.amount = 40
	em.lifetime = 3.0
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.6
	em.direction = Vector3.UP
	em.spread = 25.0
	em.gravity = Vector3(0.3, 0.6, 0)
	em.initial_velocity_min = 0.5
	em.initial_velocity_max = 1.6
	em.scale_amount_min = 0.5
	em.scale_amount_max = 1.2
	var qm := SphereMesh.new()
	qm.radius = 0.03
	qm.height = 0.06
	qm.radial_segments = 4
	qm.rings = 2
	em.mesh = qm
	em.material_override = T.neon(c, 4.0)
	add_child(em)


func _gate(p: Vector3, r: float, c1: Color, c2: Color) -> void:
	var n := _node(p + Vector3(0, r + 0.3, 0))
	T.mi(T.torus(r * 0.92, r * 1.08), T.mat(Color(0.3, 0.28, 0.36), 0.0, 0.6), n, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2.0, 0, 0))
	var ring := _node(p + Vector3(0, r + 0.3, 0.2))
	T.mi(T.torus(r * 0.86, r * 0.9), T.neon(c2, 2.5), ring, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2.0, 0, 0))
	for i in 12:
		var a := TAU * i / 12.0
		T.mi(T.box(r * 0.12, r * 0.22, 0.2), T.neon(c1, 2.5), ring, Vector3(cos(a) * r, sin(a) * r, 0.1), Vector3.ONE, Vector3(0, 0, a))
	spinners.append([ring, Vector3.BACK, 0.3])
	var disk := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(r * 1.8, r * 1.8)
	disk.mesh = qm
	disk.material_override = T.portal(c1, c2)
	disk.position = p + Vector3(0, r + 0.3, 0.05)
	add_child(disk)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, r, 2.0)
	l.light_color = c1.lerp(c2, 0.5)
	l.light_energy = 4.0
	l.omni_range = r * 4.0
	add_child(l)
	# Опоры
	for sx in [-1.0, 1.0]:
		T.mi(T.box(r * 0.3, r * 0.6, r * 0.4), T.mat(Color(0.28, 0.26, 0.34)), self, p + Vector3(sx * r * 0.85, r * 0.3, 0))


func _platform(c: Color, neon: Color) -> void:
	T.mi(T.cyl(14.0, 13.0, 1.5, 32), T.mat(c, 0.0, 0.2), self, Vector3(0, -0.75, -2))
	T.mi(T.torus(13.6, 14.0), T.neon(neon, 2.2), self, Vector3(0, 0.0, -2))
	T.mi(T.torus(5.0, 5.2), T.neon(neon, 1.8), self, Vector3(0, 0.01, -2), Vector3(1, 0.05, 1))
	for i in 10:
		var a := TAU * i / 10.0 + 0.3
		var h := _rng.randf_range(1.0, 5.0)
		if sin(a) > 0.6:
			continue   # спереди колонн нет — там ходит камера
		var pp := Vector3(cos(a) * 12.0, h * 0.5, -2 + sin(a) * 12.0)
		T.mi(T.cyl(0.55, 0.65, h, 10), T.mat(c.lightened(0.05)), self, pp)
		T.mi(T.cyl(0.7, 0.7, 0.25, 10), T.mat(c.lightened(0.15)), self, pp + Vector3(0, h * 0.5, 0))


func _chimney(p: Vector3) -> void:
	var h := _rng.randf_range(10, 20)
	T.mi(T.cyl(1.0, 1.4, h, 12), T.mat(Color(0.3, 0.22, 0.2)), self, p + Vector3(0, h * 0.5, 0))
	T.mi(T.torus(1.0, 1.2), T.neon(Color(1.0, 0.45, 0.1), 2.5), self, p + Vector3(0, h, 0))
	T.mi(T.sphere(1.6), T.halo(Color(1.0, 0.4, 0.1, 0.4), 1.2), self, p + Vector3(0, h + 0.5, 0))


func _crystal(p: Vector3, s: float) -> void:
	var n := _node(p)
	T.mi(T.cyl(0.0, s * 0.35, s * 2.4, 6), T.glass(Color(0.55, 0.9, 1.0, 0.55), 0.9), n, Vector3(0, s * 1.2, 0))
	T.mi(T.cyl(0.0, s * 0.2, s * 1.4, 6), T.neon(Color(0.7, 0.95, 1.0), 1.5), n, Vector3(0, s * 0.8, 0))
	bobbers.append([n, p.y, _rng.randf() * TAU])


# ---------- Жизнь декораций ----------

func _process(delta: float) -> void:
	_t += delta
	for f in flames:
		var n: Node3D = f[0]
		var l: OmniLight3D = f[1]
		var k := 1.0 + sin(_t * 17.0) * 0.06 + sin(_t * 7.3) * 0.08
		n.scale = Vector3(1.0 / sqrt(k), k, 1.0 / sqrt(k))
		l.light_energy = 1.6 * k
	for s in spinners:
		(s[0] as Node3D).rotate(s[1], float(s[2]) * delta)
	for b in bobbers:
		(b[0] as Node3D).position.y = float(b[1]) + sin(_t * 0.8 + float(b[2])) * 0.5
	for l in flashes:
		var ph := fmod(_t, 4.3)
		(l as OmniLight3D).light_energy = 6.0 if (ph < 0.08 or (ph > 0.18 and ph < 0.24)) else 0.0
