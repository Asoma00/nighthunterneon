extends Node
## Игра на одном экране: чьи кнопки сейчас управляют окнами и действиями.
## Узел вешается последним в корень дерева и первым получает ввод: нажатия с чужих
## устройств (другие геймпады, «чужая» половина клавиатуры) гасятся, чтобы кнопка A
## одного игрока не открывала диалог или не выбирала карточку за другого.
## Своё движение и умения каждый игрок по-прежнему читает напрямую со своего устройства.

const DevInput := preload("res://scripts/devinput.gd")
## Клавиши правой половины клавиатуры (Игрок со «стрелками + Enter»)
const RIGHT_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE,
	KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9,
	KEY_KP_PERIOD, KEY_KP_ADD, KEY_KP_SUBTRACT, KEY_DELETE, KEY_END, KEY_PAGEDOWN, KEY_PAGEUP, KEY_HOME, KEY_INSERT]

var devices: Array = []     # устройства игроков по порядку (Data.coop_devices)
var owner_idx := 0          # чей ввод сейчас принимается (-1 — всех)
var last_idx := 0           # кто нажимал последним (для окон, открытых «кем-то»)


## С какого устройства пришло событие: номер геймпада, KB_LEFT/KB_RIGHT; null — мышь/касание.
static func dev_of(ev: InputEvent) -> Variant:
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		return ev.device
	if ev is InputEventKey:
		return DevInput.KB_RIGHT if (ev as InputEventKey).physical_keycode in RIGHT_KEYS else DevInput.KB_LEFT
	return null


## Номер игрока по событию (или -1, если устройство ничьё / мышь).
func idx_of(ev: InputEvent) -> int:
	var d = dev_of(ev)
	if d == null:
		return -1
	for i in devices.size():
		var dv := int(devices[i])
		if dv == int(d):
			return i
		# Одна клавиатура на всех: «вся клавиатура» принадлежит единственному игроку с клавиатуры
		if d is int and int(d) < 0 and dv < 0 and not (DevInput.KB_LEFT in devices and DevInput.KB_RIGHT in devices):
			return i
	return -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(ev: InputEvent) -> void:
	if devices.size() < 2 or ev is InputEventAction:
		return
	var d = dev_of(ev)
	if d == null:
		return   # мышь и касания — общие
	var i := idx_of(ev)
	if ev.is_pressed() and i >= 0:
		last_idx = i
	if owner_idx >= 0 and i != owner_idx:
		# Отпускания пропускаем всегда, чтобы ни одна кнопка не «залипла»
		if ev.is_pressed() or ev is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()


## Повесить фильтр на корень (последним, чтобы он первым видел ввод) на время жизни owner.
static func attach(owner: Node, devs: Array) -> Node:
	var f = load("res://scripts/party_input.gd").new()
	f.name = "PartyInput"
	f.devices = devs.duplicate()
	var root := owner.get_tree().root
	root.add_child.call_deferred(f)
	owner.tree_exiting.connect(func():
		if is_instance_valid(f):
			f.queue_free())
	return f
