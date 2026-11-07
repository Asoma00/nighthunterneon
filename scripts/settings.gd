extends Node
## Настройки экрана и звука: режим окна, формат, разрешение, громкость.
## Сохраняются в user://settings.cfg и применяются при каждом запуске.
## Подключён как автозагрузка «Settings».

const Data := preload("res://scripts/data.gd")
const PATH := "user://settings.cfg"
const BASE := Vector2(1280, 720)  # под этот размер свёрстан интерфейс

const RES_16_9: Array[Vector2i] = [
	Vector2i(7680, 4320), Vector2i(5120, 2880), Vector2i(3840, 2160), Vector2i(3200, 1800),
	Vector2i(2560, 1440), Vector2i(2048, 1152), Vector2i(1920, 1080), Vector2i(1600, 900),
	Vector2i(1366, 768), Vector2i(1280, 720), Vector2i(1024, 576), Vector2i(960, 540),
	Vector2i(854, 480), Vector2i(640, 360),
]
const RES_4_3: Array[Vector2i] = [
	Vector2i(3200, 2400), Vector2i(2880, 2160), Vector2i(2560, 1920), Vector2i(2048, 1536),
	Vector2i(1920, 1440), Vector2i(1600, 1200), Vector2i(1440, 1080), Vector2i(1400, 1050),
	Vector2i(1280, 960), Vector2i(1152, 864), Vector2i(1024, 768), Vector2i(800, 600),
	Vector2i(640, 480),
]

## fullscreen — полный экран, windowed — в окне, borderless — в окне без рамки
var mode := "fullscreen"
## native — родное разрешение монитора, иначе "16:9" или "4:3"
var aspect := "native"
## Vector2i.ZERO — родное разрешение монитора
var resolution := Vector2i.ZERO
## Графический API: vulkan, d3d12 или opengl. Меняется после перезапуска игры.
var api := "vulkan"
## Кадры: "monitor" — по частоте экрана, "0" — без ограничения, иначе число кадров в секунду
var fps := "monitor"
## Вертикальная синхронизация: off / on / adaptive
var vsync := "on"
## Количество эффектов: 0 — мало, 1 — средне, 2 — много
var effects := 2
## Тени: 0 — выкл, 1 — низкие, 2 — средние, 3 — высокие
var shadows := 2
## Чёткость текстур мира: auto — по разрешению экрана, иначе 1.0 / 1.5 / 2.0
var tex_quality := "auto"
const FPS_OPTIONS := ["monitor", "30", "60", "75", "90", "120", "144", "165", "240", "0"]
const APIS := ["vulkan", "d3d12", "opengl"]


## Телефон / планшет (Android) — сенсорное управление и облегчённая графика.
## Для проверки на ПК: запустить игру с аргументом --touch.
func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("web_ios") or OS.has_feature("web_android") \
		or "--touch" in OS.get_cmdline_user_args() or "--touch" in OS.get_cmdline_args()


## Запущена в браузере (веб-версия: iPhone через Safari / «На экран Домой»)
func is_web() -> bool:
	return OS.has_feature("web")


const MOBILE_HEIGHTS := [360, 450, 540, 720, 900, 1080]

# ---- Дополнительные настройки для слабых телефонов ----
var glow := true          # свечение (самый тяжёлый проход на телефоне)
var weather := true       # погода и парящие частицы
var decor := 1            # 0 — упрощённый пол (без пятен и подсветки), 1 — полный
var view_dist := 2        # дальность прорисовки: 0 ближняя, 1 средняя, 2 полная
var crowd := 1            # врагов на экране: 0 — меньше (100, крепче), 1 — обычно (150)
var preset := -1          # последний выбранный профиль графики (−1 — свой)

const PRESET_NAMES := ["Минимум (слабые телефоны)", "Низкий", "Средний", "Высокий"]


## Профиль графики для телефона: разом выставляет все параметры.
func apply_preset(i: int) -> void:
	preset = i
	var keep_h := mobile_h
	match i:
		0:
			mobile_h = 360; effects = -1; shadows = 0; tex_quality = "low"; glow = false
			weather = false; decor = 0; view_dist = 0; crowd = 0; fps = "30"
		1:
			mobile_h = 540; effects = 0; shadows = 0; tex_quality = "low"; glow = false
			weather = false; decor = 0; view_dist = 1; crowd = 0; fps = "60"
		2:
			mobile_h = 720; effects = 1; shadows = 0; tex_quality = "low"; glow = true
			weather = true; decor = 1; view_dist = 2; crowd = 1; fps = "60"
		3:
			mobile_h = 900; effects = 2; shadows = 1; tex_quality = "auto"; glow = true
			weather = true; decor = 1; view_dist = 2; crowd = 1; fps = "60"
	if not is_mobile():
		# ПК и Steam Deck: разрешение экрана профиль не трогает, кадры — по экрану
		mobile_h = keep_h
		if i == 3:
			shadows = 2
			fps = "monitor"
		elif i == 2:
			shadows = 1
	apply_display()
	apply_graphics()
	save_settings()


