extends RefCounted
## Внешняя графика: PNG из res://art/.
## Если файла нет — игра рисует как раньше, процедурно (pixel.gd). Ничего не ломается.
##
## Куда класть:
##   art/sprites/<key>.png    — атлас кадров: ширина = w × кадров, высота = h × 1..3 полосы
##                              полосы сверху вниз: base, emit (неон), flash (вспышка)
##   art/icons/<id>.png       — иконки оружия и модулей, 36×36
##   art/ground/base.png      — плитка пола 128×128 (тайлится)
##   art/ground/emit.png      — неоновый слой пола 128×128
##   art/surface/<kind>.png   — текстура для 3D-материалов 16×16 (panel, brick, tile, wood)
##
## Размеры кадров берутся из Pixel.SPECS: художник рисует в тех же пикселях, что и код,
## поэтому менять масштабы и позиции в игре не нужно.

const ROOT := "res://art"

static var _tex := {}    # путь -> Texture2D или null
static var _img := {}    # путь -> Image или null
static var _known := {}  # путь -> true (файл уже проверяли)


## Текстура по пути; null, если файла нет.
static func load_tex(path: String) -> Texture2D:
	if _known.has(path):
		return _tex.get(path)
	_known[path] = true
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = ResourceLoader.load(path) as Texture2D
	_tex[path] = t
	return t


## Картинка по пути; null, если файла нет.
static func image(path: String) -> Image:
	if _img.has(path):
		return _img.get(path)
	var t := load_tex(path)
	var im: Image = null
	if t != null:
		im = t.get_image()
		if im != null and im.is_compressed():
			im.decompress()
	_img[path] = im
	return im


## «rin~oni» и «rin|m:hp1,» → безопасное имя файла.
static func safe(key: String) -> String:
	var s := key.replace("~", "_").replace("|", "_").replace(":", "_")
	return s.replace("/", "_").replace("\\", "_").replace("*", "_").replace("?", "_")


static func sprite_path(key: String) -> String:
	return ROOT + "/sprites/" + safe(key) + ".png"


static func sprite(key: String) -> Image:
	return image(sprite_path(key))


static func icon(id: String) -> Image:
	return image(ROOT + "/icons/" + id + ".png")


static func ground(layer: String) -> Image:
	return image(ROOT + "/ground/" + layer + ".png")


static func surface(kind: String) -> Image:
	return image(ROOT + "/surface/" + kind + ".png")


## Готовые спрайты в art/sprites — для инструментов и проверки полноты.
static func sprite_keys() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ROOT + "/sprites")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".png"):
			out.append(f.get_basename())
	out.sort()
	return out
