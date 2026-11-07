extends Node
## Сетевая игра по локальной сети (автозагрузка Net).
## Хост считает всю игру, клиент присылает ввод своего героя и показывает
## присланное состояние мира и эффекты. Поиск хоста — широковещательный UDP.

signal lobby_changed
signal hosts_changed
signal status(text: String)

const PORT := 7777
const DISCO_PORT := 7779
const VERSION := "neon-1"

var mode := ""            # "" | "host" | "client"
var lobby := {"hero1": "vega", "hero2": "rin", "level": 0, "ready1": false, "ready2": false, "client": false}
var hosts := {}           # ip -> {"name": String, "t": float}
var main: Node            # текущий забег (если идёт)
var in_game := false
var replaying := false    # клиент проигрывает эффекты хоста
var _fx: Array = []       # эффекты хоста, накопленные до отправки
var _bc: PacketPeerUDP
var _listen: PacketPeerUDP
var _bc_t := 0.0
var _ab_count := 0        # клиент: сколько раз нажата способность
var _ab_seen := 0         # хост: сколько нажатий клиента уже применено
var last_snap: Dictionary = {}
# Убежище хоста
var host_hub := {}        # клиент: здания/жители хоста
var buddy := {}           # позиция и герой второго игрока в убежище
var peer_profile := {}    # хост: прокачка второго игрока из его сохранения
var peer_hero := "rin"    # хост: герой второго игрока
var peer_nick := ""
# Распределённая симуляция: клиент сам считает своего героя, его оружие и эффекты,
# а хосту отправляет только итог — попадания, своё состояние и эффекты для показа.
var local := false        # клиент: сейчас идёт своя (локальная) симуляция
var _c_hits: Array = []   # клиент: попадания по врагам для хоста
var _c_fx: Array = []     # клиент: свои эффекты для показа у хоста
var _cstate := {}         # хост: последнее состояние клиента
var _cstate_new := false
var _cfx_pending: Array = []
const CFX_SKIP := ["shake", "flash", "glitch", "hurt", "snd", "number"]       # ник второго игрока (у хоста — клиента, у клиента — хоста)
var my_hero := ""         # клиент: свой герой (Data.selected_character меняется на время забега)
var _hub_t := 0.0
var _snap_new := false
var _pending_fx: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func():
		status.emit("Подключено. Ждём хоста...")
		rpc_id(1, "c_hello", VERSION, lobby["hero2"]))
	multiplayer.connection_failed.connect(func():
		status.emit("Не удалось подключиться")
		leave())
	multiplayer.server_disconnected.connect(func():
		_drop("Хост отключился"))


func is_host() -> bool:
	return mode == "host"


func is_client() -> bool:
	return mode == "client"


func host() -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		return "Не удалось открыть порт %d (ошибка %d)" % [PORT, err]
	multiplayer.multiplayer_peer = peer
	mode = "host"
	lobby = {"hero1": lobby["hero1"], "hero2": lobby["hero2"], "level": lobby["level"],
		"ready1": false, "ready2": false, "client": false}
	_bc = PacketPeerUDP.new()
	_bc.set_broadcast_enabled(true)
	_bc.set_dest_address("255.255.255.255", DISCO_PORT)
	lobby_changed.emit()
	return ""


func join(ip: String) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return "Ошибка подключения (%d)" % err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	status.emit("Подключение к %s..." % ip)
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
	in_game = false
	_bc = null
	lobby["ready1"] = false
	lobby["ready2"] = false
	lobby["client"] = false
	lobby_changed.emit()


## Поиск хостов в локальной сети (включается на экране подключения).
func listen(on: bool) -> void:
	if on and _listen == null:
		_listen = PacketPeerUDP.new()
		if _listen.bind(DISCO_PORT) != OK:
			_listen = null
	elif not on and _listen != null:
		_listen.close()
		_listen = null


func _process(delta: float) -> void:
	if _bc != null and not in_game:
		_bc_t -= delta
		if _bc_t <= 0.0:
			_bc_t = 1.0
			var pc := OS.get_environment("COMPUTERNAME")
			if pc == "":
				pc = OS.get_environment("HOSTNAME")
			_bc.put_packet(("NEON|%s|%s|%d" % [VERSION, pc if pc != "" else "Хост", 1 if lobby["client"] else 0]).to_utf8_buffer())
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pk := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := pk.split("|")
			if parts.size() >= 4 and parts[0] == "NEON" and parts[1] == VERSION:
				if not hosts.has(ip):
					changed = true
				hosts[ip] = {"name": parts[2], "busy": parts[3] == "1", "t": Time.get_ticks_msec()}
		for ip in hosts.keys():
			if Time.get_ticks_msec() - int(hosts[ip]["t"]) > 3500:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


func _drop(reason: String) -> void:
	var was_game := in_game
	leave()
	status.emit(reason)
	if was_game and main != null and is_instance_valid(main):
		main.net_lost(reason)


func _on_peer_connected(id: int) -> void:
	if mode == "host":
		status.emit("Игрок подключился")


