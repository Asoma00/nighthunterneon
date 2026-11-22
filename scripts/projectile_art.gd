extends RefCounted
## Текстуры оружия и размеры их видимой части в 3D.

const TEXTURES := {
	"bolt": preload("res://assets/projectiles/bolt.png"),
	"shard": preload("res://assets/projectiles/shard.png"),
	"arrow": preload("res://assets/projectiles/arrow.png"),
	"spirit": preload("res://assets/projectiles/spirit.png"),
	"shuriken": preload("res://assets/projectiles/shuriken.png"),
	"flask": preload("res://assets/projectiles/flask.png"),
	"fire": preload("res://assets/projectiles/fire.png"),
	"ball": preload("res://assets/projectiles/ball.png"),
	"acid": preload("res://assets/projectiles/acid.png"),
	"ice": preload("res://assets/projectiles/ice.png"),
	"wave": preload("res://assets/projectiles/wave.png"),
	"pellet": preload("res://assets/projectiles/pellet.png"),
	"blade": preload("res://assets/projectiles/blade.png"),
	"mine": preload("res://assets/projectiles/mine.png"),
	"drone": preload("res://assets/projectiles/drone.png"),
	"vortex": preload("res://assets/projectiles/vortex.png"),
}
const WORLD_SPAN := {
	"bolt": 0.67, "shard": 0.58, "arrow": 0.81, "spirit": 0.73,
	"shuriken": 0.42, "flask": 0.43, "fire": 0.75, "ball": 0.77,
	"acid": 0.52, "ice": 0.68, "wave": 1.28, "pellet": 0.43,
	"blade": 0.74, "mine": 0.65, "drone": 0.78,
}
const DIRECTIONAL := ["bolt", "shard", "arrow", "spirit", "fire", "ice", "wave", "pellet"]
const SPIN := {"shuriken": 19.0, "flask": 8.0, "acid": 3.0}
const SPIRIT_ATLAS := preload("res://assets/projectiles/spirit_motion.png")
const SPIRIT_FRAME_SIZE := Vector2i(128, 80)
const SPIRIT_BIRTH := [8, 9, 0]
const SPIRIT_GLIDE := [0, 1, 4, 5, 2, 3, 2, 1]
const SPIRIT_LUNGE := [6, 10, 7, 10]
const SPIRIT_FLASH := 7
const SPIRIT_BREAKUP := 11
static var _spirit_frames: Array[ImageTexture] = []
static var _volumes := {}


static func select(style: String, source: String, status: String) -> String:
	if source == "mines":
		return "mine"
	if source == "scatter":
		return "pellet"
	if style != "orb" and TEXTURES.has(style):
		return style
	match status:
		"burn": return "fire"
		"poison", "toxin": return "acid"
		"chill", "freeze": return "ice"
		_: return "bolt"


static func texture(key: String) -> Texture2D:
	return TEXTURES.get(key, TEXTURES["bolt"])


static func world_size(key: String) -> Vector2:
	var size := texture(key).get_size()
	return size * (float(WORLD_SPAN.get(key, 0.6)) / maxf(size.x, size.y))


static func spirit_pose(age: float, phase: float, lunging: bool) -> int:
	if age < 0.24:
		return SPIRIT_BIRTH[mini(2, floori(age / 0.08))]
	var sequence := SPIRIT_LUNGE if lunging else SPIRIT_GLIDE
	var fps := 17.0 if lunging else 11.0
	return sequence[posmod(floori((age - 0.24) * fps + phase), sequence.size())]


static func spirit_frame(frame: int) -> Texture2D:
	if _spirit_frames.is_empty():
		var atlas := SPIRIT_ATLAS.get_image()
		for index in 12:
			var start := Vector2i(index % 4, index / 4) * SPIRIT_FRAME_SIZE
			_spirit_frames.append(ImageTexture.create_from_image(atlas.get_region(Rect2i(start, SPIRIT_FRAME_SIZE))))
	return _spirit_frames[frame]


