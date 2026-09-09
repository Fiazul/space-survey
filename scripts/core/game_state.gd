# Autoload singleton (registered as `GameState` in project.godot).
# The player's persisted profile + economy. Phase 2 of the restructure (ADR-0001) extracts
# this state out of main.gd one cohesive slice at a time.
#
# Persistence note: main._save_profile / _load_profile stay the SINGLE writer of profile.cfg
# and read/write these fields, until the final Phase 2 slice moves persistence into
# GameState.save()/load(). One writer avoids profile-clobber during the transition.
extends Node

# --- Economy (Phase 2a) ---
var coins := 0                 # player currency
var claimed := {}              # body name -> true once its capture reward is claimed

# --- Discovery / navigation (Phase 2b) ---
var visited := {}              # system id -> true once reached (= DISCOVERED → free fast-travel)
var nav_unlocked := {}         # star id -> true: navigation unlocked (paid / chest-dropped)
var wormholes_found := {}      # star id -> true: this star's wormhole found by radar in the hub

# --- Onboarding progress (Phase 2c) — persisted; the UPDATE loop stays in main ---
var onboarding_step := 0       # first-run guided tips: which step the player is on
var onboarding_done := {}      # set of completed beginner-quest step ids (event-latched)

# Saved per-ship body colour and finish. Booster appearance is intentionally absent.
var customization := {}

# Cloud coverage the player wants to fly through: 0 Off, 1 Light (default), 2 Full.
# Read by PlanetSystem._cloud_recipe() to scale a COPY of the body recipe's
# cloud_amount before it reaches the deck (CloudLayer) or the fly-through fog.
var cloud_quality := 1

const CAPTURE_REWARD := 100
const ARRIVAL_REWARD := 150    # coins granted the FIRST time you reach a new system
const NAV_COST := 40           # coins to buy a navigator (map Navigate / Auto-pilot)
const NAV_UNLOCK_BASE := 80    # base coin cost to unlock navigation to a LOCKED star…
const NAV_UNLOCK_PER_LY := 9   # …plus this per light-year of real distance (far = pricey)

func add_coins(n: int) -> void:
	coins += n

# Claimable = captured (discovered) but not yet claimed.
func can_claim(body_name: String) -> bool:
	return Codex.is_discovered(body_name) and not claimed.has(body_name)

# Pure economy: grant the per-mission bounty once. Returns the bounty (0 if not claimable).
# main wraps this to add the onboarding note + persistence.
func claim_reward(body_name: String) -> int:
	if not can_claim(body_name):
		return 0
	var bounty := MissionDB.reward(body_name)
	coins += bounty
	claimed[body_name] = true
	return bounty


# --- Persistence (Phase 2d) -------------------------------------------------------------
# GameState owns the (de)serialization of its OWN profile fields. main keeps the ConfigFile
# orchestration (it also persists ship/session keys it owns: active_quest, system, pos, ship_index).

func load_from(cfg: ConfigFile) -> void:
	coins = int(cfg.get_value("player", "coins", 0))
	claimed = _key_set(cfg.get_value("player", "claimed", []))
	visited = _key_set(cfg.get_value("player", "visited", []))
	nav_unlocked = _key_set(cfg.get_value("player", "nav_unlocked", []))
	wormholes_found = _key_set(cfg.get_value("player", "wormholes_found", []))
	onboarding_step = int(cfg.get_value("player", "onboarding_step", 0))
	onboarding_done = _key_set(cfg.get_value("player", "onboarding_done", []))
	customization = cfg.get_value("player", "customization", {})
	cloud_quality = int(cfg.get_value("player", "cloud_quality", 1))

func save_into(cfg: ConfigFile) -> void:
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "claimed", claimed.keys())
	cfg.set_value("player", "visited", visited.keys())
	cfg.set_value("player", "nav_unlocked", nav_unlocked.keys())
	cfg.set_value("player", "wormholes_found", wormholes_found.keys())
	cfg.set_value("player", "onboarding_step", onboarding_step)
	cfg.set_value("player", "onboarding_done", onboarding_done.keys())
	cfg.set_value("player", "customization", customization)
	cfg.set_value("player", "cloud_quality", cloud_quality)

# Clear to a brand-new-game state. REQUIRED on the no-save / Reset Progress path because this
# autoload SURVIVES reload_current_scene() — its memory would otherwise keep stale values.
func reset() -> void:
	coins = 0
	claimed = {}
	visited = {}
	nav_unlocked = {}
	wormholes_found = {}
	onboarding_step = 0
	onboarding_done = {}
	customization = {}
	cloud_quality = 1

static func _key_set(keys) -> Dictionary:
	var d := {}
	for k in keys:
		d[str(k)] = true
	return d
