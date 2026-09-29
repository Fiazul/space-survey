class_name Onboarding
extends Node
# The GETTING STARTED beginner quest — a tiny staged guide that teaches the core loop using
# actions the player already performs (Phase 3 extraction from main.gd). Each step shows one tip;
# doing the thing advances to the next; past the last it never shows again. Persisted progress
# lives in the GameState autoload (onboarding_step / onboarding_done); this owns the step list +
# the per-frame update loop. Holds a `main` ref for the game context it observes (combat / ship /
# hud) and for persistence.

var main   # set by main right after construction

var _ob_done_toast := false   # so the "quest complete" toast fires only once
var _map_seen := false        # latched when the star map is first opened
var _log_seen := false        # latched when the mission log is first opened

# Order: core loop → travel → combat. Surfaced as the pinned top quest in the J log + on-screen tip.
var _onboard := [
	{ "id": "thrust", "title": "Take the helm",
		"tip": "Hold  W  to thrust  ·  steer with the mouse, A/D strafe, Space/Ctrl up·down" },
	{ "id": "scan", "title": "Survey a world",
		"tip": "Fly close to a planet or moon — it is surveyed into the Codex (L) automatically" },
	{ "id": "log", "title": "Open the mission log",
		"tip": "Press  J  for the MISSION LOG — every star, planet & moon is a mission" },
	{ "id": "dock", "title": "Dock at a station",
		"tip": "Approach a platform/station and press  F  to dock (swap & customise ships)" },
	{ "id": "teleport_net", "title": "Use the teleport network",
		"tip": "While docked, open the  TELEPORT NETWORK  (bottom-centre) to fast-travel" },
	{ "id": "fire", "title": "Open fire",
		"tip": "Left-click to fire — line a hostile up in the crosshair" },
]


# Spawned after the profile is loaded. The saved step is an index into whatever list shipped
# when it was written, so re-derive it from the id set before anything reads it; a finished
# quest pre-arms the toast latch so "complete" doesn't re-fire on boot.
func _ready() -> void:
	GameState.onboarding_step = resume_step()
	_ob_done_toast = GameState.onboarding_step >= _onboard.size()


func resume_step() -> int:
	for i in _onboard.size():
		if not GameState.onboarding_done.get(_onboard[i].id, false):
			return i
	return _onboard.size()


# Called by StarMap when the map is first opened (the map pauses the tree, so main._process
# can't observe map._open itself — the map notifies us instead).
func notify_map_opened() -> void:
	_map_seen = true

# Latched by QuestLog the first time the mission log is opened (drives the final onboarding tip).
func notify_log_opened() -> void:
	_log_seen = true
	note("log")


# Latch a beginner-quest step done (event-driven, so a restart can re-arm each one).
func note(id: String) -> void:
	GameState.onboarding_done[id] = true


# Restart the GETTING STARTED quest from step 1 — re-arms every step (counters re-baseline).
func restart() -> void:
	GameState.onboarding_done.clear()
	GameState.onboarding_step = 0
	_ob_done_toast = false
	main._save_profile()
	main.hud.toast = "✦  GETTING STARTED — quest restarted."
	main.hud.toast_t = 2.5


# Snapshot for the J-log questline: each step's title/tip/done plus the current index.
func state() -> Dictionary:
	var steps := []
	for i in _onboard.size():
		var s = _onboard[i]
		steps.append({ "title": s.title, "tip": s.tip,
			"done": GameState.onboarding_done.get(s.id, false), "current": i == GameState.onboarding_step })
	return { "steps": steps, "step": GameState.onboarding_step, "total": _onboard.size(),
		"complete": GameState.onboarding_step >= _onboard.size() }


# The id of the step currently being asked of the player ("" once complete). Read by main's
# objective arrow.
func current_step_id() -> String:
	if GameState.onboarding_step < _onboard.size():
		return _onboard[GameState.onboarding_step].id
	return ""


# Driven from main._process: latch action-counted steps, advance past completed ones, show the tip.
func update() -> void:
	var ship = main.ship
	var hud = main.hud
	if ship.transiting:
		hud.set_tip("")
		return
	# Live latches for the action-counted steps (re-armed on restart via the baselines).
	if ship.velocity.length() > 30.0:
		note("thrust")
	# Advance past every completed step (persist as it moves).
	var advanced := false
	while GameState.onboarding_step < _onboard.size() and GameState.onboarding_done.get(_onboard[GameState.onboarding_step].id, false):
		GameState.onboarding_step += 1
		advanced = true
	if advanced:
		main._save_profile()
	if GameState.onboarding_step >= _onboard.size():
		if not _ob_done_toast:
			_ob_done_toast = true
			hud.toast = "✦  GETTING STARTED complete. The dark is yours to chart, pilot."
			hud.toast_t = 4.0
		hud.set_tip("")
		return
	hud.set_tip("◈  GETTING STARTED  ·  " + _onboard[GameState.onboarding_step].tip)
