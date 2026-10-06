# Autoload singleton (registered as `GameState` in project.godot).
# The player's persisted profile. Phase 2 of the restructure (ADR-0001) extracts
# this state out of main.gd one cohesive slice at a time.
#
# Persistence note: main._save_profile / _load_profile stay the SINGLE writer of profile.cfg
# and read/write these fields, until the final Phase 2 slice moves persistence into
# GameState.save()/load(). One writer avoids profile-clobber during the transition.
extends Node

# --- Discovery (Phase 2b) ---
var visited := {}              # system id -> true once reached; the teleport unlock set

# --- Onboarding progress (Phase 2c) — persisted; the UPDATE loop stays in main ---
var onboarding_step := 0       # first-run guided tips: which step the player is on
var onboarding_done := {}      # set of completed beginner-quest step ids (event-latched)

# Saved per-ship body colour and finish. Booster appearance is intentionally absent.
var customization := {}

# Swappable module set per kind (ShipSystems.WEAPON_SCENES / PAD_SCENES keys).
var weapon_set := "mk1"
var pad_set := "mk1"

# Cloud coverage the player wants to fly through: 0 Off, 1 Light (default), 2 Full.
# Read by PlanetSystem._cloud_recipe() to scale a COPY of the body recipe's
# cloud_amount before it reaches the deck (CloudLayer) or the fly-through fog.
var cloud_quality := 1

# Ship tier t (1-based) unlocks once this many distinct systems beyond Sol are reached.
const SHIP_UNLOCK := [0, 1, 2, 4, 6, 9, 12, 16]

func profile_path() -> String:
	return ProfileDir.path("profile.cfg")

func systems_reached() -> int:
	return visited.size() - (1 if visited.has(SystemDB.SOL) else 0)

func ship_unlock_need(tier: int) -> int:
	return int(SHIP_UNLOCK[clampi(tier, 1, SHIP_UNLOCK.size()) - 1])

func ship_unlocked(tier: int) -> bool:
	return tier <= 1 or (tier <= SHIP_UNLOCK.size() and systems_reached() >= ship_unlock_need(tier))

# --- Persistence (Phase 2d) -------------------------------------------------------------
# GameState owns the (de)serialization of its OWN profile fields. main keeps the ConfigFile
# orchestration (it also persists ship/session keys it owns: active_quest, system, pos, ship_index).

# Keys an older save holds that this profile no longer has are ignored.
func load_from(cfg: ConfigFile) -> void:
	visited = _key_set(cfg.get_value("player", "visited", []))
	onboarding_step = int(cfg.get_value("player", "onboarding_step", 0))
	onboarding_done = _key_set(cfg.get_value("player", "onboarding_done", []))
	customization = cfg.get_value("player", "customization", {})
	cloud_quality = int(cfg.get_value("player", "cloud_quality", 1))
	weapon_set = String(cfg.get_value("player", "weapon_set", "mk1"))
	pad_set = String(cfg.get_value("player", "pad_set", "mk1"))

func save_into(cfg: ConfigFile) -> void:
	cfg.set_value("player", "visited", visited.keys())
	cfg.set_value("player", "onboarding_step", onboarding_step)
	cfg.set_value("player", "onboarding_done", onboarding_done.keys())
	cfg.set_value("player", "customization", customization)
	cfg.set_value("player", "cloud_quality", cloud_quality)
	cfg.set_value("player", "weapon_set", weapon_set)
	cfg.set_value("player", "pad_set", pad_set)

# Clear to a brand-new-game state. REQUIRED on the no-save / Reset Progress path because this
# autoload SURVIVES reload_current_scene() — its memory would otherwise keep stale values.
func reset() -> void:
	visited = {}
	onboarding_step = 0
	onboarding_done = {}
	customization = {}
	cloud_quality = 1
	weapon_set = "mk1"
	pad_set = "mk1"

static func _key_set(keys) -> Dictionary:
	var d := {}
	for k in keys:
		d[str(k)] = true
	return d
