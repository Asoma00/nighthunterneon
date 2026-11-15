extends Node
const REV := 15025   # версия скрипта автозагрузки (см. hotswap.gd)
## Сетевая игра по локальной сети (автозагрузка Net).
## Хост считает всю игру, клиент присылает ввод своего героя и показывает
## присланное состояние мира и эффекты. Поиск хоста — широковещательный UDP.

signal lobby_changed
signal hosts_changed
signal status(text: String)

const PORT := 7777
const DISCO_PORT := 7779
const VERSION := "neon-3"
const MAX_PLAYERS := 5      # хост + до 4 подключившихся

var mode := ""            # "" | "host" | "client"
# «client» — подключился хотя бы один игрок (для совместимости со старым кодом)
var lobby := {"hero1": "vega", "hero2": "rin", "level": 0, "client": false}
var hosts := {}           # ip -> {"name": String, "t": float}
var main: Node            # текущий забег (если идёт)
var in_game := false
var replaying := false    # клиент проигрывает эффекты хоста
var _fx: Array = []       # эффекты хоста, накопленные до отправки
var _bc: PacketPeerUDP
var _listen: PacketPeerUDP
var _bc_t := 0.0
var _ab_count := 0        # клиент: сколько раз нажата способность
var _ab_seen := {}        # хост: индекс игрока -> сколько нажатий уже применено
var last_snap: Dictionary = {}
# Убежище хоста
var host_hub := {}        # клиент: здания/жители хоста
var buddies := {}         # id пира -> позиция и герой его аватара в убежище
var buddy := {}           # (совместимость) последний присланный аватар
var peers := {}           # хост: id пира -> {"hero", "sprite", "nick", "profile"}
var order: Array = []     # порядок игроков в забеге: id пиров, первым — хост (1)
var my_idx := 0           # свой номер в забеге (хост — 0)
var run_players: Array = []   # [{"id", "hero", "sprite", "nick"}] — состав забега
var peer_profile := {}    # (совместимость)
var peer_hero := "rin"
var peer_sprite := ""
var peer_nick := ""
# Распределённая симуляция: клиент сам считает своего героя, его оружие и эффекты,
# а хосту отправляет только итог — попадания, своё состояние и эффекты для показа.
var local := false        # клиент: сейчас идёт своя (локальная) симуляция
var _c_hits: Array = []   # клиент: попадания по врагам для хоста
var _c_fx: Array = []     # клиент: свои эффекты для показа у хоста
var _cstate := {}         # хост: индекс игрока -> последнее состояние
var _cfx_pending := {}    # хост: индекс игрока -> накопленные эффекты
const CFX_SKIP := ["shake", "flash", "glitch", "hurt", "snd", "number"]
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


## Сколько человек в игре вместе с хостом.
func player_count() -> int:
	if mode == "host":
		return 1 + peers.size()
	if mode == "client":
		return maxi(2, int(lobby.get("count", 2)))
	return 1


func host() -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return "Не удалось открыть порт %d (ошибка %d)" % [PORT, err]
	multiplayer.multiplayer_peer = peer
	mode = "host"
	peers = {}
	buddies = {}
	lobby = {"hero1": lobby["hero1"], "hero2": lobby["hero2"], "level": lobby["level"], "client": false, "count": 1}
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
	peers = {}
	buddies = {}
	buddy = {}
	order = []
	my_idx = 0
	lobby["client"] = false
	lobby["count"] = 1
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
			var full := player_count() >= MAX_PLAYERS
			_bc.put_packet(("NEON|%s|%s|%d|%d" % [VERSION, pc if pc != "" else "Хост", 1 if full else 0, player_count()]).to_utf8_buffer())
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pk := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := pk.split("|")
			if parts.size() >= 4 and parts[0] == "NEON" and parts[1] == VERSION:
				if not hosts.has(ip):
					changed = true
				var cnt := int(parts[4]) if parts.size() > 4 else 1
				if hosts.has(ip) and int(hosts[ip].get("count", 1)) != cnt:
					changed = true
				hosts[ip] = {"name": parts[2], "busy": parts[3] == "1", "count": cnt, "t": Time.get_ticks_msec()}
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
		buddies.erase(id)
		var had := peers.has(id)
		peers.erase(id)
		_sync_counts()
		if had:
			rpc("h_gone", id)
		lobby_changed.emit()
		var idx := order.find(id)
		if in_game and idx > 0 and main != null and is_instance_valid(main):
			if peers.is_empty():
				main.net_lost("Все игроки отключились")
			else:
				main.net_peer_left(idx)
				event("gone", idx)
		status.emit("Игрок отключился")


