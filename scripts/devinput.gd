extends RefCounted
## Ввод одного игрока с конкретного устройства (для кооператива и лобби).
## dev >= 0 — номер геймпада; KB_LEFT — клавиатура WASD + Пробел;
## KB_RIGHT — стрелки + Enter/Num0/Ctrl; ANY — любое устройство (одиночная/сетевая игра).

const KB_LEFT := -2
const KB_RIGHT := -3
const ANY := -1
const DEAD := 0.35

var dev := ANY
var _prev := {}
var _now := {}


func _init(device := ANY) -> void:
	dev = device


static func device_name(d: int) -> String:
	match d:
		KB_LEFT:
			return "Клавиатура: WASD + Пробел"
		KB_RIGHT:
			return "Клавиатура: стрелки + Enter"
		ANY:
			return "Любое устройство"
	var n := Input.get_joy_name(d)
	return "Геймпад %d%s" % [d + 1, (": " + n) if n != "" else ""]


static func ability_hint(d: int) -> String:
	match d:
		KB_LEFT:
			return "ПРОБЕЛ"
		KB_RIGHT:
			return "ENTER"
		ANY:
			return Settings.key("ability")
	return "A / RB"


func _key(k: int) -> bool:
	return Input.is_physical_key_pressed(k)


func _btn(b: int) -> bool:
	if dev >= 0:
		return Input.is_joy_button_pressed(dev, b)
	if dev == ANY:
		for j in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(j, b):
				return true
	return false


func _axis(a: int) -> float:
	if dev >= 0:
		return Input.get_joy_axis(dev, a)
	if dev == ANY:
		var best := 0.0
		for j in Input.get_connected_joypads():
			var v := Input.get_joy_axis(j, a)
			if absf(v) > absf(best):
				best = v
		return best
	return 0.0


## Направление движения (-1..1 по осям).
func vector() -> Vector2:
	var v := Vector2.ZERO
	if dev == KB_LEFT or dev == ANY:
		v += Vector2(float(_key(KEY_D)) - float(_key(KEY_A)), float(_key(KEY_S)) - float(_key(KEY_W)))
	if dev == KB_RIGHT or dev == ANY:
		v += Vector2(float(_key(KEY_RIGHT)) - float(_key(KEY_LEFT)), float(_key(KEY_DOWN)) - float(_key(KEY_UP)))
	if dev >= 0 or dev == ANY:
		var stick := Vector2(_axis(JOY_AXIS_LEFT_X), _axis(JOY_AXIS_LEFT_Y))
		if stick.length() > DEAD:
			v += stick
		v += Vector2(float(_btn(JOY_BUTTON_DPAD_RIGHT)) - float(_btn(JOY_BUTTON_DPAD_LEFT)),
			float(_btn(JOY_BUTTON_DPAD_DOWN)) - float(_btn(JOY_BUTTON_DPAD_UP)))
	return v.limit_length(1.0)


func _state(what: String) -> bool:
	match what:
		"ability", "ok":
			if dev == KB_LEFT or dev == ANY:
				if _key(KEY_SPACE) or (what == "ability" and _key(KEY_SHIFT)):
					return true
			if dev == KB_RIGHT or dev == ANY:
				if _key(KEY_ENTER) or _key(KEY_KP_0) or _key(KEY_KP_ENTER) or (what == "ability" and _key(KEY_CTRL)):
					return true
			return _btn(JOY_BUTTON_A) or (what == "ability" and (_btn(JOY_BUTTON_X) or _btn(JOY_BUTTON_RIGHT_SHOULDER)))
		"back":
			if dev == KB_LEFT or dev == ANY:
				if _key(KEY_ESCAPE):
					return true
			if dev == KB_RIGHT and _key(KEY_BACKSPACE):
				return true
			return _btn(JOY_BUTTON_B)
		"left":
			return vector().x < -0.5
		"right":
			return vector().x > 0.5
		"up":
			return vector().y < -0.5
		"down":
			return vector().y > 0.5
	return false


## Вызывать раз в кадр перед just().
func poll() -> void:
	_prev = _now
	_now = {}
	for w in ["ability", "ok", "back", "left", "right", "up", "down"]:
		_now[w] = _state(w)


func held(what: String) -> bool:
	return _now.get(what, false)


func just(what: String) -> bool:
	return _now.get(what, false) and not _prev.get(what, false)


## Какое устройство сейчас нажало «подтвердить» (для присоединения в лобби). Иначе null.
static func detect_join() -> Variant:
	if Input.is_physical_key_pressed(KEY_SPACE):
		return KB_LEFT
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_0):
		return KB_RIGHT
	for j in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(j, JOY_BUTTON_A) or Input.is_joy_button_pressed(j, JOY_BUTTON_START):
			return j
	return null
