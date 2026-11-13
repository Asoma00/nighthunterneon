extends Node
## Звук без файлов: все инструменты и эффекты синтезируются кодом при запуске,
## а музыку в реальном времени играет пошаговый секвенсор: 20 песен в стиле
## ретровейв + средневековое фэнтези, темп и слои плавно следуют за накалом боя.
## Подключён как автозагрузка «Sound».

const RATE := 22050
var Data:
	get: return load("res://scripts/data.gd")

var _samples := {}
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _music_pb: AudioStreamPlaybackPolyphonic
var _sfx_pb: AudioStreamPlaybackPolyphonic
var _last_play := {}

var _track := ""
var _bpm := 120.0
var _step := 0
var _step_time := 0.0
var _bar := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_samples()
	_synthwave_samples()
	_music_player = _make_player(48)
	_sfx_player = _make_player(48)
	_music_pb = _music_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_music_player.bus = _music_bus()
	_sfx_pb = _sfx_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	apply_volumes()


## Шина музыки с эффектами: фильтр снимает резкость, хорус расширяет пэды,
## эхо и реверберация дают «синтвейвный» объём.
func _music_bus() -> String:
	var name := "Music"
	if AudioServer.get_bus_index(name) >= 0:
		return name
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 8000.0
	AudioServer.add_bus_effect(idx, lp)
	var ch := AudioEffectChorus.new()
	ch.wet = 0.3
	AudioServer.add_bus_effect(idx, ch)
	var dl := AudioEffectDelay.new()
	dl.tap1_delay_ms = 375.0
	dl.tap1_level_db = -16.0
	dl.tap2_delay_ms = 750.0
	dl.tap2_level_db = -22.0
	AudioServer.add_bus_effect(idx, dl)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.8
	rv.damping = 0.5
	rv.wet = 0.25
	rv.dry = 0.9
	AudioServer.add_bus_effect(idx, rv)
	return name


func _make_player(voices: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = voices
	p.stream = poly
	add_child(p)
	p.play()
	return p


func apply_volumes() -> void:
	_music_player.volume_db = linear_to_db(maxf(Data.music_volume, 0.0001)) - 4.0
	_sfx_player.volume_db = linear_to_db(maxf(Data.sfx_volume, 0.0001)) - 2.0


# ================= Эффекты =================

## Проиграть эффект. min_gap — не чаще раза в N секунд (чтобы толпа не оглушала).
func play(name: String, volume_db := 0.0, pitch := 1.0, pitch_rand := 0.0, min_gap := 0.03) -> void:
	# Сетевая игра: звуки боя приходят от хоста
	if Net.in_game and Net.mode == "client" and not Net.replaying and not Net.local and not (name in ["click", "hover"]):
		return
	if Net.in_game and Net.mode == "host" and not Net.replaying and not (name in ["click", "hover"]):
		Net.fx("snd", [name, volume_db, pitch, pitch_rand, min_gap])
	if _sfx_pb == null or not _samples.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(name, -10.0)) < min_gap:
		return
	_last_play[name] = now
	var p := pitch * (1.0 + randf_range(-pitch_rand, pitch_rand))
	_sfx_pb.play_stream(_samples[name], 0.0, volume_db, p)


# ================= Музыка =================
## 10 боевых и 10 спокойных песен: ретровейв + средневековое фэнтези.
## В бою — только напористая музыка, в меню и убежище — спокойная; при каждом
## заходе случайная новая песня. Темп и слои плавно следуют за накалом боя,
## песни сменяются через затухание, босс не меняет песню, а добавляет слои.

const SCALES := {
	"aeolian": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10], "harmonic": [0, 2, 3, 5, 7, 8, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10], "ionian": [0, 2, 4, 5, 7, 9, 11],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
}