func _sync_counts() -> void:
	lobby["client"] = not peers.is_empty()
	lobby["count"] = 1 + peers.size()
	# Совместимость со старыми полями (один напарник)
	if not peers.is_empty():
		var first: Dictionary = peers[peers.keys()[0]]
		peer_hero = str(first.get("hero", "rin"))
		peer_sprite = str(first.get("sprite", ""))
		peer_nick = str(first.get("nick", ""))
		peer_profile = first.get("profile", {})
	if mode == "host" and lobby["client"]:
		rpc("h_lobby", lobby)


@rpc("authority", "reliable")
func h_gone(id: int) -> void:
	buddies.erase(id)


# ================= Лобби =================

@rpc("any_peer", "reliable")
func c_hello(ver: String, hero2: String) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION or peers.size() >= MAX_PLAYERS - 1 or in_game:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peers[id] = {"hero": hero2, "sprite": "", "nick": "", "profile": {}}
	_sync_counts()
	lobby_changed.emit()
	rpc_id(id, "h_welcome", hub_state())
	status.emit("Игрок %d вошёл в убежище" % (1 + peers.size()))


@rpc("authority", "reliable")
func h_lobby(state: Dictionary) -> void:
	lobby = state
	lobby_changed.emit()


func set_local(hero: String, _ready: bool, level := -1) -> void:
	if mode == "host":
		lobby["hero1"] = hero
		if level >= 0:
			lobby["level"] = level
	elif mode == "client":
		lobby["hero2"] = hero
	lobby_changed.emit()


## Бой можно начинать, когда в убежище хоста есть хотя бы ещё один игрок.
func can_start() -> bool:
	return mode == "host" and not peers.is_empty() and not in_game


func start() -> void:
	start_run(int(lobby.get("level", 0)))


## Номер игрока в забеге по id пира (или -1).
func idx_of(id: int) -> int:
	return order.find(id)


@rpc("authority", "call_local", "reliable")
func h_start(state: Dictionary, wseed: int) -> void:
	lobby = state
	run_players = state.get("players", [])
	order = []
	for rp in run_players:
		order.append(int(rp["id"]))
	my_idx = maxi(0, order.find(multiplayer.get_unique_id())) if mode == "client" else 0
	var Data := load("res://scripts/data.gd")
	if mode == "client":
		my_hero = Data.selected_character
		if not run_players.is_empty():
			peer_nick = str(run_players[0].get("nick", ""))
	var heroes: Array = []
	for rp in run_players:
		heroes.append(str(rp["hero"]))
	Data.coop = true
	Data.selected_character = heroes[0]
	Data.selected_character2 = heroes[1] if heroes.size() > 1 else heroes[0]
	Data.coop_heroes = heroes
	Data.selected_level = int(state["level"])
	Data.world_seed = wseed
	in_game = true
	_ab_count = 0
	_ab_seen = {}
	_cstate = {}
	_cfx_pending = {}
	_fx.clear()
	last_snap = {}
	get_tree().paused = false
	_go("res://main.tscn")


