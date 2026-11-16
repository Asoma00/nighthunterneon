extends Node
## Облачные сохранения через аккаунт Google — по желанию игрока.
## Вход по коду (OAuth 2.0 Device Flow): игра показывает короткий код, игрок открывает
## google.com/device на любом устройстве и вводит его. Работает одинаково на ПК, Steam Deck,
## телефонах и в браузере — без встроенного окна входа.
## Сохранения лежат в скрытой папке приложения на Google Диске (appDataFolder):
## другие файлы Диска игре не видны, а сохранения не видны в обычном Диске.

const Meta := preload("res://scripts/meta.gd")
const Conf := preload("res://scripts/cloud_config.gd")

const STATE_PATH := "user://cloud.cfg"
const FILE_NAME := "nighthunter_save.json"
const SCOPE := "https://www.googleapis.com/auth/drive.appdata"
const DEVICE_URL := "https://oauth2.googleapis.com/device/code"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const REVOKE_URL := "https://oauth2.googleapis.com/revoke"
const FILES_URL := "https://www.googleapis.com/drive/v3/files"
const UPLOAD_URL := "https://www.googleapis.com/upload/drive/v3/files"
const ABOUT_URL := "https://www.googleapis.com/drive/v3/about?fields=user(displayName,emailAddress)"

signal changed

## off — вход не настроен в этой сборке; out — не вошли; code — ждём ввода кода;
## in — вошли; busy — идёт обмен с облаком; conflict — надо выбрать сохранение
var state := "out"
var msg := ""
var user_code := ""
var verify_url := ""
var email := ""
var last_sync := 0          # время облачной копии при последней синхронизации (unix)
var conflict := {}          # {"cloud": {...}, "local": {...}}

var _refresh := ""
var _access := ""
var _access_until := 0.0
var _synced_local := 0      # отметка локальных файлов при последней синхронизации
var _file_id := ""
var _device_code := ""
var _poll_t := 0.0
var _poll_every := 5.0
var _code_until := 0.0
var _dirty_t := -1.0
var _busy := false
var _popup: CanvasLayer

static var _inst: Node


static func get_inst() -> Node:
	if _inst == null or not is_instance_valid(_inst):
		var ml := Engine.get_main_loop()
		if not (ml is SceneTree):
			return null
		_inst = load("res://scripts/cloud.gd").new()
		_inst.name = "Cloud"
		(ml as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


func signed_in() -> bool:
	return _refresh != ""


static func configured() -> bool:
	return Conf.CLIENT_ID != ""


## Прогресс записан на диск — отправить в облако чуть позже (несколько сохранений подряд — одна отправка).
static func on_saved() -> void:
	if _inst != null and is_instance_valid(_inst) and _inst.state == "in":
		_inst._dirty_t = 6.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := ConfigFile.new()
	if c.load(STATE_PATH) == OK:
		_refresh = str(c.get_value("google", "refresh", ""))
		email = str(c.get_value("google", "email", ""))
		last_sync = int(c.get_value("google", "last_sync", 0))
		_synced_local = int(c.get_value("google", "synced_local", 0))
		_file_id = str(c.get_value("google", "file_id", ""))
	if not configured():
		state = "off"
	elif _refresh != "":
		state = "in"
		auto_sync.call_deferred()


func _save_state() -> void:
	var c := ConfigFile.new()
	c.set_value("google", "refresh", _refresh)
	c.set_value("google", "email", email)
	c.set_value("google", "last_sync", last_sync)
	c.set_value("google", "synced_local", _synced_local)
	c.set_value("google", "file_id", _file_id)
	c.save(STATE_PATH)


func _st(st: String, m := "") -> void:
	state = st
	msg = m
	changed.emit()


func _process(delta: float) -> void:
	if state == "code":
		if Time.get_unix_time_from_system() > _code_until:
			_st("out", "Код устарел — попробуйте войти ещё раз.")
			return
		_poll_t -= delta
		if _poll_t <= 0.0 and not _busy:
			_poll_t = _poll_every
			_poll_token()
	elif _dirty_t > 0.0:
		_dirty_t -= delta
		if _dirty_t <= 0.0 and state == "in" and not _busy:
			upload()


# ---------------- HTTP ----------------

func _req(url: String, method: int, headers: Array, body := PackedByteArray()) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = 25.0
	add_child(h)
	var hs := PackedStringArray(headers)
	var err := h.request_raw(url, hs, method, body)
	if err != OK:
		h.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}}
	var r: Array = await h.request_completed
	h.queue_free()
	var raw: PackedByteArray = r[3]
	var js = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 and raw.size() < 4000000 else null
	return {"ok": int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) >= 200 and int(r[1]) < 300,
		"code": int(r[1]), "body": raw, "json": js if js is Dictionary else {}}