func _on_peer_disconnected(id: int) -> void:
	if mode == "host":
		buddy = {}
		peer_profile = {}
		lobby["client"] = false
		lobby["ready2"] = false
		lobby_changed.emit()
		if in_game and main != null and is_instance_valid(main):
			main.net_lost("Игрок 2 отключился")
		status.emit("Игрок 2 отключился")


# ================= Лобби =================

@rpc("any_peer", "reliable")
func c_hello(ver: String, hero2: String) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	lobby["client"] = true
	lobby["hero2"] = hero2
	peer_hero = hero2
	lobby["ready2"] = false
	_push_lobby()
	rpc_id(id, "h_welcome", hub_state())
	status.emit("Игрок 2 вошёл в убежище")


## Клиент меняет своего героя / готовность.
@rpc("any_peer", "reliable")
func c_lobby(hero2: String, ready2: bool) -> void:
	if mode != "host":
		return
	lobby["hero2"] = hero2
	lobby["ready2"] = ready2
	_push_lobby()


@rpc("authority", "reliable")
func h_lobby(state: Dictionary) -> void:
	lobby = state
	lobby_changed.emit()


func set_local(hero: String, ready: bool, level := -1) -> void:
	if mode == "host":
		lobby["hero1"] = hero
		lobby["ready1"] = ready
		if level >= 0:
			lobby["level"] = level
		_push_lobby()
	elif mode == "client":
		lobby["hero2"] = hero
		lobby["ready2"] = ready
		rpc_id(1, "c_lobby", hero, ready)
		lobby_changed.emit()


func _push_lobby() -> void:
	lobby_changed.emit()
	if mode == "host" and lobby["client"]:
		rpc("h_lobby", lobby)


func can_start() -> bool:
	return mode == "host" and lobby["client"] and lobby["ready1"] and lobby["ready2"]


func start() -> void:
	if not can_start():
		return
	rpc("h_start", lobby, randi() % 2000000000 + 1)


@rpc("authority", "call_local", "reliable")
func h_start(state: Dictionary, wseed: int) -> void:
	lobby = state
	lobby["ready1"] = false
	lobby["ready2"] = false
	lobby["client"] = true
	var Data := preload("res://scripts/data.gd")
	if mode == "client":
		my_hero = Data.selected_character
		if state.has("nick1"):
			peer_nick = state["nick1"]
	Data.coop = true
	Data.selected_character = state["hero1"]
	Data.selected_character2 = state["hero2"]
	Data.selected_level = int(state["level"])
	Data.world_seed = wseed
	in_game = true
	_ab_count = 0
	_ab_seen = 0
	_fx.clear()
	last_snap = {}
	get_tree().paused = false
	Loader.go("res://main.tscn")


## Конец забега: оба возвращаются в убежище хоста.
func back_to_lobby() -> void:
	in_game = false
	main = null
	var Data := preload("res://scripts/data.gd")
	Data.coop = false
	if mode == "client" and my_hero != "":
		Data.selected_character = my_hero
	get_tree().paused = false
	if mode == "":
		Data.menu_page = "net"
		Loader.go("res://menu.tscn")
	else:
		Loader.go("res://hub.tscn")


# ================= Убежище хоста =================

func hub_state() -> Dictionary:
	var Meta := preload("res://scripts/meta.gd")
	var Data := preload("res://scripts/data.gd")
	return {"buildings": Meta.buildings.duplicate(), "followers": Meta.followers.duplicate(true),
		"levels_cleared": Meta.levels_cleared, "hero": Data.selected_character}


@rpc("authority", "reliable")
func h_welcome(state: Dictionary) -> void:
	host_hub = state
	status.emit("Вы в убежище хоста")
	var Data := preload("res://scripts/data.gd")
	Data.coop = false
	Loader.go("res://hub.tscn")


## Хост обновил убежище (построил здание, нанял жителя).
func push_hub() -> void:
	if mode == "host" and lobby["client"]:
		rpc("h_hub", hub_state())


@rpc("authority", "reliable")
func h_hub(state: Dictionary) -> void:
	host_hub = state


## Позиция своего аватара в убежище (оба направления).
func send_hub_pos(pos: Vector3, left: bool, moving: bool, hero: String) -> void:
	if mode == "" or in_game:
		return
	if mode == "host" and not lobby["client"]:
		return
	rpc("hub_pos", pos, left, moving, hero, preload("res://scripts/meta.gd").nickname)


@rpc("any_peer", "unreliable_ordered")
func hub_pos(pos: Vector3, left: bool, moving: bool, hero: String, nick := "") -> void:
	buddy = {"pos": pos, "left": left, "moving": moving, "hero": hero, "t": Time.get_ticks_msec(), "nick": nick}
	if nick != "":
		peer_nick = nick
	if mode == "host":
		peer_hero = hero


## Клиент: отправить хосту свою прокачку для выбранного героя.
func send_profile() -> void:
	if mode != "client":
		return
	var Data := preload("res://scripts/data.gd")
	var Meta := preload("res://scripts/meta.gd")
	rpc_id(1, "c_profile", Data.selected_character, Meta.profile(Data.selected_character))