## Переход сцены, даже если идёт загрузка (вылазку начали, пока кто-то ещё грузил убежище).
func _go(path: String) -> void:
	var guard := 0
	while Loader.busy and guard < 3600:
		guard += 1
		await get_tree().process_frame
	if path == "res://main.tscn" and not in_game:
		return
	Loader.go(path)


## Сведения об игроке забега: облик, ник, прокачка (у хоста — присланная игроком).
func run_info(idx: int) -> Dictionary:
	if idx < 0 or idx >= run_players.size():
		return {}
	return run_players[idx]


func profile_of(idx: int) -> Dictionary:
	if mode != "host" or idx <= 0 or idx >= order.size():
		return {}
	return peers.get(order[idx], {}).get("profile", {})


## Конец забега: все возвращаются в убежище хоста.
func back_to_lobby() -> void:
	in_game = false
	main = null
	var Data := load("res://scripts/data.gd")
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
	var Meta := load("res://scripts/meta.gd")
	var Data := load("res://scripts/data.gd")
	return {"buildings": Meta.buildings.duplicate(), "followers": Meta.followers.duplicate(true),
		"levels_cleared": Meta.levels_cleared, "hero": Data.selected_character}


@rpc("authority", "reliable")
func h_welcome(state: Dictionary) -> void:
	host_hub = state
	lobby["client"] = true
	status.emit("Вы в убежище хоста")
	var Data := load("res://scripts/data.gd")
	Data.coop = false
	_go("res://hub.tscn")


## Хост обновил убежище (построил здание, нанял жителя).
func push_hub() -> void:
	if mode == "host" and lobby["client"]:
		rpc("h_hub", hub_state())


@rpc("authority", "reliable")
func h_hub(state: Dictionary) -> void:
	host_hub = state


## Позиция своего аватара в убежище — всем остальным (через хост).
func send_hub_pos(pos: Vector3, left: bool, moving: bool, hero: String) -> void:
	if mode == "" or in_game:
		return
	if mode == "host" and not lobby["client"]:
		return
	var M = load("res://scripts/meta.gd")
	rpc("hub_pos", pos, left, moving, hero, M.nickname, M.hero_sprite(hero))


@rpc("any_peer", "unreliable_ordered")
func hub_pos(pos: Vector3, left: bool, moving: bool, hero: String, nick := "", sprite := "") -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == multiplayer.get_unique_id():
		return
	var b := {"pos": pos, "left": left, "moving": moving, "hero": hero, "t": Time.get_ticks_msec(), "nick": nick, "sprite": sprite, "host": id == 1}
	buddies[id] = b
	buddy = b
	if mode == "host" and peers.has(id):
		peers[id]["hero"] = hero
		if sprite != "":
			peers[id]["sprite"] = sprite
		if nick != "":
			peers[id]["nick"] = nick


## Клиент: отправить хосту свою прокачку для выбранного героя.
func send_profile() -> void:
	if mode != "client":
		return
	var Data := load("res://scripts/data.gd")
	var Meta := load("res://scripts/meta.gd")
	var prof: Dictionary = Meta.profile(Data.selected_character)
	prof["sprite"] = Meta.hero_sprite(Data.selected_character)
	prof["nick"] = Meta.nickname
	rpc_id(1, "c_profile", Data.selected_character, prof)


@rpc("any_peer", "reliable")
func c_profile(hero: String, prof: Dictionary) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id]["hero"] = hero
	peers[id]["profile"] = prof
	peers[id]["sprite"] = str(prof.get("sprite", ""))
	if str(prof.get("nick", "")) != "":
		peers[id]["nick"] = str(prof["nick"])
	_sync_counts()


