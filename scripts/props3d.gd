extends RefCounted
## Объёмные 3D-модели объектов поля боя (дома, башни, стены, деревья, кристаллы...).
## Размеры в единицах 3D-сцены боя: 1 единица = 100 пикселей мира.

const Pixel := preload("res://scripts/pixel.gd")
const BuildingMesh := preload("res://scripts/building_mesh.gd")

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
	"obelisk0", "obelisk1", "obelisk2", "manor0", "keep0", "crate0", "crate1", "barrel0", "barrel1", "cart0", "fence0",
	"wreck0", "wreck1", "rock0", "rock1", "crystal0", "crystal1", "crystal_big0", "crystal_big1",
	"pine0", "pine1", "pine2", "tree0", "tree1", "tree2", "tree3", "bush0", "bush1", "mushroom0", "mushroom1"]
## Деревья, кусты и грибы рисуются пиксель-артом (спрайты), а не 3D-моделями.
const PIXEL_KINDS: Array = []


static func supports(kind: String) -> bool:
	if kind.begins_with("c_"):
		return true
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
		m.uv1_scale = Vector3.ONE * (tile * Pixel.EnvironmentArt.MATERIAL_REPEAT)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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


static func _box(x: float, y: float, z: float) -> Mesh:
	return BuildingMesh.box(Vector3(x, y, z))


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
	if kind in VOXEL_KINDS:
		return _vox_build(kind, rng)
	var root := Node3D.new()
	if kind.begins_with("c_"):
		_chap3d(root, kind, rng)
		var cs := rng.randf_range(0.94, 1.08)
		root.scale = Vector3(cs, cs, cs)
		return root
	var stone := mat(Color(0.34, 0.31, 0.4), "brick", 2.2)
	var dark := mat(Color(0.2, 0.19, 0.26), "panel", 2.0)
	var wood := mat(Color(0.45, 0.32, 0.24), "wood", 2.4)
	var metal := mat(Color(0.3, 0.3, 0.38), "panel", 2.6, 0.5)
	match kind:
		"house0", "house1", "house2", "manor0":
			_house3d(root, kind, rng)
		"keep0":
			_keep3d(root, rng)
		"tower0":
			_add(root, _cyl(0.62, 0.66, 0.22, 12), dark, Vector3(0, 0.11, 0))
			_add(root, _cyl(0.5, 0.58, 3.1, 12), stone, Vector3(0, 1.55, 0))
			_add(root, _cyl(0.66, 0.6, 0.28, 12), dark, Vector3(0, 3.22, 0))
			for k in 10:
				var a := TAU * k / 10.0
				_add(root, _box(0.16, 0.22, 0.16), dark, Vector3(cos(a) * 0.6, 3.47, sin(a) * 0.6), Vector3(0, -rad_to_deg(a), 0))
			_add(root, _cyl(0.0, 0.62, 0.95, 12), mat(Color(0.38, 0.16, 0.24), "wood", 2.0), Vector3(0, 4.0, 0))
			_add(root, _cyl(0.55, 0.55, 0.06, 12), emat(PURPLE, 2.4), Vector3(0, 2.0, 0), Vector3.ZERO, false)
			for y in [0.95, 1.6, 2.6]:
				_add(root, _box(0.1, 0.3, 0.03), emat(GOLD, 2.0), Vector3(0, y, 0.56), Vector3.ZERO, false)
			_add(root, _box(0.42, 0.62, 0.05), mat(Color(0.26, 0.18, 0.13), "wood", 3.0), Vector3(0, 0.42, 0.57))
			_add(root, _cyl(0.015, 0.015, 0.7, 4), metal, Vector3(0, 4.75, 0))
			_add(root, _box(0.4, 0.24, 0.02), emat(MAGENTA, 1.6), Vector3(0.2, 4.95, 0), Vector3.ZERO, false)
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
	if kind.begins_with("house") or kind == "manor0":
		# Дома в росте человека: дверь выше героя, этаж ~1.3 его роста
		sc = 1.4 * rng.randf_range(0.96, 1.06)
	root.scale = Vector3(sc, sc, sc)
	return root


## Формы основания для столкновений (в единицах 3D, до масштаба модели):
## ["r", центр_x, центр_z, полуширина, полуглубина] или ["c", центр_x, центр_z, радиус].
## Кусты и грибы — проходимые, у них форм нет.
static func shapes(kind: String) -> Array:
	if kind.begins_with("c_"):
		match kind.get_slice("_", 2):
			"w":
				return [["r", 0.0, 0.0, 0.62, 0.2]]
			"b":
				return [["c", 0.0, 0.0, 0.42]]
			_:
				return [["c", 0.0, 0.0, 0.1]]
	match kind:
		"house0", "house1":
			return [["r", 0.0, 0.0, 0.8, 0.62]]
		"house2":
			return [["r", 0.0, 0.0, 0.7, 0.62]]
		"manor0":
			return [["r", 0.0, 0.0, 1.32, 0.8], ["r", 0.0, 0.88, 0.6, 0.12]]
		"keep0":
			return [["r", 0.0, 0.0, 1.2, 1.2]]
		"tower0":
			return [["c", 0.0, 0.0, 0.62]]
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
		"tree0", "tree1", "tree2", "tree3":
			return [["c", 0.0, 0.0, 0.18]]
		"pine2":
			return [["c", 0.0, 0.0, 0.26]]
	return []


