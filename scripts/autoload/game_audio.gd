# Autoload singleton (registered as `GameAudio` in project.godot) — reach it from any
# module as `GameAudio.play_x()`; no injection needed. (class_name dropped per ADR-0001.)
extends Node
# Code-spawned SFX, same spirit as everything else in Cold Light: rapid laser fire
# (pooled so shots overlap), a "crush" boom on alien death, and a three-part
# engine voice (start -> seamless loop -> stop) that the ship drives every frame.

const _FM := preload("res://scripts/flight/flight_mode.gd")

const FIRE_VOICES := 8          # round-robin players so rapid shots overlap cleanly
const FIRE_DB := -19.0          # bullet fire — gentle/soft
const EXPLOSION_DB := -3.0
const LASER_DB := -14.0         # continuous beam hum — present but not harsh
const CLICK_DB := -12.0         # soft UI click
const PICKUP_DB := -17.0        # energy-cell grab — short, low, unobtrusive
const TELEPORT_DB := -6.0       # teleport "voooouuu" whoosh — prominent

# --- Engine voice ---
# Mix intent: the engine is present and has weight, but the music still leads.
# Cruise sits just above the bgm (≈ -24 dB) so you clearly feel the engine; Shift
# opens it up into a powerful roar. Gunfire still punches over everything.
const ENGINE_LOOP_DB := -23.0   # cruise — present but gentle; the bgm is the star
const ENGINE_QUIET_DB := -34.0  # barely on the gas — quiet idle
const ENGINE_BOOST_DB := 7.0    # Shift = a noticeable surge (peak still tasteful)
const ENGINE_OFF_DB := -60.0    # effectively silent (loop fades here, then pauses)
const ENGINE_TRANS_DB := -19.0  # the one-shot start/stop "whoosh" — soft
# Pitch shapes the character. Normal flight sits LOW/deep; Shift revs it UP into a
# faster, higher note (and we smooth harder so it glides in rather than snapping).
const ENGINE_PITCH_IDLE := 0.82
const ENGINE_PITCH_FULL := 0.92
const ENGINE_PITCH_BOOST := 1.10
# Slow eases so the engine swells in/out gently — never a sudden, jarring change.
const ENGINE_SMOOTH := 4.5      # normal ease toward target volume/pitch (per second)
const ENGINE_SMOOTH_BOOST := 2.5  # gentler ease while boosting -> "even smoother"
# Continuous-drive clock: climbs while driving, unwinds when you ease off (no hard reset,
# so a brief coast doesn't restart it). It now only shapes the engine's pitch SPOOL — the
# old music duck/crossover is gone; music is a state machine in main.gd and the engine just
# layers beneath it, never ducking out (per the audio rules).
const DRIVE_MAX := 20.0             # clock cap (seconds)
const DRIVE_DECAY := 2.0            # how fast the clock unwinds when you let off
const ENGINE_SPOOL_TIME := 12.0     # pitch spools up to its cruise note over this long
const ENGINE_SUSTAIN_PITCH := 0.12  # pitch climbed at full cruise (×pitch_mul per ship)

# --- Air entry wind / rumble ---
# Both loops are procedural PCM (no asset file) so the whole entry-feel pass ships
# without new binary assets. Driven by FlightMode.air_load / Ship.mach_number through a
# LOG mapping (see _log_db_for/wind_db_for/rumble_db_for below), NOT a raw linear clamp.
# A linear map over air_load's full [0,1] range was wrong at both ends: a linear map
# compresses small-but-real values into a fraction of a dB near the OFF floor
# (inaudible), while a DEV tool (F9 thrust and/or FASTAIR drag) saturates air_load to ~1
# almost immediately, pinning the old law at its loudest setting — which was LOUDER than
# the engine's own boost peak (2026-09-09 "air sound too loud" report). air_load == 0
# (vacuum) still means both sit at their OFF floor and stop, same rule as every other
# entry-FX.
#
# 2026-09-12: the onset/full LOAD anchors below are DERIVED from FlightMode's own
# air_load curve (FlightMode.load_at_sea_level / AIR_LOAD_TARGET_FRAC) at a named
# reference speed, not hand-picked — so a future move of FlightMode.AIR_TERMINAL_KMS
# (the drag-rescale target, docs/ROADMAP.md L.3) can't silently strand these at a stale
# calibration again. That's exactly what happened once already: these were hand-picked
# for a 12 km/s target (0.0158/0.0058), then AIR_TERMINAL_KMS moved to 50 km/s and both
# anchors were quietly ~17x too loud for their actual reference speed until this pass.
# _RHO0 mirrors ephemeris.gd's RHO0 (not read off the Ephemeris autoload directly) so
# this file stays autoload-free / preloadable under --script, same convention every
# tools/test_*.gd file already uses for the same reason. The dB targets/caps below are
# unchanged — they're a perceptual choice independent of the physics scale.
const _RHO0 := 1.225   # ephemeris.gd:62, kg/m^3 at sea level

