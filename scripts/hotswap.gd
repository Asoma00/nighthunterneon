extends RefCounted
## Обновление автозагрузок «на лету».
## Беда старых сборок: скрипт автообновления ссылался на Settings/Loader/Net, и при его
## компиляции эти скрипты загружались из УСТАНОВЛЕННОЙ версии — раньше, чем подключался
## скачанный пакет. Вся игра шла новой, а автозагрузки — старыми (не было переходов,
## клавиши «Поговорить», вкладка «Управление» роняла игру).
## Здесь первая сцена подменяет скрипты автозагрузок свежими из пакета.

const LIST := [["Settings", "res://scripts/settings.gd"], ["Loader", "res://scripts/loader.gd"],
	["Touch", "res://scripts/touch_controls.gd"], ["Net", "res://scripts/net.gd"]]

## Версии скриптов автозагрузок в этой сборке (их const REV). Меняя такой скрипт,
## поднимите REV в нём и здесь. Свежий скрипт грузится, только если работает старее —
## повторная загрузка «на месте» ломает живой экземпляр.
const REVS := {"Settings": 15026, "Loader": 15025, "Touch": 15023, "Net": 15025}

static var done := false
static var report := ""


static func _rev(s: Script) -> int:
	if s == null:
		return 0
	return int(s.get_script_constant_map().get("REV", 0))


static func run() -> void:
	if done:
		return
	done = true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for pair in LIST:
		var n: Node = tree.root.get_node_or_null(pair[0])
		if n == null:
			continue
		var cur_rev := _rev(n.get_script())
		if cur_rev >= int(REVS.get(pair[0], 0)):
			continue
		var fresh: Script = ResourceLoader.load(pair[1], "", ResourceLoader.CACHE_MODE_IGNORE)
		if _rev(fresh) <= cur_rev:
			continue
		if fresh == null:
			continue
		# Скрипт мог обновиться прямо на месте — экземпляр при этом остаётся со старым
		# набором переменных. Снимаем скрипт и ставим заново: экземпляр создаётся свежим.
		n.set_script(null)
		n.set_script(fresh)
		report += "%s; " % pair[0]
		if n.has_method("_hotswapped"):
			n.call("_hotswapped")
	if report != "":
		print("[Обновление автозагрузок] ", report)
