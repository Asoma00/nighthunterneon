extends Node2D
## Бесконечный процедурный мир боя. Земля разбита на чанки, каждый чанк получает
## район по шуму (новый узор в каждом забеге): улица, рынок, парк, поля, лес,
## кристальное поле, руины, крепость, свалка. Набор районов задаёт уровень, поэтому
## уровни выглядят по-разному. Район — продуманная застройка, а не случайная россыпь.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Props3D := preload("res://scripts/props3d.gd")

const CHUNK := 768.0
## Мир замкнут: через WORLD_CHUNKS чанков (≈123 м) в любую сторону местность повторяется,
## как на торе. Уйдя достаточно далеко, герой снова выходит к знакомым местам.
const WORLD_CHUNKS := 40   # ≈ 300 м до повтора — за забег одно и то же место не встречается
const WORLD_SIZE := CHUNK * WORLD_CHUNKS


static func wrap_key(k: Vector2i) -> Vector2i:
	return Vector2i(posmod(k.x, WORLD_CHUNKS), posmod(k.y, WORLD_CHUNKS))


## Точка мира, приведённая к исходной «копии» вокруг (0, 0).
static func wrap_pos(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x + WORLD_SIZE / 2.0, WORLD_SIZE) - WORLD_SIZE / 2.0,
		fposmod(p.y + WORLD_SIZE / 2.0, WORLD_SIZE) - WORLD_SIZE / 2.0)

const BIOMES := [
	{"name": "Кибер-посад", "tint": Color(0.35, 0.6, 1.0),
		"props": ["house0", "house1", "house2", "lantern0", "lantern0", "stall0", "stall1", "well0", "banner0",
			"cart0", "barrel0", "barrel1", "crate0", "sign0", "sign1", "fence0", "puddle0", "lamp1"],
		"decals": ["decal_cobble", "decal_cobble", "decal_road", "decal_cable"], "landmarks": ["street", "market"],
		"count": [16, 24]},
	{"name": "Кристальные пустоши", "tint": Color(0.6, 0.35, 1.0),
		"props": ["crystal0", "crystal1", "crystal_big0", "crystal_big1", "rock0", "rock1", "rock0", "pine1", "bush1", "pillar1"],
		"decals": ["decal_crater", "decal_rune"], "landmarks": ["grove"], "count": [12, 18]},
	{"name": "Неоновая крепость", "tint": Color(1.0, 0.6, 0.3),
		"props": ["tower0", "wall0", "wall0", "banner0", "banner1", "pillar0", "pillar1", "statue0", "obelisk0",
			"lantern0", "well0", "rock1", "house2"],
		"decals": ["decal_rune", "decal_cobble", "decal_moss"], "landmarks": ["castle", "ruins"], "count": [12, 18]},
	{"name": "Техно-лес", "tint": Color(0.3, 1.0, 0.55),
		"props": ["pine0", "pine0", "pine1", "tree0", "tree1", "tree2", "bush0", "bush1", "bush0", "mushroom0",
			"mushroom1", "rock1", "lantern0"],
		"decals": ["decal_moss", "decal_moss"], "landmarks": ["glade", "hamlet"], "count": [22, 32]},
	{"name": "Свалка дронов", "tint": Color(1.0, 0.4, 0.3),
		"props": ["wreck0", "wreck1", "barrel0", "barrel1", "crate0", "crate1", "cart0", "fence0", "rock0", "sign1"],
		"decals": ["decal_cable", "decal_crater", "decal_grate", "decal_road"], "landmarks": ["junk"], "count": [14, 20]},
]

const LIGHT_PROPS := {
	"lamp0": Color(0.25, 0.9, 1.0), "lamp1": Color(1.0, 0.3, 0.75), "crystal_big0": Color(0.3, 0.9, 1.0),
	"crystal_big1": Color(0.7, 0.4, 1.0), "tree1": Color(1.0, 0.3, 0.75), "sign0": Color(1.0, 0.3, 0.75),
	"sign1": Color(0.3, 0.9, 1.0), "mushroom1": Color(1.0, 0.3, 0.75), "tree2": Color(0.3, 0.9, 1.0),
	"lantern0": Color(1.0, 0.7, 0.35), "house0": Color(1.0, 0.35, 0.75), "house1": Color(0.3, 0.9, 1.0),
	"house2": Color(1.0, 0.75, 0.35), "tower0": Color(0.7, 0.4, 1.0), "stall0": Color(1.0, 0.35, 0.75),
	"stall1": Color(0.3, 0.9, 1.0), "well0": Color(0.3, 0.9, 1.0), "gate0": Color(0.3, 0.9, 1.0),
	"pine1": Color(0.3, 0.9, 1.0), "pine2": Color(0.75, 0.6, 1.0), "tree3": Color(0.3, 0.9, 1.0),
	"tree0": Color(0.35, 1.0, 0.55), "manor0": Color(1.0, 0.78, 0.45), "keep0": Color(0.7, 0.4, 1.0),
}

var main: Node2D
var props_parent: Node2D

var _ground: Sprite2D
var _ground_emit: Sprite2D
var _period := 0.0
var _chunks := {}
var _t := 0.0
var _noise := FastNoiseLite.new()
var _current_district := ""
var _lights := 0
const CELL := 128.0
var _grid := {}
var _chunk_obst := {}
var _building_key := Vector2i.ZERO


func _ready() -> void:
	_noise.seed = preload("res://scripts/data.gd").world_seed if preload("res://scripts/data.gd").world_seed != 0 else randi()
	_noise.frequency = 0.22
	_noise.noise_type = FastNoiseLite.TYPE_VALUE
	_dnoise.seed = _noise.seed + 7
	# Ячеистый шум: районы — сплошные области из нескольких чанков, все районы равновероятны
	_dnoise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_dnoise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_dnoise.frequency = 0.45
	_dnoise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var g := Pixel.ground()
	_period = float(g["size"]) * Pixel.PX
	_ground = _make_ground_sprite(g["base"])
	_ground_emit = _make_ground_sprite(g["emit"])
	_ground_emit.material = Pixel.mat_add()


func _make_ground_sprite(t: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, t.get_width() * 8, t.get_height() * 8)
	s.scale = Vector2.ONE * Pixel.PX
	s.z_index = -20
	add_child(s)
	return s


func biome_at(key: Vector2i) -> int:
	return int(DISTRICTS[district_at(key)]["biome"])


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_t += delta
	var c: Vector2 = main.view_center()
	var origin := (c / _period).floor() * _period - Vector2(_period, _period) * 4.0
	_ground.position = origin
	_ground_emit.position = origin
	_ground_emit.modulate = Color(1, 1, 1, 0.4 + 0.2 * sin(_t * 1.7))
	_update_chunks(main.world_centers())
	# Сообщение о входе в новый биом
	var dk := district_at(Vector2i(floori(c.x / CHUNK), floori(c.y / CHUNK)))
	if dk != _current_district:
		if _current_district != "":
			var info: Dictionary = BIOMES[int(DISTRICTS[dk]["biome"])]
			if main.hud and main.hud.has_method("show_area"):
				main.hud.show_area(DISTRICTS[dk]["name"], info["tint"])
		_current_district = dk