const AIR_WIND_OFF_DB := -60.0        # inaudible floor (matches ENGINE_OFF_DB's silence rule)
# Onset reference speed: a light cruise, not yet a dive; "just audible" should start
# becoming noticeable here. AIR_WIND_ONSET_LOAD is FlightMode.air_load at this speed,
# sea level — a static var (not const) because it calls a function, computed once at
# script load.
const AIR_WIND_ONSET_KMS := 1.0
static var AIR_WIND_ONSET_LOAD: float = _FM.load_at_sea_level(AIR_WIND_ONSET_KMS, _RHO0)
const AIR_WIND_ONSET_DB := -40.0      # "just audible" hint of wind, not a wash
# Dive reference: boosted sea-level equilibrium. FlightMode.air_load lands EXACTLY at
# AIR_LOAD_TARGET_FRAC there BY CONSTRUCTION (air_load_q_ref is solved for that), so this
# is not a second number to re-derive — it's the loudest air_load an ordinary
# Shift-boost dive settles into, without any DEV tool.
const AIR_WIND_FULL_LOAD := _FM.AIR_LOAD_TARGET_FRAC
# The engine's own loudest moment is ENGINE_LOOP_DB + ENGINE_BOOST_DB = -16 dB (boosting,
# see the engine block above). Wind must stay >=6 dB under that so the engine roar always
# reads as the loudest layer even mid-dive-boost - that puts the cap at -22, not the -18
# a first guess assumed before checking the actual engine peak in this file.
const AIR_WIND_MAX_DB := -22.0
# Below onset, wind fades to the OFF floor over this many decades of air_load (log10
# units) instead of a hard on/off snap - shared by both wind and rumble's floor segment.
const AIR_FADE_DECADES := 0.6

const AIR_RUMBLE_OFF_DB := -60.0
# Rumble is gated by air_load * mach_frac - it is the "diving HARD in air" layer, not
# felt from air presence alone - so its onset/full references are taken from that same
# product, at the SAME reference speed as the wind onset above (AIR_WIND_ONSET_KMS) for
# onset, and the same boosted sea-level equilibrium for full.
static var AIR_RUMBLE_ONSET_LOAD: float = AIR_WIND_ONSET_LOAD * clampf(_FM.mach(AIR_WIND_ONSET_KMS) / 8.0, 0.0, 1.0)
const AIR_RUMBLE_ONSET_DB := -42.0
# mach_frac is already ~1.0 well before boosted sea-level equilibrium (mach/8 clamps out
# long before AIR_TERMINAL_KMS is reached), so rumble's full reference is the same
# AIR_LOAD_TARGET_FRAC as wind's.
const AIR_RUMBLE_FULL_LOAD := _FM.AIR_LOAD_TARGET_FRAC
# A few dB under the wind cap so rumble reads as an undertone beneath the wind layer
# rather than competing with it (mirrors the old -13 vs -9 relative gap).
const AIR_RUMBLE_MAX_DB := -26.0
const AIR_SMOOTH := 3.0   # dB glide rate per second toward whichever target above