## key — тоника в полутонах от ля; prog — аккорды по тактам [сдвиг, "m"/"M"];
## steps — 16 (4/4) или 12 (6/8); bpm — [спокойно, максимум накала].
const BATTLE_SONGS := [
	{"name": "Неоновый тракт", "key": 0, "scale": "ionian", "steps": 16, "bpm": [126.0, 148.0],
		"prog": [[0, "M"], [7, "M"], [9, "m"], [5, "M"], [0, "M"], [7, "M"], [5, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "synth", "seed": 11},
	{"name": "Марш стражи", "key": 5, "scale": "mixolydian", "steps": 16, "bpm": [122.0, 142.0],
		"prog": [[0, "M"], [-2, "M"], [5, "M"], [0, "M"], [0, "M"], [-2, "M"], [5, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "march", "seed": 23},
	{"name": "Колесо удачи", "key": -2, "scale": "ionian", "steps": 16, "bpm": [110.0, 128.0],
		"prog": [[0, "M"], [5, "M"], [7, "M"], [0, "M"], [9, "m"], [5, "M"], [7, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "folk", "seed": 37},
	{"name": "Хрустальный пир", "key": 7, "scale": "lydian", "steps": 16, "bpm": [128.0, 150.0],
		"prog": [[0, "M"], [2, "M"], [9, "m"], [7, "M"], [0, "M"], [2, "M"], [4, "m"], [7, "M"]],
		"lead": "bell", "arp": "harp", "drums": "synth", "seed": 41},
	{"name": "Корона рассвета", "key": 3, "scale": "dorian", "steps": 16, "bpm": [132.0, 156.0],
		"prog": [[0, "m"], [5, "M"], [0, "m"], [5, "M"], [-2, "M"], [3, "M"], [5, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "heavy", "seed": 53},
	{"name": "Пляска машин", "key": -5, "scale": "mixolydian", "steps": 16, "bpm": [114.0, 132.0],
		"prog": [[0, "M"], [-2, "M"], [5, "M"], [0, "M"], [0, "M"], [-2, "M"], [5, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "gallop", "seed": 67},
	{"name": "Солнце над бастионом", "key": -4, "scale": "ionian", "steps": 16, "bpm": [126.0, 148.0],
		"prog": [[0, "M"], [4, "m"], [5, "M"], [7, "M"], [0, "M"], [4, "m"], [2, "m"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "break", "seed": 71},
	{"name": "Рыцари неона", "key": 2, "scale": "ionian", "steps": 16, "bpm": [130.0, 152.0],
		"prog": [[0, "M"], [7, "M"], [9, "m"], [4, "m"], [5, "M"], [0, "M"], [5, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "gallop", "seed": 83},
	{"name": "Охота на дракона", "key": 5, "scale": "dorian", "steps": 16, "bpm": [136.0, 160.0],
		"prog": [[0, "m"], [5, "M"], [3, "M"], [-2, "M"], [0, "m"], [5, "M"], [7, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "heavy", "seed": 97},
	{"name": "Праздник победы", "key": 0, "scale": "mixolydian", "steps": 16, "bpm": [116.0, 134.0],
		"prog": [[0, "M"], [5, "M"], [-2, "M"], [0, "M"], [7, "M"], [5, "M"], [-2, "M"], [7, "M"]],
		"lead": "lead", "arp": "harp", "drums": "folk", "seed": 101},
]

const CALM_SONGS := [
	{"name": "Огни посада", "key": 0, "scale": "aeolian", "steps": 16, "bpm": [84.0, 84.0],
		"prog": [[0, "m"], [-4, "M"], [3, "M"], [-5, "M"]], "lead": "bell", "arp": "harp", "drums": "calm", "seed": 5},
	{"name": "Таверна у реки", "key": 5, "scale": "mixolydian", "steps": 16, "bpm": [80.0, 80.0],
		"prog": [[0, "M"], [-2, "M"], [0, "M"], [5, "M"], [0, "M"], [-2, "M"], [-5, "m"], [0, "M"]],
		"lead": "bell", "arp": "harp", "drums": "tavern", "seed": 7},
	{"name": "Сон алхимика", "key": 7, "scale": "dorian", "steps": 16, "bpm": [74.0, 74.0],
		"prog": [[0, "m"], [5, "M"], [0, "m"], [-2, "M"]], "lead": "bell", "arp": "harp", "drums": "dream", "seed": 13},
	{"name": "Колыбель кузнеца", "key": -2, "scale": "mixolydian", "steps": 16, "bpm": [68.0, 68.0],
		"prog": [[0, "M"], [5, "M"], [-2, "M"], [0, "M"]], "lead": "harp", "arp": "harp", "drums": "lullaby", "seed": 17},
	{"name": "Тихий сад", "key": 3, "scale": "ionian", "steps": 16, "bpm": [78.0, 78.0],
		"prog": [[0, "M"], [-3, "m"], [5, "M"], [7, "M"]], "lead": "bell", "arp": "harp", "drums": "none", "seed": 19},
	{"name": "Звёзды над стеной", "key": -4, "scale": "lydian", "steps": 16, "bpm": [72.0, 72.0],
		"prog": [[0, "M"], [2, "M"], [0, "M"], [-5, "m"]], "lead": "bell", "arp": "harp", "drums": "dream", "seed": 29},
	{"name": "Дорога паломника", "key": 2, "scale": "dorian", "steps": 16, "bpm": [84.0, 84.0],
		"prog": [[0, "m"], [5, "M"], [3, "M"], [-2, "M"], [0, "m"], [5, "M"], [-2, "M"], [0, "m"]],
		"lead": "bell", "arp": "harp", "drums": "tavern", "seed": 31},
	{"name": "Неоновый дождь", "key": 0, "scale": "aeolian", "steps": 16, "bpm": [82.0, 82.0],
		"prog": [[0, "m"], [-2, "M"], [-4, "M"], [-5, "m"]], "lead": "lead", "arp": "harp", "drums": "calm", "seed": 43},
	{"name": "Песнь алтаря", "key": 5, "scale": "aeolian", "steps": 16, "bpm": [64.0, 64.0],
		"prog": [[0, "m"], [-4, "M"], [-2, "M"], [0, "m"], [3, "M"], [-2, "M"], [-4, "M"], [-5, "M"]],
		"lead": "harp", "arp": "harp", "drums": "none", "seed": 47},
	{"name": "Вечер у костра", "key": 7, "scale": "mixolydian", "steps": 16, "bpm": [88.0, 88.0],
		"prog": [[0, "M"], [-2, "M"], [5, "M"], [0, "M"]], "lead": "bell", "arp": "harp", "drums": "tavern", "seed": 59},
	{"name": "Неоновый рассвет", "key": 0, "scale": "aeolian", "steps": 16, "bpm": [96.0, 96.0],
		"prog": [[-4, "M"], [0, "m"], [5, "m"], [3, "M"]], "lead": "bell", "arp": "harp", "drums": "calm", "seed": 3},
]
const SPLASH_SONG := 10

var intensity_target := 0.0     # задаётся боем: сколько врагов, есть ли босс, мало ли здоровья
var intensity := 0.0            # плавное значение, по нему играет музыка
var boss_layer := 0.0           # 0..1 — плавно нарастает, пока жив босс
var _boss := false
var _song: Dictionary = {}
var _song_idx := -1
var _category := ""             # "battle" или "calm"
var _last := {"battle": -1, "calm": -1}
var _next := -1                 # песня, на которую идёт смена через затухание
var _fade := 1.0                # громкость музыки при смене песен
var _mel: Array = []            # [часть][такт 0..3][шаг] -> ступень или null
var _counter: Array = []
var _key := 0                   # тональность текущей песни (при мешапе новая песня подстраивается под неё)
var _inc: Dictionary = {}       # входящая песня мешапа: song, mel, counter, bar, idx
var _grp := 1.0                 # громкость текущей группы слоёв (ударные/гармония/бас/мелодия)
const MIX_BARS := 8             # за сколько тактов одна песня перетекает в другую


func current_song_name() -> String:
	return _song.get("name", "")


## Музыкальная тема. В бою — только боевые песни, в меню и убежище — спокойные.
## «boss» не меняет песню, а включает слой босса. force — новая песня даже без смены места.
func set_track(track: String, force := false, song := -1) -> void:
	var host: bool = Net.in_game and Net.mode == "host"
	if track == "boss":
		_boss = true
		if host:
			Net.fx("track", [track])
		return
	if track == "battle":
		_boss = false
	var cat := "battle" if track == "battle" else "calm"
	if cat == _category and not force and _track != "":
		_track = track
		if host:
			Net.fx("track", [track])
		return
	_track = track
	_category = cat
	var list: Array = BATTLE_SONGS if cat == "battle" else CALM_SONGS
	var idx := song
	if idx < 0 or idx >= list.size():
		idx = randi() % list.size()
		if idx == int(_last[cat]):
			idx = (idx + 1 + randi() % (list.size() - 1)) % list.size()
	_last[cat] = idx
	if host:
		Net.fx("track", [track, true, idx])
	if _song.is_empty():
		_load_song(idx)
		_fade = 0.0       # первая песня мягко нарастает
	else:
		# Музыка не выключается: новая песня вплетается в текущую (мешап),
		# в той же тональности и на том же такте, темп перетекает плавно.
		_start_mix(idx, list)


func _load_song(idx: int) -> void:
	var list: Array = BATTLE_SONGS if _category == "battle" else CALM_SONGS
	_song_idx = idx
	_song = list[idx]
	_key = int(_song["key"])
	_inc = {}
	_step = 0
	_bar = 0
	_step_time = 0.0
	_bpm = lerpf(_song["bpm"][0], _song["bpm"][1], intensity)
	var m := _melodies(_song)
	_mel = m[0]
	_counter = m[1]


func _melodies(song: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(song["seed"])
	var mel: Array = []
	var counter: Array = []
	for part in 3:
		mel.append(_compose(rng, 4, 2, song["steps"]))
		counter.append(_compose(rng, -3, 1, song["steps"]))
	return [mel, counter]


## Следующая боевая песня для мешапа: с тем же размером (4/4 или 6/8).
func _mix_pick() -> int:
	var opts: Array = []
	for i in BATTLE_SONGS.size():
		if i != _song_idx and int(BATTLE_SONGS[i]["steps"]) == int(_song["steps"]):
			opts.append(i)
	return opts[randi() % opts.size()] if not opts.is_empty() else _song_idx


## Мешап: новая песня играет вместе с текущей на одном такте и в той же тональности.
## Сначала смешиваются ударные, на середине — гармония и бас, потом входит новая мелодия.
func _start_mix(idx: int, list: Array = BATTLE_SONGS) -> void:
	var song: Dictionary = list[idx]
	if song == _song:
		_inc = {}
		return
	var m := _melodies(song)
	var bar := 0
	if not _inc.is_empty():
		bar = mini(int(_inc["bar"]), MIX_BARS / 2)   # смена цели посреди мешапа — без скачка
	_inc = {"song": song, "mel": m[0], "counter": m[1], "bar": bar, "idx": idx}


## Мелодия из 4 тактов: сильные доли — звуки аккорда, слабые — шаги по ладу,
## последний такт — разрешение на тонику.
func _compose(rng: RandomNumberGenerator, center: int, density: int, steps: int) -> Array:
	var rhythms: Array
	if steps == 16:
		rhythms = [[0, 3, 6, 8, 12], [0, 4, 6, 8, 10, 12], [0, 2, 4, 7, 10, 12, 14], [0, 6, 8, 11, 12], [0, 8, 10, 12, 14], [0, 2, 3, 4, 8, 11, 12]]
	else:
		rhythms = [[0, 3, 5, 6, 9], [0, 2, 3, 6, 8, 9, 11], [0, 4, 6, 9], [0, 3, 6, 8, 10], [0, 1, 2, 3, 6, 9]]
	var phrase: Array = []
	var deg := center
	var motif: Array = rhythms[rng.randi_range(0, rhythms.size() - 1)]
	for bar in 4:
		var row: Array = []
		row.resize(steps)
		var rh: Array = motif if bar % 2 == 0 else rhythms[rng.randi_range(0, rhythms.size() - 1)]
		if density == 1:
			rh = rh.filter(func(x): return x % (steps / 4) == 0)
		if bar == 3:
			rh = [0, steps / 4, steps / 2]
		for s in rh:
			var strong: bool = s == 0 or s == steps / 2
			if bar == 3 and s == steps / 2:
				deg = center - posmod(center, 7)
			elif strong:
				deg = center + [0, 2, 4, -3, 2][rng.randi_range(0, 4)]
			else:
				deg += [-1, 1, 1, -1, 2, -2][rng.randi_range(0, 5)]
				deg = clampi(deg, center - 4, center + 5)
			row[s] = deg
		phrase.append(row)
	return phrase


func _deg_semis(deg: int, song: Dictionary = {}, key := 999) -> int:
	if song.is_empty():
		song = _song
	var sc: Array = SCALES[song["scale"]]
	return (_key if key == 999 else key) + int(sc[posmod(deg, 7)]) + 12 * floori(deg / 7.0)


## Громкость слоя: плавно от тишины (накал lo) до полной (накал hi).
func _layer(lo: float, hi: float) -> float:
	return smoothstep(lo, hi, intensity)


func _nl(sample: String, semis: float, vol: float, gain: float) -> void:
	gain *= _fade * _grp
	if gain < 0.04:
		return
	_note(sample, semis, vol + linear_to_db(gain))


func _process(delta: float) -> void:
	if _track == "" or _music_pb == null or _song.is_empty():
		return
	# Накал растёт за ~8 с и спадает за ~14 с — перемены почти незаметны
	var target := clampf(intensity_target, 0.0, 1.0) if _category == "battle" else 0.0
	intensity = move_toward(intensity, target, delta / (8.0 if target > intensity else 14.0))
	boss_layer = move_toward(boss_layer, 1.0 if _boss and _category == "battle" else 0.0, delta / 6.0)
	# Темп подтягивается не быстрее 1.5 удара в минуту за секунду
	var ik := clampf(intensity + boss_layer * 0.25, 0.0, 1.0)
	var want_bpm := lerpf(_song["bpm"][0], _song["bpm"][1], ik)
	if not _inc.is_empty():
		var inc_bpm := lerpf(_inc["song"]["bpm"][0], _inc["song"]["bpm"][1], ik)
		want_bpm = lerpf(want_bpm, inc_bpm, clampf(float(_inc["bar"]) / MIX_BARS, 0.0, 1.0))
	_bpm = move_toward(_bpm, want_bpm, delta * 1.5)
	# Смена песни: затухание 2.5 с, затем новая песня нарастает 2.5 с
	if _next >= 0:
		_fade = move_toward(_fade, 0.0, delta / 5.0)
		if _fade <= 0.0:
			_load_song(_next)
			_next = -1
	else:
		_fade = move_toward(_fade, 1.0, delta / 5.0)
	_step_time -= delta
	var steps: int = _song["steps"]
	var step_len := 60.0 / _bpm / (4.0 if steps == 16 else 3.0)
	var guard := 0
	while _step_time <= 0.0 and guard < 4:
		guard += 1
		_step_time += step_len
		_play_step()
		_step += 1
		if _step >= steps:
			_step = 0
			_bar += 1
			if not _inc.is_empty():
				_inc["bar"] += 1
				if _inc["bar"] >= MIX_BARS:
					# Мешап завершён: новая песня становится основной (в той же тональности)
					_song = _inc["song"]
					_mel = _inc["mel"]
					_counter = _inc["counter"]
					_song_idx = _inc["idx"]
					_bar = _inc["bar"]
					_inc = {}
			# В бою песни перетекают друг в друга мешапом каждые 40 тактов
			elif _category == "battle" and _bar % 40 == 0 and _next < 0:
				_start_mix(_mix_pick())
			elif _category == "calm" and _bar % 32 == 0 and _next < 0:
				# В меню и убежище песни тоже перетекают друг в друга
				var ci := randi() % CALM_SONGS.size()
				if CALM_SONGS[ci] != _song:
					_start_mix(ci, CALM_SONGS)


func _note(sample: String, semis: float, vol := 0.0) -> void:
	_music_pb.play_stream(_samples[sample], 0.0, vol, pow(2.0, semis / 12.0))


func _play_step() -> void:
	if _inc.is_empty():
		_play_ctx(_song, _mel, _counter, _bar, {"drums": 1.0, "harm": 1.0, "bass": 1.0, "mel": 1.0})
		return
	var steps: int = _song["steps"]
	var p := (float(_inc["bar"]) + float(_step) / steps) / MIX_BARS
	var x_dr := smoothstep(0.1, 0.55, p)
	var a_g := {"drums": 1.0 - x_dr, "harm": 1.0 - smoothstep(0.45, 0.6, p), "bass": 1.0 if p < 0.5 else 0.0, "mel": 1.0 - smoothstep(0.2, 0.5, p)}
	var b_g := {"drums": x_dr, "harm": smoothstep(0.45, 0.6, p), "bass": 0.0 if p < 0.5 else 1.0, "mel": smoothstep(0.62, 0.8, p)}
	_play_ctx(_song, _mel, _counter, _bar, a_g)
	_play_ctx(_inc["song"], _inc["mel"], _inc["counter"], _inc["bar"], b_g)
	_grp = 1.0


func _play_ctx(song: Dictionary, mel: Array, counter: Array, bar: int, g: Dictionary) -> void:
	var s := _step
	var steps: int = song["steps"]
	var q := steps / 4                      # шагов в доле
	var prog: Array = song["prog"]
	var ch: Array = prog[bar % prog.size()]
	var root: int = _key + int(ch[0])
	var chord := _chord(root, ch[1] == "m")
	var part := (bar / 8) % 3              # 0 — тема, 1 — вариация с подголоском, 2 — хор
	var I := intensity
	var B := boss_layer
	var style: String = song["drums"]
	var calm := CALM_SONGS.has(song)
	var bar_end := bar % 8 == 7 and s >= steps - q * 2

	# --- Гармония: пэд, хор, колокола
	_grp = g["harm"]
	if s == 0:
		for n in chord.slice(0, 3):
			_nl("pad", n, -13.0, 0.9 - 0.25 * I)
		if part == 2 or calm or B > 0.05:
			_nl("choir", chord[0], -11.0, 0.45 + 0.4 * maxf(I, B))
			_nl("choir", chord[2], -13.0, 0.35 + 0.4 * maxf(I, B))
	if s == steps / 2 and B > 0.05:
		_nl("choir", chord[1] + 12, -15.0, B * 0.6)
	if s == 0 and bar % 4 == 0:
		_nl("bell", chord[2] + 12, -14.0, 0.8 if calm else 0.35)

	# --- Ударные. Основа боевого ритма звучит всегда; накал добавляет плотность.
	_grp = g["drums"]
	match style:
		"synth", "heavy":
			if s % q == 0:
				_nl("kick", 0, -4.0, 0.9)
			if style == "heavy" and s % 2 == 0 and s % q != 0:
				_nl("kick", 0, -8.0, maxf(_layer(0.35, 0.95), B))
			if steps == 16 and (s == 4 or s == 12):
				_nl("snare", 0, -7.0, 0.85)
			if s % 2 == 1:
				_nl("hat", 0, -16.0, 0.55 + 0.45 * I)
			elif s % q != 0:
				_nl("hat", 0, -20.0, _layer(0.2, 0.8))
			if bar_end and s % 2 == 0:
				_nl("tom", (steps - s) * 0.5, -8.0, 0.4 + 0.6 * I)
		"break":
			if s in [0, 6, 10]:
				_nl("kick", 0, -4.0, 0.9)
			if s == 4 or s == 12:
				_nl("snare", 0, -6.0, 0.9)
			if s in [7, 15]:
				_nl("snare", 0, -16.0, _layer(0.15, 0.7))
			if s % 2 == 0:
				_nl("hat", 0, -17.0, 0.6)
			else:
				_nl("hat", 0, -21.0, _layer(0.25, 0.85))
			if bar_end and s % 2 == 1:
				_nl("tom", (steps - s) * 0.4, -9.0, _layer(0.2, 0.7))
		"march":
			if s == 0 or s == 8:
				_nl("kick", 0, -5.0, 0.9)
			if s == 4 or s == 12:
				_nl("snare", 0, -7.0, 0.85)
			if s in [14, 15, 7]:
				_nl("snare", 0, -15.0, 0.3 + 0.6 * I)
			if s % 4 == 0:
				_nl("tom", 0, -9.0, 0.7)
			if s % 2 == 0:
				_nl("tamb", 0, -17.0, 0.5 + 0.5 * I)
			if s % 2 == 1:
				_nl("hat", 0, -20.0, _layer(0.2, 0.8))
			if s % 4 == 2:
				_nl("kick", 0, -10.0, _layer(0.45, 0.95))
		"gallop":
			# Галоп: «та-та-там» — бочка на доле и двух шестнадцатых перед ней
			if steps == 16:
				if s % 4 == 0 or s % 4 == 2 or s % 4 == 3:
					_nl("kick", 0, -5.0 if s % 4 == 0 else -9.0, 0.9 if s % 4 == 0 else 0.5 + 0.5 * I)
				if s == 4 or s == 12:
					_nl("snare", 0, -7.0, 0.85)
			else:
				if s % 3 == 0 or s % 3 == 2:
					_nl("kick", 0, -5.0 if s % 3 == 0 else -9.0, 0.9 if s % 3 == 0 else 0.5 + 0.5 * I)
				if s == 3 or s == 9:
					_nl("snare", 0, -7.0, 0.85)
			_nl("hat", 0, -18.0 if s % 2 == 0 else -21.0, 0.45 + 0.55 * I)
			if bar_end and s % 2 == 0:
				_nl("tom", (steps - s) * 0.5, -8.0, 0.4 + 0.6 * I)
		"folk":
			if s == 0 or s == 6:
				_nl("kick", 0, -4.0, 0.9)
				_nl("tom", 0, -7.0, 0.8)
			if s == 3 or s == 9:
				_nl("snare", 0, -8.0, 0.75)
			if s % 3 == 2:
				_nl("tom", 5, -12.0, 0.5 + 0.5 * I)
			_nl("tamb", 0, -18.0 if s % 3 else -14.0, 0.45 + 0.55 * I)
			if s % 3 == 0 and s % 6 != 0:
				_nl("kick", 0, -9.0, _layer(0.3, 0.9))
		"calm":
			if s == 0 or s == 10:
				_nl("kick", 0, -13.0, 0.7)
			if s % 4 == 2:
				_nl("hat", 0, -22.0, 0.7)
		"dream":
			if s == 0:
				_nl("kick", 0, -15.0, 0.6)
			if s % 4 == 2:
				_nl("tamb", 0, -24.0, 0.5)
		"lullaby":
			if s == 0:
				_nl("tom", 0, -14.0, 0.6)
		"tavern":
			if s == 0 or s == 6:
				_nl("tom", 0, -11.0, 0.8)
			if s % 3 == 0 and s != 0:
				_nl("tamb", 0, -20.0, 0.7)
	# Слой босса: бубен и удары томов на каждую долю
	if B > 0.05:
		if s % q == q - 1:
			_nl("tamb", 0, -15.0, B)
		if s % q == 0:
			_nl("tom", -5, -10.0, B * 0.7)

	# --- Бас
	_grp = g["bass"]
	if calm:
		if s == 0:
			_nl("bass", root, -9.0, 1.0)
		elif s == steps / 2:
			_nl("bass", root + 7, -11.0, 1.0)
	elif steps == 12:
		if s % 3 == 0:
			_nl("bass", root + (7 if s == 6 else 0), -6.0, 1.0 if s % 6 == 0 else 0.7)
		elif s % 3 == 2:
			_nl("bass", root, -10.0, _layer(0.3, 0.9))
	else:
		if s % 2 == 0:
			_nl("bass", root + (12 if s % 8 == 6 else 0), -5.0, 1.0 if s % 4 == 0 else 0.8)
		else:
			_nl("bass", root, -9.0, _layer(0.3, 0.9))

	# --- Арпеджио (лютня/клавесин): восьмые всегда, шестнадцатые — с накалом
	_grp = g["harm"]
	var arp_inst: String = song["arp"]
	var pat := [0, 1, 2, 3, 2, 1, 3, 2]
	var octave := -12 if arp_inst == "lute" else 0
	var on_eighth := s % 2 == 0 if steps == 16 else true
	var n_arp: int = chord[pat[s % 8] % chord.size()] + octave
	if on_eighth:
		_nl(arp_inst, n_arp, -13.0, 0.6 + 0.2 * I if not calm else 0.55)
	elif not calm:
		_nl("arp", n_arp + 12, -19.0, _layer(0.25, 0.9))

	# --- Мелодия и подголосок
	_grp = g["mel"]
	var bar4 := bar % 4
	var m = mel[part][bar4][s]
	if m != null:
		var lead: String = song["lead"]
		var mg := 0.85
		if calm:
			mg = 0.6 if (bar / 4) % 2 == 1 else 0.0
		var oct := 12 if lead == "bell" else 0
		_nl(lead, _deg_semis(m, song) + oct, -12.0 if lead != "chip" else -14.0, mg)
		if not calm:
			# С накалом мелодию подхватывает второй голос: синт-лид или чиптюн
			_nl("lead" if lead != "lead" else "chip", _deg_semis(m, song) + (12 if lead == "lead" else 0), -16.0, maxf(_layer(0.35, 1.0), B * 0.8))
	var c = counter[part][bar4][s]
	if c != null and part == 1:
		_nl("lute", _deg_semis(c, song), -12.0, 0.7)


func _chord(root: int, minor: bool) -> Array:
	return [root, root + (3 if minor else 4), root + 7, root + 12]


# ================= Синтез =================

func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


static func _saw(ph: float) -> float:
	return 2.0 * (ph - floor(ph)) - 1.0


static func _sq(ph: float) -> float:
	return 1.0 if ph - floor(ph) < 0.5 else -1.0


func _build_samples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	# --- Бочка: синус с падающей частотой
	var b := _buf(0.35)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 45.0 + 110.0 * exp(-t * 28.0)
		ph += f / RATE
		b[i] = sin(ph * TAU) * exp(-t * 9.0) * 0.95
	_samples["kick"] = _wav(b)

	# --- Малый: шум + тон
	b = _buf(0.22)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (rng.randf_range(-1, 1) * 0.6 + sin(t * 190.0 * TAU) * 0.4) * exp(-t * 16.0) * 0.8
	_samples["snare"] = _wav(b)

	# --- Хэт: высокочастотный шум
	b = _buf(0.06)
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		b[i] = (n - prev) * 0.5 * exp(-t * 60.0)
		prev = n
	_samples["hat"] = _wav(b)

	# --- Бас: пила 55 Гц через фильтр
	b = _buf(0.32)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cutoff := 0.05 + 0.25 * exp(-t * 14.0)
		lp += (_saw(t * 55.0) - lp) * cutoff
		b[i] = lp * minf(1.0, t * 300.0) * exp(-t * 5.0) * 0.9
	_samples["bass"] = _wav(b)

	# --- Арпеджио: квадрат 440 Гц
	b = _buf(0.22)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_sq(t * 440.0) - lp) * 0.35
		b[i] = lp * exp(-t * 14.0) * 0.45
	_samples["arp"] = _wav(b)

	# --- Лид: пила с вибрато
	b = _buf(0.5)
	lp = 0.0
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += 440.0 * (1.0 + 0.006 * sin(t * 34.0)) / RATE
		lp += (_saw(ph) - lp) * 0.2
		b[i] = lp * minf(1.0, t * 60.0) * exp(-t * 4.0) * 0.45
	_samples["lead"] = _wav(b)

	# --- Пэд: три расстроенные пилы, медленная атака
	b = _buf(1.6)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := _saw(t * 220.0) + _saw(t * 221.3) + _saw(t * 218.8)
		lp += (v / 3.0 - lp) * 0.06
		var env := minf(1.0, t * 3.0) * minf(1.0, (1.6 - t) * 2.5)
		b[i] = lp * env * 0.55
	_samples["pad"] = _wav(b)

	# ---------- Средневековые инструменты ----------
	_samples["lute"] = _pluck(440.0, 1.1, 0.996, 0.5, 0.55)
	_samples["harp"] = _pluck(440.0, 1.3, 0.998, 0.72, 0.42)

	# Чиптюн-лид: квадрат с узкой скважностью и быстрым вибрато — весёлый ретро-звук
	b = _buf(0.32)
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += 440.0 * (1.0 + 0.012 * sin(t * 38.0) * minf(1.0, t * 6.0)) / RATE
		var duty := 0.25 if t < 0.08 else 0.5
		var sq := 1.0 if fmod(ph, 1.0) < duty else -1.0
		b[i] = sq * 0.22 * minf(1.0, t * 200.0) * (0.75 + 0.25 * exp(-t * 10.0)) * minf(1.0, (0.32 - t) * 12.0)
	_samples["chip"] = _wav(b)

	# Флейта: синус с обертонами, дыхание и запаздывающее вибрато
	b = _buf(0.75)
	ph = 0.0
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += 440.0 * (1.0 + 0.007 * sin(t * 33.0) * minf(1.0, t * 3.0)) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.12
		var env := minf(1.0, t * 14.0) * minf(1.0, (0.75 - t) * 5.0)
		b[i] = (sin(ph * TAU) + 0.22 * sin(ph * 2.0 * TAU) + 0.07 * sin(ph * 3.0 * TAU) + lp * 0.18) * env * 0.42
	_samples["flute"] = _wav(b)

	# Хор «а-а»: гармоники, усиленные возле формант голоса, три голоса вразброс
	b = _buf(2.2)
	var formants := [[700.0, 1.0], [1220.0, 0.55], [2600.0, 0.25]]
	var amps: Array = []
	for k in range(1, 16):
		var fk := 220.0 * k
		var a := 0.0
		for fm in formants:
			a += float(fm[1]) * exp(-pow((fk - float(fm[0])) / 260.0, 2.0))
		amps.append(a + 0.08 / k)
	# Один период формы волны в таблицу — быстро читаем её тремя голосами
	var table := PackedFloat32Array()
	table.resize(1024)
	for j in 1024:
		var x := float(j) / 1024.0
		for k in amps.size():
			table[j] += float(amps[k]) * sin(x * (k + 1) * TAU)
	var phs := [0.0, 0.31, 0.67]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for vi in 3:
			var det: float = [0.0, 0.9, -0.7][vi]
			phs[vi] = fmod(phs[vi] + (220.0 + det + 1.2 * sin(t * 30.0 + det)) / RATE, 1.0)
			v += table[int(phs[vi] * 1024.0) & 1023]
		var env := minf(1.0, t * 1.8) * minf(1.0, (2.2 - t) * 1.6)
		b[i] = v * env * 0.07
	_samples["choir"] = _wav(b)

	# Колокол: FM с негармоничным модулятором
	b = _buf(1.8)
	for i in b.size():
		var t := float(i) / RATE
		var mod := 1.4 * sin(t * 880.0 * 1.41 * TAU) * exp(-t * 3.0)
		b[i] = sin(t * 880.0 * TAU + mod) * exp(-t * 2.4) * 0.4 * minf(1.0, t * 500.0)
	_samples["bell"] = _wav(b)

	# Рамочный барабан (том)
	b = _buf(0.45)
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (78.0 + 60.0 * exp(-t * 18.0)) / RATE
		b[i] = (sin(ph * TAU) * 0.85 + rng.randf_range(-1, 1) * 0.25 * exp(-t * 40.0)) * exp(-t * 7.0) * 0.8
	_samples["tom"] = _wav(b)

	# Бубен: несколько звонких всплесков
	b = _buf(0.16)
	prev = 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		var jingle := 1.0 + 0.6 * sin(t * 7000.0 * TAU)
		b[i] = (n - prev) * jingle * 0.35 * (exp(-t * 35.0) + 0.5 * exp(-maxf(0.0, t - 0.03) * 45.0) * float(t > 0.03))
		prev = n
	_samples["tamb"] = _wav(b)

	# ---------- Звуковые эффекты ----------
	_samples["shoot"] = _sweep(0.09, 1100.0, 420.0, "sq", 0.25, 30.0)
	_samples["zap"] = _sweep(0.07, 1800.0, 900.0, "saw", 0.22, 40.0)
	_samples["gem"] = _sweep(0.07, 1300.0, 1900.0, "sine", 0.3, 25.0)
	_samples["hurt"] = _sweep(0.22, 320.0, 90.0, "saw", 0.5, 10.0)
	_samples["click"] = _sweep(0.04, 900.0, 1200.0, "sq", 0.2, 50.0)
	_samples["hover"] = _sweep(0.03, 1500.0, 1600.0, "sine", 0.15, 60.0)

	# Попадание: короткий шумовой щелчок с низким ударом
	b = _buf(0.07)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (rng.randf_range(-1, 1) * 0.5 + sin(t * 150.0 * TAU) * 0.6) * exp(-t * 45.0) * 0.5
	_samples["hit"] = _wav(b)

	# Смерть врага: «цифровой» хруст с падением тона
	b = _buf(0.22)
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (600.0 * exp(-t * 10.0) + 60.0) / RATE
		var v := _sq(ph) * 0.4 + rng.randf_range(-1, 1) * 0.3
		v = floor(v * 6.0) / 6.0
		b[i] = v * exp(-t * 14.0) * 0.5
	_samples["kill"] = _wav(b)

	# Взрыв (реакции, смерть элиты)
	b = _buf(0.7)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * (0.08 + 0.3 * exp(-t * 8.0))
		b[i] = (lp * 1.6 + sin(t * 55.0 * TAU) * exp(-t * 6.0) * 0.6) * exp(-t * 4.5) * 0.8
	_samples["boom"] = _wav(b)

	# Молния: треск + раскат
	b = _buf(0.6)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		var crackle := rng.randf_range(-1, 1) if rng.randf() < 0.3 + 0.7 * exp(-t * 12.0) else 0.0
		lp += (rng.randf_range(-1, 1) - lp) * 0.03
		b[i] = (crackle * 0.5 * exp(-t * 8.0) + lp * 2.0 * exp(-t * 3.0)) * 0.7
	_samples["thunder"] = _wav(b)

	# Свист клинка
	b = _buf(0.2)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := sin(t / 0.2 * PI)
		lp += (rng.randf_range(-1, 1) - lp) * (0.1 + 0.5 * k)
		b[i] = lp * k * 0.6
	_samples["slash"] = _wav(b)

	# Удар молота о землю
	b = _buf(0.5)
	ph = 0.0
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (40.0 + 90.0 * exp(-t * 20.0)) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.05
		b[i] = (sin(ph * TAU) * 0.9 + lp * 1.5) * exp(-t * 6.0) * 0.8
	_samples["slam"] = _wav(b)

	# Арпеджио-фанфары
	_samples["levelup"] = _arpeggio([0, 4, 7, 12, 16], 0.07, 523.25, 0.35)
	_samples["chest"] = _arpeggio([0, 3, 7, 10, 12, 15, 19, 24], 0.06, 392.0, 0.35)
	_samples["evolve"] = _arpeggio([0, 7, 12, 16, 19, 24, 28, 31], 0.09, 261.6, 0.4)
	_samples["reaction"] = _arpeggio([0, 7, 12], 0.035, 880.0, 0.25)
	_samples["ability"] = _sweep(0.35, 200.0, 1400.0, "saw", 0.35, 4.0)

	# Сирена босса
	b = _buf(1.4)
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (300.0 + 180.0 * sin(t * TAU * 1.5)) / RATE
		b[i] = _saw(ph) * 0.35 * minf(1.0, t * 10.0) * minf(1.0, (1.4 - t) * 4.0)
	_samples["siren"] = _wav(b)


func _sweep(dur: float, f0: float, f1: float, wave: String, vol: float, decay: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		ph += f / RATE
		var v := 0.0
		match wave:
			"sq":
				v = _sq(ph)
			"saw":
				v = _saw(ph)
			_:
				v = sin(ph * TAU)
		b[i] = v * vol * exp(-t * decay) * minf(1.0, t * 800.0)
	return _wav(b)


func _arpeggio(notes: Array, step: float, base: float, vol: float) -> AudioStreamWAV:
	var dur := step * notes.size() + 0.35
	var b := _buf(dur)
	for n in notes.size():
		var f: float = base * pow(2.0, float(notes[n]) / 12.0)
		var start := int(n * step * RATE)
		for i in range(start, b.size()):
			var t := float(i - start) / RATE
			b[i] += (_sq(t * f) * 0.5 + sin(t * f * TAU) * 0.5) * exp(-t * 7.0) * vol
	return _wav(b)


## Щипковая струна (алгоритм Карплуса — Стронга): лютня и клавесин.
func _pluck(freq: float, dur: float, decay: float, bright: float, vol: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var n := int(RATE / freq)
	var ring := PackedFloat32Array()
	ring.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 13.0 + bright * 100.0)
	for i in n:
		ring[i] = rng.randf_range(-1, 1)
	var idx := 0
	var last := 0.0
	for i in b.size():
		var cur := ring[idx]
		var nxt := ring[(idx + 1) % n]
		var y := (cur * bright + nxt * (1.0 - bright)) * decay
		ring[idx] = y
		idx = (idx + 1) % n
		last += (cur - last) * 0.6
		var t := float(i) / RATE
		b[i] = last * vol * minf(1.0, (dur - t) * 8.0)
	return _wav(b)


## Инструменты в стиле синтвейва — мягче и «дороже» звучат через шину эффектов.
func _synthwave_samples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	# Пэд: три расстроенные пилы через тёмный фильтр, медленная атака и длинный хвост
	var b := _buf(2.8)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := _saw(t * 220.0) + _saw(t * 221.0) + _saw(t * 219.1)
		lp += (v / 3.0 - lp) * 0.05
		lp2 += (lp - lp2) * 0.12
		b[i] = lp2 * minf(1.0, t / 0.7) * minf(1.0, (2.8 - t) / 1.2) * 0.6
	_samples["pad"] = _wav(b)
	# Мягкий синт-лид: треугольник с поздним вибрато
	b = _buf(0.9)
	var ph := 0.0
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += 440.0 * (1.0 + 0.005 * sin(t * 32.0) * minf(1.0, t * 3.0)) / RATE
		var tri := 1.0 - 4.0 * absf(fmod(ph, 1.0) - 0.5)
		lp += (tri - lp) * 0.3
		b[i] = lp * minf(1.0, t / 0.03) * exp(-t * 1.6) * minf(1.0, (0.9 - t) / 0.2) * 0.5
	_samples["lead"] = _wav(b)
	_samples["chip"] = _samples["lead"]
	# Колокольчик-арпеджио: синус с мягким обертоном
	b = _buf(1.4)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(t * 440.0 * TAU) + 0.3 * sin(t * 880.0 * TAU) * exp(-t * 5.0)) * exp(-t * 3.2) * minf(1.0, t * 300.0) * 0.4
	_samples["harp"] = _wav(b)
	# Синт-щипок вместо лютни: пила через закрывающийся фильтр
	b = _buf(0.7)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_saw(t * 440.0) - lp) * (0.04 + 0.3 * exp(-t * 12.0))
		b[i] = lp * exp(-t * 4.5) * minf(1.0, t * 400.0) * 0.5
	_samples["lute"] = _wav(b)
	_samples["arp"] = _samples["lute"]
	# Мягкий бас: синус + немного пилы через фильтр
	b = _buf(0.5)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((sin(t * 55.0 * TAU) + 0.35 * _saw(t * 55.0)) - lp) * 0.15
		b[i] = lp * minf(1.0, t * 200.0) * exp(-t * 3.5) * 0.9
	_samples["bass"] = _wav(b)
	# Бочка мягче, малый — «хлопок» с хвостом (ревербом его доделает шина)
	b = _buf(0.45)
	ph = 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (48.0 + 80.0 * exp(-t * 26.0)) / RATE
		b[i] = sin(ph * TAU) * exp(-t * 7.5) * 0.85
	_samples["kick"] = _wav(b)
	b = _buf(0.35)
	lp = 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		lp += (n - lp) * 0.45
		var env := (exp(-t * 30.0) + 0.6 * exp(-maxf(t - 0.012, 0.0) * 30.0) * float(t > 0.012) + 0.35 * exp(-t * 9.0))
		b[i] = lp * env * 0.45
	_samples["snare"] = _wav(b)
