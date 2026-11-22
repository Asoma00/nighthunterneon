extends RefCounted
## PNG атласы персонажей: одна колонка на позу, строки тела, свечения и вспышки.
## Повторяющиеся позы делят колонку; порядок кадров совпадает с анимациями игры.

const DIRECTORY := "res://assets/actors/"
const LAYERS := ["base", "emit", "flash"]
const FRAME_COLUMNS := {
	1: [0],
	12: [0, 1, 0, 1, 0, 1, 0, 2, 2, 1, 3, 0],
	19: [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 0, 3, 3, 3, 0],
	35: [0, 1, 2, 3, 2, 1, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 10,
		11, 12, 12, 13, 13, 12, 14, 0, 16, 17, 18, 18, 19, 19, 5, 15, 7],
	36: [0, 0, 1, 1, 0, 1, 6, 6, 2, 2, 0, 1, 0, 3, 3, 0, 4, 0, 5, 5,
		0, 6, 6, 6, 0, 7, 7, 1, 0, 8, 8, 0, 1, 9, 9, 0],
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
	var path := DIRECTORY + key + ".png"
	return path if ResourceLoader.exists(path, "Texture2D") else ""


static func read_atlas(path: String, size: Vector2i, count: int) -> Image:
	if path.is_empty() or not FRAME_COLUMNS.has(count):
		return null
	var atlas := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var columns: Array = FRAME_COLUMNS[count]
	var expected_size := Vector2i(size.x * (int(columns.max()) + 1), size.y * LAYERS.size())
	if atlas == null or Vector2i(atlas.get_size()) != expected_size:
		push_error("Неверный размер атласа: " + path)
		return null
	var image := atlas.get_image()
	if image == null or image.is_empty():
		push_error("Не удалось прочитать атлас: " + path)
		return null
	if image.is_compressed() and image.decompress() != OK:
		push_error("Не удалось распаковать атлас: " + path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


static func frame_image(atlas: Image, size: Vector2i, column: int, layer: int) -> Image:
	return atlas.get_region(Rect2i(Vector2i(column * size.x, layer * size.y), size))