## Дом в пропорциях: цоколь, каменный первый этаж, фахверковый второй с выносом,
## крыша со свесами и слуховым окном, окна с рамами и ставнями, дверь с козырьком.
static func _house3d(root: Node3D, kind: String, rng: RandomNumberGenerator) -> void:
	var stone := mat(Color(0.36, 0.33, 0.42), "brick", 2.6)
	var plinth := mat(Color(0.24, 0.22, 0.29), "brick", 3.0)
	var beam := mat(Color(0.24, 0.16, 0.13), "", 1.0)
	var plaster := mat([Color(0.62, 0.55, 0.48), Color(0.5, 0.47, 0.56), Color(0.56, 0.5, 0.42)][rng.randi_range(0, 2)] as Color, "panel", 3.0)
	var frame := mat(Color(0.16, 0.12, 0.12), "", 1.0)
	var wc: Color = {"house0": MAGENTA, "house1": CYAN, "house2": GOLD, "manor0": GOLD}[kind]
	var warm := Color(1.0, 0.78, 0.45)
	var big := kind == "manor0"
	var tall := kind == "house2"
	var w := 2.5 if big else (1.3 if tall else 1.5)
	var d := 1.5 if big else 1.15
	var p_h := 0.12
	var h1 := 0.95
	var floors_up := 2 if (tall or big) else 1
	var h2 := 0.78
	var top := p_h + h1 + h2 * floors_up
	_add(root, _box(w + 0.12, p_h, d + 0.12), plinth, Vector3(0, p_h / 2.0, 0))
	_add(root, _box(w, h1, d), stone, Vector3(0, p_h + h1 / 2.0, 0))
	var fz := d / 2.0
	for f in floors_up:
		var y0 := p_h + h1 + f * h2
		var jw := w + 0.14 + f * 0.04
		var jd := d + 0.14 + f * 0.04
		_add(root, _box(jw, h2, jd), plaster, Vector3(0, y0 + h2 / 2.0, 0))
		_add(root, _box(jw + 0.04, 0.07, jd + 0.04), beam, Vector3(0, y0 + 0.035, 0))
		# Фахверк: стойки и раскосы на фасаде
		var n := int(round(jw / 0.42))
		for k in n + 1:
			var x := -jw / 2.0 + k * jw / n
			_add(root, _box(0.06, h2, 0.03), beam, Vector3(x, y0 + h2 / 2.0, jd / 2.0 + 0.01), Vector3.ZERO, false)
		for s in [-1.0, 1.0]:
			_add(root, _box(0.05, h2 * 1.1, 0.03), beam, Vector3(s * (jw / 2.0 - 0.2), y0 + h2 / 2.0, jd / 2.0 + 0.012), Vector3(0, 0, s * 32.0), false)
			# Боковые стойки
			_add(root, _box(0.03, h2, 0.06), beam, Vector3(s * (jw / 2.0 + 0.01), y0 + h2 / 2.0, 0), Vector3.ZERO, false)
		# Окна этажа
		var wn := 3 if big else 2
		for k in wn:
			var x := (k - (wn - 1) / 2.0) * (w / wn)
			var lit := rng.randf() < 0.65
			_add(root, _box(0.3, 0.34, 0.03), frame, Vector3(x, y0 + h2 * 0.52, jd / 2.0 + 0.02), Vector3.ZERO, false)
			_add(root, _box(0.22, 0.26, 0.03), emat(warm if lit else wc.darkened(0.55), 1.9 if lit else 0.6), Vector3(x, y0 + h2 * 0.52, jd / 2.0 + 0.03), Vector3.ZERO, false)
			_add(root, _box(0.26, 0.02, 0.03), frame, Vector3(x, y0 + h2 * 0.52, jd / 2.0 + 0.04), Vector3.ZERO, false)
			# Цветочный ящик под окном
			if rng.randf() < 0.5:
				_add(root, _box(0.3, 0.06, 0.08), mat(Color(0.35, 0.22, 0.15), "wood", 3.0), Vector3(x, y0 + h2 * 0.28, jd / 2.0 + 0.06), Vector3.ZERO, false)
				_add(root, _box(0.26, 0.05, 0.05), emat([MAGENTA, GOLD, GREEN][rng.randi_range(0, 2)] as Color, 1.4), Vector3(x, y0 + h2 * 0.32, jd / 2.0 + 0.06), Vector3.ZERO, false)
	# Первый этаж: дверь с аркой и козырьком, окна со ставнями
	var dx := 0.0 if not big else 0.0
	_add(root, _box(0.44, 0.7, 0.04), frame, Vector3(dx, p_h + 0.35, fz + 0.01))
	_add(root, _box(0.36, 0.64, 0.04), mat(Color(0.34, 0.22, 0.15), "wood", 4.0), Vector3(dx, p_h + 0.32, fz + 0.02))
	_add(root, _sph(0.03, 6), emat(GOLD, 2.5), Vector3(dx + 0.12, p_h + 0.32, fz + 0.05), Vector3.ZERO, false)
	_add(root, _box(0.6, 0.04, 0.3), beam, Vector3(dx, p_h + 0.78, fz + 0.15), Vector3(-18, 0, 0))
	_add(root, _box(0.5, 0.06, 0.2), plinth, Vector3(dx, 0.03, fz + 0.12))
	_add(root, _sph(0.045, 6), emat(warm, 3.0), Vector3(dx + 0.3, p_h + 0.62, fz + 0.06), Vector3.ZERO, false)
	var gx := [-w * 0.32, w * 0.32] if not big else [-w * 0.36, -w * 0.18, w * 0.18, w * 0.36]
	for x in gx:
		var lit := rng.randf() < 0.55
		_add(root, _box(0.3, 0.36, 0.03), frame, Vector3(x, p_h + 0.5, fz + 0.01), Vector3.ZERO, false)
		_add(root, _box(0.22, 0.28, 0.03), emat(wc if lit else Color(0.1, 0.1, 0.16), 2.0 if lit else 0.4), Vector3(x, p_h + 0.5, fz + 0.02), Vector3.ZERO, false)
		for s in [-1.0, 1.0]:
			_add(root, _box(0.1, 0.36, 0.02), mat(Color(0.28, 0.32, 0.4) if kind != "house0" else Color(0.4, 0.2, 0.25), "wood", 4.0), Vector3(x + s * 0.21, p_h + 0.5, fz + 0.02), Vector3.ZERO, false)
	# Неоновая вывеска над дверью
	if rng.randf() < 0.75:
		_add(root, _box(0.62, 0.12, 0.03), emat([CYAN, MAGENTA, GREEN, GOLD][rng.randi_range(0, 3)] as Color, 2.6), Vector3(dx, p_h + h1 - 0.06, fz + 0.04), Vector3.ZERO, false)
	# Крыша со свесами, конёк, слуховое окно, труба
	var roof_c := [Color(0.5, 0.18, 0.24), Color(0.22, 0.2, 0.45), Color(0.2, 0.34, 0.36), Color(0.36, 0.24, 0.18)][rng.randi_range(0, 3)] as Color
	var rh := 0.75 if not big else 0.95
	var rd := d + 0.14 * floors_up + 0.42
	_add(root, _prism(rd, rh, w + 0.45), mat(roof_c, "wood", 2.4), Vector3(0, top + rh / 2.0, 0), Vector3(0, 90, 0))
	_add(root, _box(w + 0.52, 0.13, 0.14), beam, Vector3(0, top + rh, 0))
	for s in [-1.0, 1.0]:
		_add(root, _box(w + 0.52, 0.12, 0.13), beam, Vector3(0, top + 0.015, s * rd / 2.0))
		_add(root, _box(w + 0.34, 0.06, 0.11), plinth, Vector3(0, top - 0.065, s * rd * 0.44))
	if big or rng.randf() < 0.6:
		var dz := rd * 0.22
		_add(root, _box(0.36, 0.34, 0.3), plaster, Vector3(0, top + rh * 0.42, dz))
		_add(root, _prism(0.46, 0.24, 0.36), mat(roof_c, "wood", 2.4), Vector3(0, top + rh * 0.42 + 0.29, dz))
		_add(root, _box(0.18, 0.18, 0.02), emat(warm, 1.8), Vector3(0, top + rh * 0.42, dz + 0.16), Vector3.ZERO, false)
	var cx := w * (0.3 if rng.randf() < 0.5 else -0.3)
	_add(root, _box(0.2, 0.7, 0.2), stone, Vector3(cx, top + rh * 0.6, -rd * 0.15))
	_add(root, _box(0.26, 0.06, 0.26), plinth, Vector3(cx, top + rh * 0.6 + 0.36, -rd * 0.15))
	# Пристройка-навес сбоку с дровами
	if not big and rng.randf() < 0.5:
		var sx := (w / 2.0 + 0.22) * (1.0 if rng.randf() < 0.5 else -1.0)
		_add(root, _box(0.44, 0.04, d * 0.8), mat(roof_c.darkened(0.2), "wood", 3.0), Vector3(sx, p_h + 0.72, 0), Vector3(0, 0, -14.0 * signf(sx)))
		for z in [-d * 0.35, d * 0.35]:
			_add(root, _box(0.04, 0.72, 0.04), beam, Vector3(sx + 0.16 * signf(sx), 0.36, z))
		_add(root, _box(0.3, 0.3, d * 0.6), mat(Color(0.42, 0.3, 0.2), "wood", 5.0), Vector3(sx, 0.15, 0))
	if big:
		# Особняк: балкон с перилами и колонны крыльца
		var by := p_h + h1
		_add(root, _box(1.1, 0.06, 0.4), beam, Vector3(0, by + 0.02, fz + 0.26))
		_add(root, _box(1.1, 0.03, 0.03), beam, Vector3(0, by + 0.32, fz + 0.45))
		for k in 7:
			_add(root, _box(0.025, 0.3, 0.025), beam, Vector3(-0.5 + k * (1.0 / 6.0), by + 0.17, fz + 0.45), Vector3.ZERO, false)
		for s in [-1.0, 1.0]:
			_add(root, _cyl(0.04, 0.05, h1, 6), stone, Vector3(s * 0.5, p_h + h1 / 2.0, fz + 0.4))
		_add(root, _box(1.2, 0.08, 0.6), plinth, Vector3(0, 0.04, fz + 0.3))
		_add(root, _box(0.9, 0.16, 0.03), emat(GOLD, 2.4), Vector3(0, top + rh * 0.42 + 0.55, rd * 0.22 + 0.2), Vector3.ZERO, false)


