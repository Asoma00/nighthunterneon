extends RefCounted
## Объёмные 3D-модели объектов поля боя (дома, башни, стены, деревья, кристаллы...).
## Размеры в единицах 3D-сцены боя: 1 единица = 100 пикселей мира.

const Pixel := preload("res://scripts/pixel.gd")

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.75, 0.35)
const PURPLE := Color(0.7, 0.4, 1.0)
const GREEN := Color(0.4, 1.0, 0.5)

static var _mats := {}
static var _meshes := {}

## Какие объекты строятся в 3D (остальные — спрайты).
const KINDS := ["house0", "house1", "house2", "tower0", "wall0", "gate0", "stall0", "stall1", "well0",
	"lantern0", "lamp0", "lamp1", "sign0", "sign1", "banner0", "banner1", "pillar0", "pillar1",
	"obelisk0", "obelisk1", "obelisk2", "crate0", "crate1", "barrel0", "barrel1", "cart0", "fence0",
	"wreck0", "wreck1", "rock0", "rock1", "crystal0", "crystal1", "crystal_big0", "crystal_big1",
	"pine0", "pine1", "tree0", "tree1", "tree2", "bush0", "bush1", "mushroom0", "mushroom1"]
## Деревья, кусты и грибы рисуются пиксель-артом (спрайты), а не 3D-моделями.
const PIXEL_KINDS := ["pine0", "pine1", "pine2", "tree0", "tree1", "tree2", "tree3", "bush0", "bush1", "mushroom0", "mushroom1"]


static func supports(kind: String) -> bool:
	return kind in KINDS and not (kind in PIXEL_KINDS)


# ---------- Материалы и меши (кэш, чтобы не плодить копии) ----------

static func mat(color: Color, surface := "panel", tile := 1.6, rough := 0.85) -> StandardMaterial3D:
	var key := "m%s%s%.2f" % [color.to_html(), surface, tile]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if surface != "":
		m.albedo_texture = Pixel.surface(surface)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(tile, tile, tile)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mats[key] = m
	return m


static func emat(color: Color, energy := 2.2) -> StandardMaterial3D:
	var key := "e%s%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var key := "b%.3f_%.3f_%.3f" % [x, y, z]
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		_meshes[key] = b
	return _meshes[key]


static func _cyl(top: float, bottom: float, h: float, seg := 10) -> CylinderMesh:
	var key := "c%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func _sph(r: float, seg := 10) -> SphereMesh:
	var key := "s%.3f_%d" % [r, seg]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = seg
		s.rings = maxi(4, seg / 2)
		_meshes[key] = s
	return _meshes[key]


static func _prism(x: float, y: float, z: float) -> PrismMesh:
	var key := "p%.3f_%.3f_%.3f" % [x, y, z]
	if not _meshes.has(key):
		var p := PrismMesh.new()
		p.size = Vector3(x, y, z)
		_meshes[key] = p
	return _meshes[key]