func _update_chunks(centers: Array) -> void:
	var needed := {}
	for c in centers:
		var cx := floori(c.x / CHUNK)
		var cy := floori(c.y / CHUNK)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var key := Vector2i(cx + dx, cy + dy)
				needed[key] = true
				if not _chunks.has(key):
					_chunks[key] = _build_chunk(key)
	for key in _chunks.keys():
		if not needed.has(key):
			for n in _chunks[key]:
				if is_instance_valid(n):
					n.queue_free()
			_chunks.erase(key)
			for o in _chunk_obst.get(key, []):
				var arr: Array = _grid.get(o[0], [])
				arr.erase(o[1])
			_chunk_obst.erase(key)


func _build_chunk(key: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wrap_key(key)) ^ _noise.seed   # замкнутый мир: одинаковая застройка у повторов
	var nodes: Array = []
	_building_key = key
	_chunk_obst[key] = []
	var biome: Dictionary = BIOMES[biome_at(key)]
	var origin := Vector2(key) * CHUNK

	# Цветовой оттенок области — мягкое пятно цвета биома на земле
	var tint := Sprite2D.new()
	tint.texture = Pixel.glow()
	tint.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tint.position = origin + Vector2(CHUNK, CHUNK) / 2.0
	tint.scale = Vector2.ONE * CHUNK * 1.4 / 128.0
	tint.modulate = Color(biome["tint"], 0.2)
	tint.z_index = -19
	tint.material = Pixel.mat_add()
	tint.visible = Settings.decor_full()
	add_child(tint)
	nodes.append(tint)

	# Немного «шума» пола биома и затем осмысленная застройка района
	# (на телефоне с упрощённым декором — без пятен-шума)
	# (случайность расходуется одинаково — у напарника по сети мир тот же)
	for i in rng.randi_range(1, 3):
		var dk: String = biome["decals"][rng.randi_range(0, biome["decals"].size() - 1)]
		if dk != "decal_road":
			var dn := _make_decal(dk, origin + Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK), rng)
			if not Settings.decor_full():
				dn.visible = false
			nodes.append(dn)
	_lights = 0
	_road_bands = []
	_build_roads(key, origin, rng, nodes)
	_build_district(district_at(key), origin, rng, nodes, key)
	return nodes


# ================= Сквозные дороги =================
# Каждые ROAD_EVERY участков проходит дорога через всю карту (в своей строке/колонке
# со своим смещением), на пересечениях — площади. Постройки дорогу не перекрывают.

const ROAD_EVERY := 3
const ROAD_HALF := 64.0
var _road_bands: Array = []    # [ось ("h"/"v"), координата в участке]


func _line_off(axis: String, idx: int) -> float:
	var h := hash(Vector3i(idx, 7 if axis == "h" else 13, _noise.seed))
	return float(posmod(h, 300)) - 150.0


func _build_roads(key: Vector2i, origin: Vector2, rng: RandomNumberGenerator, nodes: Array) -> void:
	var wk := wrap_key(key)
	var has_h := posmod(wk.y, ROAD_EVERY) == 1
	var has_v := posmod(wk.x, ROAD_EVERY) == 1
	var H := CHUNK / 2.0
	var hy := H + _line_off("h", floori(float(wk.y) / ROAD_EVERY))
	var vx := H + _line_off("v", floori(float(wk.x) / ROAD_EVERY))
	if has_h:
		_road_h(nodes, origin, rng, hy)
		_road_bands.append(["h", hy])
	if has_v:
		_road_v(nodes, origin, rng, vx)
		_road_bands.append(["v", vx])
	if has_h and has_v:
		# Перекрёсток-площадь: мощёный круг, четыре фонаря, указатель
		var c := Vector2(vx, hy)
		_decal(nodes, origin, "decal_cobble", c, rng, 2.4, 0.0)
		for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_put_force(nodes, origin, "lamp%d" % (0 if k.x < 0 else 1), c + k * 105.0, 0.0, k.x < 0 and k.y < 0)
		_put_force(nodes, origin, "sign%d" % rng.randi_range(0, 1), c + Vector2(118, -18), 0.0, false)
	elif has_h or has_v:
		# Вдоль дороги — придорожные фонари через равные промежутки
		for i in 2:
			var t := 192.0 + i * 384.0
			var p := Vector2(t, hy - 92.0) if has_h else Vector2(vx + 92.0, t)
			_put_force(nodes, origin, "lamp%d" % (i % 2), p, 0.0, i == 0 and rng.randf() < 0.5)


## Точка на дороге? Тогда постройки сюда не ставим.
func _on_road(local: Vector2, pad := 0.0) -> bool:
	for b in _road_bands:
		var d: float = absf(local.y - b[1]) if b[0] == "h" else absf(local.x - b[1])
		if d < ROAD_HALF + pad:
			return true
	return false


func _put_force(nodes: Array, origin: Vector2, kind: String, local: Vector2, rot := 0.0, light := false) -> void:
	var bands := _road_bands
	_road_bands = []
	_put(nodes, origin, kind, local, rot, light)
	_road_bands = bands


# ================= Постройки из комнат (каждый раз своя планировка) =================
# Прямоугольник делится на комнаты (BSP), стены — сегментами, в каждой стене проход.
# Размер, пропорции, число комнат, проходы и содержимое — случайные: двух одинаковых нет.

const WALL_SEG := 148.0


func _wall_line(nodes: Array, origin: Vector2, a: Vector2, b: Vector2, kind: String, rng: RandomNumberGenerator, door := true) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 60.0:
		return
	var n := maxi(1, int(round(ln / WALL_SEG)))
	var step := ln / n
	var gap := rng.randi_range(0, n - 1) if door else -1
	var rot := 0.0 if absf(d.x) > absf(d.y) else PI / 2.0
	for i in n:
		if i == gap:
			continue
		_put(nodes, origin, kind, a + d.normalized() * (step * (i + 0.5)), rot)


func _bsp(rect: Rect2, rng: RandomNumberGenerator, depth: int, out: Array) -> void:
	var can_x := rect.size.x > 330.0
	var can_y := rect.size.y > 330.0
	if depth <= 0 or (not can_x and not can_y) or (depth < 2 and rng.randf() < 0.3):
		out.append(rect)
		return
	var split_x := can_x and (not can_y or rect.size.x > rect.size.y * (0.8 + rng.randf() * 0.4))
	var t := rng.randf_range(0.35, 0.65)
	if split_x:
		var w := snappedf(rect.size.x * t, 37.0)
		_bsp(Rect2(rect.position, Vector2(w, rect.size.y)), rng, depth - 1, out)
		_bsp(Rect2(rect.position + Vector2(w, 0), Vector2(rect.size.x - w, rect.size.y)), rng, depth - 1, out)
	else:
		var h := snappedf(rect.size.y * t, 37.0)
		_bsp(Rect2(rect.position, Vector2(rect.size.x, h)), rng, depth - 1, out)
		_bsp(Rect2(rect.position + Vector2(0, h), Vector2(rect.size.x, rect.size.y - h)), rng, depth - 1, out)


