extends Node
## Soundtrack autoload — area playlists + global order. Missing files = silent (no crash).
## Radio (General panel): radio_next / radio_prev cycle track_01…track_20.

const BASE := "res://assets/audio/soundtrack/"
const TARGET_VOL := 0.4
const FADE_SEC := 1.1
const RADIO_TRACK_COUNT := 20

## Global order covers the full score across a long session (1–20; missing skip).
const GLOBAL_ORDER: PackedStringArray = [
	"track_01", "track_02", "track_03", "track_04",
	"track_05", "track_06", "track_07", "track_08",
	"track_09", "track_10", "track_11", "track_12",
	"track_13", "track_14", "track_15", "track_16",
	"track_17", "track_18", "track_19", "track_20",
]

## Thematic area playlists — every unique track used at least once.
const AREA_PLAYLISTS := {
	"yard": ["track_01", "track_02"],           # hub calm
	"tree": ["track_03", "track_07"],           # mystic roots
	# TODO KickItOn: original name not found in project/docs/tags — interim martial leftover track_08
	"north": ["track_08"],                      # Druid Glade main (was KickItOn TBD)
	"road": ["track_05", "track_09"],           # Crossroads fight (ex north/glade playlist)
	"coast": ["track_06", "track_10"],          # shore tension
	"hostel": ["track_11", "track_01"],         # dark peat + calm reprise
	"chess": ["track_12", "track_04"],          # martial + freed travel colour
	"well_defence": ["track_07", "track_06"],   # mystic defence tension
}

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _using_a: bool = true
var _area_id: String = ""
var _playlist: PackedStringArray = PackedStringArray()
var _pl_idx: int = 0
var _global_idx: int = 0
var _area_cycles: int = 0
var _fade_tw: Tween
var _current_stem: String = ""
## Radio override: when true, finished advances radio index instead of area playlist.
var _radio_mode: bool = false
var _radio_idx: int = 0

func _ready() -> void:
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	_a.name = "MusicA"
	_b.name = "MusicB"
	_a.bus = "Master"
	_b.bus = "Master"
	_a.volume_db = -80.0
	_b.volume_db = -80.0
	add_child(_a)
	add_child(_b)
	_a.finished.connect(_on_finished)
	_b.finished.connect(_on_finished)

func play_area(area_id: String) -> void:
	var key := area_id.strip_edges().to_lower()
	if key.is_empty():
		return
	# Aliases
	match key:
		"north_holy", "northholy":
			key = "north"
		"travel_road", "travelroad":
			key = "road"
		"tree_well", "tree_well_room", "well_room":
			key = "tree"
		"well", "welldefence", "defence":
			key = "well_defence"
		"warboard", "chess_board":
			key = "chess"
		"druid_yard", "hub":
			key = "yard"
	if key == _area_id and _active_player().playing and not _radio_mode:
		return
	_radio_mode = false
	_area_id = key
	_area_cycles = 0
	if AREA_PLAYLISTS.has(key):
		var arr: Array = AREA_PLAYLISTS[key]
		_playlist = PackedStringArray()
		for s in arr:
			_playlist.append(str(s))
	else:
		_playlist = GLOBAL_ORDER.duplicate()
	_pl_idx = 0
	_play_stem(_playlist[0], true)

func stop_music(fade: bool = true) -> void:
	_area_id = ""
	_playlist = PackedStringArray()
	_current_stem = ""
	_radio_mode = false
	if fade:
		_crossfade_to(null)
	else:
		_a.stop()
		_b.stop()
		_a.volume_db = -80.0
		_b.volume_db = -80.0

func set_volume_linear(v: float) -> void:
	# Hot volume tweak; next play uses TARGET_VOL still — this only scales live.
	var db := linear_to_db(clampf(v, 0.0, 1.0))
	_active_player().volume_db = db

func current_track_stem() -> String:
	return _current_stem

func current_track_label() -> String:
	if _current_stem.is_empty():
		return "—"
	return _current_stem.replace("track_", "Track ")

func radio_index() -> int:
	## 1-based track number for UI (1…20), or 0 if unknown.
	if _current_stem.begins_with("track_"):
		var n: int = int(_current_stem.substr(6))
		if n >= 1 and n <= RADIO_TRACK_COUNT:
			return n
	return _radio_idx + 1 if _radio_idx >= 0 else 0

func radio_next() -> void:
	_radio_step(1)

func radio_prev() -> void:
	_radio_step(-1)