## Донжон крепости: массивная башня с зубцами, угловыми башенками и воротами.
static func _keep3d(root: Node3D, rng: RandomNumberGenerator) -> void:
	var stone := mat(Color(0.36, 0.33, 0.42), "brick", 2.2)
	var dark := mat(Color(0.2, 0.19, 0.26), "brick", 2.8)
	var roof := mat(Color(0.38, 0.16, 0.24), "wood", 2.0)
	var s := 2.1
	var h := 2.9
	_add(root, _box(s + 0.2, 0.2, s + 0.2), dark, Vector3(0, 0.1, 0))
	_add(root, _box(s, h, s), stone, Vector3(0, h / 2.0, 0))
	_add(root, _box(s + 0.12, 0.12, s + 0.12), dark, Vector3(0, h * 0.5, 0))
	for k in 6:
		var x := -s / 2.0 + 0.15 + k * (s - 0.3) / 5.0
		for z in [-s / 2.0, s / 2.0]:
			_add(root, _box(0.2, 0.26, 0.2), stone, Vector3(x, h + 0.13, z))
		for z2 in [-s / 2.0, s / 2.0]:
			_add(root, _box(0.2, 0.26, 0.2), stone, Vector3(z2, h + 0.13, x))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p := Vector3(cx * s / 2.0, 0, cz * s / 2.0)
			_add(root, _cyl(0.32, 0.36, h + 0.6, 10), stone, p + Vector3(0, (h + 0.6) / 2.0, 0))
			_add(root, _cyl(0.0, 0.42, 0.8, 10), roof, p + Vector3(0, h + 1.0, 0))
			_add(root, _box(0.06, 0.2, 0.02), emat(GOLD, 2.0), p + Vector3(0, h * 0.7, 0.35 * cz), Vector3.ZERO, false)
	# Ворота с решёткой и окна-бойницы
	_add(root, _box(0.8, 1.1, 0.05), Props3D_dark_wood(), Vector3(0, 0.75, s / 2.0 + 0.01))
	for k in 4:
		_add(root, _box(0.03, 1.0, 0.03), emat(CYAN, 1.8), Vector3(-0.3 + k * 0.2, 0.7, s / 2.0 + 0.05), Vector3.ZERO, false)
	_add(root, _cyl(0.4, 0.4, 0.06, 10), dark, Vector3(0, 1.3, s / 2.0 + 0.02), Vector3(90, 0, 0))
	for y in [1.7, 2.4]:
		for x in [-0.6, 0.0, 0.6]:
			_add(root, _box(0.1, 0.3, 0.03), emat(Color(1.0, 0.7, 0.35), 1.8), Vector3(x, y, s / 2.0 + 0.01), Vector3.ZERO, false)
	_add(root, _box(s * 0.8, 0.05, 0.03), emat(PURPLE, 2.2), Vector3(0, h * 0.5 + 0.08, s / 2.0 + 0.07), Vector3.ZERO, false)
	# Флагшток с флагом
	_add(root, _cyl(0.025, 0.025, 1.2, 4), mat(Color(0.3, 0.3, 0.38), "panel", 2.6), Vector3(0, h + 0.6, 0))
	_add(root, _box(0.5, 0.3, 0.02), emat(MAGENTA, 1.4), Vector3(0.26, h + 1.05, 0))


static func Props3D_dark_wood() -> StandardMaterial3D:
	return mat(Color(0.26, 0.18, 0.13), "wood", 3.0)


# ---------- Объёмные пиксельные деревья (воксели) ----------
# Деревья, кусты и грибы собраны из кубиков-вокселей: объём и тени настоящие,
# а вид — пиксельный. Видимые грани каждого варианта сливаются в один меш (кэш),
# поэтому лес из сотни деревьев — это сотня копий нескольких мешей.

const VOXEL_KINDS := ["pine0", "pine1", "pine2", "tree0", "tree1", "tree2", "tree3", "bush0", "bush1", "mushroom0", "mushroom1"]
const VOX := 0.09
static var _vox_cache := {}
static var _vox_materials := {}
static var _vox_glow: StandardMaterial3D


static func _vox_build(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var variant := rng.randi_range(0, 2)
	var key := "%s_%d" % [kind, variant]
	if not _vox_cache.has(key):
		var vr := RandomNumberGenerator.new()
		vr.seed = hash(key)
		_vox_cache[key] = _vox_mesh(kind, vr)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _vox_cache[key]
	mi.set_meta("vox", true)
	root.add_child(mi)
	var sc := rng.randf_range(0.9, 1.12) * (1.3 if kind.begins_with("tree") else (1.2 if kind.begins_with("pine") else 1.0))
	root.scale = Vector3(sc, sc, sc)
	root.rotation.y = rng.randf_range(-0.5, 0.5)
	return root


static func _vox_mesh(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var g := {}      # Vector3i -> Color
	var glow := {}   # Vector3i -> Color
	var leaf := Color(0.16, 0.36, 0.26)
	var bark := Color(0.32, 0.22, 0.17)
	match kind:
		"pine0", "pine1", "pine2":
			var big := kind == "pine0"
			var h_tr := 4 if big else 3
			for y in h_tr:
				for x in [0, 1]:
					for z in [0, 1]:
						g[Vector3i(x, y, z)] = bark.darkened(rng.randf() * 0.2)
			var layers := 5 if big else 4
			var base_r := 6.5 if big else 5.0
			if kind == "pine2":
				leaf = Color(0.22, 0.2, 0.42)
			for l in layers:
				var r := base_r - l * (base_r - 1.5) / float(layers)
				var y0 := h_tr - 1 + l * 3
				for dy in 3:
					var rr := r * (1.0 - dy * 0.28)
					for x in range(-7, 9):
						for z in range(-7, 9):
							var d := Vector2(x - 0.5, z - 0.5).length()
							if d <= rr and rng.randf() > 0.06:
								var c := leaf.lightened(0.12 * dy + rng.randf() * 0.08).darkened(0.25 if d > rr - 1.0 and dy == 0 else 0.0)
								g[Vector3i(x, y0 + dy, z)] = c
				# Неоновые огоньки на ветках
				if kind != "pine0":
					for k in 2:
						var a := rng.randf() * TAU
						var p := Vector3i(int(round(cos(a) * r * 0.8 + 0.5)), y0, int(round(sin(a) * r * 0.8 + 0.5)))
						glow[p] = Color(0.3, 0.95, 1.0) if kind == "pine1" else Color(0.75, 0.55, 1.0)
			var top := h_tr - 1 + layers * 3
			for y in 3:
				g[Vector3i(0, top + y, 0)] = leaf.lightened(0.2)
			if kind != "pine0":
				glow[Vector3i(0, top + 3, 0)] = Color(0.3, 0.95, 1.0) if kind == "pine1" else Color(0.75, 0.55, 1.0)
		"tree0", "tree1", "tree2", "tree3":
			var col: Color = {"tree0": Color(0.2, 0.42, 0.24), "tree1": Color(0.42, 0.16, 0.36), "tree2": Color(0.14, 0.34, 0.4), "tree3": Color(0.16, 0.3, 0.42)}[kind]
			var neon: Color = {"tree0": Color(0.45, 1.0, 0.55), "tree1": Color(1.0, 0.35, 0.8), "tree2": Color(0.3, 0.95, 1.0), "tree3": Color(0.3, 0.95, 1.0)}[kind]
			var big := kind == "tree3"
			var th := 8 if big else 7
			for y in th:
				for x in [0, 1]:
					for z in [0, 1]:
						g[Vector3i(x, y, z)] = bark.darkened(rng.randf() * 0.25)
			# Корни и ветви
			for d in [Vector3i(-1, 0, 0), Vector3i(2, 0, 1), Vector3i(0, 0, 2), Vector3i(1, 0, -1)]:
				g[d] = bark.darkened(0.15)
			for k in 3:
				var a := rng.randf() * TAU
				for s in 3:
					g[Vector3i(int(round(cos(a) * s)), th - 2 + s, int(round(sin(a) * s)))] = bark
			# Крона: несколько шаров
			var blobs := [[Vector3(0.5, th + 2.5, 0.5), 4.3 if big else 3.7]]
			for k in (4 if big else 3):
				var a := rng.randf() * TAU
				blobs.append([Vector3(0.5 + cos(a) * 2.6, th + 1.5 + rng.randf() * 2.0, 0.5 + sin(a) * 2.6), rng.randf_range(2.2, 3.0)])
			for b in blobs:
				var c0: Vector3 = b[0]
				var r: float = b[1]
				for x in range(int(c0.x - r) - 1, int(c0.x + r) + 2):
					for y in range(int(c0.y - r * 0.8) - 1, int(c0.y + r * 0.8) + 2):
						for z in range(int(c0.z - r) - 1, int(c0.z + r) + 2):
							var dv := Vector3(x, (y - c0.y) / 0.8 + c0.y, z) - c0
							if dv.length() <= r and rng.randf() > 0.05:
								var shade := clampf((y - (c0.y - r)) / (2.0 * r), 0.0, 1.0)
								g[Vector3i(x, y, z)] = col.darkened(0.3 * (1.0 - shade)).lightened(rng.randf() * 0.07)
								if kind != "tree0" and dv.length() > r - 1.0 and rng.randf() < 0.07:
									glow[Vector3i(x, y, z)] = neon
								elif kind == "tree0" and dv.length() > r - 1.0 and rng.randf() < 0.012:
									glow[Vector3i(x, y, z)] = Color(1.0, 0.85, 0.4)
		"bush0", "bush1":
			var c0 := Vector3(0.5, 1.6, 0.5)
			var r := 2.6 if kind == "bush0" else 2.1
			for x in range(-3, 5):
				for y in range(0, 4):
					for z in range(-3, 5):
						var dv := Vector3(x, (y - c0.y) / 0.7 + c0.y, z) - c0
						if dv.length() <= r and rng.randf() > 0.08:
							g[Vector3i(x, y, z)] = leaf.lightened(0.05 * y + rng.randf() * 0.06)
							if kind == "bush1" and dv.length() > r - 1.0 and rng.randf() < 0.12:
								glow[Vector3i(x, y, z)] = Color(1.0, 0.35, 0.8)
		"mushroom0", "mushroom1":
			var cap := Color(0.8, 0.74, 0.6) if kind == "mushroom0" else Color(0.55, 0.16, 0.45)
			for y in 3:
				g[Vector3i(0, y, 0)] = Color(0.86, 0.82, 0.74)
			for x in range(-2, 3):
				for z in range(-2, 3):
					if absi(x) + absi(z) <= 3:
						g[Vector3i(x, 3, z)] = cap
						if absi(x) + absi(z) <= 1:
							g[Vector3i(x, 4, z)] = cap.lightened(0.1)
						if kind == "mushroom1" and (x + z) % 2 == 0:
							glow[Vector3i(x, 3, z)] = Color(1.0, 0.4, 0.85)
	for p in glow:
		g.erase(p)
	var mesh := ArrayMesh.new()
	_vox_surface(mesh, g, glow)
	var surface := "forest"
	if kind.begins_with("rock") or kind.begins_with("crystal"):
		surface = "crystal"
	elif kind.begins_with("wreck"):
		surface = "salvage"
	if not _vox_materials.has(surface):
		var textured := mat(Color(1.25, 1.25, 1.25), surface, 1.45, 0.9).duplicate() as StandardMaterial3D
		textured.vertex_color_use_as_albedo = true
		_vox_materials[surface] = textured
	if _vox_glow == null:
		_vox_glow = StandardMaterial3D.new()
		_vox_glow.vertex_color_use_as_albedo = true
		_vox_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vox_glow.albedo_color = Color(2.2, 2.2, 2.2)
	mesh.surface_set_material(0, _vox_materials[surface])
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _vox_glow)
	return mesh


const _FACES := [
	[Vector3i(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)], 0.82],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)], 0.82],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)], 1.0],
	[Vector3i(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)], 0.6],
	[Vector3i(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)], 0.92],
	[Vector3i(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)], 0.92],
]