## Комплекс: стены по периметру и между комнатами, в комнатах — наполнение района.
func _compound(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, wall: String, fill: Array, corner := "", center_piece := "") -> void:
	var C := CHUNK
	var w := rng.randf_range(420.0, 640.0)
	var h := rng.randf_range(380.0, 600.0)
	var p0 := Vector2(rng.randf_range(40.0, C - w - 40.0), rng.randf_range(40.0, C - h - 40.0))
	var outer := Rect2(p0, Vector2(w, h))
	if _on_road(outer.get_center(), 120.0):
		# Комплекс не строим поперёк дороги — сдвигаем к краю участка
		p0.y = 40.0 if _road_bands.size() > 0 and _road_bands[0][1] > C / 2.0 else C - h - 40.0
		outer = Rect2(p0, Vector2(w, h))
	var rooms: Array = []
	_bsp(outer, rng, rng.randi_range(1, 3), rooms)
	# Внешние стены: в 1–2 сторонах проходы
	var sides := [[outer.position, outer.position + Vector2(w, 0)], [outer.position + Vector2(0, h), outer.end],
		[outer.position, outer.position + Vector2(0, h)], [outer.position + Vector2(w, 0), outer.end]]
	var doors := [rng.randi_range(0, 3), rng.randi_range(0, 3)]
	for i in 4:
		_wall_line(nodes, origin, sides[i][0], sides[i][1], wall, rng, i in doors)
	# Внутренние стены: правая и нижняя граница каждой комнаты, если она внутри
	for r in rooms:
		var rr: Rect2 = r
		if rr.end.x < outer.end.x - 5.0:
			_wall_line(nodes, origin, Vector2(rr.end.x, rr.position.y), rr.end, wall, rng, true)
		if rr.end.y < outer.end.y - 5.0:
			_wall_line(nodes, origin, Vector2(rr.position.x, rr.end.y), rr.end, wall, rng, true)
		# Наполнение комнаты — ближе к углам, центр свободен для боя
		var n := rng.randi_range(1, 3)
		for k in n:
			var cx := rr.position.x + (40.0 if rng.randf() < 0.5 else rr.size.x - 40.0)
			var cy := rr.position.y + (40.0 if rng.randf() < 0.5 else rr.size.y - 40.0)
			var kind: String = fill[rng.randi_range(0, fill.size() - 1)]
			if kind == "TREE":
				kind = _tree(rng)
			_put(nodes, origin, kind, Vector2(cx, cy) + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)), rng.randf() * TAU if kind.begins_with("rock") or kind.begins_with("wreck") else 0.0, rng.randf() < 0.12)
	if corner != "":
		for k in [outer.position, outer.position + Vector2(w, 0), outer.position + Vector2(0, h), outer.end]:
			_put(nodes, origin, corner, k, 0.0, rng.randf() < 0.3)
	if center_piece != "":
		var big: Rect2 = rooms[0]
		for r in rooms:
			if (r as Rect2).get_area() > big.get_area():
				big = r
		_put(nodes, origin, center_piece, big.get_center(), 0.0, true)


func _make_decal(kind: String, pos: Vector2, rng: RandomNumberGenerator, scale_k := 1.0) -> Node2D:
	var fr := Pixel.frames(kind)
	var root := Node2D.new()
	root.position = pos
	root.z_index = -18
	add_child(root)
	var base := Sprite2D.new()
	base.texture = fr["base"][0]
	base.scale = Vector2.ONE * Pixel.PX * scale_k
	base.rotation = rng.randf() * TAU if kind in ["decal_rune", "decal_crater", "decal_moss"] else (PI / 2.0 if kind == "decal_road" and rng.randf() < 0.5 else 0.0)
	base.flip_h = rng.randf() < 0.5
	root.add_child(base)
	var emit := Sprite2D.new()
	emit.texture = fr["emit"][0]
	emit.scale = base.scale
	emit.rotation = base.rotation
	emit.flip_h = base.flip_h
	emit.material = Pixel.mat_add()
	root.add_child(emit)
	return root


func _make_prop(kind: String, pos: Vector2, with_light: bool, flip: bool, rot := 0.0) -> Node2D:
	var fr := Pixel.frames(kind)
	var size: Vector2 = fr["size"] * Pixel.PX
	var root := Node2D.new()
	root.position = pos
	props_parent.add_child(root)

	var is_puddle := kind.begins_with("puddle")
	if not is_puddle:
		var sh := Sprite2D.new()
		sh.texture = Pixel.shadow()
		sh.scale = Vector2(size.x / 14.0, Pixel.PX * 0.9)
		sh.z_index = -5
		root.add_child(sh)

	# Объёмная 3D-модель вместо плоского спрайта
	if Props3D.supports(kind):
		var prng := RandomNumberGenerator.new()
		prng.seed = hash(wrap_pos(pos).round())
		var n3: Node3D = main.prop3d(kind, root, prng, rot)
		_prop_extras(kind, pos, root, size, with_light, n3.scale.x, rot)
		return root

	var base := Sprite2D.new()
	base.texture = fr["base"][0]
	base.scale = Vector2(Pixel.PX, Pixel.PX * (1.0 if is_puddle else Pixel.STAND))
	base.offset = Vector2(0, -fr["size"].y / 2.0 + 2.0)
	base.flip_h = flip
	root.add_child(base)
	var emit := Sprite2D.new()
	emit.texture = fr["emit"][0]
	emit.scale = base.scale
	emit.offset = base.offset
	emit.flip_h = flip
	emit.material = Pixel.mat_unshaded()
	emit.modulate = Pixel.hdr(Color.WHITE, 1.3)
	root.add_child(emit)

	if is_puddle:
		root.z_index = -15
		base.offset = Vector2.ZERO
		emit.offset = Vector2.ZERO
		emit.material = Pixel.mat_add()
		return root
	main.mirror(base, root, false, true)
	main.mirror(emit, root, true, true)
	_prop_extras(kind, pos, root, size, with_light)
	return root