static func _add(root: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# ---------- Модели ----------

## Построить модель. Возвращает узел, основание в (0,0,0), фасад смотрит на камеру (+Z).
static func build(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := mat(Color(0.34, 0.31, 0.4), "brick", 2.2)
	var dark := mat(Color(0.2, 0.19, 0.26), "panel", 2.0)
	var wood := mat(Color(0.45, 0.32, 0.24), "wood", 2.4)
	var metal := mat(Color(0.3, 0.3, 0.38), "panel", 2.6, 0.5)
	match kind:
		"house0", "house1", "house2":
			var wc: Color = {"house0": MAGENTA, "house1": CYAN, "house2": GOLD}[kind]
			var tall := kind == "house2"
			var w := 0.95 if tall else 1.1
			var d := 0.85
			var h1 := 0.75
			var h2 := 0.95 if tall else 0.5
			_add(root, _box(w, h1, d), stone, Vector3(0, h1 / 2.0, 0))
			_add(root, _box(w + 0.06, h2, d + 0.06), mat(Color(0.5, 0.38, 0.32), "wood", 2.4), Vector3(0, h1 + h2 / 2.0, 0))
			# Балки фахверка
			for x in [-w / 2.0 + 0.04, w / 2.0 - 0.04]:
				_add(root, _box(0.06, h2, 0.04), mat(Color(0.25, 0.17, 0.14), "", 1.0), Vector3(x, h1 + h2 / 2.0, d / 2.0 + 0.04))
			_add(root, _box(w + 0.08, 0.06, 0.04), mat(Color(0.25, 0.17, 0.14), "", 1.0), Vector3(0, h1 + 0.03, d / 2.0 + 0.04))
			var roof_c := [Color(0.5, 0.18, 0.24), Color(0.22, 0.2, 0.45), Color(0.2, 0.34, 0.36)][rng.randi_range(0, 2)] as Color
			_add(root, _prism(d + 0.3, 0.6, w + 0.25), mat(roof_c, "wood", 2.0), Vector3(0, h1 + h2 + 0.3, 0), Vector3(0, 90, 0))
			# Труба
			_add(root, _box(0.16, 0.45, 0.16), stone, Vector3(w * 0.25, h1 + h2 + 0.45, -d * 0.15))
			# Окна и дверь
			var floors := 2 if tall else 1
			for f in floors:
				for x in [-w * 0.26, w * 0.26]:
					_add(root, _box(0.2, 0.18, 0.03), emat(wc, 2.2), Vector3(x, h1 + 0.22 + f * 0.45, d / 2.0 + 0.045), Vector3.ZERO, false)
			_add(root, _box(0.26, 0.5, 0.03), mat(Color(0.22, 0.15, 0.12), "wood", 3.0), Vector3(0, 0.25, d / 2.0 + 0.02))
			_add(root, _box(0.16, 0.12, 0.03), emat(wc, 1.6), Vector3(w * 0.3, 0.45, d / 2.0 + 0.02), Vector3.ZERO, false)
			# Неоновая вывеска
			if rng.randf() < 0.7:
				_add(root, _box(0.5, 0.12, 0.03), emat([CYAN, MAGENTA, GREEN][rng.randi_range(0, 2)] as Color, 2.6), Vector3(0, h1 - 0.08, d / 2.0 + 0.06), Vector3.ZERO, false)
		"tower0":
			_add(root, _cyl(0.38, 0.44, 2.3, 10), stone, Vector3(0, 1.15, 0))
			_add(root, _cyl(0.5, 0.5, 0.22, 10), dark, Vector3(0, 2.4, 0))
			for k in 8:
				var a := TAU * k / 8.0
				_add(root, _box(0.14, 0.18, 0.14), dark, Vector3(cos(a) * 0.44, 2.6, sin(a) * 0.44))
			_add(root, _cyl(0.0, 0.46, 0.7, 10), mat(Color(0.38, 0.16, 0.24), "wood", 2.0), Vector3(0, 3.0, 0))
			_add(root, _cyl(0.42, 0.42, 0.06, 10), emat(PURPLE, 2.4), Vector3(0, 1.5, 0), Vector3.ZERO, false)
			for y in [0.8, 1.9]:
				_add(root, _box(0.08, 0.25, 0.03), emat(GOLD, 2.0), Vector3(0, y, 0.43), Vector3.ZERO, false)
			_add(root, _cyl(0.015, 0.015, 0.6, 4), metal, Vector3(0, 3.6, 0))
			_add(root, _box(0.35, 0.2, 0.02), emat(MAGENTA, 1.6), Vector3(0.18, 3.75, 0), Vector3.ZERO, false)
		"wall0":
			_add(root, _box(1.45, 1.05, 0.34), stone, Vector3(0, 0.525, 0))
			for k in 4:
				_add(root, _box(0.24, 0.2, 0.36), stone, Vector3(-0.54 + k * 0.36, 1.15, 0))
			_add(root, _box(1.2, 0.05, 0.03), emat(PURPLE, 2.2), Vector3(0, 0.6, 0.18), Vector3.ZERO, false)
		"gate0":
			for x in [-0.58, 0.58]:
				_add(root, _box(0.32, 1.9, 0.42), stone, Vector3(x, 0.95, 0))
				_add(root, _cyl(0.0, 0.22, 0.4, 4), mat(Color(0.38, 0.16, 0.24), "wood", 2.0), Vector3(x, 2.1, 0), Vector3(0, 45, 0))
			_add(root, _box(1.5, 0.32, 0.42), stone, Vector3(0, 1.75, 0))
			for k in 5:
				_add(root, _box(0.03, 1.45, 0.03), emat(CYAN, 1.8), Vector3(-0.32 + k * 0.16, 0.85, 0), Vector3.ZERO, false)
			_add(root, _box(0.8, 0.03, 0.03), emat(CYAN, 1.8), Vector3(0, 1.0, 0), Vector3.ZERO, false)
		"stall0", "stall1":
			var c := MAGENTA if kind == "stall0" else CYAN
			_add(root, _box(0.9, 0.42, 0.42), wood, Vector3(0, 0.21, 0))
			for x in [-0.42, 0.42]:
				_add(root, _cyl(0.02, 0.02, 1.0, 4), wood, Vector3(x, 0.5, -0.18))
				_add(root, _cyl(0.02, 0.02, 0.8, 4), wood, Vector3(x, 0.4, 0.2))
			_add(root, _box(1.05, 0.04, 0.65), emat(c.darkened(0.3), 0.8), Vector3(0, 0.95, 0.02), Vector3(-14, 0, 0))
			for k in 5:
				_add(root, _cyl(0.035, 0.045, 0.11, 6), emat([CYAN, MAGENTA, GOLD, GREEN][rng.randi_range(0, 3)] as Color, 2.2), Vector3(-0.32 + k * 0.16, 0.47, 0.05), Vector3.ZERO, false)
		"well0":
			_add(root, _cyl(0.3, 0.33, 0.38, 10), stone, Vector3(0, 0.19, 0))
			_add(root, _cyl(0.25, 0.25, 0.03, 10), emat(Color(0.2, 0.55, 1.0), 1.8), Vector3(0, 0.37, 0), Vector3.ZERO, false)
			for x in [-0.27, 0.27]:
				_add(root, _cyl(0.025, 0.025, 0.7, 4), wood, Vector3(x, 0.55, 0))
			_add(root, _prism(0.75, 0.25, 0.45), mat(Color(0.45, 0.2, 0.24), "wood", 2.0), Vector3(0, 0.98, 0))
		"lantern0":
			_add(root, _cyl(0.03, 0.04, 1.0, 5), metal, Vector3(0, 0.5, 0))
			_add(root, _box(0.16, 0.2, 0.16), emat(GOLD, 2.6), Vector3(0, 1.05, 0), Vector3.ZERO, false)
			_add(root, _cyl(0.0, 0.13, 0.1, 4), dark, Vector3(0, 1.2, 0), Vector3(0, 45, 0))
		"lamp0", "lamp1":
			var c := CYAN if kind == "lamp0" else MAGENTA
			_add(root, _cyl(0.03, 0.05, 1.8, 6), metal, Vector3(0, 0.9, 0))
			_add(root, _box(0.35, 0.04, 0.04), metal, Vector3(0.15, 1.78, 0))
			_add(root, _sph(0.08, 8), emat(c, 3.0), Vector3(0.3, 1.7, 0), Vector3.ZERO, false)
		"sign0", "sign1":
			var c := MAGENTA if kind == "sign0" else CYAN
			_add(root, _cyl(0.03, 0.03, 1.1, 4), metal, Vector3(0, 0.55, 0))
			_add(root, _box(0.5, 0.36, 0.06), dark, Vector3(0, 1.15, 0))
			_add(root, _box(0.42, 0.28, 0.02), emat(c, 2.4), Vector3(0, 1.15, 0.04), Vector3.ZERO, false)
		"banner0", "banner1":
			var c := MAGENTA if kind == "banner0" else CYAN
			_add(root, _cyl(0.025, 0.025, 1.8, 4), metal, Vector3(0, 0.9, 0))
			_add(root, _box(0.36, 0.9, 0.02), emat(c.darkened(0.25), 1.3), Vector3(0.2, 1.3, 0), Vector3.ZERO, true)
			_add(root, _box(0.1, 0.1, 0.03), emat(GOLD, 2.0), Vector3(0.2, 1.4, 0.015), Vector3.ZERO, false)
		"pillar0":
			_add(root, _box(0.42, 0.14, 0.42), stone, Vector3(0, 0.07, 0))
			_add(root, _cyl(0.16, 0.18, 1.4, 8), stone, Vector3(0, 0.84, 0))
			_add(root, _box(0.42, 0.14, 0.42), stone, Vector3(0, 1.6, 0))
			_add(root, _cyl(0.17, 0.17, 0.04, 8), emat(PURPLE, 2.0), Vector3(0, 0.9, 0), Vector3.ZERO, false)
		"pillar1":
			_add(root, _box(0.42, 0.14, 0.42), stone, Vector3(0, 0.07, 0))
			_add(root, _cyl(0.16, 0.18, 0.8, 8), stone, Vector3(0, 0.54, 0), Vector3(0, 0, 6))
			_add(root, _cyl(0.16, 0.16, 0.35, 8), stone, Vector3(0.35, 0.16, 0.1), Vector3(90, 30, 0))
		"obelisk0", "obelisk1", "obelisk2":
			var c := [CYAN, MAGENTA, GOLD][int(kind.substr(7))] as Color
			_add(root, _box(0.5, 0.15, 0.5), dark, Vector3(0, 0.075, 0))
			_add(root, _cyl(0.1, 0.22, 1.4, 4), dark, Vector3(0, 0.85, 0), Vector3(0, 45, 0))
			_add(root, _cyl(0.0, 0.1, 0.18, 4), emat(c, 2.6), Vector3(0, 1.64, 0), Vector3(0, 45, 0), false)
			for y in [0.5, 0.8, 1.1]:
				_add(root, _box(0.06, 0.12, 0.02), emat(c, 2.2), Vector3(0, y, 0.17 - y * 0.06), Vector3.ZERO, false)
		"crate0", "crate1":
			var s := 0.42 + rng.randf() * 0.12
			_add(root, _box(s, s, s), wood, Vector3(0, s / 2.0, 0), Vector3(0, rng.randf_range(-20, 20), 0))
			if kind == "crate1":
				_add(root, _box(s * 0.7, s * 0.7, s * 0.7), wood, Vector3(0.08, s + s * 0.35, 0), Vector3(0, rng.randf_range(0, 60), 0))
			_add(root, _box(s + 0.01, 0.05, s + 0.01), emat(CYAN, 1.2), Vector3(0, s * 0.5, 0), Vector3.ZERO, false)
		"barrel0", "barrel1":
			_add(root, _cyl(0.17, 0.17, 0.46, 10), wood, Vector3(0, 0.23, 0))
			_add(root, _cyl(0.18, 0.18, 0.04, 10), metal, Vector3(0, 0.12, 0))
			_add(root, _cyl(0.18, 0.18, 0.04, 10), metal, Vector3(0, 0.36, 0))
			if kind == "barrel1":
				_add(root, _cyl(0.15, 0.15, 0.02, 10), emat(GREEN, 2.0), Vector3(0, 0.465, 0), Vector3.ZERO, false)
		"cart0":
			_add(root, _box(0.85, 0.3, 0.5), wood, Vector3(0, 0.38, 0))
			for x in [-0.28, 0.28]:
				for z in [-0.28, 0.28]:
					_add(root, _cyl(0.17, 0.17, 0.05, 10), mat(Color(0.3, 0.22, 0.16), "wood", 2.0), Vector3(x, 0.17, z), Vector3(90, 0, 0))
			_add(root, _box(0.5, 0.04, 0.04), wood, Vector3(0.6, 0.3, 0))
			_add(root, _box(0.3, 0.2, 0.3), emat(GOLD.darkened(0.3), 1.0), Vector3(-0.1, 0.62, 0))
		"fence0":
			for x in [-0.42, 0.0, 0.42]:
				_add(root, _box(0.07, 0.5, 0.07), wood, Vector3(x, 0.25, 0))
			for y in [0.18, 0.38]:
				_add(root, _box(0.95, 0.05, 0.04), wood, Vector3(0, y, 0))
		"wreck0", "wreck1":
			_add(root, _box(0.7, 0.32, 0.5), metal, Vector3(0, 0.16, 0), Vector3(0, rng.randf_range(0, 360), rng.randf_range(-12, 12)))
			_add(root, _box(0.5, 0.06, 0.18), dark, Vector3(0.3, 0.3, 0.1), Vector3(0, 30, -25))
			_add(root, _sph(0.07, 6), emat(MAGENTA if kind == "wreck0" else CYAN, 2.4), Vector3(-0.2, 0.32, 0.22), Vector3.ZERO, false)
		"rock0", "rock1":
			var r := 0.32 if kind == "rock0" else 0.24
			var rk := _add(root, _sph(r, 6), mat(Color(0.3, 0.28, 0.35), "brick", 3.0), Vector3(0, r * 0.45, 0), Vector3(rng.randf_range(0, 40), rng.randf_range(0, 360), 0))
			rk.scale = Vector3(1.3, 0.7, 1.0)
		"crystal0", "crystal1":
			var c := CYAN if kind == "crystal0" else PURPLE
			for k in 3:
				var h := rng.randf_range(0.25, 0.5)
				_add(root, _cyl(0.0, 0.08, h, 5), emat(c, 2.0), Vector3(rng.randf_range(-0.15, 0.15), h / 2.0, rng.randf_range(-0.1, 0.1)),
					Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), false)
		"crystal_big0", "crystal_big1":
			var c := CYAN if kind == "crystal_big0" else PURPLE
			_add(root, _cyl(0.0, 0.26, 1.0, 6), emat(c, 1.8), Vector3(0, 0.85, 0), Vector3.ZERO, false)
			_add(root, _cyl(0.26, 0.0, 0.35, 6), emat(c.darkened(0.2), 1.6), Vector3(0, 0.18, 0), Vector3.ZERO, false)
			_add(root, _cyl(0.0, 0.12, 0.5, 5), emat(c, 2.0), Vector3(0.25, 0.25, 0.05), Vector3(0, 0, -25), false)
			_add(root, _cyl(0.0, 0.1, 0.4, 5), emat(c, 2.0), Vector3(-0.22, 0.2, -0.05), Vector3(0, 0, 25), false)
		"pine0", "pine1":
			var big := kind == "pine0"
			var s := 1.0 if big else 0.8
			_add(root, _cyl(0.05 * s, 0.08 * s, 0.4 * s, 6), mat(Color(0.32, 0.22, 0.18), "wood", 3.0), Vector3(0, 0.2 * s, 0))
			var leaf := mat(Color(0.14, 0.3 + rng.randf() * 0.06, 0.26), "", 1.0)
			for k in 3:
				_add(root, _cyl(0.0, (0.55 - k * 0.13) * s, 0.6 * s, 7), leaf, Vector3(0, (0.55 + k * 0.38) * s, 0))
			if not big:
				_add(root, _sph(0.06, 6), emat(CYAN, 3.0), Vector3(0, 1.62 * s, 0), Vector3.ZERO, false)
		"tree0", "tree1", "tree2":
			var c := {"tree0": Color(0.25, 0.55, 0.35), "tree1": MAGENTA, "tree2": CYAN}[kind] as Color
			_add(root, _cyl(0.06, 0.1, 0.8, 6), mat(Color(0.3, 0.22, 0.2), "wood", 3.0), Vector3(0, 0.4, 0))
			var crown_m := mat(c.darkened(0.45), "", 1.0) if kind == "tree0" else emat(c.darkened(0.5), 0.9)
			var cr := _add(root, _sph(0.48, 10), crown_m, Vector3(0, 1.05, 0))
			cr.scale = Vector3(1.0, 0.8, 1.0)
			if kind != "tree0":
				_add(root, _cyl(0.46, 0.46, 0.03, 12), emat(c, 2.2), Vector3(0, 0.98, 0), Vector3.ZERO, false)
		"bush0", "bush1":
			var b := _add(root, _sph(0.25 if kind == "bush0" else 0.2, 8), mat(Color(0.18, 0.36, 0.26), "", 1.0), Vector3(0, 0.14, 0))
			b.scale = Vector3(1.3, 0.75, 1.1)
			if kind == "bush1":
				_add(root, _sph(0.04, 6), emat(MAGENTA, 2.6), Vector3(0.1, 0.28, 0.1), Vector3.ZERO, false)
		"mushroom0", "mushroom1":
			var c := Color(0.8, 0.75, 0.6) if kind == "mushroom0" else MAGENTA
			_add(root, _cyl(0.05, 0.07, 0.3, 6), mat(Color(0.85, 0.82, 0.75), "", 1.0), Vector3(0, 0.15, 0))
			var cap := _add(root, _sph(0.2, 8), emat(c, 1.6) if kind == "mushroom1" else mat(c, "", 1.0), Vector3(0, 0.32, 0))
			cap.scale = Vector3(1.0, 0.5, 1.0)
	var sc := rng.randf_range(0.92, 1.1)
	root.scale = Vector3(sc, sc, sc)
	return root


## Формы основания для столкновений (в единицах 3D, до масштаба модели):
## ["r", центр_x, центр_z, полуширина, полуглубина] или ["c", центр_x, центр_z, радиус].
## Кусты и грибы — проходимые, у них форм нет.
static func shapes(kind: String) -> Array:
	match kind:
		"house0", "house1":
			return [["r", 0.0, 0.0, 0.58, 0.47]]
		"house2":
			return [["r", 0.0, 0.0, 0.51, 0.47]]
		"tower0":
			return [["c", 0.0, 0.0, 0.48]]
		"wall0":
			return [["r", 0.0, 0.0, 0.74, 0.19]]
		"gate0":
			return [["r", -0.58, 0.0, 0.17, 0.22], ["r", 0.58, 0.0, 0.17, 0.22]]
		"stall0", "stall1":
			return [["r", 0.0, 0.0, 0.47, 0.25]]
		"well0":
			return [["c", 0.0, 0.0, 0.34]]
		"lantern0", "lamp0", "lamp1", "sign0", "sign1", "banner0", "banner1":
			return [["c", 0.0, 0.0, 0.07]]
		"pillar0", "pillar1":
			return [["r", 0.0, 0.0, 0.22, 0.22]]
		"obelisk0", "obelisk1", "obelisk2":
			return [["r", 0.0, 0.0, 0.26, 0.26]]
		"crate0", "crate1":
			return [["r", 0.0, 0.0, 0.27, 0.27]]
		"barrel0", "barrel1":
			return [["c", 0.0, 0.0, 0.19]]
		"cart0":
			return [["r", 0.05, 0.0, 0.5, 0.32]]
		"fence0":
			return [["r", 0.0, 0.0, 0.48, 0.05]]
		"wreck0", "wreck1":
			return [["c", 0.0, 0.0, 0.36]]
		"rock0":
			return [["c", 0.0, 0.0, 0.38]]
		"rock1":
			return [["c", 0.0, 0.0, 0.29]]
		"crystal0", "crystal1":
			return [["c", 0.0, 0.0, 0.16]]
		"crystal_big0", "crystal_big1":
			return [["c", 0.0, 0.0, 0.3]]
		"pine0":
			return [["c", 0.0, 0.0, 0.32]]
		"pine1":
			return [["c", 0.0, 0.0, 0.26]]
		"tree0", "tree1", "tree2":
			return [["c", 0.0, 0.0, 0.18]]
	return []
