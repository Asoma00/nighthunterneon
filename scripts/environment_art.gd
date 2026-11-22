extends RefCounted
## Repeatable ground and material textures. Ground size is measured in game texels.

const TILE_SIZE := 128
const BASE := {
	"slate": preload("res://assets/environment/slate.png"),
	"panel": preload("res://assets/environment/panel.png"),
	"brick": preload("res://assets/environment/brick.png"),
	"wood": preload("res://assets/environment/wood.png"),
	"tile": preload("res://assets/environment/tile.png"),
	"asphalt": preload("res://assets/environment/asphalt.png"),
	"crystal": preload("res://assets/environment/crystal.png"),
	"forest": preload("res://assets/environment/forest.png"),
	"salvage": preload("res://assets/environment/salvage.png"),
	"rune": preload("res://assets/environment/rune.png"),
	"temple": preload("res://assets/environment/temple.png"),
	"forge": preload("res://assets/environment/forge.png"),
	"flooded": preload("res://assets/environment/flooded.png"),
	"frost": preload("res://assets/environment/frost.png"),
	"grave": preload("res://assets/environment/grave.png"),
	"storm": preload("res://assets/environment/storm.png"),
}
const GLOW := {
	"slate": preload("res://assets/environment/slate_glow.png"),
	"rune": preload("res://assets/environment/rune_glow.png"),
	"temple": preload("res://assets/environment/temple_glow.png"),
	"forge": preload("res://assets/environment/forge_glow.png"),
	"flooded": preload("res://assets/environment/flooded_glow.png"),
	"grave": preload("res://assets/environment/grave_glow.png"),
	"storm": preload("res://assets/environment/storm_glow.png"),
}
const BIOME_FLOOR := ["asphalt", "crystal", "temple", "forest", "salvage",
	"rune", "temple", "forge", "flooded", "frost", "temple", "grave", "storm", "forest",
	"slate", "panel", "storm", "grave"]
const CHAPTER_FLOOR := {
	"vega": "rune", "rin": "wood", "bram": "forge", "kira": "flooded", "skyla": "frost",
	"orm": "temple", "mora": "grave", "zephyr": "storm", "iris": "forest", "kai": "wood",
	"lyra": "slate", "sol": "temple", "volt": "storm",
}
const DECAL_SURFACE := {
	"decal_cobble": "brick", "decal_road": "asphalt", "decal_cable": "salvage",
	"decal_crater": "crystal", "decal_rune": "rune", "decal_grate": "panel", "decal_moss": "forest",
}
static var _textures := {}
static var _decal_images := {}
static var _blank_glow: ImageTexture


static func _with_mipmaps(key: String, original: Texture2D) -> Texture2D:
	if not _textures.has(key):
		var image := original.get_image()
		image.generate_mipmaps()
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


static func surface(kind: String) -> Texture2D:
	return _with_mipmaps(kind, BASE.get(kind, BASE["panel"]))


static func floor_art(kind := "slate") -> Dictionary:
	var emission: Texture2D
	if GLOW.has(kind):
		emission = _with_mipmaps(kind + "_glow", GLOW[kind])
	else:
		if _blank_glow == null:
			_blank_glow = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
		emission = _blank_glow
	return {"base": surface(kind), "emit": emission, "size": TILE_SIZE}


## Preserve the shape of each map decal. Add the matching material inside its mask.
static func dress_decal(key: String, image: Image) -> void:
	if not DECAL_SURFACE.has(key):
		return
	var kind: String = DECAL_SURFACE[key]
	if not _decal_images.has(kind):
		_decal_images[kind] = (BASE[kind] as Texture2D).get_image()
	var pattern: Image = _decal_images[kind]
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var art := pattern.get_pixel((x * 4) % pattern.get_width(), (y * 4) % pattern.get_height())
			image.set_pixel(x, y, Color(pixel.lerp(art * (0.55 + 0.3 * pixel.get_luminance()), 0.53), pixel.a))