func glow_enabled() -> bool:
	return glow


func weather_enabled() -> bool:
	return weather


func decor_full() -> bool:
	return decor > 0


## Насколько далеко от центра кадра мир считается видимым (меньше — меньше работы).
func view_k() -> float:
	return [0.72, 0.86, 1.0][clampi(view_dist, 0, 2)]


func mobile_enemy_cap() -> int:
	return 100 if crowd == 0 else 150


## Сколько врагов одновременно на ПК / Steam Deck
func desktop_enemy_cap() -> int:
	return 200 if crowd == 0 else 320


## Steam Deck (Steam выставляет SteamDeck=1; в режиме рабочего стола — SteamOS)
func is_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	if OS.get_name() == "Linux" and FileAccess.file_exists("/etc/os-release"):
		return FileAccess.get_file_as_string("/etc/os-release").to_lower().contains("steamos")
	return false


## Во сколько раз уменьшена текстура мира на телефоне (зависит от «Чёткости»)
func mobile_world_scale() -> float:
	match mobile_h:
		360:
			return 0.36
		450:
			return 0.44
		540:
			return 0.5
		720:
			return 0.62
		900:
			return 0.78
	return 0.92
## Высота картинки на телефоне (ширина — по пропорциям экрана)
var mobile_h := 720
## Размер сенсорных кнопок: 0 — маленькие, 1 — обычные, 2 — крупные
var touch_size := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	get_window().size_changed.connect(_on_window_resized)
	if is_deck() and not FileAccess.file_exists(PATH):
		# Steam Deck: экран 1280×800, полный экран, средний профиль, 60 кадров
		mode = "fullscreen"
		resolution = Vector2i.ZERO
		fps = "60"
		effects = 1
		shadows = 1
		tex_quality = "auto"
		glow = true
		weather = true
		decor = 1
		view_dist = 2
		crowd = 0
		preset = 2
	if is_web():
		# В браузере нет системных шрифтов: значки ◆ ★ ✓ → ≡ и т. п. берём из DejaVu Sans
		var fb: Font = ThemeDB.fallback_font
		var dv = load("res://fonts/DejaVuSans.ttf")
		if fb and dv:
			var arr: Array[Font] = fb.fallbacks
			arr.append(dv)
			fb.fallbacks = arr
	if is_mobile():
		# Облегчённые значения по умолчанию для телефона
		mode = "fullscreen"
		fps = "60"
		effects = 0
		shadows = 0
		tex_quality = "low"
		glow = false
		weather = false
		decor = 0
		view_dist = 1
		crowd = 0
		mobile_h = 540
		preset = 1
		if is_web():
			# Браузер медленнее родного приложения — средний профиль
			mobile_h = 720; effects = 1; shadows = 0; tex_quality = "low"; glow = true
			weather = true; decor = 1; view_dist = 1; crowd = 0; fps = "60"; preset = 2
		elif OS.has_feature("ios"):
			# iPhone (A15–A17 и новее) тянет высокий профиль; кадры — 60, а не 120 (меньше греется)
			mobile_h = 900; effects = 2; shadows = 1; tex_quality = "auto"; glow = true
			weather = true; decor = 1; view_dist = 2; crowd = 1; fps = "60"; preset = 3
	load_settings()
	apply_display()
	apply_graphics()


func native_size() -> Vector2i:
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


const FORMATS := ["native", "16:9", "16:10", "21:9", "4:3", "5:4"]
const RATIOS := {"16:9": 16.0 / 9.0, "16:10": 1.6, "21:9": 64.0 / 27.0, "4:3": 4.0 / 3.0, "5:4": 1.25}
const HEIGHTS := [4320, 2880, 2160, 2048, 1800, 1600, 1536, 1440, 1350, 1200, 1152, 1080, 1050, 1024,
	960, 900, 864, 800, 768, 720, 648, 600, 576, 540, 480, 450, 400, 360, 300, 240]


