class_name MusicDirector
extends Node
# Two-state music director (platform ⇄ flight), spawned by main (Phase 3 extraction from
# main.gd). PLATFORM is `bgm_lobby.ogg`, the docked station/hangar backdrop — only while
# `docked`. FLIGHT is a playlist (FLIGHT_TRACKS) that plays sequentially whenever the ship is
# NOT docked (in-system or interstellar alike — that distinction no longer selects a track);
# each track plays once and the `finished` signal (the one idiomatic built-in signal this
# codebase uses, per CLAUDE.md) advances to the next, wrapping back to the first. Cross-fades
# the two states with an engine-only GAP between them, fed each frame by main:
# `update(delta, docked)`. Owns its AudioStreamPlayers and ducks the engine (GameAudio
# autoload) under the flight track. Playlist-ordering math lives in MusicPlaylist
# (autoload-free, see tools/test_music_director.gd) since this script can't compile
# under `--script` (it touches the GameAudio autoload).

const FLIGHT_TRACKS := [
	"res://assets/bgm.ogg",
	"res://assets/bgm_flight_2.ogg",
	"res://assets/bgm_flight_3.ogg",
]

var _music: AudioStreamPlayer          # current FLIGHT playlist track
var _flight_streams: Array[AudioStream] = []
var _flight_idx := 0                   # persists across dock/undock — resumes mid-track
var _music_platform: AudioStreamPlayer # the PLATFORM / docked track (bgm_lobby.ogg)

const FLIGHT_DB := -13.0    # flight-track level once faded in
const PLATFORM_DB := -18.0  # platform-track level — a comfortable backdrop the engine sits over
const MUSIC_OFF_DB := -60.0  # silent end of either fade
const MUSIC_GAP := 1.8       # engine-only silence between platform and flight (seconds)
const WANT_DWELL := 0.4      # boundary debounce before committing a track switch
const PLATFORM_FADE_OUT := 0.6  # platform-track fade-out
const FLIGHT_FADE_OUT := 0.6     # flight-track fade-out
const MUSIC_FADE_IN := 0.7   # incoming fade speed — slow, cinematic swell
const FLIGHT_ENGINE_DUCK_DB := 10.0  # dB the engine recedes once flight music is up
var _cur_track := "flight"        # "platform" | "flight" — game starts undocked
var _xfade_phase := "fadein"      # start by swelling the flight track in at launch
var _gap_t := 0.0                  # remaining engine-only gap (seconds)
var _want_dwell := 0.0             # how long the wanted track has differed from _cur_track


func _ready() -> void:
	# OGG Vorbis, not MP3: MP3 padding leaves an audible loop gap; Vorbis loops seamlessly
	# (only PLATFORM loops — flight tracks play once each and hand off via `finished`).
	for path in MusicPlaylist.filter_existing(FLIGHT_TRACKS):
		var stream := _load_music(path, false)
		if stream != null:
			_flight_streams.append(stream)

	if not _flight_streams.is_empty():
		_music = AudioStreamPlayer.new()
		_music.stream = _flight_streams[_flight_idx]
		_music.volume_db = MUSIC_OFF_DB
		_music.bus = "Master"
		# PROCESS_MODE_ALWAYS: keep playing through a paused tree (HUD edit mode pauses via
		# `get_tree().paused = true`, hud.gd:650) so opening that overlay never cuts the music.
		_music.process_mode = Node.PROCESS_MODE_ALWAYS
		_music.finished.connect(_on_flight_finished)
		add_child(_music)
		_music.play()
		_music.stream_paused = false   # game starts undocked → the state machine swells this in
		print("music: %d flight tracks" % _flight_streams.size())

	var platform := _load_music("res://assets/bgm_lobby.ogg", true)
	if platform != null:
		_music_platform = AudioStreamPlayer.new()
		_music_platform.stream = platform
		_music_platform.volume_db = MUSIC_OFF_DB
		_music_platform.bus = "Master"
		_music_platform.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_platform)
		_music_platform.play()
		_music_platform.stream_paused = true


