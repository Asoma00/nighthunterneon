extends Node
## Автообновление.
## Как только устройство в сети, игра проверяет на GitHub Pages, не вышла ли новая сборка.
## Если вышла — в фоне скачивает пакет игры (один .pck для всех платформ, ~1 МБ),
## проверяет контрольную сумму и, как только вы в меню или убежище (не посреди боя),
## сразу перезапускается уже обновлённой — выходить из игры не нужно.
## В браузере (iPhone) просто перезагружается страница с новой версией.
##
## Это ПЕРВАЯ автозагрузка: в _init она подключает скачанный пакет раньше,
## чем загрузятся остальные скрипты, — поэтому вся игра запускается уже новой.

const BASE_URL := "https://asoma00.github.io/nighthunterneon/update/"
const DIR := "user://update/"
const STATE := "user://update/current.cfg"
const CHECK_EVERY := 180.0   # раз в 3 минуты, пока игра открыта

signal status_changed(text: String)

var build := 0          # номер работающей сборки (из пакета, если он подключён)
var version := "?"
var status := ""        # текст для меню: «Проверка обновлений…», «Скачано 0.15» и т. п.
var _ready_build := 0   # скачанная и проверенная, ждёт перезапуска
var _ready_path := ""
var _remote_version := ""
var _http: HTTPRequest
var _t := 5.0
var _busy := false
var _restarting := false


func _init() -> void:
	# Подключаем скачанное обновление до загрузки остальных скриптов игры
	var cfg := ConfigFile.new()
	if cfg.load(STATE) == OK:
		var path: String = cfg.get_value("update", "path", "")
		var b: int = int(cfg.get_value("update", "build", 0))
		var base_build: int = _builtin_build()
		if path != "" and b > base_build and FileAccess.file_exists(path):
			if not ProjectSettings.load_resource_pack(path, true):
				push_warning("Обновление не подключилось — играем встроенной версией")
		elif b <= base_build:
			_cleanup()   # установлена версия новее скачанной — старое обновление не нужно


## Номер сборки, вшитой в установленное приложение (до подключения обновлений).
## Хранится в настройках проекта — пакет обновления их не меняет.
## «0.14.1» → 14001; старый формат «0.14» → 14 (как было в сборке 0.14).
static func _builtin_build() -> int:
	var v := str(ProjectSettings.get_setting("application/config/version", "0.0"))
	var parts := v.split(".")
	if parts.size() > 2:
		return int(parts[1]) * 1000 + int(parts[2])
	return int(parts[1]) if parts.size() > 1 else 0


## На ПК старые сборки запускались с отдельным потоком рендера (экспериментальный режим
## Godot) — с ним игра вылетала при загрузке убежища. Настройки движка из обновления
## не применяются (они зашиты в .exe), поэтому кладём рядом с игрой override.cfg:
## со следующего запуска рендер работает в безопасном режиме.
func _safe_render_override() -> void:
	if OS.has_feature("editor") or OS.has_feature("web") or OS.has_feature("mobile"):
		return
	var path := OS.get_executable_path().get_base_dir().path_join("override.cfg")
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("thread_model=1"):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return   # папка только для чтения — ничего не поделать
	f.store_string("; Безопасный режим отрисовки (без отдельного потока рендера)\n[rendering]\n\ndriver/threads/thread_model=1\n")
	f.close()
	if int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)) == 2:
		print("[Обновление] включён безопасный режим рендера — подействует после перезапуска")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bs = load("res://scripts/build.gd")
	build = int(bs.BUILD)
	version = str(bs.VERSION)
	print("[Обновление] работает сборка %s (%d)" % [version, build])
	_safe_render_override()
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.use_threads = not OS.has_feature("web")
	add_child(_http)
	_http.request_completed.connect(_on_done)


func _process(delta: float) -> void:
	if _restarting:
		return
	if _ready_build > 0:
		_try_apply()
		return
	_t -= delta
	if _t <= 0.0 and not _busy:
		_t = CHECK_EVERY
		check()


func platform_key() -> String:
	if OS.has_feature("web"):
		return "web"
	return "pack"


# ---------- Проверка и загрузка ----------

var _stage := ""   # "check" / "download"
var _remote: Dictionary = {}