## Все разрешения формата — от максимально доступного на этом мониторе до минимального.
## «Как у монитора» — все разрешения с пропорциями экрана, начиная с родного.
func resolutions_for(fmt: String) -> Array[Vector2i]:
	var screen := native_size()
	var ratio: float = float(screen.x) / maxf(1.0, float(screen.y)) if fmt == "native" else float(RATIOS.get(fmt, 16.0 / 9.0))
	var out: Array[Vector2i] = []
	if fmt == "native":
		out.append(screen)
	for h in HEIGHTS:
		var w := int(round(h * ratio / 2.0)) * 2
		if w == 1364 and h == 768:
			w = 1366   # привычное 1366×768
		var r := Vector2i(w, h)
		if w <= screen.x and h <= screen.y and not (r in out):
			out.append(r)
	if out.is_empty():
		out.append(Vector2i(int(round(240 * ratio / 2.0)) * 2, 240))
	return out


func current_resolution() -> Vector2i:
	if resolution == Vector2i.ZERO:
		return native_size()
	return resolution


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_mobile():
		_apply_mobile_display()
		return
	var res := current_resolution()
	var screen := native_size()
	res = Vector2i(mini(res.x, screen.x), mini(res.y, screen.y))
	var win := get_window()
	match mode:
		"fullscreen":
			win.borderless = false
			win.mode = Window.MODE_FULLSCREEN
		"windowed", "borderless":
			win.mode = Window.MODE_WINDOWED
			win.borderless = mode == "borderless"
			win.size = res
			var origin := DisplayServer.screen_get_position(DisplayServer.window_get_current_screen())
			win.position = origin + (screen - res) / 2
	# Игра рисуется ровно в выбранном разрешении; в полноэкранном режиме картинка
	# растягивается на монитор с сохранением формата (4:3 — с полосами по бокам).
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = res
	win.content_scale_factor = minf(res.x / BASE.x, res.y / BASE.y)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mode = cfg.get_value("display", "mode", mode)
	aspect = cfg.get_value("display", "aspect", aspect)
	resolution = cfg.get_value("display", "resolution", resolution)
	api = cfg.get_value("display", "api", current_api())
	fps = cfg.get_value("graphics", "fps", fps)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	effects = cfg.get_value("graphics", "effects", effects)
	shadows = cfg.get_value("graphics", "shadows", shadows)
	tex_quality = cfg.get_value("graphics", "tex_quality", tex_quality)
	Data.music_volume = cfg.get_value("audio", "music", Data.music_volume)
	Data.sfx_volume = cfg.get_value("audio", "sfx", Data.sfx_volume)
	mobile_h = cfg.get_value("mobile", "height", mobile_h)
	glow = cfg.get_value("mobile", "glow", glow)
	weather = cfg.get_value("mobile", "weather", weather)
	decor = cfg.get_value("mobile", "decor", decor)
	view_dist = cfg.get_value("mobile", "view", view_dist)
	crowd = cfg.get_value("mobile", "crowd", crowd)
	preset = cfg.get_value("mobile", "preset", preset)
	touch_size = cfg.get_value("mobile", "touch_size", touch_size)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", mode)
	cfg.set_value("display", "aspect", aspect)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "api", api)
	cfg.set_value("graphics", "fps", fps)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "effects", effects)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "tex_quality", tex_quality)
	cfg.set_value("audio", "music", Data.music_volume)
	cfg.set_value("audio", "sfx", Data.sfx_volume)
	cfg.set_value("mobile", "height", mobile_h)
	cfg.set_value("mobile", "glow", glow)
	cfg.set_value("mobile", "weather", weather)
	cfg.set_value("mobile", "decor", decor)
	cfg.set_value("mobile", "view", view_dist)
	cfg.set_value("mobile", "crowd", crowd)
	cfg.set_value("mobile", "preset", preset)
	cfg.set_value("mobile", "touch_size", touch_size)
	cfg.save(PATH)



## Телефон: всегда весь экран; картинка рисуется в mobile_h строк по пропорциям экрана
## и растягивается на дисплей — без полос, интерфейс свёрстан под 720 строк.
func _apply_mobile_display() -> void:
	var win := get_window()
	if not is_web():
		win.mode = Window.MODE_FULLSCREEN   # в браузере весь экран даёт сам Safari (ярлык «Домой»)
	var screen := Vector2(get_window().size)
	if screen.x < 10.0 or screen.y < 10.0:
		screen = Vector2(native_size())
	# Короткая сторона экрана = mobile_h строк; интерфейс свёрстан под 720 по короткой стороне.
	# Работает и в горизонтальном, и в вертикальном положении телефона.
	var short_px := minf(screen.x, screen.y)
	var ratio := maxf(screen.x, screen.y) / maxf(1.0, short_px)
	var h := float(mini(mobile_h, int(short_px)))
	var long_side := int(round(h * ratio / 2.0)) * 2
	var res := Vector2i(long_side, int(h)) if screen.x >= screen.y else Vector2i(int(h), long_side)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = res
	win.content_scale_factor = h / BASE.y
	_last_portrait = screen.y > screen.x