func _form(d: Dictionary) -> PackedByteArray:
	var parts: Array = []
	for k in d:
		parts.append("%s=%s" % [k, str(d[k]).uri_encode()])
	return "&".join(parts).to_utf8_buffer()


const FORM := ["Content-Type: application/x-www-form-urlencoded"]


# ---------------- Вход ----------------

func sign_in() -> void:
	if not configured() or _busy:
		return
	_busy = true
	_st("busy", "Связь с Google…")
	var r: Dictionary = await _req(DEVICE_URL, HTTPClient.METHOD_POST, FORM, _form({"client_id": Conf.CLIENT_ID, "scope": SCOPE}))
	_busy = false
	if not r["ok"]:
		_st("out", "Не удалось связаться с Google (%d). Проверьте интернет." % r["code"])
		return
	var j: Dictionary = r["json"]
	_device_code = str(j.get("device_code", ""))
	user_code = str(j.get("user_code", ""))
	verify_url = str(j.get("verification_url", j.get("verification_uri", "https://www.google.com/device")))
	_poll_every = maxf(5.0, float(j.get("interval", 5)))
	_poll_t = _poll_every
	_code_until = Time.get_unix_time_from_system() + float(j.get("expires_in", 1800))
	_st("code", "")


func open_verify_page() -> void:
	if verify_url != "":
		OS.shell_open(verify_url)


func cancel_sign_in() -> void:
	_device_code = ""
	_st("out", "")


func _poll_token() -> void:
	if _device_code == "":
		return
	_busy = true
	var r: Dictionary = await _req(TOKEN_URL, HTTPClient.METHOD_POST, FORM, _form({"client_id": Conf.CLIENT_ID,
		"client_secret": Conf.CLIENT_SECRET, "device_code": _device_code,
		"grant_type": "urn:ietf:params:oauth:grant-type:device_code"}))
	_busy = false
	if state != "code":
		return
	var j: Dictionary = r["json"]
	if r["ok"]:
		_refresh = str(j.get("refresh_token", ""))
		_access = str(j.get("access_token", ""))
		_access_until = Time.get_unix_time_from_system() + float(j.get("expires_in", 3600)) - 60.0
		_device_code = ""
		_file_id = ""
		last_sync = 0
		_synced_local = 0
		_st("in", "Вход выполнен.")
		await _fetch_email()
		_save_state()
		auto_sync(true)
		return
	match str(j.get("error", "")):
		"authorization_pending":
			pass
		"slow_down":
			_poll_every += 5.0
		"access_denied":
			_st("out", "Вход отменён.")
		"expired_token":
			_st("out", "Код устарел — попробуйте войти ещё раз.")
		_:
			if r["code"] != 0:
				_st("out", "Google отклонил вход (%s)." % str(j.get("error", r["code"])))


func _fetch_email() -> void:
	var r: Dictionary = await _api(ABOUT_URL, HTTPClient.METHOD_GET)
	if r["ok"]:
		var u: Dictionary = r["json"].get("user", {})
		email = str(u.get("emailAddress", u.get("displayName", "")))
		changed.emit()


func sign_out() -> void:
	if _refresh != "":
		_req(REVOKE_URL, HTTPClient.METHOD_POST, FORM, _form({"token": _refresh}))
	_refresh = ""
	_access = ""
	email = ""
	_file_id = ""
	last_sync = 0
	_synced_local = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
	_st("out", "Вы вышли из аккаунта. Сохранения на этом устройстве остались.")


func _token() -> bool:
	if _access != "" and Time.get_unix_time_from_system() < _access_until:
		return true
	if _refresh == "":
		return false
	var r: Dictionary = await _req(TOKEN_URL, HTTPClient.METHOD_POST, FORM, _form({"client_id": Conf.CLIENT_ID,
		"client_secret": Conf.CLIENT_SECRET, "refresh_token": _refresh, "grant_type": "refresh_token"}))
	if not r["ok"]:
		if str(r["json"].get("error", "")) == "invalid_grant":
			# Доступ отозван в аккаунте Google — нужно войти снова
			_refresh = ""
			_save_state()
			_st("out", "Доступ к Google отозван — войдите снова.")
		return false
	_access = str(r["json"].get("access_token", ""))
	_access_until = Time.get_unix_time_from_system() + float(r["json"].get("expires_in", 3600)) - 60.0
	return _access != ""


func _api(url: String, method: int, extra := [], body := PackedByteArray()) -> Dictionary:
	if not await _token():
		return {"ok": false, "code": 401, "body": PackedByteArray(), "json": {}}
	return await _req(url, method, ["Authorization: Bearer " + _access] + extra, body)


# ---------------- Сохранения ----------------