var _fire: Array[AudioStreamPlayer] = []
var _fire_i := 0
var _explosion: AudioStreamPlayer
var _laser_loop: AudioStreamPlayer
var _laser_on := false
var _click: AudioStreamPlayer
var _teleport: AudioStreamPlayer  # teleport "voooouuu" whoosh
var _notify: AudioStreamPlayer    # tutorial notification "ting-tong"
var _reward: AudioStreamPlayer    # capture-reward "happy" fanfare
var _pickup: AudioStreamPlayer   # short low blip for grabbing an energy cell

var _eng_loop: AudioStreamPlayer
var _eng_start: AudioStreamPlayer
var _eng_stop: AudioStreamPlayer
var _eng_on := false            # is the engine currently "running" (loop active)?
var _eng_default: AudioStream   # shared authored-ship engine loop
var _eng_sustain := 0.0         # seconds of continuous driving (drives cruise settle)
var _engine_duck_db := 0.0      # dB the engine is pulled back (set by main while ship music is up)

var _air_wind: AudioStreamPlayer
var _air_rumble: AudioStreamPlayer


# Pull the engine back under the interstellar ship music. Main feeds this each frame,
# scaled by how present the ship track is, so the engine eases down/up with the music
# (and stays full during the engine-only gap, when the ship track is silent).
func set_engine_duck(db: float) -> void:
	_engine_duck_db = maxf(db, 0.0)


const MASTER_DB := 4.0   # slight overall lift on everything (all audio routes here)

