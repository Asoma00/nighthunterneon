extends SceneTree
## Выгружает всю процедурную графику в PNG — шаблоны для художника.
## Запуск: godot --headless --path . --script tools/bake_art.gd
## Результат: art_ref/ (в папке лежит .gdignore, поэтому в игру и в экспорт не попадает).

const Pixel := preload("res://scripts/pixel.gd")
const Icons := preload("res://scripts/icons.gd")

const OUT := "res://art_ref"

var done := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for d in ["sprites", "icons", "ground", "surface"]:
		DirAccess.make_dir_recursive_absolute(OUT + "/" + d)

	var keys := list_sprites()
	for key in keys:
		if bake_sprite(key):
			done += 1
	print("спрайтов: %d из %d" % [done, keys.size()])

	done = 0
	for id in list_icons():
		var im: Image = Icons.draw(id)
		if im != null and im.save_png(OUT + "/icons/" + id + ".png") == OK:
			done += 1
	print("иконок: %d" % done)

	var g: Dictionary = Pixel.ground()
	(g["base"] as ImageTexture).get_image().save_png(OUT + "/ground/base.png")
	(g["emit"] as ImageTexture).get_image().save_png(OUT + "/ground/emit.png")
	print("пол: %d×%d" % [int(g["size"]), int(g["size"])])

	for kind in ["panel", "brick", "tile", "wood"]:
		(Pixel.surface(kind) as ImageTexture).get_image().save_png(OUT + "/surface/" + kind + ".png")

	print("готово за %.1f с" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func list_sprites() -> Array:
	var out: Array = []
	for k in Pixel.SPECS.keys():
		out.append(str(k))
	out.sort()
	return out


func list_icons() -> Array:
	return Icons.IDS


func bake_sprite(key: String) -> bool:
	var spec: Array = Pixel.SPECS[key]
	var w: int = spec[0]
	var h: int = spec[1]
	var fr: Dictionary = Pixel.frames(key)
	var base: Array = fr.get("base", [])
	if base.is_empty():
		push_warning("пусто: " + key)
		return false
	var count := base.size()
	var atlas := Image.create_empty(w * count, h * 3, false, Image.FORMAT_RGBA8)
	for f in count:
		atlas.blit_rect((base[f] as ImageTexture).get_image(), Rect2i(0, 0, w, h), Vector2i(f * w, 0))
		atlas.blit_rect((fr["emit"][f] as ImageTexture).get_image(), Rect2i(0, 0, w, h), Vector2i(f * w, h))
		atlas.blit_rect((fr["flash"][f] as ImageTexture).get_image(), Rect2i(0, 0, w, h), Vector2i(f * w, h * 2))
	var ok := atlas.save_png(OUT + "/sprites/" + key + ".png") == OK
	print("  %-14s %d×%d  %d кадр.  %s" % [key, w, h, count, "ok" if ok else "ОШИБКА"])
	return ok