func _save_files() -> Array:
	var out: Array = [Meta.SLOTS_PATH]
	for n in range(1, Meta.MAX_SLOTS + 1):
		out.append(Meta.slot_path(n))
	return out


## Отметка «когда менялись сохранения на этом устройстве».
func _local_stamp() -> int:
	var t := 0
	for p in _save_files():
		if FileAccess.file_exists(p):
			t = maxi(t, int(FileAccess.get_modified_time(p)))
	return t


func _summary_local() -> Dictionary:
	var best := {}
	for n in range(1, Meta.MAX_SLOTS + 1):
		var i: Dictionary = Meta.slot_info(n)
		if not i.is_empty() and int(i.get("runs", 0)) >= int(best.get("runs", -1)):
			best = i
	return {"runs": int(best.get("runs", 0)), "levels": int(best.get("levels", 0)), "saved": str(best.get("saved", ""))}


func _pack() -> PackedByteArray:
	if Meta.loaded:
		Meta.save()
	var files := {}
	for p in _save_files():
		if FileAccess.file_exists(p):
			files[p.get_file()] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(p))
	var d := {"v": 1, "time": int(Time.get_unix_time_from_system()), "device": OS.get_name(),
		"build": int(load("res://scripts/build.gd").BUILD), "summary": _summary_local(), "files": files}
	return JSON.stringify(d).to_utf8_buffer()


func _apply(d: Dictionary) -> void:
	var files: Dictionary = d.get("files", {})
	if files.is_empty():
		return
	var allowed: Array = _save_files().map(func(p): return String(p).get_file())
	for fname in files:
		if not String(fname) in allowed:
			continue   # только наши файлы сохранений — ничего лишнего из облака не пишем
		var f := FileAccess.open("user://" + String(fname), FileAccess.WRITE)
		if f != null:
			f.store_buffer(Marshalls.base64_to_raw(str(files[fname])))
			f.close()
	Meta.slot = 0
	Meta.reset()
	Meta.ensure_loaded()


func _find_file() -> String:
	if _file_id != "":
		return _file_id
	var q := ("name='%s'" % FILE_NAME).uri_encode()
	var r: Dictionary = await _api(FILES_URL + "?spaces=appDataFolder&fields=files(id,modifiedTime)&q=" + q, HTTPClient.METHOD_GET)
	if r["ok"]:
		var fs: Array = r["json"].get("files", [])
		if not fs.is_empty():
			_file_id = str(fs[0].get("id", ""))
	return _file_id


func _download() -> Dictionary:
	var id: String = await _find_file()
	if id == "":
		return {"none": true}
	var r: Dictionary = await _api(FILES_URL + "/" + id + "?alt=media", HTTPClient.METHOD_GET)
	if r["code"] == 404:
		_file_id = ""
		return {"none": true}
	if not r["ok"]:
		return {"error": r["code"]}
	var js = JSON.parse_string((r["body"] as PackedByteArray).get_string_from_utf8())
	return js if js is Dictionary else {"error": -1}


func upload() -> void:
	if state != "in" or _busy:
		return
	_busy = true
	_dirty_t = -1.0
	_st("busy", "Сохраняю в облако…")
	var body := _pack()
	var id: String = await _find_file()
	var r: Dictionary
	if id != "":
		r = await _api(UPLOAD_URL + "/" + id + "?uploadType=media", HTTPClient.METHOD_PATCH, ["Content-Type: application/json"], body)
	if id == "" or r["code"] == 404:
		_file_id = ""
		var bnd := "nhn" + str(randi())
		var meta := JSON.stringify({"name": FILE_NAME, "parents": ["appDataFolder"]})
		var mp := ("--%s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s\r\n--%s\r\nContent-Type: application/json\r\n\r\n" % [bnd, meta, bnd]).to_utf8_buffer()
		mp.append_array(body)
		mp.append_array(("\r\n--%s--" % bnd).to_utf8_buffer())
		r = await _api(UPLOAD_URL + "?uploadType=multipart&fields=id", HTTPClient.METHOD_POST,
			["Content-Type: multipart/related; boundary=" + bnd], mp)
		if r["ok"]:
			_file_id = str(r["json"].get("id", ""))
	_busy = false
	if r["ok"]:
		var js = JSON.parse_string(body.get_string_from_utf8())
		last_sync = int(js.get("time", 0)) if js is Dictionary else int(Time.get_unix_time_from_system())
		_synced_local = _local_stamp()
		_save_state()
		_st("in", "Сохранено в облаке.")
	else:
		_st("in" if _refresh != "" else "out", "Не удалось сохранить в облако (%d)." % r["code"])