## Препятствие, тень от света героя и источник света объекта.
func _prop_extras(kind: String, pos: Vector2, root: Node2D, size: Vector2, with_light: bool, k3 := 1.0, rot := 0.0) -> void:
	if Props3D.supports(kind):
		# Точная форма основания 3D-модели: прямоугольники и круги, с масштабом и поворотом
		var s := k3 * 100.0
		var ang := -rot
		for sh in Props3D.shapes(kind):
			var c: Vector2 = pos + (Vector2(sh[1], sh[2]) * s).rotated(ang)
			if sh[0] == "r":
				_add_obst([c, Vector2(sh[3], sh[4]) * s, ang])
			else:
				_add_obst([c, float(sh[3]) * s])
	else:
		var obst_r := size.x * (0.16 if kind.begins_with("tree") else (0.2 if kind.begins_with("pine") else 0.3))
		if obst_r >= 12.0 and not kind.begins_with("bush") and not kind.begins_with("mushroom"):
			_add_obst([pos, obst_r])

	# Тень от света героя — только для плоских спрайтов. У 3D-моделей своя тень,
	# а 2D-заслонка под ними давала резкие вспышки тени, когда герой пробегал рядом.
	if not Props3D.supports(kind):
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var hw := size.x * 0.3
		poly.polygon = PackedVector2Array([Vector2(-hw, -8), Vector2(hw, -8), Vector2(hw, 2), Vector2(-hw, 2)])
		occ.occluder = poly
		root.add_child(occ)

	if with_light and LIGHT_PROPS.has(kind):
		var col: Color = LIGHT_PROPS[kind]
		var top := Vector2(0, -size.y * Pixel.STAND * 0.75)
		var light := PointLight2D.new()
		light.texture = Pixel.glow()
		light.color = col
		light.energy = 1.1
		light.texture_scale = 3.4
		light.position = top
		root.add_child(light)
		main.mirror_light(light, root, 1.6)
		var halo := Sprite2D.new()
		halo.texture = Pixel.glow()
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.material = Pixel.mat_add()
		halo.modulate = Color(col, 0.22)
		halo.scale = Vector2(0.7, 0.7 * Pixel.STAND)
		halo.position = top
		if not Props3D.supports(kind):
			root.add_child(halo)


## Регистрирует препятствие во всех клетках сетки, которых оно касается.
func _add_obst(entry: Array) -> void:
	var c: Vector2 = entry[0]
	var ext: float = (entry[1] as Vector2).length() if entry.size() == 3 else float(entry[1])
	for cx in range(floori((c.x - ext) / CELL), floori((c.x + ext) / CELL) + 1):
		for cy in range(floori((c.y - ext) / CELL), floori((c.y + ext) / CELL) + 1):
			var cell := Vector2i(cx, cy)
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append(entry)
			if _chunk_obst.has(_building_key):
				_chunk_obst[_building_key].append([cell, entry])


## Свободна ли точка (для появления врагов и предметов).
func is_free(pos: Vector2, r: float) -> bool:
	return push_out(pos, r).distance_squared_to(pos) < 1.0


func push_out(pos: Vector2, r: float, iterations := 2) -> Vector2:
	for _it in iterations:
		pos = _push_once(pos, r)
	return pos


func _push_once(pos: Vector2, r: float) -> Vector2:
	var cx := floori(pos.x / CELL)
	var cy := floori(pos.y / CELL)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var arr = _grid.get(Vector2i(cx + dx, cy + dy))
			if arr == null:
				continue
			for o in arr:
				var c: Vector2 = o[0]
				if o.size() == 3:
					pos = _push_rect(pos, r, c, o[1], o[2])
					continue
				var min_d: float = o[1] + r
				var d := pos - c
				var dist := d.length()
				if dist < min_d:
					if dist < 0.01:
						d = Vector2.DOWN
						dist = 1.0
					pos = c + d / dist * min_d
	return pos


## Выталкивание круга из повёрнутого прямоугольника.
func _push_rect(pos: Vector2, r: float, c: Vector2, half: Vector2, ang: float) -> Vector2:
	var lp := (pos - c).rotated(-ang)
	if absf(lp.x) > half.x + r or absf(lp.y) > half.y + r:
		return pos
	var q := Vector2(clampf(lp.x, -half.x, half.x), clampf(lp.y, -half.y, half.y))
	var d := lp - q
	var dist := d.length()
	if dist > 0.001:
		if dist >= r:
			return pos
		lp = q + d / dist * r
	else:
		# Центр внутри — выталкиваем по кратчайшей оси
		var px := half.x + r - absf(lp.x)
		var py := half.y + r - absf(lp.y)
		if px < py:
			lp.x = (half.x + r) * (1.0 if lp.x >= 0.0 else -1.0)
		else:
			lp.y = (half.y + r) * (1.0 if lp.y >= 0.0 else -1.0)
	return c + lp.rotated(ang)


# ================= Районы: логичная застройка чанков =================

## Район чанка: улица, рынок, парк, поля, лес, кристальное поле, руины, крепость, свалка.
const DISTRICTS := {
	"street": {"name": "Улица посада", "biome": 0},
	"market": {"name": "Рыночная площадь", "biome": 0},
	"park": {"name": "Неоновый парк", "biome": 3},
	"field": {"name": "Поля и огороды", "biome": 3},
	"forest": {"name": "Техно-лес", "biome": 3},
	"crystal": {"name": "Кристальное поле", "biome": 1},
	"ruins": {"name": "Древние руины", "biome": 2},
	"castle": {"name": "Неоновая крепость", "biome": 2},
	"junk": {"name": "Свалка дронов", "biome": 4},
}

var _dnoise := FastNoiseLite.new()


func district_at(key: Vector2i) -> String:
	var list: Array = main.level.get("districts", ["street", "market", "park", "forest"]) if main and main.level else ["street"]
	key = wrap_key(key)
	if key == Vector2i.ZERO:
		return list[0]
	var n := (_dnoise.get_noise_2d(key.x, key.y) + 1.0) * 0.5
	return list[clampi(int(n * list.size()), 0, list.size() - 1)]


## Объект района: локальные координаты чанка, поворот модели, свет.
func _put(nodes: Array, origin: Vector2, kind: String, local: Vector2, rot := 0.0, light := false) -> void:
	var p := origin + local
	if wrap_pos(p).length() < 230.0:
		return  # точка появления героя всегда свободна
	if not kind.begins_with("puddle") and _on_road(local, 10.0):
		return  # сквозная дорога всегда проходима
	if light:
		if _lights >= 5:
			light = false
		else:
			_lights += 1
	nodes.append(_make_prop(kind, p, light, false, rot))


func _decal(nodes: Array, origin: Vector2, kind: String, local: Vector2, rng: RandomNumberGenerator, k := 1.0, rot := -1.0) -> void:
	var d := _make_decal(kind, origin + local, rng, k)
	if rot >= 0.0:
		(d.get_child(0) as Sprite2D).rotation = rot
		if d.get_child_count() > 1:
			(d.get_child(1) as Sprite2D).rotation = rot
	nodes.append(d)


func _hk(k: Vector2i) -> int:
	k = wrap_key(k)
	return hash(Vector3i(k.x, k.y, _noise.seed))


## «Сердце» района: чанк, у которого хэш больше, чем у всех соседей того же района.
## Там стоит главная постройка (площадь, крепость, круг руин), остальные чанки — окраины.
func _is_anchor(key: Vector2i) -> bool:
	var d := district_at(key)
	var hv := _hk(key)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := key + Vector2i(dx, dy)
			if k != key and district_at(k) == d and _hk(k) > hv:
				return false
	return true