## Хост в портале начинает вылазку для всех, кто в убежище (от двух человек).
func start_run(level: int) -> void:
	var Data := load("res://scripts/data.gd")
	if not can_start():
		return
	var M = load("res://scripts/meta.gd")
	var plist: Array = [{"id": 1, "hero": Data.selected_character, "nick": M.nickname,
		"sprite": M.hero_sprite(Data.selected_character)}]
	var ids: Array = peers.keys()
	ids.sort()
	for id in ids:
		var pr: Dictionary = peers[id]
		plist.append({"id": id, "hero": str(pr.get("hero", "rin")), "nick": str(pr.get("nick", "")),
			"sprite": str(pr.get("sprite", ""))})
	var state := {"level": level, "players": plist, "client": true, "count": plist.size(),
		"hero1": plist[0]["hero"], "hero2": plist[1]["hero"], "nick1": M.nickname,
		"sprite1": plist[0]["sprite"], "sprite2": plist[1]["sprite"]}
	rpc("h_start", state, randi() % 2000000000 + 1)


# ================= Забег =================

## Хост: записать эффект для отправки клиенту.
func fx(kind: String, args: Array) -> void:
	if mode == "host" and in_game and _fx.size() < 400:
		_fx.append([kind, args])


## Хост: переслать эффект одного клиента остальным (сам он его не проиграет повторно).
func fx_from(idx: int, kind: String, args: Array) -> void:
	if mode == "host" and in_game and _fx.size() < 500:
		_fx.append([kind, args, idx])


func take_fx() -> Array:
	var f := _fx
	_fx = []
	return f


func send_snapshot(snap: Dictionary) -> void:
	if mode == "host" and not peers.is_empty():
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
	var idx := idx_of(multiplayer.get_remote_sender_id())
	if idx <= 0:
		return
	_cstate[idx] = s
	var pend: Array = _cfx_pending.get(idx, [])
	pend.append_array(s.get("fx", []))
	if pend.size() > 400:
		pend = pend.slice(pend.size() - 400)
	_cfx_pending[idx] = pend


@rpc("any_peer", "reliable")
func c_hits(h: Array) -> void:
	if mode == "host" and main != null and is_instance_valid(main):
		var idx := idx_of(multiplayer.get_remote_sender_id())
		if idx > 0:
			main.net_client_hits(h, idx)


## Хост: забрать свежие состояния клиентов {индекс: состояние}.
func take_cstates() -> Dictionary:
	var out := {}
	for idx in _cstate:
		var s: Dictionary = _cstate[idx]
		s["fx"] = _cfx_pending.get(idx, [])
		out[idx] = s
	_cstate = {}
	_cfx_pending = {}
	return out


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
	var idx := idx_of(multiplayer.get_remote_sender_id())
	if idx <= 0 or idx >= main.players.size():
		return
	var p2 = main.players[idx]
	p2.net_vec = v
	if ab > int(_ab_seen.get(idx, 0)):
		_ab_seen[idx] = ab
		p2.net_ability = true


## Надёжные события хоста: выбор улучшений, сундук, конец игры, музыка.
func event(kind: String, data: Variant = null) -> void:
	if mode == "host" and in_game and not peers.is_empty():
		rpc("h_event", kind, data)


## Событие только одному игроку (по номеру в забеге).
func event_to(idx: int, kind: String, data: Variant = null) -> void:
	if mode != "host" or not in_game or idx <= 0 or idx >= order.size():
		return
	if peers.has(order[idx]):
		rpc_id(order[idx], "h_event", kind, data)


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
		var idx := idx_of(multiplayer.get_remote_sender_id())
		if idx > 0:
			main.net_remote_choice(index, idx)


## Клиент закрыл окно своего сундука.
func chest_closed() -> void:
	if mode == "client":
		rpc_id(1, "c_chest_closed")


@rpc("any_peer", "reliable")
func c_chest_closed() -> void:
	pass


## Свежий скрипт подставлен вместо старого (см. hotswap.gd): переподключаем сигналы сети.
func _hotswapped() -> void:
	for sig in [multiplayer.peer_connected, multiplayer.peer_disconnected, multiplayer.connected_to_server,
			multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c in (sig as Signal).get_connections():
			if (c["callable"] as Callable).get_object() == self:
				(sig as Signal).disconnect(c["callable"])
	_ready()