## Сверка при запуске и после входа: забрать новое из облака, отправить своё или спросить игрока.
func auto_sync(after_login := false) -> void:
	if state != "in" or _busy:
		return
	_busy = true
	_st("busy", "Сверяю сохранения с облаком…")
	var d: Dictionary = await _download()
	_busy = false
	if d.has("error"):
		_st("in", "Облако недоступно — играем с локальными сохранениями.")
		return
	if d.get("none", false):
		_st("in", "")
		upload()
		return
	var cloud_t := int(d.get("time", 0))
	var local_changed := _local_stamp() > _synced_local
	var cloud_changed := cloud_t > last_sync
	var has_local: bool = int(_summary_local()["runs"]) > 0 or Meta.slot_exists(Meta.current_slot())
	if after_login and has_local and cloud_t > 0:
		# Первый вход на этом устройстве, а в облаке уже есть прогресс — спросить
		_ask(d)
	elif cloud_changed and local_changed:
		_ask(d)
	elif cloud_changed:
		_take(d)
	elif local_changed:
		_st("in", "")
		upload()
	else:
		_st("in", "Сохранения совпадают с облаком.")


func _take(d: Dictionary) -> void:
	_apply(d)
	last_sync = int(d.get("time", 0))
	_synced_local = _local_stamp()
	_save_state()
	_st("in", "Загружено из облака.")
	_reload_scene()


func _reload_scene() -> void:
	# Меню и убежище перечитывают прогресс; в бою прогресс применится после забега
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var sp := tree.current_scene.scene_file_path
	if sp.ends_with("menu.tscn") or sp.ends_with("hub.tscn"):
		tree.reload_current_scene.call_deferred()


func sync_now() -> void:
	if state == "in":
		auto_sync()


# ---------------- Выбор при расхождении ----------------

func _ask(d: Dictionary) -> void:
	var loc := _summary_local()
	loc["stamp"] = _local_stamp()
	conflict = {"cloud": d, "local": loc}
	_st("conflict", "")
	_show_popup()


func resolve(use_cloud: bool) -> void:
	if conflict.is_empty():
		return
	var d: Dictionary = conflict["cloud"]
	conflict = {}
	if _popup != null:
		_popup.queue_free()
		_popup = null
	state = "in"
	if use_cloud:
		_take(d)
	else:
		upload()


static func when_text(unix: int) -> String:
	if unix <= 0:
		return "—"
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d.%02d.%d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]


func _show_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = CanvasLayer.new()
	_popup.layer = 120
	add_child(_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(cc)
	var pnl := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.1, 0.97)
	sb.border_color = Color(0.3, 0.95, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0.3, 0.95, 1.0, 0.35)
	sb.shadow_size = 14
	sb.set_content_margin_all(26)
	pnl.add_theme_stylebox_override("panel", sb)
	cc.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pnl.add_child(v)
	var vw := 640.0
	if get_viewport() != null:
		vw = minf(640.0, get_viewport().get_visible_rect().size.x - 60.0)
	var t := Label.new()
	t.text = "ДВА РАЗНЫХ СОХРАНЕНИЯ"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	v.add_child(t)
	var cl: Dictionary = conflict["cloud"]
	var cs: Dictionary = cl.get("summary", {})
	var ls: Dictionary = conflict["local"]
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = vw
	info.add_theme_font_size_override("font_size", 20)
	info.text = ("В облаке и на этом устройстве разный прогресс. Какой оставить?\n\n"
		+ "☁ Облако: забегов %d, уровней %d — %s (%s)\n" % [int(cs.get("runs", 0)), int(cs.get("levels", 0)), when_text(int(cl.get("time", 0))), str(cl.get("device", "?"))]
		+ "▣ Это устройство: забегов %d, уровней %d — %s\n\n" % [int(ls.get("runs", 0)), int(ls.get("levels", 0)), when_text(int(ls.get("stamp", 0)))]
		+ "Другое сохранение будет заменено.")
	v.add_child(info)
	var row := BoxContainer.new()
	row.vertical = vw < 560.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var b1 := _pbtn("☁ ИЗ ОБЛАКА", Color(0.4, 0.95, 1.0))
	b1.pressed.connect(func(): resolve(true))
	row.add_child(b1)
	var b2 := _pbtn("▣ ЭТО УСТРОЙСТВО", Color(1.0, 0.4, 0.85))
	b2.pressed.connect(func(): resolve(false))
	row.add_child(b2)
	b1.grab_focus.call_deferred()


func _pbtn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 58)
	b.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "focus", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.04, 0.16, 0.95) if st == "normal" else Color(0.14, 0.07, 0.26, 0.95)
		s.border_color = accent.darkened(0.35) if st == "normal" else accent
		s.set_border_width_all(2 if st == "normal" else 3)
		s.set_corner_radius_all(8)
		s.set_content_margin_all(10)
		b.add_theme_stylebox_override(st, s)
	return b