func _tree(rng: RandomNumberGenerator, conifer := 0.4) -> String:
	if rng.randf() < conifer:
		return ["pine0", "pine0", "pine1", "pine2"][rng.randi_range(0, 3)]
	return ["tree0", "tree0", "tree1", "tree2", "tree3"][rng.randi_range(0, 4)]


func _house(rng: RandomNumberGenerator) -> String:
	return ["house0", "house1", "house2"][rng.randi_range(0, 2)]


func _junk(rng: RandomNumberGenerator) -> String:
	return ["barrel0", "barrel1", "crate0", "crate1"][rng.randi_range(0, 3)]


## Ряд домов вдоль дороги: x0..x1 на высоте y, фасадом к дороге (rot), с пропусками.
func _house_row(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, y: float, rot: float, x0: float, x1: float, skip: Array = []) -> void:
	var x := x0 + rng.randf_range(0, 40)
	while x < x1:
		var blocked := false
		for r in skip:
			if x > r.x - 80 and x < r.y + 80:
				blocked = true
		if not blocked:
			var roll := rng.randf()
			if roll < 0.14 and x + 200.0 < x1:
				# Особняк — крупное здание на два участка
				x += 70.0
				_put(nodes, origin, "manor0", Vector2(x, y + (-20.0 if rot == 0.0 else 20.0)), rot, true)
				x += 90.0
			elif roll < 0.72:
				_put(nodes, origin, _house(rng), Vector2(x, y + rng.randf_range(-8, 8)), rot + rng.randf_range(-0.06, 0.06), rng.randf() < 0.3)
			elif roll < 0.88:
				_put(nodes, origin, _tree(rng, 0.2), Vector2(x, y + (-30.0 if rot == 0.0 else 30.0)), 0.0)
				_put(nodes, origin, "bush%d" % rng.randi_range(0, 1), Vector2(x + 35, y + (-10.0 if rot == 0.0 else 10.0)))
			else:
				_put(nodes, origin, _junk(rng), Vector2(x, y))
				_put(nodes, origin, _junk(rng), Vector2(x + 34, y + 10))
		x += rng.randf_range(235, 290)


func _road_h(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, y: float, x0 := 0.0, x1 := CHUNK) -> void:
	var x := x0 + 96.0
	while x < x1 + 40.0:
		_decal(nodes, origin, "decal_road", Vector2(x, y), rng, 1.0, 0.0)
		x += 192.0


func _road_v(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, x: float, y0 := 0.0, y1 := CHUNK) -> void:
	var y := y0 + 96.0
	while y < y1 + 40.0:
		_decal(nodes, origin, "decal_road", Vector2(x, y), rng, 1.0, PI / 2.0)
		y += 192.0


func _scatter(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, kinds: Array, n: int, center := Vector2(-1, -1), spread := Vector2.ZERO, light_chance := 0.0) -> void:
	for i in n:
		var p: Vector2
		if center.x < 0.0:
			p = Vector2(rng.randf_range(30, CHUNK - 30), rng.randf_range(30, CHUNK - 30))
		else:
			p = center + Vector2(rng.randf_range(-spread.x, spread.x), rng.randf_range(-spread.y, spread.y))
		var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		if k == "TREE":
			k = _tree(rng)
		elif k == "PINE":
			k = _tree(rng, 1.0)
		elif k == "LEAF":
			k = _tree(rng, 0.0)
		var rot := rng.randf() * TAU if k.begins_with("rock") or k.begins_with("crystal") or k.begins_with("wreck") else 0.0
		_put(nodes, origin, k, p, rot, rng.randf() < light_chance)


func _fenced_plot(nodes: Array, origin: Vector2, rng: RandomNumberGenerator, c: Vector2, cols: int, rows: int) -> void:
	var hw := cols * 55.0
	var hh := rows * 55.0
	_decal(nodes, origin, "decal_moss", c, rng, 1.2 + cols * 0.6)
	var gap := rng.randi_range(0, cols - 1)
	for k in cols:
		_put(nodes, origin, "fence0", c + Vector2(-hw + 55 + k * 110, -hh))
		if k != gap:
			_put(nodes, origin, "fence0", c + Vector2(-hw + 55 + k * 110, hh))
	for k in rows:
		_put(nodes, origin, "fence0", c + Vector2(-hw - 4, -hh + 55 + k * 110), PI / 2.0)
		_put(nodes, origin, "fence0", c + Vector2(hw + 4, -hh + 55 + k * 110), PI / 2.0)
	var crop := "bush0" if rng.randf() < 0.6 else "mushroom0"
	for i in cols * rows * 2:
		_put(nodes, origin, crop, c + Vector2(rng.randf_range(-hw + 25, hw - 25), rng.randf_range(-hh + 20, hh - 20)))


