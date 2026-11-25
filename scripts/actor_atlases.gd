extends RefCounted
## The original animation cells, in rows of eight, with body, light and hit layers.

const DIRECTORY := "res://assets/actors/"
const LAYERS := ["base", "emit", "flash"]
const RESOLUTION := 2
const GRID_COLUMNS := 8
const FRAME_COUNTS := {1: 1, 2: 2, 12: 12, 19: 19, 35: 40, 36: 36}


static func path_for(key: String) -> String:
	# Стражи одного уровня используют те же кадры в каждом зале.
	if key.get_slice("~", 1).begins_with("gh") and key.get_slice("-", 1).is_valid_int():
		key = key.get_slice("-", 0)
	for part in key.split("~"):
		if not part.is_valid_identifier():
			return ""
	var path := DIRECTORY + key + ".webp.bytes"
	return path if FileAccess.file_exists(path) else ""


static func read_atlas(path: String, size: Vector2i, count: int) -> Image:
	if path.is_empty() or not FRAME_COUNTS.has(count):
		return null
	var poses: int = FRAME_COUNTS[count]
	var cols := mini(GRID_COLUMNS, poses)
	var expected_size := Vector2i(size.x * cols, size.y * LAYERS.size() * ceili(float(poses) / cols))
	var image := Image.new()
	if image.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		push_error("Не удалось прочитать атлас: " + path)
		return null
	if image.get_size() != expected_size:
		push_error("Неверный размер атласа: " + path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


static func frame_image(atlas: Image, size: Vector2i, column: int, layer: int) -> Image:
	var cols := atlas.get_width() / size.x
	var x := (column % cols) * size.x
	var y := (column / cols * LAYERS.size() + layer) * size.y
	return atlas.get_region(Rect2i(Vector2i(x, y), size))