var _last_portrait := false
signal orientation_changed(portrait: bool)


## Телефон повернули: пересчитать картинку и сообщить сценам, чтобы перестроили интерфейс
func _on_window_resized() -> void:
	if not is_mobile():
		return
	var s := Vector2(get_window().size)
	var p := s.y > s.x
	if p != _last_portrait:
		_apply_mobile_display()
		orientation_changed.emit(p)


## Безопасная зона экрана телефона (вырез камеры, «динамический остров», полоска «домой»):
## отступы [слева, сверху, справа, снизу] в единицах интерфейса.
func safe_margins() -> Array:
	if not is_mobile() or DisplayServer.get_name() == "headless":
		return [0.0, 0.0, 0.0, 0.0]
	var sa := DisplayServer.get_display_safe_area()
	var ws := Vector2(get_window().size)
	if sa.size.x <= 0 or sa.size.y <= 0 or ws.x < 10.0:
		return [0.0, 0.0, 0.0, 0.0]
	var vs := get_window().get_visible_rect().size
	var kx := vs.x / ws.x
	var ky := vs.y / ws.y
	return [maxf(0.0, sa.position.x * kx), maxf(0.0, sa.position.y * ky),
		maxf(0.0, (ws.x - sa.end.x) * kx), maxf(0.0, (ws.y - sa.end.y) * ky)]


## Вписать корневой элемент интерфейса в безопасную зону.
func apply_safe(c: Control) -> void:
	var m := safe_margins()
	c.offset_left = m[0]
	c.offset_top = m[1]
	c.offset_right = -m[2]
	c.offset_bottom = -m[3]


# ---------- Подсказки управления: каждая версия показывает только своё ----------

signal input_mode_changed(mode: String)
var _pad_used := false

## «touch» — телефон/планшет/iPhone, «pad» — Steam Deck или геймпад на ПК, «kb» — клавиатура и мышь.
func input_mode() -> String:
	if is_mobile():
		return "touch"
	if is_deck() or _pad_used:
		return "pad"
	return "kb"


func _track_input_mode(event: InputEvent) -> void:
	if is_mobile():
		return
	var pad := _pad_used
	if event is InputEventJoypadButton and event.pressed:
		pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		pad = true
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		pad = is_deck() and event is InputEventMouseButton   # на Deck тачскрин — не повод показывать клавиатуру
	if pad != _pad_used:
		_pad_used = pad
		input_mode_changed.emit(input_mode())


const HINTS := {
	"back": {"kb": "ESC", "pad": "B", "touch": ""},
	"pause": {"kb": "ESC", "pad": "START", "touch": "II"},
	"ability": {"kb": "ПРОБЕЛ", "pad": "A", "touch": "2× ТАП"},
	"stats": {"kb": "TAB", "pad": "SELECT", "touch": "≡"},
	"interact": {"kb": "E", "pad": "A", "touch": "ВОЙТИ"},
	"move": {"kb": "WASD", "pad": "левый стик", "touch": "касание и сдвиг пальца"},
	"pick": {"kb": "клавиши 1, 2, 3", "pad": "крестовина и A", "touch": "коснитесь карточки"},
	"accept": {"kb": "ENTER", "pad": "A", "touch": ""},
}


## Название кнопки для действия в текущей версии управления («» — кнопки нет).
func key(action: String) -> String:
	return str(HINTS.get(action, {}).get(input_mode(), ""))


## «ЗАКРЫТЬ  [ESC]» на ПК, «ЗАКРЫТЬ  [B]» на Deck, просто «ЗАКРЫТЬ» на телефоне.
func with_key(text: String, action: String) -> String:
	var k := key(action)
	if k == "" or input_mode() == "touch":
		return text
	return "%s  [%s]" % [text, k]


## Вертикальный ли сейчас экран
func is_portrait() -> bool:
	var vs := get_window().get_visible_rect().size
	return vs.y > vs.x


# ---------- Графика: кадры, синхронизация, эффекты, тени, текстуры ----------

