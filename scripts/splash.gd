extends Control
## Заставка при запуске в стиле 80-х: закатное солнце, неоновая сетка и три логотипа
## (хром + неон + полосатый треугольник): Godot, Claude, CPA4KA — под синтвейв.
## Любая клавиша, клик или касание — пропустить. Музыка — общий движок игры (audio.gd).

const RetroLogo := preload("res://scripts/retro_logo.gd")
const MENU := "res://menu.tscn"
const BPM := 96.0
const STAGES := [3.8, 3.8, 4.8]

static var shown := false
static var to_menu := false     # меню после заставки — зажигается неоном
var _t := 0.0
var _all_t := 0.0
var _stage := -1
var _done := false
var _logo: Control
var _icon: TextureRect
var _flash := 0.0
var _stars: Array = []


func _ready() -> void:
	# Старые установки: выбросить из кэша скрипты, загруженные до подключения обновления
	preload("res://scripts/boot.gd").refresh()
	shown = true
	# Тёмный фон и между сценами — никакого серого кадра при переходе в меню
	RenderingServer.set_default_clear_color(Color(0, 0, 0))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 70:
		_stars.append(Vector3(randf(), randf() * 0.55, randf()))
	# Музыка — общим музыкальным движком игры: та же песня плавно продолжится в меню
	# и в убежище, а в бою перетечёт в боевую (мешап), не выключаясь.
	Sound.set_track("menu", true, Sound.SPLASH_SONG)
	_next()


func _input(e: InputEvent) -> void:
	if _done or _all_t < 0.3:
		return
	if (e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed():
		_finish()


func _process(delta: float) -> void:
	_t += delta
	_all_t += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	if is_instance_valid(_logo):
		var dur: float = STAGES[_stage]
		_logo.modulate.a = clampf(_t / 0.2, 0.0, 1.0)
		# Лёгкое «дыхание» логотипа в такт
		var beat := fmod(_all_t * BPM / 60.0, 1.0)
		_logo.scale = Vector2.ONE * (1.0 + 0.012 * exp(-beat * 6.0))
		if is_instance_valid(_icon):
			_icon.modulate.a = _logo.modulate.a * clampf((dur - _t) / 0.4, 0.0, 1.0)
			var k := ease(clampf(_t / 0.7, 0.0, 1.0), 0.35)
			_icon.scale = Vector2(k, k)
			_icon.rotation = (1.0 - k) * -0.6
		if _stage == 2 and _t > 1.0 and _t - delta <= 1.0:
			_flash = 0.6
		if _t >= dur - 0.45 and _logo.leaving < 0.0:
			_logo.leave()
		if _t >= dur and not _done:
			_next()
	queue_redraw()


func _next() -> void:
	_stage += 1
	_t = 0.0
	if is_instance_valid(_logo):
		_logo.queue_free()
	if is_instance_valid(_icon):
		_icon.queue_free()
	if _stage >= STAGES.size():
		_finish()
		return
	_logo = RetroLogo.new()
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_logo)
	_logo.pivot_offset = get_viewport_rect().size / 2.0
	var big := clampf(get_viewport_rect().size.x / 9.0, 70.0, 140.0)
	match _stage:
		0:
			_logo.setup("GODOT", "engine", int(big), true)
		1:
			_logo.setup("CLAUDE", "", int(big * 1.05), true)
		2:
			_logo.setup("CPA4KA", "", int(big * 1.2), true)
	_logo.play()


func _finish() -> void:
	if _done:
		return
	_done = true
	to_menu = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.4)
	tw.tween_callback(func(): get_tree().change_scene_to_file(MENU))


# ---------------- Синтвейв-фон ----------------

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0))
	# Едва заметные звёзды и вспышка при появлении CPA4KA
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_all_t * 2.0 + st.z * 20.0)
		draw_rect(Rect2(Vector2(st.x * vs.x, st.y * vs.y / 0.55), Vector2(2, 2)), Color(0.8, 0.8, 1.0, 0.12 * tw * st.z))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.9, 1, _flash * 0.5))
