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
	var fps := 14.0 if lunging else 9.0
	return sequence[posmod(floori((age - 0.24) * fps + phase), sequence.size())]


static func spirit_frame(frame: int) -> Texture2D:
	if _spirit_frames.is_empty():
		var atlas := SPIRIT_ATLAS.get_image()
		for index in 12:
			var start := Vector2i(index % 4, index / 4) * SPIRIT_FRAME_SIZE
			_spirit_frames.append(ImageTexture.create_from_image(atlas.get_region(Rect2i(start, SPIRIT_FRAME_SIZE))))
	return _spirit_frames[frame]