## Адрес обновлений (для проверки можно подменить переменной окружения NHN_UPDATE_URL)
func _base() -> String:
	var e := OS.get_environment("NHN_UPDATE_URL")
	return e if e != "" else BASE_URL


func check() -> void:
	if _busy or OS.has_feature("editor"):
		return
	_busy = true
	_stage = "check"
	var err := _http.request(_base() + "version.json?t=%d" % Time.get_unix_time_from_system())
	if err != OK:
		_busy = false


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	print("[Обновление] %s: результат %d, код %d" % [_stage, result, code])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if _stage == "download":
			_set_status("")
		return   # нет сети — попробуем позже
	if _stage == "check":
		var data = JSON.parse_string(body.get_string_from_utf8())
		if not (data is Dictionary) or int(data.get("build", 0)) <= build:
			return
		_remote = data
		_remote_version = str(data.get("version", "?"))
		if OS.has_feature("web"):
			_ready_build = int(data["build"])
			_set_status("Обновление %s — перезагрузка…" % _remote_version)
			return
		var pack: Dictionary = data.get("pack", {})
		if pack.is_empty():
			return
		DirAccess.make_dir_recursive_absolute(DIR)
		_ready_path = DIR + "game_%d.pck" % int(data["build"])
		_stage = "download"
		_busy = true
		_set_status("Загрузка обновления %s…" % _remote_version)
		_http.download_file = _ready_path
		if _http.request(_base() + str(pack["file"]) + "?t=%d" % Time.get_unix_time_from_system()) != OK:
			_busy = false
			_http.download_file = ""
	elif _stage == "download":
		_http.download_file = ""
		var pack: Dictionary = _remote.get("pack", {})
		var sum := FileAccess.get_sha256(_ready_path)
		if sum != str(pack.get("sha256", "")):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_ready_path))
			_set_status("")
			return   # файл повреждён — скачаем заново при следующей проверке
		var cfg := ConfigFile.new()
		cfg.set_value("update", "build", int(_remote["build"]))
		cfg.set_value("update", "version", _remote_version)
		cfg.set_value("update", "path", _ready_path)
		cfg.save(STATE)
		_ready_build = int(_remote["build"])
		_set_status("Обновление %s скачано" % _remote_version)


# ---------- Применение ----------

## Перезапуск только там, где ничего не потеряется: в главном меню или в убежище.
func _try_apply() -> void:
	var scene := get_tree().current_scene
	if scene == null or Loader.busy:
		return
	var f := scene.scene_file_path
	if not (f.ends_with("menu.tscn") or f.ends_with("hub.tscn")):
		return
	if Net.mode != "":
		return   # в сетевой игре не перезапускаемся — напарник потеряет связь
	_restarting = true
	_show_overlay("ОБНОВЛЕНИЕ %s" % _remote_version, "Перезапуск в новой версии…")
	await get_tree().create_timer(1.6).timeout
	_save_all()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(async () => {
			try { if ('serviceWorker' in navigator) { for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister(); } } catch (e) {}
			try { if (window.caches) { for (const k of await caches.keys()) await caches.delete(k); } } catch (e) {}
			location.reload();
		})()""", true)
		return
	# Новый процесс игры (он подключит обновление в _init), а этот закрываем
	var pid := OS.create_instance(OS.get_cmdline_args())
	if pid > 0 or pid == 0:
		get_tree().quit()
		return
	# Платформа не умеет перезапускаться сама (iPhone): обновление включится при следующем запуске
	_restarting = false
	_ready_build = 0
	_hide_overlay()
	_set_status("Обновление %s установится при следующем запуске" % _remote_version)


## Сохранить настройки и прогресс перед перезапуском.
func _save_all() -> void:
	Settings.save_settings()
	var meta = load("res://scripts/meta.gd")
	if meta.loaded:
		meta.save()


func _cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


var _overlay: CanvasLayer


func _show_overlay(title: String, sub: String) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 130
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.012, 0.055, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position -= Vector2(300, 50)
	v.custom_minimum_size = Vector2(600, 0)
	_overlay.add_child(v)
	for pair in [[title, 36, Color(0.3, 0.95, 1.0)], [sub, 18, Color(0.85, 0.85, 1.0)]]:
		var l := Label.new()
		l.text = pair[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", pair[1])
		l.add_theme_color_override("font_color", pair[2])
		v.add_child(l)


func _hide_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