static func _vox_surface(mesh: ArrayMesh, g: Dictionary, glow: Dictionary) -> void:
	for pass_i in 2:
		var src: Dictionary = g if pass_i == 0 else glow
		if src.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in src:
			var c: Color = src[p]
			for f in _FACES:
				var nb: Vector3i = p + f[0]
				if g.has(nb) or glow.has(nb):
					continue
				var q: Array = f[1]
				var base := Vector3(p.x - 0.5, p.y, p.z - 0.5) * VOX
				st.set_normal(Vector3(f[0]))
				st.set_color(c * float(f[2]) if pass_i == 0 else c)
				for idx in [0, 1, 2, 0, 2, 3]:
					st.add_vertex(base + (q[idx] as Vector3) * VOX)
		st.commit(mesh)


## Полупрозрачность воксельной модели (герой за деревом): прозрачность с предпроходом
## глубины — видна только внешняя оболочка, ствол и внутренние грани не просвечивают.
static var _fade_cache := {}


static func fade_mats(k: float) -> Array:
	var q := int(round(k * 10.0))
	if not _fade_cache.has(q):
		var a := 1.0 - float(q) / 10.0
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.albedo_color = Color(1, 1, 1, a)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		var gm := StandardMaterial3D.new()
		gm.vertex_color_use_as_albedo = true
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(2.2, 2.2, 2.2, a)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_fade_cache[q] = [m, gm]
	return _fade_cache[q]


static func set_fade(mi: MeshInstance3D, k: float) -> void:
	var n := mi.mesh.get_surface_count() if mi.mesh else 0
	if k <= 0.001:
		for i in n:
			mi.set_surface_override_material(i, null)
		return
	var ms := fade_mats(k)
	for i in n:
		mi.set_surface_override_material(i, ms[mini(i, 1)])


## Полупрозрачность обычных мешей (дома, заборы, деревья без вокселей).
## Свойство GeometryInstance3D.transparency рендер Compatibility (Android, iPhone)
## не поддерживает — там подменяем материалы поверхностей на полупрозрачные копии.
static var _alpha_cache := {}


static func set_fade_any(gi: GeometryInstance3D, k: float) -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility" or not (gi is MeshInstance3D):
		gi.transparency = k
		return
	var mi := gi as MeshInstance3D
	if mi.mesh == null:
		return
	var n := mi.mesh.get_surface_count()
	if not mi.has_meta("orig_mats"):
		var orig: Array = []
		for i in n:
			orig.append(mi.get_surface_override_material(i))
		mi.set_meta("orig_mats", orig)
	var orig2: Array = mi.get_meta("orig_mats")
	if mi.material_override != null and not mi.has_meta("orig_override"):
		mi.set_meta("orig_override", mi.material_override)
	var ov: Material = mi.get_meta("orig_override", null)
	var q := int(round(k * 10.0))
	if q <= 0:
		for i in n:
			mi.set_surface_override_material(i, orig2[i] if i < orig2.size() else null)
		if ov != null:
			mi.material_override = ov
		return
	if ov != null:
		mi.material_override = null
	for i in n:
		var base: Material = ov
		if base == null:
			base = orig2[i] if i < orig2.size() and orig2[i] != null else mi.mesh.surface_get_material(i)
		if not (base is StandardMaterial3D):
			continue
		var key := "%d:%d" % [base.get_instance_id(), q]
		if not _alpha_cache.has(key):
			var c := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			c.albedo_color.a = (base as StandardMaterial3D).albedo_color.a * (1.0 - float(q) / 10.0)
			_alpha_cache[key] = c
		mi.set_surface_override_material(i, _alpha_cache[key])


# ================= Свои объекты глав героев =================
# У каждой главы — свой набор: стена коридора (w), крупный объект (b), убранство (d).
# Всё собрано из примитивов по лору края, а не из общих объектов поля боя.

const CHAP_COL := {"vega": Color(0.69, 0.40, 1.00), "rin": Color(1.00, 0.29, 0.42), "bram": Color(1.00, 0.54, 0.16),
	"kira": Color(0.23, 1.00, 0.78), "skyla": Color(0.75, 0.85, 1.00), "orm": Color(1.00, 0.72, 0.29),
	"mora": Color(0.75, 0.25, 1.00), "zephyr": Color(0.48, 0.82, 1.00), "iris": Color(0.54, 1.00, 0.23),
	"lyra": Color(1.00, 0.42, 0.82), "sol": Color(1.00, 0.87, 0.33), "volt": Color(0.27, 0.87, 1.00), "kai": Color(0.55, 0.55, 1.00)}