func _ready() -> void:
	# Nudge the whole mix up a touch — music, engine and SFX all sit on Master.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), MASTER_DB)
	var fire_stream := load("res://assets/sfx_fire.wav") as AudioStream
	for i in FIRE_VOICES:
		var p := AudioStreamPlayer.new()
		p.stream = fire_stream
		p.volume_db = FIRE_DB
		add_child(p)
		_fire.append(p)

	_explosion = AudioStreamPlayer.new()
	_explosion.stream = load("res://assets/sfx_explosion.mp3") as AudioStream
	_explosion.volume_db = EXPLOSION_DB
	add_child(_explosion)

	# Engine: a looping body bookended by one-shot start/stop transients.
	_eng_default = _load_loop("res://assets/engine_loop.ogg")
	_eng_loop = AudioStreamPlayer.new()
	_eng_loop.stream = _eng_default
	_eng_loop.volume_db = ENGINE_OFF_DB
	add_child(_eng_loop)

	_eng_start = AudioStreamPlayer.new()
	_eng_start.stream = load("res://assets/engine_start.ogg") as AudioStream
	_eng_start.volume_db = ENGINE_TRANS_DB
	add_child(_eng_start)

	_eng_stop = AudioStreamPlayer.new()
	_eng_stop.stream = load("res://assets/engine_stop.ogg") as AudioStream
	_eng_stop.volume_db = ENGINE_TRANS_DB
	add_child(_eng_stop)

	# Soft UI click for menus/buttons.
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/ui_click.wav") as AudioStream
	_click.volume_db = CLICK_DB
	add_child(_click)

	# Teleport whoosh ("voooouuu") — played when the teleport ritual begins.
	_teleport = AudioStreamPlayer.new()
	_teleport.stream = load("res://assets/teleport.wav") as AudioStream
	_teleport.volume_db = TELEPORT_DB
	add_child(_teleport)

	# Tutorial notification chime ("ting-tong").
	_notify = AudioStreamPlayer.new()
	_notify.stream = load("res://assets/notify.wav") as AudioStream
	_notify.volume_db = CLICK_DB
	add_child(_notify)

	# Capture-reward fanfare ("happy" rising arpeggio).
	_reward = AudioStreamPlayer.new()
	_reward.stream = load("res://assets/reward.wav") as AudioStream
	_reward.volume_db = -4.0
	add_child(_reward)

	# Energy-cell grab: a tiny synthesized blip (low, short) — no asset needed.
	_pickup = AudioStreamPlayer.new()
	_pickup.stream = _make_blip()
	_pickup.volume_db = PICKUP_DB
	add_child(_pickup)

	# Laser beam: a seamless looping hum, played only while the beam is firing.
	_laser_loop = AudioStreamPlayer.new()
	var ls := load("res://assets/laser_loop.wav")
	if ls is AudioStreamWAV:
		(ls as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(ls as AudioStreamWAV).loop_end = (ls as AudioStreamWAV).data.size() / 2   # 16-bit mono
	_laser_loop.stream = ls
	_laser_loop.volume_db = LASER_DB
	add_child(_laser_loop)

	_air_wind = AudioStreamPlayer.new()
	_air_wind.stream = _make_wind_noise()
	_air_wind.volume_db = AIR_WIND_OFF_DB
	add_child(_air_wind)

	_air_rumble = AudioStreamPlayer.new()
	_air_rumble.stream = _make_rumble()
	_air_rumble.volume_db = AIR_RUMBLE_OFF_DB
	add_child(_air_rumble)


# Load an OGG and flag it as looping (no-op / null if the file is missing).
func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true   # seamless continuous loop
	return s


# Engine voice, driven by the ship every frame.
#   thrusting : is the player on the gas (any thrust input)?
#   intensity : 0..1 throttle (how hard) — shapes cruise volume + pitch
#   boost     : Shift held — louder, revved up higher/faster, eased in smoothly
#   pitch_mul : per-ship pitch nudge layered on top of the distinct loop
# Plays a one-shot "start" whoosh on the rising edge, a "stop" whoosh on release,
# and crossfades the continuous loop in between.
func update_engine(_ship_name: String, thrusting: bool, intensity: float, boost: bool, pitch_mul: float, delta: float) -> void:
	intensity = clampf(intensity, 0.0, 1.0)

	if thrusting and not _eng_on:
		_eng_on = true
		_eng_start.pitch_scale = pitch_mul
		_eng_start.play()
		if not _eng_loop.playing:
			_eng_loop.play()
	elif not thrusting and _eng_on:
		_eng_on = false
		_eng_stop.pitch_scale = pitch_mul
		_eng_stop.play()

	# Continuous-drive clock: climbs while driving, unwinds when you ease off.
	if _eng_on:
		_eng_sustain = minf(_eng_sustain + delta, DRIVE_MAX)
	else:
		_eng_sustain = maxf(_eng_sustain - delta * DRIVE_DECAY, 0.0)
	# Pitch spools up over the first ~12s of a steady run (character only — volume no longer
	# ducks for the music; the engine just layers under whichever track is up, see main.gd).
	var spool := smoothstep(0.0, ENGINE_SPOOL_TIME, _eng_sustain)

	# Targets: silent when off; otherwise volume tracks throttle, boost adds punch.
	var target_db := ENGINE_OFF_DB
	var target_pitch := ENGINE_PITCH_IDLE
	if _eng_on:
		target_db = lerpf(ENGINE_QUIET_DB, ENGINE_LOOP_DB, intensity)
		target_pitch = lerpf(ENGINE_PITCH_IDLE, ENGINE_PITCH_FULL, intensity)
		if boost:
			target_db += ENGINE_BOOST_DB
			target_pitch = ENGINE_PITCH_BOOST   # revved up — faster, higher
		else:
			target_pitch += ENGINE_SUSTAIN_PITCH * spool   # cruise spools pitch up a touch
		# State-driven duck: main pulls the engine back under the interstellar ship music
		# (0 while the lobby track is up, so the engine stays present in local flight).
		target_db -= _engine_duck_db
	target_pitch *= pitch_mul

	# Ease toward the targets; boost uses a gentler rate for that smooth swell.
	var rate := ENGINE_SMOOTH_BOOST if boost else ENGINE_SMOOTH
	var k := clampf(rate * delta, 0.0, 1.0)
	_eng_loop.volume_db = lerpf(_eng_loop.volume_db, target_db, k)
	_eng_loop.pitch_scale = lerpf(_eng_loop.pitch_scale, target_pitch, k)

	# Once fully faded out and idle, pause the loop to save a voice.
	if not _eng_on and _eng_loop.playing and _eng_loop.volume_db <= ENGINE_OFF_DB + 1.0:
		_eng_loop.stop()


# Seconds of continuous driving so far (0 when stopped/docked). Now only feeds the
# engine's own cruise pitch-spool (the music no longer reads it).
func drive_time() -> float:
	return _eng_sustain


# Hard-silence the engine immediately (docked / wormhole transit). Also clears the
# drive clock, so the music + cruise arc restart fresh next time you fly out.
func engine_off() -> void:
	_eng_on = false
	_eng_sustain = 0.0
	_eng_loop.volume_db = ENGINE_OFF_DB
	if _eng_loop.playing:
		_eng_loop.stop()


# A laser shot — round-robins voices so rapid shots never cut each other off.
func play_fire() -> void:
	var p := _fire[_fire_i]
	_fire_i = (_fire_i + 1) % _fire.size()
	p.pitch_scale = randf_range(0.82, 0.92)   # lower pitch reads softer/gentler
	p.play()


# Alien destroyed — the "crush" boom.
func play_explosion() -> void:
	_explosion.pitch_scale = randf_range(0.9, 1.06)
	_explosion.play()


# Soft UI click for buttons/menus (slight pitch variance so repeats don't feel robotic).
func play_click() -> void:
	if _click != null:
		_click.pitch_scale = randf_range(0.96, 1.06)
		_click.play()


# Teleport "voooouuu" whoosh — played at the start of the ritual; main fades its volume
# in then out across the teleport with set_teleport_db(), and stops it on arrival/cancel.
func play_teleport() -> void:
	if _teleport != null:
		_teleport.play()


func set_teleport_db(db: float) -> void:
	if _teleport != null:
		_teleport.volume_db = db


func stop_teleport() -> void:
	if _teleport != null:
		_teleport.stop()


# Soft "ting-tong" chime when a tutorial notification appears.
func play_notify() -> void:
	if _notify != null:
		_notify.play()


# Happy rising fanfare when you capture a body.
func play_reward() -> void:
	if _reward != null:
		_reward.play()


# Short, low "blip" for grabbing an energy cell — quieter and deeper than the UI click.
func play_pickup() -> void:
	if _pickup != null:
		_pickup.pitch_scale = randf_range(0.94, 1.02)
		_pickup.play()


# Broadband hiss (one-pole low-passed white noise) - reads as wind, not static. 2s
# loop; noise camouflages the seam, no crossfade needed.
func _make_wind_noise() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4177
	var lp := 0.0
	for i in n:
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.12
		data.encode_s16(i * 2, int(clampf(lp * 2.2, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav


# Low double-sine rumble for a hard dive. 42 Hz / 67 Hz over exactly 2.0s both land on
# a whole number of cycles (84 / 134), so the loop is genuinely seamless - no click.
func _make_rumble() -> AudioStreamWAV:
	var rate := 22050
	var dur := 2.0
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var s := sin(TAU * 42.0 * t) * 0.6 + sin(TAU * 67.0 * t) * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav


# Log-mapped dB for a physics scalar `x` (air_load, or air_load*mach_frac for rumble)
# given a cruise-audible onset point and a maxed-out "full" point, both in the same
# units as x. Linear in log10(x) between onset and full; fades to off_db over
# `decades` below onset; clamps flat at full_db beyond full. Never louder than
# full_db, never quieter than off_db, monotonic in x by construction — this is the
# one perceptual-mapping law both air layers (and any future physics-driven audio
# parameter in this file) should route through instead of a raw linear clamp.
static func _log_db_for(x: float, onset: float, full: float, onset_db: float,
		full_db: float, off_db: float, decades: float) -> float:
	var v := maxf(x, 0.0)
	if v <= 0.0:
		return off_db
	var floor_load := onset / pow(10.0, decades)
	var l := log(v) / log(10.0)
	var l_floor := log(floor_load) / log(10.0)
	var l_onset := log(onset) / log(10.0)
	var l_full := log(full) / log(10.0)
	if l <= l_floor:
		return off_db
	if l >= l_full:
		return full_db
	if l <= l_onset:
		return lerpf(off_db, onset_db, (l - l_floor) / (l_onset - l_floor))
	return lerpf(onset_db, full_db, (l - l_onset) / (l_full - l_onset))


# Wind loop target dB for a given FlightMode.air_load (see the AIR_WIND_* reference
# constants above). Static + pure so it is unit-testable without the autoload's node
# tree — tools/test_air_audio.gd preloads this script and calls it directly.
static func wind_db_for(air_load: float) -> float:
	return _log_db_for(air_load, AIR_WIND_ONSET_LOAD, AIR_WIND_FULL_LOAD,
		AIR_WIND_ONSET_DB, AIR_WIND_MAX_DB, AIR_WIND_OFF_DB, AIR_FADE_DECADES)


# Rumble loop target dB for air_load * mach_frac (mach capped the same way this file
# always has: mach/8, clamped 0..1 — a generous ceiling above anything Sol newton
# flight reaches without a DEV tool). See the AIR_RUMBLE_* reference constants above.
static func rumble_db_for(air_load: float, mach: float) -> float:
	var mach_frac := clampf(mach / 8.0, 0.0, 1.0)
	var p := air_load * mach_frac
	return _log_db_for(p, AIR_RUMBLE_ONSET_LOAD, AIR_RUMBLE_FULL_LOAD,
		AIR_RUMBLE_ONSET_DB, AIR_RUMBLE_MAX_DB, AIR_RUMBLE_OFF_DB, AIR_FADE_DECADES)


# Called next to update_engine, every fly() frame. air_load 0 (vacuum) settles both
# loops back to their OFF floor and stops them - real silence, not just quiet. Both
# targets - and the play/stop gate itself - are driven off the SAME log law above,
# not a second raw-scalar threshold (that was the same category of bug: a bare
# air_load > 0.02 gate never once fired in controlled flight, since air_load tops
# out at 0.0044 there — the loops literally never started playing).
func update_air(air_load: float, mach: float, delta: float) -> void:
	if _air_wind == null or _air_rumble == null:
		return
	var mach_frac := clampf(mach / 8.0, 0.0, 1.0)
	var k := clampf(AIR_SMOOTH * delta, 0.0, 1.0)

	var wind_target := wind_db_for(air_load)
	_air_wind.volume_db = lerpf(_air_wind.volume_db, wind_target, k)
	_air_wind.pitch_scale = clampf(lerpf(0.85, 1.35, mach_frac), 0.85, 1.35)
	if wind_target > AIR_WIND_OFF_DB + 1.0 and not _air_wind.playing:
		_air_wind.play()
	elif wind_target <= AIR_WIND_OFF_DB + 1.0 and _air_wind.playing \
			and _air_wind.volume_db <= AIR_WIND_OFF_DB + 1.0:
		_air_wind.stop()

	# Diving hard IN the air (both air present and speed high) - not a vacuum groan.
	var rumble_target := rumble_db_for(air_load, mach)
	_air_rumble.volume_db = lerpf(_air_rumble.volume_db, rumble_target, k)
	if rumble_target > AIR_RUMBLE_OFF_DB + 1.0 and not _air_rumble.playing:
		_air_rumble.play()
	elif rumble_target <= AIR_RUMBLE_OFF_DB + 1.0 and _air_rumble.playing \
			and _air_rumble.volume_db <= AIR_RUMBLE_OFF_DB + 1.0:
		_air_rumble.stop()


# Build a ~70 ms low sine blip with a fast decay (no external asset). A slight downward
# pitch sweep gives it a soft "boop" that reads as "absorbed" rather than a sharp click.
func _make_blip() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.07
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 40.0)                 # fast decay → short
		var freq := 200.0 - 70.0 * (t / dur)      # gentle downward sweep → low + soft
		var s := sin(TAU * freq * t) * env * 0.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


# Laser beam on/off — start/stop the seamless looping hum (called each frame by combat).
func laser(on: bool) -> void:
	if _laser_loop == null or on == _laser_on:
		return
	_laser_on = on
	if on:
		_laser_loop.play()
	else:
		_laser_loop.stop()