func refresh_rate() -> int:
	var r := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return int(round(r)) if r > 1.0 else 60


func apply_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match vsync:
		"off":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"adaptive":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if fps == "monitor":
		Engine.max_fps = refresh_rate()
	else:
		Engine.max_fps = int(fps)
	# Размер атласа теней направленного света (в убежище)
	var dsize: int = [512, 1024, 2048, 4096][clampi(shadows, 0, 3)]
	RenderingServer.directional_shadow_atlas_set_size(dsize, true)


## Множитель количества эффектов.
func fx_k() -> float:
	if effects < 0:
		return 0.18   # «Минимум» — только самые нужные вспышки
	return [0.35, 0.65, 1.0][clampi(effects, 0, 2)]


## Во сколько раз текстура мира чётче базовой — зависит от разрешения экрана.
func tex_scale() -> float:
	match tex_quality:
		"low":
			return 1.0
		"medium":
			return 1.5
		"high":
			return 2.0
	var h := float(get_window().size.y) if is_inside_tree() else 720.0
	return clampf(snappedf(h / 720.0, 0.25), 1.0, 2.0)


## Каким API игра рисует сейчас.
func current_api() -> String:
	var drv := RenderingServer.get_current_rendering_driver_name().to_lower()
	if drv.begins_with("d3d12"):
		return "d3d12"
	if drv.begins_with("opengl"):
		return "opengl"
	return "vulkan"


## Выбрать графический API. Записывает override.cfg рядом с игрой — Godot читает его
## при запуске. Возвращает текст для игрока (или ошибку).
func set_api(new_api: String) -> String:
	api = new_api
	save_settings()
	if OS.has_feature("editor"):
		return "В редакторе API задаётся в настройках проекта"
	var path := OS.get_executable_path().get_base_dir().path_join("override.cfg")
	var cfg := ConfigFile.new()
	cfg.load(path)
	match new_api:
		"d3d12":
			cfg.set_value("rendering", "renderer/rendering_method", "forward_plus")
			cfg.set_value("rendering", "rendering_device/driver.windows", "d3d12")
		"opengl":
			cfg.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
		_:
			cfg.set_value("rendering", "renderer/rendering_method", "forward_plus")
			cfg.set_value("rendering", "rendering_device/driver.windows", "vulkan")
	# Отдельный поток отрисовки нестабилен с OpenGL — для него рисуем в основном потоке
	cfg.set_value("rendering", "driver/threads/thread_model", 1 if new_api == "opengl" else 2)
	# Если выбранный API не запустится, Godot сам вернётся к другому
	cfg.set_value("rendering", "rendering_device/fallback_to_vulkan", true)
	cfg.set_value("rendering", "rendering_device/fallback_to_d3d12", true)
	var err := cfg.save(path)
	if err != OK:
		return "Не удалось сохранить (папка игры только для чтения?)"
	return "Сохранено — перезапустите игру"


## Управление для всей игры (меню, убежище, забег).
func _input(event: InputEvent) -> void:
	_track_input_mode(event)
	preload("res://scripts/ui_focus.gd").on_input(event)


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"ability": [KEY_SPACE, KEY_SHIFT],
		"pause": [KEY_ESCAPE, KEY_P],
		"interact": [KEY_E, KEY_ENTER],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	# Геймпад (любой): стик и крестовина — движение, A/X/RB — способность,
	# A — взаимодействие, Start — пауза. В меню работают стандартные ui_* (стик, A, B).
	var joy_axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	var joy_btns := {"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
		"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
		"ability": [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
		"interact": [JOY_BUTTON_A], "pause": [JOY_BUTTON_START]}
	# В меню и окнах: A — выбрать, B — назад (на любом геймпаде)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var jb := InputEventJoypadButton.new()
		jb.device = -1
		jb.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], jb):
			InputMap.action_add_event(pair[0], jb)
	var UiF := preload("res://scripts/ui_focus.gd")
	UiF.pad_mode = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(func(_d, connected):
		if connected:
			UiF.pad_mode = true)
	for action in joy_axes:
		InputMap.action_set_deadzone(action, 0.3)
		var m := InputEventJoypadMotion.new()
		m.device = -1
		m.axis = joy_axes[action][0]
		m.axis_value = joy_axes[action][1]
		InputMap.action_add_event(action, m)
	for action in joy_btns:
		for bi in joy_btns[action]:
			var b := InputEventJoypadButton.new()
			b.device = -1
			b.button_index = bi
			InputMap.action_add_event(action, b)
