extends RefCounted
## Sprite sheets have up to eight columns of poses. Each band contains body, emission and flash rows.
## The frame order reuses held poses and includes a half-step between moving poses.

const DIRECTORY := "res://assets/actors/"
const LAYERS := ["base", "emit", "flash"]
const RESOLUTION := 2
const GRID_COLUMNS := 8
const FRAME_COLUMNS := {
	1: [0],
	12: [0, 4, 1, 5, 0, 4, 1, 5, 0, 4, 1, 5, 0, 6, 2, 2, 2, 7, 1, 1, 3, 8, 0, 0],
	19: [0, 7, 4, 8, 5, 9, 6, 10, 5, 11, 4, 12, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
		0, 15, 3, 3, 3, 3, 3, 16, 0, 0],
	35: [0, 20, 1, 21, 2, 22, 3, 23, 2, 24, 1, 25, 4, 4, 4, 26, 5, 5, 5, 27, 6, 6, 6, 28, 7, 7, 7, 29,
		8, 8, 8, 30, 9, 31, 10, 32, 11, 11, 12, 12, 12, 33, 13, 13, 13, 34, 12, 12, 14, 35, 0, 0, 16, 36, 17, 37,
		18, 18, 18, 38, 19, 19, 19, 19, 5, 39, 15, 40, 7, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51],
	36: [0, 0, 0, 10, 1, 1, 1, 11, 0, 10, 1, 11, 6, 6, 6, 12, 2, 2, 2, 13, 0, 10, 1, 1, 0, 14, 3, 3,
		3, 15, 0, 0, 4, 16, 0, 0, 5, 5, 5, 5, 0, 17, 6, 6, 6, 6, 6, 18, 0, 19, 7, 7, 7, 20, 1, 11,
		0, 21, 8, 8, 8, 22, 0, 0, 1, 23, 9, 9, 9, 24, 0, 10],
}


static func path_for(key: String) -> String:
	if key.begins_with("citizen_") and key.is_valid_identifier():
		var named := _existing_path(key)
		if not named.is_empty():
			return named
		var role := key.get_slice("_", 1)
		return _existing_path("npc_blacksmith" if role == "smith" else "npc_" + role)
	if key.begins_with("villager_"):
		return _existing_path("npc_walker")
	# Стражи одного уровня делят атлас, независимо от номера зала.
	if key.get_slice("~", 1).begins_with("gh") and key.get_slice("-", 1).is_valid_int():
		key = key.get_slice("-", 0)
	for part in key.split("~"):
		if not part.is_valid_identifier():
			return ""
	return _existing_path(key)


static func _existing_path(key: String) -> String:
	var path := DIRECTORY + key + ".webp.bytes"
	return path if FileAccess.file_exists(path) else ""


static func frame_size(legacy_size: Vector2i, count: int) -> Vector2i:
	if count == 35:
		return Vector2i(168, 120)
	if count == 19:
		return Vector2i(128, 120)
	return legacy_size * RESOLUTION


static func read_atlas(path: String, size: Vector2i, count: int) -> Image:
	if path.is_empty() or not FRAME_COLUMNS.has(count):
		return null
	var frames: Array = FRAME_COLUMNS[count]
	var poses := int(frames.max()) + 1
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