func _build_district(dist: String, origin: Vector2, rng: RandomNumberGenerator, nodes: Array, key: Vector2i) -> void:
	var C := CHUNK
	var H := C / 2.0
	var anchor := _is_anchor(key)
	var v := rng.randi_range(0, 2)
	# Примерно каждый третий не-центральный участок — уникальный комплекс из комнат
	if not anchor and rng.randf() < 0.34:
		match dist:
			"ruins":
				_compound(nodes, origin, rng, "wall0", ["pillar1", "rock1", "statue0", "TREE", "bush1"], "pillar0", "obelisk%d" % rng.randi_range(0, 2))
				return
			"castle":
				_compound(nodes, origin, rng, "wall0", ["barrel0", "crate1", "banner%d" % rng.randi_range(0, 1), "stall1", "lantern0"], "tower0", "well0")
				return
			"junk":
				_compound(nodes, origin, rng, "fence0", ["wreck0", "wreck1", "barrel1", "crate0", "crate1"], "", "cart0")
				return
			"field", "street":
				_compound(nodes, origin, rng, "fence0", ["bush0", "LEAF", "barrel0", "cart0", "mushroom0"], "lantern0", "house%d" % rng.randi_range(0, 2))
				return
			"crystal":
				_compound(nodes, origin, rng, "crystal_big%d" % rng.randi_range(0, 1), ["crystal0", "crystal1", "rock0"], "", "obelisk%d" % rng.randi_range(0, 2))
				return
			"forest", "park":
				_compound(nodes, origin, rng, "fence0", ["TREE", "TREE", "bush0", "mushroom1"], "lantern0", "statue0")
				return
	match dist:
		"street":
			_road_h(nodes, origin, rng, H)
			if anchor:
				# Перекрёсток с площадью: колодец, фонари, дома по четырём углам
				_road_v(nodes, origin, rng, H)
				_decal(nodes, origin, "decal_cobble", Vector2(H, H), rng, 2.6, 0.0)
				_put(nodes, origin, "well0", Vector2(H, H), 0.0, true)
				for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					_put(nodes, origin, "lantern0", Vector2(H, H) + c * 120.0, 0.0, c.x < 0 and c.y < 0)
				_house_row(nodes, origin, rng, H - 170, 0.0, 30, C - 30, [Vector2(H - 90, H + 90)])
				_house_row(nodes, origin, rng, H + 210, PI, 30, C - 30, [Vector2(H - 90, H + 90)])
			elif v == 0:
				# Обычная улица: дома с двух сторон, фонари вдоль
				_house_row(nodes, origin, rng, H - 170, 0.0, 30, C - 30)
				_house_row(nodes, origin, rng, H + 210, PI, 30, C - 30)
				for i in 4:
					_put(nodes, origin, "lamp%d" % (i % 2), Vector2(96 + i * 192, H + (-62.0 if i % 2 == 0 else 62.0)), 0.0, i % 2 == 0)
			elif v == 1:
				# Окраина: дома с одной стороны, огороды и сады с другой
				_house_row(nodes, origin, rng, H - 170, 0.0, 30, C - 30)
				_fenced_plot(nodes, origin, rng, Vector2(rng.randf_range(200, C - 200), H + 230), 2, 1)
				_scatter(nodes, origin, rng, ["LEAF", "bush0", "bush1"], 6, Vector2(H, H + 300), Vector2(H - 40, 50))
				_put(nodes, origin, "lantern0", Vector2(rng.randf_range(100, C - 100), H + 60), 0.0, true)
			else:
				# Улица с переулком вверх (Т-перекрёсток)
				var ax := rng.randf_range(220, C - 220)
				_road_v(nodes, origin, rng, ax, -40, H - 60)
				_house_row(nodes, origin, rng, H - 170, 0.0, 30, C - 30, [Vector2(ax - 40, ax + 40)])
				_house_row(nodes, origin, rng, H + 210, PI, 30, C - 30)
				_put(nodes, origin, "sign%d" % rng.randi_range(0, 1), Vector2(ax + 70, H - 60), 0.0, true)
				_put(nodes, origin, "lamp1", Vector2(ax - 70, H - 60), 0.0, true)
			if rng.randf() < 0.5:
				_put(nodes, origin, "puddle%d" % rng.randi_range(0, 1), Vector2(rng.randf_range(60, C - 60), H + rng.randf_range(-30, 30)))
			if rng.randf() < 0.5:
				_put(nodes, origin, "cart0", Vector2(rng.randf_range(80, C - 80), H + 95), rng.randf_range(-0.3, 0.3))
		"market":
			if anchor:
				# Большая рыночная площадь: лавки по кругу прилавком внутрь
				_decal(nodes, origin, "decal_cobble", Vector2(H, H), rng, 3.6, 0.0)
				_put(nodes, origin, "well0", Vector2(H, H), 0.0, true)
				for i in 8:
					var a := TAU * i / 8.0 + 0.2
					var lp := Vector2(H, H) + Vector2(cos(a), sin(a)) * Vector2(230, 180)
					_put(nodes, origin, "stall%d" % (i % 2), lp, atan2(H - lp.x, H - lp.y), i % 3 == 0)
				_put(nodes, origin, "banner0", Vector2(H - 70, H - 80))
				_put(nodes, origin, "banner1", Vector2(H + 70, H - 80))
				for c in [Vector2(90, 90), Vector2(C - 90, 90), Vector2(90, C - 90), Vector2(C - 90, C - 90)]:
					_put(nodes, origin, "lantern0", c, 0.0, true)
			elif v == 0:
				# Торговый ряд вдоль дороги
				_road_h(nodes, origin, rng, H)
				var x := 60.0 + rng.randf_range(0, 60)
				while x < C - 60:
					if rng.randf() < 0.6:
						_put(nodes, origin, "stall%d" % rng.randi_range(0, 1), Vector2(x, H - 120), 0.0, rng.randf() < 0.25)
					else:
						_put(nodes, origin, _junk(rng), Vector2(x, H - 110))
					if rng.randf() < 0.45:
						_put(nodes, origin, "stall%d" % rng.randi_range(0, 1), Vector2(x + 60, H + 130), PI, rng.randf() < 0.25)
					x += rng.randf_range(170, 260)
				_house_row(nodes, origin, rng, H - 290, 0.0, 40, C - 40)
				_put(nodes, origin, "lamp0", Vector2(rng.randf_range(100, C - 100), H + 60), 0.0, true)
			else:
				# Стоянка каравана: телеги кругом, ящики, костровой фонарь
				var c := Vector2(rng.randf_range(260, C - 260), rng.randf_range(260, C - 260))
				for i in 5:
					var a := TAU * i / 5.0 + rng.randf() * 0.3
					_put(nodes, origin, "cart0", c + Vector2(cos(a), sin(a)) * 150.0, a + PI / 2.0)
				_put(nodes, origin, "lantern0", c, 0.0, true)
				_scatter(nodes, origin, rng, ["crate0", "crate1", "barrel0", "barrel1"], 6, c, Vector2(90, 70))
				_put(nodes, origin, "banner%d" % rng.randi_range(0, 1), c + Vector2(0, -190))
				_put(nodes, origin, "stall%d" % rng.randi_range(0, 1), c + Vector2(rng.randf_range(-60, 60), 230), PI)
				_scatter(nodes, origin, rng, ["TREE", "bush0", "rock1"], 5)
		"park":
			if anchor:
				# Центральная лужайка: статуя, кольцо деревьев, фонари, дорожки-лучи
				_decal(nodes, origin, "decal_moss", Vector2(H, H), rng, 3.4)
				_put(nodes, origin, "statue0", Vector2(H, H - 10), 0.0, true)
				for i in 4:
					var a := TAU * i / 4.0 + PI / 4.0
					_decal(nodes, origin, "decal_cobble", Vector2(H, H) + Vector2(cos(a), sin(a)) * 170.0, rng, 1.0, a)
					_put(nodes, origin, "lantern0", Vector2(H, H) + Vector2(cos(a), sin(a)) * 110.0, 0.0, i % 2 == 0)
				for i in 10:
					var a := TAU * i / 10.0
					_put(nodes, origin, _tree(rng, 0.15), Vector2(H, H) + Vector2(cos(a), sin(a)) * Vector2(290, 240))
				_scatter(nodes, origin, rng, ["bush0", "bush1", "mushroom1"], 6, Vector2(H, H), Vector2(200, 170))
			elif v == 0:
				# Аллеи: дорожка и ряды деревьев с разными промежутками
				var horiz := rng.randf() < 0.5
				for i in 4:
					var p := Vector2(96 + i * 192, H)
					_decal(nodes, origin, "decal_cobble", p if horiz else Vector2(p.y, p.x), rng, 1.0, 0.0 if horiz else PI / 2.0)
				for off in [-90.0, 90.0, -260.0, 250.0]:
					var t := 60.0 + rng.randf_range(0, 50)
					while t < C - 50:
						if rng.randf() < 0.75:
							var p := Vector2(t, H + off + rng.randf_range(-12, 12))
							_put(nodes, origin, _tree(rng, 0.15), p if horiz else Vector2(p.y, p.x))
						t += rng.randf_range(100, 170)
				for i in 3:
					var p := Vector2(150 + i * 230, H - 50)
					_put(nodes, origin, "lantern0", p if horiz else Vector2(p.y, p.x), 0.0, i == 1)
			else:
				# Рощицы и пруд из луж
				var pond := Vector2(rng.randf_range(220, C - 220), rng.randf_range(220, C - 220))
				for i in 5:
					_put(nodes, origin, "puddle%d" % (i % 2), pond + Vector2(rng.randf_range(-70, 70), rng.randf_range(-30, 30)))
				_scatter(nodes, origin, rng, ["bush0", "bush1", "mushroom1"], 6, pond, Vector2(140, 90))
				for g in rng.randi_range(2, 4):
					var c := Vector2(rng.randf_range(80, C - 80), rng.randf_range(80, C - 80))
					if c.distance_to(pond) > 200:
						_scatter(nodes, origin, rng, ["LEAF", "LEAF", "bush0"], rng.randi_range(3, 5), c, Vector2(90, 70))
				_put(nodes, origin, "lantern0", pond + Vector2(0, -110), 0.0, true)
		"field":
			if anchor:
				# Хутор: два дома, огороженный двор, телега, сад
				var c := Vector2(H + rng.randf_range(-80, 80), H - 60)
				_put(nodes, origin, "manor0", c + Vector2(-120, -80), 0.0, true)
				_put(nodes, origin, "house0", c + Vector2(175, -40), -0.15)
				_fenced_plot(nodes, origin, rng, c + Vector2(0, 230), 3, 1)
				_put(nodes, origin, "cart0", c + Vector2(30, 60), 0.4)
				_put(nodes, origin, "well0", c + Vector2(-170, 80), 0.0, true)
				_scatter(nodes, origin, rng, ["LEAF"], 5, c + Vector2(0, -260), Vector2(300, 40))
			elif v == 0:
				# Огороженные участки разного размера
				for fx in 2:
					for fy in 2:
						if rng.randf() < 0.3:
							continue
						_fenced_plot(nodes, origin, rng, Vector2(200 + fx * 370, 200 + fy * 370), rng.randi_range(1, 2), rng.randi_range(1, 2))
				_scatter(nodes, origin, rng, ["barrel0", "crate0"], 3, Vector2(H, H), Vector2(60, 60))
			else:
				# Луг: кусты, грибы, одинокие деревья, камни
				_decal(nodes, origin, "decal_moss", Vector2(rng.randf_range(150, C - 150), rng.randf_range(150, C - 150)), rng, 3.0)
				_scatter(nodes, origin, rng, ["bush0", "bush1", "bush0", "mushroom0", "mushroom1"], 14)
				_scatter(nodes, origin, rng, ["LEAF", "rock0", "rock1"], 4)
				if rng.randf() < 0.5:
					_put(nodes, origin, "fence0", Vector2(rng.randf_range(100, C - 100), rng.randf_range(100, C - 100)), rng.randf_range(-0.4, 0.4))
		"forest":
			if anchor:
				# Поляна с лесным хутором в чаще
				var c := Vector2(H, H)
				_decal(nodes, origin, "decal_moss", c, rng, 3.0)
				_put(nodes, origin, "house2", c + Vector2(-60, -40), 0.0, true)
				_put(nodes, origin, "fence0", c + Vector2(60, 40))
				_put(nodes, origin, "lantern0", c + Vector2(90, -20), 0.0, true)
				_scatter(nodes, origin, rng, ["mushroom1", "bush0"], 4, c, Vector2(140, 100))
				for i in 34:
					var p := Vector2(rng.randf_range(20, C - 20), rng.randf_range(20, C - 20))
					if p.distance_to(c) > 230:
						_put(nodes, origin, _tree(rng, 0.55), p)
			elif v == 0:
				# Густой лес с маленькой поляной
				var clearing := Vector2(rng.randf_range(200, C - 200), rng.randf_range(200, C - 200))
				for i in rng.randi_range(30, 40):
					var p := Vector2(rng.randf_range(20, C - 20), rng.randf_range(20, C - 20))
					if p.distance_to(clearing) > 140:
						_put(nodes, origin, _tree(rng, 0.6) if rng.randf() < 0.85 else "bush%d" % rng.randi_range(0, 1), p)
				_scatter(nodes, origin, rng, ["mushroom1", "mushroom0"], 4, clearing, Vector2(70, 50), 0.2)
			elif v == 1:
				# Лесная тропа наискось
				var a := Vector2(0, rng.randf_range(100, C - 100))
				var b := Vector2(C, rng.randf_range(100, C - 100))
				for i in 5:
					_decal(nodes, origin, "decal_moss", a.lerp(b, (i + 0.5) / 5.0), rng, 1.4)
				for i in 30:
					var p := Vector2(rng.randf_range(20, C - 20), rng.randf_range(20, C - 20))
					var t := clampf(p.x / C, 0.0, 1.0)
					if absf(p.y - a.lerp(b, t).y) > 90:
						_put(nodes, origin, _tree(rng, 0.5), p)
				_put(nodes, origin, "lantern0", a.lerp(b, 0.5) + Vector2(0, -60), 0.0, true)
			else:
				# Редколесье с валунами
				_scatter(nodes, origin, rng, ["TREE", "TREE", "PINE", "rock0", "rock1", "bush1"], 20)
		"crystal":
			if anchor:
				# Великая друза: кольцо больших кристаллов вокруг обелиска на руне
				_decal(nodes, origin, "decal_rune", Vector2(H, H), rng, 2.4)
				_put(nodes, origin, "obelisk%d" % rng.randi_range(0, 2), Vector2(H, H), 0.0, true)
				for i in 7:
					var a := TAU * i / 7.0
					_put(nodes, origin, "crystal_big%d" % (i % 2), Vector2(H, H) + Vector2(cos(a), sin(a)) * Vector2(210, 170), rng.randf() * TAU, i % 3 == 0)
				_scatter(nodes, origin, rng, ["crystal0", "crystal1", "rock1"], 8)
			elif v == 0:
				for g in rng.randi_range(2, 4):
					var c := Vector2(rng.randf_range(120, C - 120), rng.randf_range(120, C - 120))
					_decal(nodes, origin, "decal_crater", c, rng, 1.6)
					_scatter(nodes, origin, rng, ["crystal0", "crystal1", "crystal_big0", "crystal_big1"], rng.randi_range(3, 5), c, Vector2(90, 70), 0.15)
				_scatter(nodes, origin, rng, ["rock0", "rock1"], 4)
			else:
				# Каменистая пустошь с ледяными елями
				_scatter(nodes, origin, rng, ["rock0", "rock1", "rock0", "pine2", "crystal0", "crystal1"], 14)
				_decal(nodes, origin, "decal_crater", Vector2(rng.randf_range(100, C - 100), rng.randf_range(100, C - 100)), rng, 2.2)
		"ruins":
			if anchor:
				_decal(nodes, origin, "decal_rune", Vector2(H, H), rng, 2.6)
				for i in 8:
					var a := TAU * i / 8.0
					_put(nodes, origin, "pillar0" if i % 3 != 0 else "pillar1", Vector2(H, H) + Vector2(cos(a), sin(a)) * Vector2(190, 150))
				_put(nodes, origin, "statue0", Vector2(H, H - 10), 0.0, true)
				_scatter(nodes, origin, rng, ["rock1", "TREE"], 5)
			elif v == 0:
				# Остатки зданий: стены под прямым углом, обломки колонн
				for r in rng.randi_range(2, 3):
					var c := Vector2(rng.randf_range(150, C - 150), rng.randf_range(150, C - 150))
					_put(nodes, origin, "wall0", c + Vector2(0, -75))
					if rng.randf() < 0.7:
						_put(nodes, origin, "wall0", c + Vector2(-75, 0), PI / 2.0)
					_put(nodes, origin, "pillar1", c + Vector2(70, 60))
				_scatter(nodes, origin, rng, ["rock1", "pillar1", "bush1"], 5)
			else:
				# Заросшие руины: колонны среди деревьев
				_scatter(nodes, origin, rng, ["pillar0", "pillar1", "pillar1"], 6)
				_scatter(nodes, origin, rng, ["TREE", "TREE", "bush0", "rock0"], 12)
				_put(nodes, origin, "obelisk%d" % rng.randi_range(0, 2), Vector2(rng.randf_range(100, C - 100), rng.randf_range(100, C - 100)), 0.0, true)
		"castle":
			if anchor:
				# Крепость: башни, стены, двое ворот, двор
				var c := Vector2(H, H)
				var hw := 270.0
				var hh := 210.0
				for k in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(-hw, hh), Vector2(hw, hh)]:
					_put(nodes, origin, "tower0", c + k, 0.0, true)
				for sy in [-hh, hh]:
					for k in 2:
						_put(nodes, origin, "wall0", c + Vector2((-1.0 if k == 0 else 1.0) * (hw * 0.55), sy))
					_put(nodes, origin, "gate0", c + Vector2(0, sy), 0.0, sy > 0)
				for sx in [-hw, hw]:
					for k in 3:
						_put(nodes, origin, "wall0", c + Vector2(sx, -hh + (k + 0.5) * (2.0 * hh / 3.0)), PI / 2.0)
				_decal(nodes, origin, "decal_cobble", c, rng, 3.4, 0.0)
				# Донжон в глубине двора
				_put(nodes, origin, "keep0", c + Vector2(0, -75), 0.0, true)
				_put(nodes, origin, "well0", c + Vector2(150, -110), 0.0, true)
				_put(nodes, origin, "banner0", c + Vector2(-150, 0))
				_put(nodes, origin, "banner1", c + Vector2(150, 0))
				_put(nodes, origin, "house2", c + Vector2(-190, 140), 0.0, true)
				_put(nodes, origin, "stall1", c + Vector2(160, 110), PI)
			elif v == 0:
				# Крепостная стена поперёк местности: башни, ворота, лагерь у стены
				var y := rng.randf_range(220, C - 300)
				var gx := rng.randf_range(250, C - 250)
				_put(nodes, origin, "tower0", Vector2(50, y), 0.0, false)
				_put(nodes, origin, "tower0", Vector2(C - 50, y), 0.0, true)
				_put(nodes, origin, "gate0", Vector2(gx, y), 0.0, true)
				# Стены от башен до ворот (ворота ~150 px шириной)
				for seg in [Vector2(98, gx - 75), Vector2(gx + 75, C - 98)]:
					var x: float = seg.x
					while x + 20.0 < seg.y:
						var ln := minf(148.0, seg.y - x)
						_put(nodes, origin, "wall0", Vector2(x + ln / 2.0, y))
						x += 148.0
				_put(nodes, origin, "banner%d" % rng.randi_range(0, 1), Vector2(gx - 120, y + 90))
				_scatter(nodes, origin, rng, ["barrel0", "crate1", "stall0"], 4, Vector2(gx, y + 220), Vector2(180, 50))
			else:
				# Сторожевой пост: башня, угол стены, припасы
				var c := Vector2(rng.randf_range(250, C - 250), rng.randf_range(250, C - 250))
				_put(nodes, origin, "tower0", c, 0.0, true)
				_put(nodes, origin, "wall0", c + Vector2(135, 0))
				_put(nodes, origin, "wall0", c + Vector2(0, 135), PI / 2.0)
				_put(nodes, origin, "banner%d" % rng.randi_range(0, 1), c + Vector2(80, 80))
				_scatter(nodes, origin, rng, ["barrel0", "barrel1", "crate0"], 4, c + Vector2(130, 120), Vector2(50, 40))
				_scatter(nodes, origin, rng, ["TREE", "rock0", "bush0"], 6)
		"junk":
			if anchor:
				# Большая свалка: кольцо обломков вокруг кратера
				_decal(nodes, origin, "decal_crater", Vector2(H, H), rng, 3.0)
				for i in 12:
					var a := TAU * i / 12.0 + rng.randf() * 0.2
					_put(nodes, origin, "wreck%d" % (i % 2), Vector2(H, H) + Vector2(cos(a), sin(a)) * Vector2(250, 200), rng.randf() * TAU, i % 4 == 0)
				_put(nodes, origin, "cart0", Vector2(H, H), rng.randf() * TAU)
			elif v == 0:
				for row in 3:
					var y := 140.0 + row * 240.0
					var x := 60.0 + rng.randf_range(0, 80)
					while x < C - 60:
						if rng.randf() < 0.7:
							var k: String = ["wreck0", "wreck1", "barrel0", "barrel1", "crate0", "crate1"][rng.randi_range(0, 5)]
							_put(nodes, origin, k, Vector2(x, y + rng.randf_range(-30, 30)), rng.randf() * TAU, rng.randf() < 0.08)
						x += rng.randf_range(90, 150)
					_decal(nodes, origin, "decal_cable", Vector2(rng.randf_range(60, C - 60), y + 110), rng)
			else:
				# Кучи хлама и заборы-перегородки
				for g in rng.randi_range(2, 4):
					var c := Vector2(rng.randf_range(120, C - 120), rng.randf_range(120, C - 120))
					_scatter(nodes, origin, rng, ["wreck0", "wreck1", "barrel1", "crate1"], rng.randi_range(3, 5), c, Vector2(80, 60), 0.1)
				for i in 3:
					_put(nodes, origin, "fence0", Vector2(rng.randf_range(60, C - 60), rng.randf_range(60, C - 60)), rng.randf_range(-0.3, 0.3))
				_scatter(nodes, origin, rng, ["PINE", "rock0"], 3)