@rpc("any_peer", "reliable")
func c_profile(hero: String, prof: Dictionary) -> void:
	if mode == "host":
		peer_hero = hero
		peer_profile = prof
		if prof.get("nick", "") != "":
			peer_nick = prof["nick"]


## Хост в портале начинает вылазку для обоих.
func start_run(level: int) -> void:
	var Data := preload("res://scripts/data.gd")
	if mode != "host" or not lobby["client"]:
		return
	var state := {"hero1": Data.selected_character, "hero2": peer_hero, "level": level, "nick1": preload("res://scripts/meta.gd").nickname}
	rpc("h_start", state, randi() % 2000000000 + 1)


# ================= Забег =================

## Хост: записать эффект для отправки клиенту.
func fx(kind: String, args: Array) -> void:
	if mode == "host" and in_game and _fx.size() < 400:
		_fx.append([kind, args])


func take_fx() -> Array:
	var f := _fx
	_fx = []
	return f


func send_snapshot(snap: Dictionary) -> void:
	if mode == "host" and lobby["client"]:
		rpc("h_snap", snap)


@rpc("authority", "unreliable_ordered")
func h_snap(snap: Dictionary) -> void:
	# Применяем только последний снимок за кадр, эффекты копим из всех
	last_snap = snap
	_snap_new = true
	_pending_fx.append_array(snap.get("fx", []))
	if _pending_fx.size() > 600:
		_pending_fx = _pending_fx.slice(_pending_fx.size() - 600)


## Клиент: забрать свежий снимок (или пустой словарь) и накопленные эффекты.
func take_snapshot() -> Dictionary:
	if not _snap_new:
		return {}
	_snap_new = false
	var s := last_snap
	s["fx"] = _pending_fx
	_pending_fx = []
	return s


## Клиент: попадание своим оружием по врагу (урон уже посчитан у клиента).
func client_hit(id: int, amount: float, st: String, crit: bool, src: String) -> void:
	if mode == "client" and in_game and _c_hits.size() < 2000:
		_c_hits.append([id, amount, st, crit, src])


## Клиент: свой эффект, который нужно показать и у хоста.
func cfx(kind: String, args: Array) -> void:
	if mode == "client" and in_game and _c_fx.size() < 300 and not (kind in CFX_SKIP):
		_c_fx.append([kind, args])


func send_client_state(state: Dictionary) -> void:
	if mode != "client" or not in_game:
		return
	state["fx"] = _c_fx
	_c_fx = []
	rpc_id(1, "c_state", state)
	if not _c_hits.is_empty():
		rpc_id(1, "c_hits", _c_hits)
		_c_hits = []


@rpc("any_peer", "unreliable_ordered")
func c_state(s: Dictionary) -> void:
	if mode != "host":
		return
	_cstate = s
	_cstate_new = true
	_cfx_pending.append_array(s.get("fx", []))
	if _cfx_pending.size() > 400:
		_cfx_pending = _cfx_pending.slice(_cfx_pending.size() - 400)


@rpc("any_peer", "reliable")
func c_hits(h: Array) -> void:
	if mode == "host" and main != null and is_instance_valid(main):
		main.net_client_hits(h)


## Хост: забрать свежее состояние клиента (или пустой словарь).
func take_cstate() -> Dictionary:
	if not _cstate_new:
		return {}
	_cstate_new = false
	var s := _cstate
	s["fx"] = _cfx_pending
	_cfx_pending = []
	return s


## Клиент: ввод своего героя.
func send_input(v: Vector2, ability_pressed: bool) -> void:
	if mode != "client" or not in_game:
		return
	if ability_pressed:
		_ab_count += 1
	rpc_id(1, "c_input", v, _ab_count)


@rpc("any_peer", "unreliable_ordered")
func c_input(v: Vector2, ab: int) -> void:
	if mode != "host" or main == null or not is_instance_valid(main):
		return
	var p2 = main.players[1] if main.players.size() > 1 else null
	if p2 == null:
		return
	p2.net_vec = v
	if ab > _ab_seen:
		_ab_seen = ab
		p2.net_ability = true


## Надёжные события хоста: выбор улучшений, сундук, конец игры, музыка.
func event(kind: String, data: Variant = null) -> void:
	if mode == "host" and in_game and lobby["client"]:
		rpc("h_event", kind, data)


@rpc("authority", "reliable")
func h_event(kind: String, data: Variant) -> void:
	if main != null and is_instance_valid(main):
		main.net_event(kind, data)


## Клиент выбрал карточку улучшения.
func choose(index: int) -> void:
	if mode == "client":
		rpc_id(1, "c_choose", index)


@rpc("any_peer", "reliable")
func c_choose(index: int) -> void:
	if mode == "host" and main != null and is_instance_valid(main):
		main.net_remote_choice(index)


## Клиент закрыл окно своего сундука.
func chest_closed() -> void:
	if mode == "client":
		rpc_id(1, "c_chest_closed")


@rpc("any_peer", "reliable")
func c_chest_closed() -> void:
	pass