func _radio_step(dir: int) -> void:
	## Cycle track_01…track_20; missing files skip silently (try up to 20 times).
	_radio_mode = true
	var start: int = _radio_idx
	if _current_stem.begins_with("track_"):
		var cur_n: int = int(_current_stem.substr(6))
		if cur_n >= 1 and cur_n <= RADIO_TRACK_COUNT:
			start = cur_n - 1
	var tries: int = 0
	var idx: int = start
	while tries < RADIO_TRACK_COUNT:
		idx = (idx + dir) % RADIO_TRACK_COUNT
		if idx < 0:
			idx += RADIO_TRACK_COUNT
		var stem: String = "track_%02d" % (idx + 1)
		var stream: AudioStream = _load_stream(stem)
		if stream != null:
			_radio_idx = idx
			_global_idx = idx
			_current_stem = stem
			_crossfade_to(stream)
			return
		tries += 1
	# Nothing playable — stay silent, no crash.
	push_warning("Music radio: no playable tracks in track_01…track_%02d" % RADIO_TRACK_COUNT)

func _on_finished() -> void:
	# Ignore finished from the player we just faded out (active still playing).
	if _active_player().playing:
		return
	if _radio_mode:
		_radio_step(1)
		return
	if _playlist.is_empty():
		return
	_pl_idx += 1
	if _pl_idx >= _playlist.size():
		_pl_idx = 0
		_area_cycles += 1
		# After one full area cycle, inject next global-order track so a long
		# stay still covers the full score, then resume the area playlist.
		if _area_cycles >= 1:
			_global_idx = (_global_idx + 1) % GLOBAL_ORDER.size()
			_play_stem(GLOBAL_ORDER[_global_idx], false)
			return
	_play_stem(_playlist[_pl_idx], false)

func _play_stem(stem: String, crossfade: bool) -> void:
	if stem == _current_stem and _active_player().playing:
		return
	var stream := _load_stream(stem)
	if stream == null:
		# Skip missing; try next in playlist once.
		push_warning("Music: missing %s — playing muted / skip" % stem)
		if _playlist.size() > 1:
			_pl_idx = (_pl_idx + 1) % _playlist.size()
			var alt := _load_stream(_playlist[_pl_idx])
			if alt == null:
				return
			stem = _playlist[_pl_idx]
			stream = alt
		else:
			return
	_current_stem = stem
	# Keep global / radio cursor roughly in sync when hearing a track.
	var gi: int = 0
	while gi < GLOBAL_ORDER.size():
		if GLOBAL_ORDER[gi] == stem:
			_global_idx = gi
			_radio_idx = gi
			break
		gi += 1
	if crossfade:
		_crossfade_to(stream)
	else:
		var p := _active_player()
		p.stop()
		p.stream = stream
		p.volume_db = linear_to_db(TARGET_VOL)
		p.play()

func _load_stream(stem: String) -> AudioStream:
	var ogg_path := BASE + stem + ".ogg"
	var mp3_path := BASE + stem + ".mp3"
	if ResourceLoader.exists(ogg_path):
		var s: Resource = load(ogg_path)
		if s is AudioStream:
			return s as AudioStream
	if FileAccess.file_exists(ogg_path):
		# Pre-import / editor-less: load bytes into AudioStreamOggVorbis if possible.
		var ogg := AudioStreamOggVorbis.load_from_file(ogg_path)
		if ogg != null:
			return ogg
	if ResourceLoader.exists(mp3_path):
		var s2: Resource = load(mp3_path)
		if s2 is AudioStream:
			return s2 as AudioStream
	if FileAccess.file_exists(mp3_path):
		var f := FileAccess.open(mp3_path, FileAccess.READ)
		if f:
			var data := f.get_buffer(f.get_length())
			f.close()
			var mp3 := AudioStreamMP3.new()
			mp3.data = data
			return mp3
	return null

func _active_player() -> AudioStreamPlayer:
	return _a if _using_a else _b

func _idle_player() -> AudioStreamPlayer:
	return _b if _using_a else _a

func _crossfade_to(stream: AudioStream) -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	var from_p := _active_player()
	var to_p := _idle_player()
	if stream == null:
		_fade_tw = create_tween()
		_fade_tw.tween_property(from_p, "volume_db", -80.0, FADE_SEC)
		_fade_tw.tween_callback(func() -> void: from_p.stop())
		return
	to_p.stop()
	to_p.stream = stream
	to_p.volume_db = -80.0
	to_p.play()
	_using_a = not _using_a
	_fade_tw = create_tween()
	_fade_tw.set_parallel(true)
	_fade_tw.tween_property(to_p, "volume_db", linear_to_db(TARGET_VOL), FADE_SEC)
	_fade_tw.tween_property(from_p, "volume_db", -80.0, FADE_SEC)
	_fade_tw.chain().tween_callback(func() -> void:
		from_p.stop()
		from_p.volume_db = -80.0
	)