## Размер объекта главы в пикселях спрайта (для границ видимости и света).
static func csize(kind: String) -> Vector2:
	match kind.get_slice("_", 2):
		"w":
			return Vector2(46, 40)
		"b":
			return Vector2(36, 90)
	return Vector2(18, 20)


static func cglow(kind: String) -> Color:
	return CHAP_COL.get(kind.get_slice("_", 1), CYAN)


static func _chap3d(root: Node3D, kind: String, rng: RandomNumberGenerator) -> void:
	var h := kind.get_slice("_", 1)
	var part := kind.get_slice("_", 2)
	var g: Color = CHAP_COL.get(h, CYAN)
	var gl := emat(g, 1.6)
	var gs := emat(g, 0.8)
	match h + "_" + part:
		# ---- Вега: сгоревшая Академия техномагии ----
		"vega_w":
			var char_w := mat(Color(0.16, 0.12, 0.16), "wood", 2.4)
			_add(root, _box(1.3, 1.25, 0.36), char_w, Vector3(0, 0.62, 0))
			for y: float in [0.3, 0.68, 1.05]:
				_add(root, _box(1.2, 0.04, 0.3), mat(Color(0.1, 0.08, 0.1), "", 1.0), Vector3(0, y - 0.12, 0.02))
				for k in 7:
					if rng.randf() < 0.75:
						var bh := rng.randf_range(0.18, 0.28)
						_add(root, _box(0.11, bh, 0.24), mat(Color(0.25 + rng.randf() * 0.2, 0.12, 0.2 + rng.randf() * 0.2), "", 1.0), Vector3(-0.5 + k * 0.165, y - 0.1 + bh / 2.0, 0.03), Vector3(0, 0, rng.randf_range(-8, 8)))
			_add(root, _box(1.32, 0.03, 0.03), gl, Vector3(0, 1.26, 0.19), Vector3.ZERO, false)
			_add(root, _box(0.5, 0.08, 0.02), emat(Color(1.0, 0.45, 0.2), 2.4), Vector3(rng.randf_range(-0.3, 0.3), 0.08, 0.19), Vector3.ZERO, false)
		"vega_b":
			var st := mat(Color(0.3, 0.27, 0.36), "brick", 2.0)
			_add(root, _cyl(0.4, 0.46, 0.3, 8), st, Vector3(0, 0.15, 0))
			_add(root, _cyl(0.22, 0.28, 2.2, 8), st, Vector3(0, 1.4, 0), Vector3(0, 0, 4))
			_add(root, _box(0.7, 0.12, 0.5), mat(Color(0.18, 0.14, 0.2), "wood", 2.0), Vector3(0.05, 2.5, 0), Vector3(-18, 0, 4))
			for k in 3:
				var an := TAU * k / 3.0
				_add(root, _box(0.08, 0.16, 0.02), gs, Vector3(cos(an) * 0.32, 2.85 + k * 0.12, sin(an) * 0.32), Vector3(0, -rad_to_deg(an), 20), false)
			_add(root, _sph(0.12, 8), gl, Vector3(0, 2.95, 0), Vector3.ZERO, false)
		"vega_d":
			for k in 4:
				_add(root, _box(0.36 - k * 0.04, 0.08, 0.26 - k * 0.02), mat(Color(0.3, 0.16, 0.3).lightened(k * 0.08), "", 1.0), Vector3(0, 0.04 + k * 0.08, 0), Vector3(0, rng.randf_range(-25, 25), 0))
			_add(root, _box(0.18, 0.18, 0.01), gl, Vector3(0, 0.55, 0), Vector3(0, 30, 0), false)
		# ---- Рин: поместье клана Тэцу ----
		"rin_w":
			var wd := mat(Color(0.28, 0.14, 0.12), "wood", 2.6)
			for x: float in [-0.6, 0.6]:
				_add(root, _box(0.1, 1.5, 0.12), wd, Vector3(x, 0.75, 0))
			_add(root, _box(1.3, 0.1, 0.14), wd, Vector3(0, 1.5, 0))
			_add(root, _box(1.3, 0.08, 0.14), wd, Vector3(0, 0.08, 0))
			_add(root, _box(1.1, 1.3, 0.04), emat(Color(1.0, 0.9, 0.82), 0.45), Vector3(0, 0.78, 0))
			for x: float in [-0.2, 0.2]:
				_add(root, _box(0.03, 1.3, 0.06), wd, Vector3(x, 0.78, 0))
			_add(root, _box(1.1, 0.03, 0.06), wd, Vector3(0, 0.8, 0))
			_add(root, _box(0.18, 0.18, 0.02), gl, Vector3(0.38, 1.15, 0.04), Vector3(0, 0, 45), false)
		"rin_b":
			var red := mat(Color(0.62, 0.12, 0.14), "wood", 2.0)
			for x: float in [-0.55, 0.55]:
				_add(root, _cyl(0.09, 0.11, 2.4, 8), red, Vector3(x, 1.2, 0))
				_add(root, _cyl(0.14, 0.14, 0.18, 8), mat(Color(0.1, 0.08, 0.08), "", 1.0), Vector3(x, 0.09, 0))
			_add(root, _box(1.7, 0.16, 0.22), mat(Color(0.12, 0.08, 0.08), "wood", 2.0), Vector3(0, 2.45, 0))
			_add(root, _box(1.45, 0.12, 0.16), red, Vector3(0, 2.1, 0))
			_add(root, _box(0.24, 0.32, 0.04), gl, Vector3(0, 2.27, 0.1), Vector3.ZERO, false)
		"rin_d":
			var wd2 := mat(Color(0.2, 0.1, 0.08), "wood", 2.0)
			_add(root, _box(0.5, 0.06, 0.12), wd2, Vector3(0, 0.05, 0))
			for x: float in [-0.2, 0.2]:
				_add(root, _box(0.05, 0.45, 0.08), wd2, Vector3(x, 0.25, 0))
			for k in 2:
				_add(root, _box(0.62, 0.025, 0.02), gl if k == 0 else mat(Color(0.75, 0.75, 0.8), "", 1.0, 0.3), Vector3(0, 0.3 + k * 0.13, 0.05), Vector3(0, 0, 6), false)
		# ---- Брам: подгорные штольни и рунные кузни ----
		"bram_w":
			var wd := mat(Color(0.32, 0.22, 0.14), "wood", 2.4)
			var rk := mat(Color(0.26, 0.22, 0.22), "brick", 1.4)
			var r := _add(root, _sph(0.6, 8), rk, Vector3(0, 0.35, 0))
			r.scale = Vector3(1.15, 0.75, 0.42)
			for x: float in [-0.5, 0.5]:
				_add(root, _box(0.14, 1.3, 0.14), wd, Vector3(x, 0.65, 0.12))
			_add(root, _box(1.3, 0.16, 0.16), wd, Vector3(0, 1.32, 0.12))
			_add(root, _sph(0.07, 6), emat(Color(1.0, 0.7, 0.3), 2.6), Vector3(0, 1.18, 0.22), Vector3.ZERO, false)
			for k in 3:
				_add(root, _sph(0.05, 5), gs, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 0.55), 0.24), Vector3.ZERO, false)
		"bram_b":
			var iron := mat(Color(0.22, 0.22, 0.26), "panel", 2.0, 0.4)
			_add(root, _cyl(0.5, 0.6, 0.5, 8), mat(Color(0.3, 0.26, 0.24), "brick", 1.6), Vector3(0, 0.25, 0))
			_add(root, _box(0.5, 0.35, 0.4), iron, Vector3(0, 0.68, 0))
			_add(root, _box(1.2, 0.26, 0.5), iron, Vector3(0.1, 0.98, 0))
			_add(root, _prism(0.4, 0.26, 0.5), iron, Vector3(-0.68, 0.98, 0), Vector3(0, 0, 90))
			_add(root, _box(0.9, 0.03, 0.03), gl, Vector3(0.1, 0.98, 0.26), Vector3.ZERO, false)
			for k in 3:
				_add(root, _box(0.1, 0.1, 0.02), gl, Vector3(-0.2 + k * 0.2, 0.68, 0.21), Vector3(0, 0, 45), false)
		"bram_d":
			var ir := mat(Color(0.3, 0.26, 0.24), "panel", 2.0)
			_add(root, _box(0.5, 0.26, 0.34), ir, Vector3(0, 0.2, 0))
			for x: float in [-0.18, 0.18]:
				_add(root, _cyl(0.07, 0.07, 0.38, 8), mat(Color(0.12, 0.12, 0.14), "", 1.0), Vector3(x, 0.07, 0), Vector3(90, 0, 0))
			for k in 4:
				_add(root, _sph(0.08, 5), gl, Vector3(rng.randf_range(-0.15, 0.15), 0.36, rng.randf_range(-0.1, 0.1)), Vector3.ZERO, false)
		# ---- Кира: серверные катакомбы ----
		"kira_w":
			var bl := mat(Color(0.08, 0.1, 0.12), "panel", 3.0, 0.4)
			for x: float in [-0.33, 0.33]:
				_add(root, _box(0.6, 1.6, 0.42), bl, Vector3(x, 0.8, 0))
				for y in 8:
					_add(root, _box(0.5, 0.02, 0.02), emat(Color(0.1, 0.25, 0.25), 0.6), Vector3(x, 0.18 + y * 0.18, 0.21), Vector3.ZERO, false)
					if rng.randf() < 0.55:
						_add(root, _box(0.04, 0.04, 0.02), gl if rng.randf() < 0.7 else emat(Color(1.0, 0.3, 0.3), 2.0), Vector3(x + rng.randf_range(-0.2, 0.2), 0.24 + y * 0.18, 0.22), Vector3.ZERO, false)
		"kira_b":
			var mt := mat(Color(0.2, 0.24, 0.26), "panel", 2.0, 0.4)
			_add(root, _cyl(0.32, 0.42, 0.3, 6), mt, Vector3(0, 0.15, 0))
			_add(root, _cyl(0.06, 0.12, 3.0, 6), mt, Vector3(0, 1.7, 0))
			for k in 3:
				_add(root, _cyl(0.17 - k * 0.03, 0.17 - k * 0.03, 0.03, 10), gs, Vector3(0, 1.4 + k * 0.6, 0), Vector3.ZERO, false)
			_add(root, _sph(0.1, 8), gl, Vector3(0, 3.25, 0), Vector3.ZERO, false)
			for a in 4:
				var an := TAU * a / 4.0
				_add(root, _cyl(0.025, 0.025, 1.3, 4), mat(Color(0.05, 0.05, 0.06), "", 1.0), Vector3(cos(an) * 0.45, 0.6, sin(an) * 0.45), Vector3(sin(an) * 25, 0, -cos(an) * 25))
		"kira_d":
			for k in 3:
				var t := _add(root, _cyl(0.24 - k * 0.05, 0.24 - k * 0.05, 0.06, 12), mat(Color(0.06, 0.07, 0.08), "", 1.0), Vector3(0, 0.03 + k * 0.06, 0))
				t.scale = Vector3(1, 1, 0.8)
			_add(root, _box(0.06, 0.06, 0.06), gl, Vector3(0.12, 0.2, 0.1), Vector3.ZERO, false)
		# ---- Скайла: туманный тракт Серебряных Сов ----
		"skyla_w":
			var lg := mat(Color(0.32, 0.3, 0.3), "wood", 2.2)
			for k in 6:
				var hh := rng.randf_range(1.1, 1.45)
				_add(root, _cyl(0.1, 0.11, hh, 6), lg, Vector3(-0.55 + k * 0.22, hh / 2.0, 0), Vector3(0, 0, rng.randf_range(-4, 4)))
				_add(root, _cyl(0.0, 0.1, 0.18, 6), lg, Vector3(-0.55 + k * 0.22, hh + 0.09, 0))
			_add(root, _box(1.35, 0.08, 0.06), mat(Color(0.22, 0.2, 0.2), "wood", 2.0), Vector3(0, 0.75, 0.1))
			_add(root, _box(0.05, 0.12, 0.02), gl, Vector3(0.1, 0.95, 0.13), Vector3(0, 0, 20), false)
		"skyla_b":
			var lg2 := mat(Color(0.3, 0.28, 0.28), "wood", 2.2)
			for a in 4:
				var an := TAU * a / 4.0 + PI / 4.0
				_add(root, _cyl(0.05, 0.07, 2.4, 5), lg2, Vector3(cos(an) * 0.32, 1.2, sin(an) * 0.32), Vector3(sin(an) * -5, 0, cos(an) * 5))
			_add(root, _box(0.9, 0.08, 0.9), lg2, Vector3(0, 2.4, 0))
			_add(root, _box(0.7, 0.5, 0.7), mat(Color(0.26, 0.26, 0.3), "wood", 2.0), Vector3(0, 2.7, 0))
			_add(root, _prism(1.0, 0.45, 1.0), mat(Color(0.2, 0.22, 0.3), "wood", 2.0), Vector3(0, 3.18, 0))
			for x: float in [-0.12, 0.12]:
				_add(root, _sph(0.07, 6), gl, Vector3(x, 2.75, 0.36), Vector3.ZERO, false)
		"skyla_d":
			var wh := _add(root, _cyl(0.3, 0.3, 0.06, 10), mat(Color(0.3, 0.26, 0.22), "wood", 2.0), Vector3(0, 0.3, 0), Vector3(80, 0, 0))
			wh.scale = Vector3.ONE
			_add(root, _cyl(0.04, 0.04, 0.5, 4), mat(Color(0.2, 0.2, 0.2), "", 1.0), Vector3(0.3, 0.25, 0.1))
			_add(root, _box(0.1, 0.12, 0.1), gl, Vector3(0.3, 0.55, 0.1), Vector3.ZERO, false)
		# ---- Орм: медная цитадель ----
		"orm_w":
			var cu := mat(Color(0.62, 0.38, 0.2), "panel", 2.4, 0.35)
			_add(root, _box(1.35, 1.35, 0.3), cu, Vector3(0, 0.68, 0))
			for x in 4:
				for y in 3:
					_add(root, _sph(0.03, 4), mat(Color(0.8, 0.6, 0.35), "", 1.0, 0.3), Vector3(-0.55 + x * 0.36, 0.25 + y * 0.45, 0.16))
			_add(root, _cyl(0.07, 0.07, 1.4, 8), mat(Color(0.45, 0.28, 0.16), "panel", 2.0, 0.35), Vector3(0, 1.0, 0.2), Vector3(0, 0, 90))
			_add(root, _box(0.18, 0.18, 0.04), gl, Vector3(0.4, 0.55, 0.16), Vector3(0, 0, 45), false)
		"orm_b":
			var cu2 := mat(Color(0.6, 0.36, 0.18), "panel", 2.2, 0.35)
			_add(root, _cyl(0.5, 0.55, 1.3, 12), cu2, Vector3(0, 0.65, 0))
			_add(root, _sph(0.5, 12), cu2, Vector3(0, 1.3, 0))
			_add(root, _cyl(0.1, 0.12, 1.4, 8), mat(Color(0.25, 0.2, 0.18), "panel", 2.0), Vector3(0.2, 2.2, 0))
			_add(root, _cyl(0.2, 0.2, 0.04, 12), gl, Vector3(0, 0.6, 0.48), Vector3(90, 0, 0), false)
			_add(root, _sph(0.08, 6), emat(Color(1.0, 0.5, 0.2), 2.5), Vector3(0.2, 2.95, 0), Vector3.ZERO, false)
		"orm_d":
			var cu3 := mat(Color(0.55, 0.34, 0.18), "panel", 2.0, 0.35)
			_add(root, _cyl(0.06, 0.06, 0.5, 8), cu3, Vector3(0, 0.25, 0))
			_add(root, _cyl(0.06, 0.06, 0.4, 8), cu3, Vector3(0.18, 0.5, 0), Vector3(0, 0, 90))
			_add(root, _cyl(0.12, 0.12, 0.03, 10), gl, Vector3(0, 0.55, 0.05), Vector3(90, 0, 0), false)
		# ---- Мора: кладбище данных ----
		"mora_w":
			var gr := mat(Color(0.22, 0.2, 0.26), "brick", 2.0)
			for x: float in [-0.4, 0.4]:
				var hh := rng.randf_range(0.9, 1.25)
				_add(root, _box(0.5, hh, 0.16), gr, Vector3(x, hh / 2.0, 0), Vector3(0, 0, rng.randf_range(-6, 6)))
				_add(root, _cyl(0.25, 0.25, 0.16, 10), gr, Vector3(x, hh, 0), Vector3(90, 0, 0))
				_add(root, _box(0.3, 0.22, 0.02), gs, Vector3(x, hh * 0.65, 0.09), Vector3.ZERO, false)
				_add(root, _box(0.3 * rng.randf_range(0.2, 1.0), 0.03, 0.02), gl, Vector3(x - 0.05, hh * 0.45, 0.09), Vector3.ZERO, false)
		"mora_b":
			var gr2 := mat(Color(0.24, 0.2, 0.28), "brick", 2.0)
			_add(root, _box(0.8, 0.3, 0.8), gr2, Vector3(0, 0.15, 0))
			_add(root, _cyl(0.0, 0.32, 2.6, 4), gr2, Vector3(0, 1.6, 0), Vector3(0, 45, 0))
			_add(root, _cyl(0.22, 0.22, 0.03, 14), gs, Vector3(0, 3.0, 0), Vector3(80, 0, 0), false)
			for a in 3:
				_add(root, _box(0.06, 0.6, 0.02), gs, Vector3(-0.15 + a * 0.15, 1.0, 0.16), Vector3.ZERO, false)
		"mora_d":
			_add(root, _box(0.3, 0.2, 0.06), mat(Color(0.22, 0.2, 0.26), "brick", 2.0), Vector3(0, 0.1, 0))
			for x: float in [-0.08, 0.08]:
				_add(root, _cyl(0.025, 0.025, 0.14, 5), mat(Color(0.85, 0.82, 0.75), "", 1.0), Vector3(x, 0.27, 0.06))
				_add(root, _sph(0.03, 5), gl, Vector3(x, 0.36, 0.06), Vector3.ZERO, false)
		# ---- Зефир: степь грозы ----
		"zephyr_w":
			for k in 4:
				var hh := rng.randf_range(0.7, 1.5)
				_add(root, _cyl(0.0, rng.randf_range(0.14, 0.24), hh, 4), mat(Color(0.5, 0.65, 0.75, 1.0), "", 1.0, 0.1), Vector3(-0.5 + k * 0.33, hh / 2.0, rng.randf_range(-0.08, 0.08)), Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 90), rng.randf_range(-12, 12)))
			_add(root, _box(0.03, 0.7, 0.03), gl, Vector3(0.1, 0.4, 0.12), Vector3(0, 0, 18), false)
		"zephyr_b":
			var cu := mat(Color(0.5, 0.34, 0.2), "panel", 2.0, 0.35)
			for k in 4:
				_add(root, _cyl(0.24 - k * 0.03, 0.26 - k * 0.03, 0.6, 6), cu, Vector3(0, 0.3 + k * 0.6, 0), Vector3(0, k * 30, 0))
				_add(root, _box(0.16, 0.08, 0.02), gl, Vector3(0, 0.36 + k * 0.6, 0.24 - k * 0.03), Vector3.ZERO, false)
			for x: float in [-1.0, 1.0]:
				_add(root, _box(0.5, 0.06, 0.08), cu, Vector3(x * 0.35, 2.1, 0), Vector3(0, 0, x * 20))
			_add(root, _cyl(0.0, 0.03, 0.8, 4), gl, Vector3(0, 2.8, 0), Vector3.ZERO, false)
		"zephyr_d":
			var rk2 := _add(root, _sph(0.22, 6), mat(Color(0.32, 0.36, 0.42), "", 1.0), Vector3(0, 0.12, 0))
			rk2.scale = Vector3(1.2, 0.6, 1.0)
			for k in 3:
				_add(root, _cyl(0.01, 0.01, 0.25 + k * 0.08, 3), gl, Vector3(-0.08 + k * 0.08, 0.35, 0), Vector3.ZERO, false)
		# ---- Ирис: карантин «Сплава» ----
		"iris_w":
			var yl := mat(Color(0.75, 0.68, 0.18), "panel", 2.0)
			var bk := mat(Color(0.1, 0.1, 0.1), "", 1.0)
			for x: float in [-0.55, 0.55]:
				_add(root, _box(0.1, 0.9, 0.3), bk, Vector3(x, 0.45, 0))
			for k in 6:
				_add(root, _box(0.2, 0.2, 0.06), yl if k % 2 == 0 else bk, Vector3(-0.5 + k * 0.2, 0.75, 0.02))
			_add(root, _box(1.2, 0.04, 0.04), gl, Vector3(0, 0.35, 0.05), Vector3.ZERO, false)
			_add(root, _box(1.3, 0.5, 0.02), emat(Color(0.5, 1.0, 0.3), 0.25), Vector3(0, 1.15, 0), Vector3.ZERO, false)
		"iris_b":
			var mt2 := mat(Color(0.3, 0.32, 0.3), "panel", 2.0, 0.4)
			_add(root, _cyl(0.45, 0.5, 0.3, 12), mt2, Vector3(0, 0.15, 0))
			_add(root, _cyl(0.38, 0.38, 1.7, 12), emat(Color(g.r * 0.45, g.g * 0.45, g.b * 0.45), 0.6), Vector3(0, 1.15, 0))
			_add(root, _cyl(0.45, 0.45, 0.25, 12), mt2, Vector3(0, 2.1, 0))
			var blob := _add(root, _sph(0.22, 8), mat(Color(0.15, 0.18, 0.12), "", 1.0), Vector3(0, 1.1, 0))
			blob.scale = Vector3(1.0, 1.5, 0.8)
			for k in 3:
				_add(root, _cyl(0.03, 0.03, 0.6, 4), mt2, Vector3(-0.2 + k * 0.2, 2.5, 0), Vector3(0, 0, -20 + k * 20))
		"iris_d":
			_add(root, _cyl(0.17, 0.17, 0.42, 10), mat(Color(0.7, 0.62, 0.15), "panel", 2.0), Vector3(0, 0.21, 0))
			_add(root, _cyl(0.1, 0.1, 0.02, 3), emat(Color(0.05, 0.05, 0.05), 0.0), Vector3(0, 0.25, 0.17), Vector3(90, 0, 0), false)
			_add(root, _cyl(0.12, 0.12, 0.03, 10), gl, Vector3(0, 0.43, 0), Vector3.ZERO, false)
		# ---- Лира: цирк «Сплав» ----
		"lyra_w":
			for k in 7:
				_add(root, _box(0.17, 0.7, 0.14), mat(Color(0.85, 0.82, 0.86) if k % 2 == 0 else Color(0.7, 0.15, 0.35), "wood", 2.0), Vector3(-0.54 + k * 0.18, 0.35, 0))
				_add(root, _sph(0.06, 6), gl if k % 2 == 0 else emat(Color(1.0, 0.85, 0.4), 2.0), Vector3(-0.54 + k * 0.18, 0.76, 0), Vector3.ZERO, false)
			_add(root, _box(1.3, 0.06, 0.18), mat(Color(0.75, 0.6, 0.25), "", 1.0, 0.3), Vector3(0, 0.7, 0))
		"lyra_b":
			_add(root, _cyl(0.06, 0.08, 3.0, 8), mat(Color(0.8, 0.7, 0.4), "", 1.0, 0.3), Vector3(0, 1.5, 0))
			for k in 8:
				var an := TAU * k / 8.0
				_add(root, _cyl(0.0, 0.32, 0.7, 3), mat(Color(0.85, 0.82, 0.86) if k % 2 == 0 else Color(0.75, 0.15, 0.4), "", 1.0), Vector3(cos(an) * 0.18, 2.75, sin(an) * 0.18), Vector3(sin(an) * -25, -rad_to_deg(an), cos(an) * 25))
			_add(root, _sph(0.1, 6), gl, Vector3(0, 3.15, 0), Vector3.ZERO, false)
			for k in 6:
				_add(root, _sph(0.045, 5), emat(Color(1.0, 0.85, 0.4), 2.2), Vector3(cos(k) * 0.5, 2.3 - k * 0.2, sin(k) * 0.5), Vector3.ZERO, false)
		"lyra_d":
			_add(root, _cyl(0.2, 0.2, 0.3, 12), mat(Color(0.7, 0.15, 0.35), "", 1.0), Vector3(0, 0.15, 0))
			_add(root, _cyl(0.21, 0.21, 0.03, 12), gl, Vector3(0, 0.31, 0), Vector3.ZERO, false)
			_add(root, _sph(0.14, 10), mat(Color(0.2, 0.4, 0.95), "", 1.0), Vector3(0, 0.46, 0))
		# ---- Сол: рассвет над Вратами ----
		"sol_w":
			var mb := mat(Color(0.82, 0.78, 0.7), "brick", 1.2, 0.5)
			_add(root, _box(1.4, 0.14, 0.34), mb, Vector3(0, 0.07, 0))
			_add(root, _box(1.4, 0.14, 0.34), mb, Vector3(0, 0.95, 0))
			for k in 6:
				_add(root, _cyl(0.06, 0.09, 0.74, 8), mb, Vector3(-0.55 + k * 0.22, 0.51, 0))
			_add(root, _box(1.4, 0.03, 0.03), gl, Vector3(0, 1.03, 0.18), Vector3.ZERO, false)
		"sol_b":
			var mb2 := mat(Color(0.82, 0.78, 0.7), "brick", 1.2, 0.5)
			_add(root, _box(0.7, 0.3, 0.7), mb2, Vector3(0, 0.15, 0))
			_add(root, _cyl(0.2, 0.24, 2.2, 10), mb2, Vector3(0, 1.4, 0))
			_add(root, _cyl(0.32, 0.32, 0.05, 16), mat(Color(0.75, 0.6, 0.3), "", 1.0, 0.3), Vector3(0, 2.75, 0), Vector3(90, 0, 0))
			_add(root, _cyl(0.18, 0.18, 0.07, 14), gs, Vector3(0, 2.75, 0.02), Vector3(90, 0, 0), false)
		"sol_d":
			_add(root, _cyl(0.2, 0.08, 0.3, 8), mat(Color(0.6, 0.45, 0.22), "", 1.0, 0.3), Vector3(0, 0.35, 0))
			_add(root, _cyl(0.04, 0.04, 0.2, 6), mat(Color(0.6, 0.45, 0.22), "", 1.0, 0.3), Vector3(0, 0.1, 0))
			_add(root, _cyl(0.0, 0.14, 0.24, 6), emat(Color(1.0, 0.6, 0.2), 2.6), Vector3(0, 0.6, 0), Vector3.ZERO, false)
		# ---- Вольт: сердце грозы ----
		"volt_w":
			var mt3 := mat(Color(0.22, 0.26, 0.3), "panel", 2.4, 0.4)
			_add(root, _box(1.3, 1.0, 0.46), mt3, Vector3(0, 0.5, 0))
			for k in 6:
				_add(root, _box(0.04, 0.8, 0.06), mat(Color(0.15, 0.17, 0.2), "", 1.0), Vector3(-0.5 + k * 0.2, 0.5, 0.24))
			_add(root, _prism(0.24, 0.24, 0.02), emat(Color(1.0, 0.85, 0.2), 1.8), Vector3(0.35, 0.75, 0.25), Vector3.ZERO, false)
			for x: float in [-0.35, 0.0]:
				_add(root, _cyl(0.06, 0.08, 0.3, 8), mat(Color(0.75, 0.75, 0.7), "", 1.0, 0.3), Vector3(x, 1.15, 0))
			_add(root, _box(1.2, 0.03, 0.03), gl, Vector3(0, 0.12, 0.24), Vector3.ZERO, false)
		"volt_b":
			var mt4 := mat(Color(0.3, 0.32, 0.36), "panel", 2.0, 0.4)
			for a in 3:
				var an := TAU * a / 3.0
				_add(root, _box(0.07, 3.0, 0.07), mt4, Vector3(cos(an) * 0.25, 1.5, sin(an) * 0.25), Vector3(sin(an) * -4, 0, cos(an) * 4))
			for k in 4:
				_add(root, _cyl(0.2 - k * 0.025, 0.2 - k * 0.025, 0.05, 10), gs, Vector3(0, 0.8 + k * 0.6, 0), Vector3.ZERO, false)
			_add(root, _sph(0.22, 10), gl, Vector3(0, 3.15, 0), Vector3.ZERO, false)
		"volt_d":
			_add(root, _cyl(0.04, 0.05, 0.6, 6), mat(Color(0.3, 0.25, 0.2), "wood", 2.0), Vector3(0, 0.3, 0))
			for k in 3:
				_add(root, _cyl(0.08, 0.08, 0.05, 8), mat(Color(0.75, 0.85, 0.8), "", 1.0, 0.2), Vector3(0, 0.45 + k * 0.07, 0))
			_add(root, _sph(0.04, 5), gl, Vector3(0, 0.68, 0), Vector3.ZERO, false)
		# ---- Кай: свитки Безлунных ----
		"kai_w":
			var bm := mat(Color(0.3, 0.42, 0.22), "wood", 3.0)
			for k in 8:
				var hh := rng.randf_range(1.2, 2.0)
				var x := -0.6 + k * 0.17 + rng.randf_range(-0.03, 0.03)
				_add(root, _cyl(0.045, 0.05, hh, 6), bm, Vector3(x, hh / 2.0, rng.randf_range(-0.12, 0.12)), Vector3(0, 0, rng.randf_range(-5, 5)))
				for y in int(hh / 0.4):
					_add(root, _cyl(0.055, 0.055, 0.03, 6), mat(Color(0.2, 0.3, 0.15), "", 1.0), Vector3(x, 0.4 + y * 0.4, 0))
			_add(root, _box(0.03, 0.3, 0.03), gl, Vector3(0.2, 1.2, 0.15), Vector3.ZERO, false)
		"kai_b":
			var st2 := mat(Color(0.34, 0.34, 0.38), "brick", 1.4)
			_add(root, _box(0.6, 0.2, 0.6), st2, Vector3(0, 0.1, 0))
			_add(root, _cyl(0.1, 0.12, 0.7, 6), st2, Vector3(0, 0.55, 0))
			_add(root, _box(0.5, 0.4, 0.5), st2, Vector3(0, 1.1, 0))
			_add(root, _box(0.3, 0.22, 0.52), gl, Vector3(0, 1.1, 0), Vector3.ZERO, false)
			for k in 2:
				_add(root, _prism(0.9 - k * 0.25, 0.3, 0.9 - k * 0.25), st2, Vector3(0, 1.45 + k * 0.32, 0))
		"kai_d":
			_add(root, _cyl(0.02, 0.02, 0.6, 4), mat(Color(0.2, 0.15, 0.1), "", 1.0), Vector3(0, 0.3, 0))
			var mk := _add(root, _sph(0.13, 8), mat(Color(0.92, 0.9, 0.86), "", 1.0), Vector3(0, 0.65, 0.02))
			mk.scale = Vector3(0.9, 1.15, 0.45)
			for x: float in [-0.05, 0.05]:
				_add(root, _box(0.04, 0.015, 0.02), gl, Vector3(x, 0.68, 0.08), Vector3.ZERO, false)
			_add(root, _box(0.02, 0.1, 0.02), emat(Color(1.0, 0.25, 0.3), 1.6), Vector3(0, 0.58, 0.08), Vector3.ZERO, false)
		_:
			_add(root, _box(0.6, 0.6, 0.6), mat(Color(0.3, 0.3, 0.35), "panel", 2.0), Vector3(0, 0.3, 0))
