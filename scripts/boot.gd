extends RefCounted
## Старые установленные версии (exe/apk до 0.15.9) компилируют автозагрузки вместе со всеми
## скриптами, которые те подтягивают (данные, графика, сохранения), ДО того как подключится
## пакет обновления. Из-за этого часть игры оставалась старой, а часть — новой: например,
## жители в убежище рисовались пустыми. Здесь, в самом начале новой версии, такие устаревшие
## скрипты выбрасываются из кэша — дальше игра загружает их уже из пакета обновления.
## В новых установках (настройка проекта nhn/autoload_safe) это не нужно.

## Скрипты автозагрузок и заставки — уже работают, их не трогаем.
const KEEP := ["updater.gd", "settings.gd", "audio.gd", "net.gd", "loader.gd", "touch_controls.gd",
	"boot.gd", "splash.gd", "retro_logo.gd"]

static var done := false
static var old_data = null    # старая копия data.gd, которой пользуются старые автозагрузки


static func refresh() -> void:
	if done:
		return
	done = true
	if ProjectSettings.has_setting("nhn/autoload_safe"):
		return
	var stale: Array = []
	for f in DirAccess.get_files_at("res://scripts"):
		var p: String = "res://scripts/" + f.trim_suffix(".remap").trim_suffix(".gdc")
		if not p.ends_with(".gd") or p.get_file() in KEEP or p in stale:
			continue
		if ResourceLoader.has_cached(p):
			stale.append(p)
	if stale.is_empty():
		return
	var od = load("res://scripts/data.gd") if "res://scripts/data.gd" in stale else null
	for p in stale:
		var r: Resource = load(p)
		if r != null:
			r.resource_path = ""
	if od != null:
		old_data = od
		var nd = load("res://scripts/data.gd")
		nd.music_volume = od.music_volume
		nd.sfx_volume = od.sfx_volume
	print("[Обновление] обновлено устаревших скриптов: %d" % stale.size())


## Громкость: старые автозагрузки (звук, настройки) читают её из старой копии данных.
static func sync_volume(d) -> void:
	if old_data != null:
		old_data.music_volume = d.music_volume
		old_data.sfx_volume = d.sfx_volume