# A flight track plays once (loop = false). When it ends, advance to the next playlist entry
# (wrapping — a single-track playlist just replays itself) and hand off with no gap: leave
# volume wherever the active cross-fade phase already had it, so back-to-back tracks play at
# the same level instead of dipping through MUSIC_OFF_DB and un-ducking the engine.
func _on_flight_finished() -> void:
	if _flight_streams.is_empty():
		return
	_flight_idx = MusicPlaylist.next_index(_flight_idx, _flight_streams.size())
	_music.stream = _flight_streams[_flight_idx]
	_music.play()


# Driven from main._process. docked = is the ship parked at a station platform right now.
# Cross-fades with an engine-only gap at the platform⇄flight boundary.
func update(delta: float, docked: bool) -> void:
	if _music == null and _music_platform == null:
		return

	var want := "platform" if docked else "flight"
	# Debounce the boundary: dock state can flicker right at the edge, so only treat a
	# differing want as real once it has persisted for WANT_DWELL.
	if want != _cur_track:
		_want_dwell += delta
	else:
		_want_dwell = 0.0

	match _xfade_phase:
		"steady":
			_fade_track(_cur_track, _target_db_for(_cur_track), MUSIC_FADE_IN, delta)
			if want != _cur_track and _want_dwell >= WANT_DWELL:
				_xfade_phase = "fadeout"
		"fadeout":
			# If the player ducked back before we finished, just swell the current track again.
			if want == _cur_track:
				_xfade_phase = "fadein"
			else:
				var out_rate := FLIGHT_FADE_OUT if _cur_track == "flight" else PLATFORM_FADE_OUT
				_fade_track(_cur_track, MUSIC_OFF_DB, out_rate, delta)
				var cur_player := _player_for(_cur_track)
				if cur_player == null or cur_player.volume_db <= MUSIC_OFF_DB + 1.0:
					if cur_player != null:
						cur_player.stream_paused = true
					_gap_t = MUSIC_GAP
					_xfade_phase = "gap"
		"gap":
			# Both tracks silent — only the engine is heard across this brief window.
			_gap_t -= delta
			if _gap_t <= 0.0:
				_cur_track = want   # commit to whatever's wanted now (handles a flip mid-gap)
				_ready_track(_cur_track)
				_xfade_phase = "fadein"
		"fadein":
			if want != _cur_track and _want_dwell >= WANT_DWELL:
				_xfade_phase = "fadeout"
			else:
				_fade_track(_cur_track, _target_db_for(_cur_track), MUSIC_FADE_IN, delta)
				var p := _player_for(_cur_track)
				if p != null and p.volume_db >= _target_db_for(_cur_track) - 0.5:
					_xfade_phase = "steady"

	# Duck the engine under the flight music, scaled by how present that track is (0 when
	# silent — incl. the engine-only gap and when no flight tracks loaded — full once faded in).
	var flight_presence := 0.0
	if _music != null:
		flight_presence = clampf(inverse_lerp(MUSIC_OFF_DB, FLIGHT_DB, _music.volume_db), 0.0, 1.0)
	GameAudio.set_engine_duck(FLIGHT_ENGINE_DUCK_DB * flight_presence)


func _player_for(track: String) -> AudioStreamPlayer:
	return _music_platform if track == "platform" else _music


func _target_db_for(track: String) -> float:
	return PLATFORM_DB if track == "platform" else FLIGHT_DB


# Unpause/restart a track from silence so it can fade in cleanly.
func _ready_track(track: String) -> void:
	var p := _player_for(track)
	if p == null:
		return
	p.volume_db = MUSIC_OFF_DB
	p.stream_paused = false
	if not p.playing:
		p.play()


# Ease a track's volume toward a target; unpause it if it needs to be heard.
func _fade_track(track: String, target_db: float, rate: float, delta: float) -> void:
	var p := _player_for(track)
	if p == null:
		return
	if target_db > MUSIC_OFF_DB and p.stream_paused:
		p.stream_paused = false
		if not p.playing:
			p.play()
	p.volume_db = lerpf(p.volume_db, target_db, clampf(rate * delta, 0.0, 1.0))


# Load a bgm track (null if the file is missing). `seamless_loop` flags it to loop with no
# gap (PLATFORM only) — flight-playlist tracks play once and hand off via `finished`.
func _load_music(path: String, seamless_loop: bool) -> AudioStream:
	var stream := load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = seamless_loop
	return stream