## Объёмная оболочка по силуэту текстуры. Меш переиспользуется всеми
## снарядами одного вида, включая отдельные позы цифрового духа.
static func volume(key: String, art: Texture2D = null) -> ArrayMesh:
	if art == null:
		art = texture(key)
	var cache_key := key + ":" + str(art.get_instance_id())
	if _volumes.has(cache_key):
		return _volumes[cache_key]
	var image := art.get_image()
	var extent := world_size(key)
	if key == "spirit" and art.get_size() == Vector2(SPIRIT_FRAME_SIZE):
		extent = Vector2(SPIRIT_FRAME_SIZE) * (float(WORLD_SPAN["spirit"]) / SPIRIT_FRAME_SIZE.x)
	var depth: float = {"spirit": 0.85, "wave": 0.34, "shuriken": 0.28, "blade": 0.28,
		"ball": 1.0, "arrow": 0.43, "mine": 0.62, "drone": 0.67}.get(key, 0.74)
	var silhouette := image.get_used_rect()
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var uvs: Array[PackedVector2Array] = []
	const SECTIONS := 16
	const SIDES := 10
	for i in range(SECTIONS + 1):
		var step := float(i) / SECTIONS
		var sample_x := lerpf(silhouette.position.x, silhouette.end.x - 1, step)
		var x := clampi(roundi(sample_x), 0, image.get_width() - 1)
		var top := image.get_height()
		var bottom := -1
		for y in range(silhouette.position.y, silhouette.end.y):
			if image.get_pixel(x, y).a > 0.22:
				top = mini(top, y)
				bottom = maxi(bottom, y)
		if bottom < top:
			top = silhouette.get_center().y
			bottom = top
		var u := (sample_x + 0.5) / image.get_width()
		var axis := ((top + bottom + 1.0) / (2.0 * image.get_height()))
		var r := maxf(1.0, (bottom - top + 1.0) * 0.51) / image.get_height()
		var thick := extent.y * r * depth
		thick *= clampf(sin(PI * step) * 2.7, 0.16, 1.0)
		var points := PackedVector3Array()
		var uv := PackedVector2Array()
		var normal := PackedVector3Array()
		for j in SIDES:
			var a := TAU * j / SIDES
			var v := axis - cos(a) * r
			points.append(Vector3((u - 0.5) * extent.x, (0.5 - v) * extent.y, sin(a) * thick))
			uv.append(Vector2(u, v))
			normal.append(Vector3(0.0, cos(a) * depth, sin(a)).normalized())
		rings.append(points)
		normals.append(normal)
		uvs.append(uv)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SECTIONS:
		for j in SIDES:
			var next := (j + 1) % SIDES
			for corner in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, next),
						Vector2i(i, next), Vector2i(i + 1, j), Vector2i(i + 1, next)]:
				mesh.set_normal(normals[corner.x][corner.y])
				mesh.set_uv(uvs[corner.x][corner.y])
				mesh.add_vertex(rings[corner.x][corner.y])
	for edge in [0, SECTIONS]:
		var midpoint := (rings[edge][0] + rings[edge][SIDES / 2]) * 0.5
		for j in SIDES:
			var next := (j + 1) % SIDES
			for vertex in ([j, next, -1] if edge == 0 else [next, j, -1]):
				mesh.set_normal(Vector3.LEFT if edge == 0 else Vector3.RIGHT)
				mesh.set_uv(uvs[edge][j] if vertex == -1 else uvs[edge][vertex])
				mesh.add_vertex(midpoint if vertex == -1 else rings[edge][vertex])
	mesh.index()
	var result := mesh.commit()
	_volumes[cache_key] = result
	return result


static func volume_material(art: Texture2D, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = art
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.16
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.emission_enabled = true
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission = tint * 0.66
	m.emission_texture = art
	m.roughness = 0.38
	return m


static func volume_instance(key: String, art: Texture2D = null) -> MeshInstance3D:
	if art == null:
		art = texture(key)
	var body := MeshInstance3D.new()
	body.mesh = volume(key, art)
	body.material_override = volume_material(art)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return body
