extends Node3D
# Space Explorer — root orchestrator.
#
# Everything is spawned from code (the .tscn is a one-node stub) and wired with
# plain references — no @export drag-and-drop, so it just works on open.
#
# Floating origin: the Ship node stays pinned at (0,0,0) and only rotates. Its
# "true" position is tracked as data (ship.true_pos). Every body is rendered at
# (body.true_pos - ship.true_pos), and the starfield is a fixed backdrop on the
# world root (NOT a child of the ship), so it doesn't spin with the ship.
#
# Update order matters and is driven explicitly here: the ship integrates its
# motion first, then the planet system reads the fresh true_pos, then the HUD.

var ship: Ship
var galaxy: GalaxyModel              # the Milky Way backdrop; loomed toward the core on the voyage
var planets: PlanetSystem
var props: Props
var hud: HUD
@onready var eph := Ephemeris   # autoload (alias so main.eph accessors still work)
var wormhole: Wormhole
var combat: Combat
@onready var audio := GameAudio   # autoload (kept as alias so main.audio accessors still work)
var settings: SettingsMenu
var map: StarMap
var platform_tp: PlatformTeleport   # isolated platform fast-travel console (not the star map)
var tutor: Tutor                    # new-game onboarding tip notifications
var reward_card: RewardCard         # capture celebration card (auto-reward + fade-out)
var _fresh_game := false            # true when there was no save → start the tutorial
var quest_log: QuestLog
@onready var planet_data := PlanetData   # autoload
var planet_info: PlanetInfo
var navigator: Navigator
var minimap: MiniMap
@onready var codex := Codex   # autoload (alias so main.codex accessors still work)
var _nav_target := ""         # Tab target: the object the aim ray passes nearest to
var _tab_index := -1          # which of the 4 ray-closest targets is selected (Tab cycles)
var _tab_aim := Vector3.ZERO  # nose dir at the last Tab — moving the cursor restarts the cycle
var _nav_wormhole := ""       # when the Tab target is a wormhole, which portal (dest id) it is
var _locked_wh := ""          # which portal a LOCKED wormhole points to (snapshot at lock time)
var _aim_wh_dest := ""        # dest of the portal the ray is nearest to (set in _aim_ranked)
var _x_hold := 0.0            # seconds X has been held — ≥1s LOCKS the Tab target (orange)
var _x_fired := false
var _nav_locked := ""         # LOCKED map waypoint (orange) — persists until cancelled
# Player-placed X marks: up to 3 at once, each its own colour. HOLD X marks the current Tab
# target (toggle the same one off). Session/system-local — cleared when you change systems.
# Each entry: { name: String, wh: String } (wh = portal dest when the mark is a wormhole).
var _marks: Array = []
const MARK_MAX := 3
const MARK_COLS := [           # one colour per X-mark slot, by order placed
	Color(0.30, 0.85, 1.00),   # cyan
	Color(1.00, 0.84, 0.30),   # gold
	Color(0.45, 1.00, 0.50),   # green
]
const QUEST_COL := Color(0.78, 0.50, 1.00)   # purple — the tracked-quest marker
# coins + claimed moved to the GameState autoload (Phase 2a). main reads GameState.coins /
# GameState.claimed; persistence below still reads/writes them (single writer for now).
# visited / nav_unlocked / wormholes_found moved to the GameState autoload (Phase 2b).
# main reads GameState.visited / .nav_unlocked / .wormholes_found.
var _nav_goal := ""           # star the map asked to guide to (orange waypoint). The guide
							  #   resolves the next hop each frame: in the hub → that star's
							  #   wormhole; in a system → the exit gate. Session-only (not saved).
# onboarding_step + the onboarding-done set moved to GameState (Phase 2c) as
# GameState.onboarding_step / GameState.onboarding_done.
# GETTING STARTED beginner quest extracted to the Onboarding controller (Phase 3).
var onboarding: Onboarding
const PROFILE_PATH := "user://profile.cfg"
# Economy consts moved to GameState (Phase 2a): CAPTURE_REWARD, ARRIVAL_REWARD, NAV_COST,
# NAV_UNLOCK_BASE, NAV_UNLOCK_PER_LY — reference as GameState.NAV_COST etc.
const WORMHOLE_RADAR := 750.0 # hub range at which your radar finds an undiscovered wormhole

# Missions are per-body now (MissionDB + QuestLog, key J): every star/planet/moon is a
# mission you complete by surveying it. The top-center tracker shows the nearest unsurveyed
# body in the current system; the full board is the J log.
# The TRACKED quest: a body name you chose to chase from the Mission Log (J). It's the single
# source of truth for quest guidance — the nav arrow routes to it (cross-system via wormholes,
# then to the body in-system) until you survey it, then it auto-advances to the next unsurveyed
# body in the system (or clears when the system's done). Persisted. Mutually exclusive with the
# map's _nav_goal / paid _nav_locked (each setter clears the others).
var _active_quest := ""
var _nav_off := false         # NAV button: stop the Survey guide + waypoint marker entirely
var _was_boost_blocked := false   # edge-trigger for the "boost unavailable" toast
var _touch := false               # touch/mobile input mode (no mouse capture) — set in _ready
var touch_controls: Node          # on-screen controls overlay (mobile only)
var _perf_on := false             # F3 perf/leak readout
var _perf_t := 0.0                # throttle for the perf text update
# Restored on boot: where you left off (system + position + active hull). See _restore_location.
var _saved_system := ""
var _saved_pos := Vector3.ZERO
var _has_saved_pos := false
var _saved_ship_index := -1
var _autosave_t := 5.0            # periodic position autosave (also guards against the crash)
var _scan := 0.0             # scan progress 0..1 of the nearest body
var _last_waves_cleared := 0 # last guardian wave count we announced (for the "Wave k/N" toast)
var _scan_name := ""
const SCAN_SECONDS := 3.0     # capture takes a beat longer so the ritual reads + feels earned
const SCAN_RANGE := 1500.0    # how close you must be to start a capture (generous)
const STAR_APPROACH_RANGE := 6000.0  # in the hub, flying within this of a real star drops you into
									 # its LOCAL frame (small coords) so the last stretch is flyable
const GUARD_RANGE := 2500.0   # approach a guarded body within this → its guardians activate
const GUARD_COUNT := 5        # guardian aliens per guarded body (placeholder meshes for now)
var _env: Environment

var docked := false
var _dock_in_range := false
var current_system := SystemDB.SOL

# --- Dramatic teleport ritual (emergency home + station→station — the ONLY teleports).
# Travel between stars is always flown through wormholes; teleport is the rare, theatrical
# exception: ship held still, camera eases back, a hue-cycling RGB ring circles you, then
# you arrive. ~TELEPORT_TIME seconds. (Wormholes are NOT teleport.)
const TELEPORT_TIME := 8.0            # long, dramatic ritual: whoosh fades in, holds, fades out
const TELEPORT_PLATFORM_TIME := 8.0   # platform-network jump
const TELEPORT_SFX_DB := -9.0   # peak volume of the whoosh at the middle of its fade bell (gentle)
const TELEPORT_ZOOM := 3.0      # pull the camera BACK so it views the light-ball from OUTSIDE
const TP_ORB_BASE := 1.6        # base radius of the light-ball wrapping the ship (must stay
								# well under the camera distance ≈ 1.05 × TELEPORT_ZOOM, or the
								# camera ends up inside the additive shell and the screen goes white)
var _tp_active := false
# Galactic-core death hazard (Vela Iron Pulse voyage only). The core is a one-way grave: cross
# into it and gravitational shear shreds the hull, then the failsafe drive hurls you home.
const CORE_DANGER_LY := 600.0   # inside this distance the core turns lethal (warnings + damage)
const CORE_KILL_LY := 150.0     # the hole CAPTURES you here — you never get deeper; it takes you
const CORE_MAX_DPS := 90.0      # hull damage/sec at the kill line (ramps from 0 at the danger edge)
const CORE_PULL_GRAB := 2.6     # how hard Sgr A* redirects your heading inward (per sec × depth)
const CORE_MIN_PULL := 6_000_000.0  # min inward reel-in speed (u/s) at full depth — no escaping
var _core_dmg_accum := 0.0      # fractional hull damage carried between frames (player_hp is int)
var _core_dying := false        # true during the death kick, so the hazard doesn't re-fire mid-ritual
var _core_warned := false       # true while the danger overlay is up, so we clear it once on exit
var _skin_dying := false        # no-landing cutscene: too close to a physical skin
var _skin_t := 0.0
var _skin_body := ""
var _tp_t := 0.0
var _tp_dur := TELEPORT_TIME
var _tp_dest := ""
var _tp_label := ""
var _tp_platform := false              # this jump came from the platform network → land beside the dock
var _tp_ring: MeshInstance3D          # shiny light-ball that wraps the ship
var _tp_ring_mat: StandardMaterial3D  # additive glowing-orb material (pulses in a light wave)
# --- Music: a two-track lobby⇄ship state machine — extracted to MusicDirector (Phase 3).
# main keeps _is_interstellar() and feeds the director each frame via music.update(...).
var music: MusicDirector

# Sol start is sunlit geostationary (42,157 km from Earth's centre). Earth is
# day-lit in front of you; the Sun is behind the camera. See Ephemeris.geo_start_pos.
# Largest sane true_pos magnitude (units). In-system play keeps true_pos to ~1e5 units at most
# (it resets to a small local coord on every arrival), and the galactic drive no longer moves it.
# ~1e10 (≈1200 ly) is far above anything legitimate yet far below a corrupt ~8.7e11; a saved
# position beyond it is discarded on load. See _restore_location.
const MAX_SANE_POS := 1.0e10


func _ready() -> void:
	_load_profile()
	_setup_environment()
	music = MusicDirector.new()
	add_child(music)

	# Fixed star backdrop on the world root (never rotates with the ship).
	add_child(Starfield.new())
	# Galaxy node stays for the Iron Pulse core voyage / scanner. Hidden in Sol —
	# an outside-in spiral would be a lie; the HYG field is the real band.
	galaxy = GalaxyModel.new()
	add_child(galaxy)

	# Player ship (visual + flight). Pinned at origin; we move the universe.
	ship = Ship.new()
	add_child(ship)
	ship.load_customization(GameState.customization)
	ship.true_pos = Ephemeris.geo_start_pos()
	ship.face_toward(-ship.true_pos)   # open looking at Earth (the origin)
	ship.newton = true                 # Sol: real pull, parked spawn falls

	# Chase camera lives on the world root; the ship drives its transform each
	# frame (with a little lag) so it isn't rigidly bolted to the hull.
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = Ship.FOV_BASE   # ship._update_camera owns it after the first frame
	cam.near = 0.05
	# Keep the spherical star shell well inside the flat camera far plane. A
	# near-equal far value clips the forward cap into a camera-following black circle.
	cam.far = Ephemeris.CAM_RENDER_FAR_KM
	add_child(cam)
	ship.camera = cam

	# Real positions: live JPL Horizons for Sun+planets, catalog for stars.
	# Ephemeris is now the autoload; planets self-source it via `@onready var eph := Ephemeris`.

	# Planets / stars as dot->body LOD (reads real positions from Ephemeris).
	planets = PlanetSystem.new()
	planets.speed_zones = false   # Sol 1:1 slice: speed pass comes later
	add_child(planets)
	planets.refresh(ship.true_pos, 0.0)
	ship.gravity = planets.gravity   # first fly already feels the pull

	# Two shadowless lights give the ship/Earth/station CONTRAST and form without
	# blowing them out: a bright warm KEY from the Sun's direction, plus a dim
	# cool FILL from roughly the opposite side so the shadowed half isn't black.
	# This lets ambient + self-emission stay low, so the hull keeps its panel
	# detail instead of washing pale. Stars/planets are emissive/unshaded, so the
	# "dots and glow" look is untouched. Shadows off = nearly free on a potato.
	var sun_dir: Vector3 = eph.scene_pos("Sun").normalized()
	var sun_light := DirectionalLight3D.new()
	sun_light.light_energy = 1.05
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	sun_light.shadow_enabled = false
	add_child(sun_light)
	sun_light.look_at(-sun_dir, Vector3.UP)   # rays travel from the Sun outward

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)   # cool counter-light
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at(sun_dir + Vector3(0.0, -0.6, 0.0), Vector3.UP)  # opposite-ish, from below

	# Hand-placed GLB landmarks (station, planet, astronaut) near Earth.
	props = Props.new()
	add_child(props)

	# Wormhole portal + tunnel transit (interstellar travel between systems).
	wormhole = Wormhole.new()
	add_child(wormhole)
	wormhole.set_ship(ship)
	wormhole.set_portals(_known_portals(current_system))   # this system's KNOWN neighbour links

	# Code-spawned SFX (fire / engine / explosion) — now the GameAudio autoload;
	# ship/combat/tutor self-source it via `@onready var audio := GameAudio`.

	# Combat: alien dogfighters + your bolts (left-click to fire).
	combat = Combat.new()
	add_child(combat)
	combat.planets = planets                            # bolts curve through gravity wells
	combat.reset(SystemDB.is_hostile(current_system))   # Sol starts peaceful
	combat.player_hp = ship.max_hp                      # start at the hull's full defence
	ship.combat_ref = combat                            # shared energy pools (boost)

	# HUD labels (light-year distance, speed, nearest body).
	hud = HUD.new()
	add_child(hud)
	hud.ship = ship
	hud.ship_ref = ship          # used by the HUD layout editor to free/recapture the cursor
	hud.planets = planets
	hud.combat = combat
	hud.teleport_button.pressed.connect(teleport_home)
	hud.tp_cancel_button.pressed.connect(cancel_teleport)   # abort an in-progress teleport
	hud.ship_selected.connect(_on_hangar_pick)   # click a hangar row to swap ship
	hud.ship_color_selected.connect(_on_ship_color_pick)
	hud.ship_finish_selected.connect(_on_ship_finish_pick)
	hud.open_teleport_map.connect(_on_open_teleport_map)    # dock → open the teleport-network map

	# Discovery progress (persisted) + real planet facts + the Details panel.
	# Codex and PlanetData are now autoloads; consumers self-source them.
	planet_info = PlanetInfo.new()
	planet_info.planets = planets
	planet_info.ship = ship
	planet_info.main = self
	add_child(planet_info)
	hud.details_button.pressed.connect(planet_info.open_for_nearest)
	# Codex logbook (L): browse discovered bodies, click to read.
	var codex_panel := CodexPanel.new()
	codex_panel.info = planet_info
	codex_panel.ship = ship
	add_child(codex_panel)
	# Wire the styled top-right control bar to the panels.
	hud.codex_button.pressed.connect(codex_panel.toggle)

	# Settings overlay (Esc): volume, sensitivity, glow, render scale, fullscreen.
	settings = SettingsMenu.new()
	settings.ship = ship
	settings.env = _env
	settings.hud = hud           # for the "Edit HUD Layout" button
	settings.main = self         # for the "Reset Progress" button
	add_child(settings)

	# Waypoint navigator (Tab) + corner radar.
	var nav_canvas := CanvasLayer.new()
	add_child(nav_canvas)
	navigator = Navigator.new()
	nav_canvas.add_child(navigator)
	minimap = MiniMap.new()
	minimap.position = Vector2(24, 466)
	nav_canvas.add_child(minimap)
	hud.register_movable("radar", minimap)   # make the corner radar drag-positionable too

	# Star map (M): click a system to jump.
	map = StarMap.new()
	map.main = self
	add_child(map)
	platform_tp = PlatformTeleport.new()
	platform_tp.main = self
	add_child(platform_tp)
	tutor = Tutor.new()
	tutor.main = self
	add_child(tutor)
	reward_card = RewardCard.new()
	add_child(reward_card)
	hud.map_button.pressed.connect(map.toggle)

	# Mission log (J): every body is a mission — browse the story + navigate to it.
	quest_log = QuestLog.new()
	quest_log.main = self
	add_child(quest_log)
	hud.log_button.pressed.connect(quest_log.toggle)
	hud.settings_button.pressed.connect(settings.toggle)
	hud.nav_button.pressed.connect(toggle_nav)
	hud.cancel_nav_button.pressed.connect(cancel_locked_nav)

	# Beginner quest "GETTING STARTED" — the staged first-run guide (Onboarding controller).
	onboarding = Onboarding.new()
	onboarding.main = self
	add_child(onboarding)

	# Touch / mobile controls overlay (on a phone, or force on desktop with --touch to test).
	# Desktop keyboard+mouse play is completely unaffected when this is off.
	_touch = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	if _touch:
		touch_controls = load("res://scripts/flight/touch_controls.gd").new()
		touch_controls.ship = ship
		touch_controls.main = self
		add_child(touch_controls)

	_restore_location()   # resume where you left off (system + position + hull)

	# Onboarding is now the GETTING STARTED quest (always on, surfaced as the tip + J-log
	# questline). The tutor's scripted drip is retired — it stays only as the occasional
	# idle-nudge backup (tutor._process, beginner-gated). So we no longer call tutor.start().


# Resume the last session's location: rebuild the saved system if it isn't the Sol start,
# then drop the ship at the exact saved position with the saved hull, at FULL HP (resuming
# next to a boss at 5 HP would be a rage-quit). Reusing _arrive is safe — the system is
# already visited, so it grants no reward and clears transit/dock state for us.
func _restore_location() -> void:
	if _saved_system != "" and _saved_system != current_system:
		_arrive(_saved_system)
	# Guard against a corrupt save (the old galactic-drive bug could leave an astronomical
	# coordinate, ~8.7e11 units). true_pos is ALWAYS a small local coord by design, so anything
	# this enormous is garbage — drop it and keep the arrival/START position instead of restoring
	# nonsense (which would re-show the piled-up "From Earth" number and look unfixed).
	if _has_saved_pos and _saved_pos.length() > MAX_SANE_POS:
		_has_saved_pos = false
	if _has_saved_pos and _saved_pos.length() > 0.001:
		ship.true_pos = _saved_pos
		ship.face_toward(-_saved_pos)
	# Pre-1:1 Sol saves sit inside the real Earth. Night-side GEO saves stare at
	# a black planet that covers the Sun — snap those to the sunlit start too.
	if current_system == SystemDB.SOL:
		var r := ship.true_pos.length()
		var sun := Ephemeris.scene_pos("Sun")
		var inside := r < Ephemeris.EARTH_RADIUS_KM + 200.0
		var night_geo := r < Ephemeris.GEO_RADIUS_KM * 1.2 and sun.dot(ship.true_pos) < 0.0
		if inside or night_geo:
			ship.true_pos = Ephemeris.geo_start_pos()
			ship.face_toward(-ship.true_pos)
	if _saved_ship_index >= 0 and _saved_ship_index < ship.ship_count() \
			and _saved_ship_index != ship.current_index():
		ship.swap_ship(_saved_ship_index)
	combat.player_hp = ship.max_hp
	ship.transiting = false
	_tp_active = false
	_save_profile()       # capture the exact restored position


# Save on window close so quitting preserves your exact spot (autosave covers crashes).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_profile()


func _process(delta: float) -> void:
	_update_holds(delta)
	ship.fly(delta)
	planets.refresh(ship.true_pos, delta)
	ship.speed_limit = planets.speed_limit   # eases the ship down near a body
	# Hand the ship the SAME height function the ground rings and the contact kill
	# read, so its substep ground clamp cannot disagree with either.
	ship.terrain = planets.terrain_sampler_for(planets.nearest_name)
	ship.nearest_dir = planets.nearest_dir   # only ease down when approaching it
	ship.nearest_name = planets.nearest_name
	ship.nearest_dist = planets.nearest_dist # warp ships ease out of warp on arrival
	ship.nearest_radius = planets.nearest_radius
	ship.star_field_dist = planets.star_dist # FTL only unlocks beyond the star's gravity field
	ship.gravity = planets.gravity           # gentle pull toward bodies
	_update_skin_kill(delta)
	# Fly-to-arrive: in the deep-space hub, flying within approach range of a REAL star drops you
	# into its LOCAL frame (small coords, like Sol) so the final stretch is actually flyable — no
	# float32 freeze, no pinpoint bobbing. Placed at your current offset, so there's no teleport.
	if not ship.transiting and not docked and not _tp_active and not _core_dying \
			and planets.hub_star_id != "" and planets.hub_star_id != current_system \
			and planets.hub_star_dist < STAR_APPROACH_RANGE:
		_arrive(planets.hub_star_id, -planets.hub_star_rel)
	# Galactic drive: feed the Iron Pulse's live core-distance scanner, and loom the Milky Way in
	# at the fixed voyage pace scaled by how directly she's flying coreward (galactic_loom_rate is
	# signed: toward Sgr A* approaches, flying back out recedes). This is DECOUPLED from her real
	# velocity, so the ~26,000 ly haul is a bounded illusion that never balloons true_pos.
	if ship.has_galactic_drive:
		ship.core_total_ly = galaxy.total()
		ship.core_dist_ly = galaxy.remaining()
		galaxy.advance_ly(ship.galactic_loom_rate() * delta)
		_update_core_hazard(galaxy.remaining(), delta)
	props.update(ship.true_pos, delta)
	# Harbour speed-cap: ease down near stations/probes AND near wormholes (so you can line
	# up and dive in instead of rocketing past) — whichever zone is slowing you most wins.
	ship.struct_limit = minf(props.struct_speed_limit, wormhole.slow_limit(ship.true_pos))
	if wormhole.update(ship.true_pos, delta):
		_ob_note("wormhole")
		_arrive(wormhole.dest_id)
	# Combat runs in normal flight (not mid-transit, not docked). Docking at a
	# station is a safe harbor — the fight pauses so you can swap ships in peace.
	var want_fire := false
	var want_laser := false
	if not ship.transiting and not docked and not _tp_active and not _skin_dying:
		if _touch:
			# Mobile: fire ONLY from the on-screen FIRE button (ship.touch_fire). We must NOT
			# read the mouse here — emulate_mouse_from_touch turns EVERY screen touch into a
			# left-click, which made the whole screen a trigger. Laser hulls fire the beam.
			if ship.has_laser:
				want_laser = ship.touch_fire
			else:
				want_fire = ship.touch_fire
		else:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			want_fire = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			# Right-click fires the nose laser beam (laser-equipped hulls only, e.g. Raptor II).
			want_laser = captured and ship.has_laser and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		combat.update(ship, want_fire, delta, want_laser)
		ship.combat_lock = combat.in_combat()       # no interstellar speed mid-fight
	else:
		ship.combat_lock = false
	# Holding fire force-slows you to regular combat speed (you can't shoot at warp/boost) —
	# set even while still fast so the slowdown engages; combat only spawns bolts once slow.
	ship.firing = (want_fire and ship.can_fire) or (want_laser and ship.has_laser)
	if ship.firing:
		_ob_note("fire")
	hud.firing = want_fire                       # blooms the dynamic crosshair
	hud.coins = GameState.coins
	hud.set_cancel_nav_visible(_nav_locked != "" or _nav_goal != "" or _active_quest != "" or not _marks.is_empty())
	# Tell the player (once) when they try to boost in a slow-zone where it does nothing.
	if ship.boost_blocked and not _was_boost_blocked:
		hud.toast = "⚠  Boost unavailable here — clear the slow-zone first"
		hud.toast_t = 1.6
	_was_boost_blocked = ship.boost_blocked
	_update_teleport(delta)
	_update_dock_ui()
	if ship.autopilot:
		ship.autopilot_target = ship.true_pos + planets.rel_of(ship.autopilot_name)
	_update_navigator()
	_update_minimap()
	_update_wormhole_radar()
	_update_scan(delta)
	music.update(delta, _is_interstellar(), ship.ship_name_at(ship.current_index()))
	_update_onboarding()
	_update_quests()
	hud.lore_t = maxf(hud.lore_t - delta, 0.0)
	_update_debug(delta)
	# Periodic autosave of location (every 5s, only from a stable state) so a crash or
	# hard quit resumes you near where you were rather than back at Earth.
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = 5.0
		if not ship.transiting and not _tp_active:
			_save_profile()
	hud.refresh()


# Are we "interstellar" — flown out of the limited-speed area into open/FTL space?
# Not while docked or mid-transit; otherwise it's the ship's open-space signal (every
# speed cap lifted). Local play (in-system, docked, hangar) returns false -> lobby track.
func _is_interstellar() -> bool:
	return not docked and not ship.transiting and ship.in_open_space()


# Jump straight to a system from the star map (fast-travel, no tunnel).
func travel_to(id: String) -> void:
	if id == current_system:
		return
	_arrive(id)
	ship._set_capture(true)


# --- Corner radar: ship-relative blips for bodies / Earth / nearest / wormhole ---
func _update_minimap() -> void:
	if minimap == null:
		return
	if ship.transiting:
		minimap.set_blips([])
		return
	var binv := ship.transform.basis.inverse()
	var blips := []
	for bname in planets.targetables():
		var rel: Vector3 = planets.rel_of(bname)
		var role := MiniMap.BODY
		if codex.is_discovered(bname):
			role = MiniMap.CAPTURED                  # captured → gold beacon on the radar
		if bname == "Earth" and current_system == SystemDB.SOL:
			role = MiniMap.HOME
		elif bname == planets.nearest_name:
			role = MiniMap.NEAREST
		blips.append({ "local": binv * rel, "dist": rel.length(), "role": role, "name": bname })
	# All known wormholes, live (not just the nearest) — each its own gold blip on the radar.
	for wp in wormhole.portals_rel(ship.true_pos):
		var wrel: Vector3 = wp.rel
		blips.append({ "local": binv * wrel, "dist": wrel.length(), "role": MiniMap.WORMHOLE,
			"name": "→ %s" % SystemDB.display_name(wp.dest) })
	minimap.set_blips(blips)


# --- Capture the nearest body (hold V within range). Guarded bodies (≈80%, never in
# peaceful Sol) spawn alien guardians you must clear first. Capture = beacon + rank. ---
func _update_scan(delta: float) -> void:
	hud.toast_t = maxf(hud.toast_t - delta, 0.0)
	if _tp_active:
		return                       # no scanning/capturing mid-teleport
	# Guardian LEASH: if an active guardian fight's body is now far behind us, abandon it.
	# A parked, unreachable boss otherwise keeps summoning/firing (no distance gate in
	# _step_boss) → in_combat() stays true → warp bleeds to sublight → you're stranded.
	# Runs independent of the capturable check below so it fires even out in empty space.
	if combat.guard_body != "":
		var grel: Vector3 = planets.rel_of(combat.guard_body)
		if grel != Vector3.ZERO and grel.length() > GUARD_RANGE * 2.5:
			combat.abandon_combat()
	# Guardian fight: always-visible WAVE/capture banner + a toast as each wave falls.
	if combat.guard_body != "":
		var wp: Dictionary = combat.guard_progress()
		if wp.cleared:
			hud.set_guardian("✓  %s  —  DEFENCES DOWN · CAPTURE READY (hold V)" % combat.guard_body, true)
		else:
			hud.set_guardian("⚔  GUARDIANS OF %s     WAVE  %d / %d     · capture locked ·" % [combat.guard_body, wp.wave, wp.total], false)
		if wp.waves_cleared > _last_waves_cleared:
			_last_waves_cleared = wp.waves_cleared
			if wp.cleared:
				hud.toast = "✦  %s's guardians are destroyed — capture it now!" % combat.guard_body
			else:
				hud.toast = "✦  Wave %d/%d cleared — brace for the next" % [wp.waves_cleared, wp.total]
			hud.toast_t = 3.5
			if audio != null:
				audio.play_notify()
	else:
		hud.set_guardian("", false)
	var name := planets.nearest_name
	# Hub gate-suns (✦) and the Interstellar hub are travel markers — never captured or
	# guarded. Skip the whole flow there (no monsters in the hub, no fake captures).
	if not _capturable(name):
		_scan = maxf(_scan - delta * 2.0, 0.0)
		if _scan <= 0.0:
			_scan_name = ""
		hud.scan_progress = _scan
		hud.scan_name = _scan_name
		hud.scan_hint = ""
		return
	var captured := codex.is_discovered(name)
	var guarded := current_system != SystemDB.SOL and _is_guarded(name)

	# Approaching a guarded, un-captured body spawns its identity boss — but ONLY when
	# there's no boss currently alive and it's a different body. Without the
	# "not guard_boss_alive()" guard, a nearest_name that flips between two close bodies
	# (e.g. TRAPPIST's packed planets) would re-spawn a boss GLB every frame and freeze.
	if guarded and not captured and planets.nearest_dist < GUARD_RANGE \
			and combat.guard_body != name and not combat.guard_boss_alive() \
			and not ship.transiting and not docked:
		# Bigger bodies (stars) get a tougher boss + bigger waves (power scales with radius).
		var power: float = clampf(planets.nearest_radius / 7.0, 1.0, 3.0)
		combat.set_guardians(ship.true_pos + planets.rel_of(name), name, power)
		_last_waves_cleared = 0       # fresh fight → reset the wave-announce tracker

	# Capturable once ALL of THIS body's defending waves are beaten (finite — see combat).
	var clear := not guarded or combat.guardians_cleared(name)

	# Capture when within reach of the body's SURFACE (range scales with its size, so a
	# giant star/nebula is grabbable without diving to its centre).
	var cap_range := planets.nearest_radius + SCAN_RANGE
	var in_range := not docked and not ship.transiting and name != "" \
		and planets.nearest_dist < cap_range \
		and (_touch or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	var fresh := in_range and not captured and clear

	# Raptor 2 Neo auto-captures any clear body in range — no key needed.
	if fresh and (ship.auto_capture or Input.is_physical_key_pressed(KEY_V)):
		if name != _scan_name:
			_scan_name = name
			_scan = 0.0
		_scan = minf(_scan + delta / SCAN_SECONDS, 1.0)
		if _scan >= 1.0:
			if codex.discover(name):
				_ob_note("scan")
				# Capture complete: AUTO-grant the bounty and pop the celebration card.
				var bounty := claim_reward(name)
				if reward_card != null:
					reward_card.celebrate(name, MissionDB.title_for(name), bounty)
				if audio != null:
					audio.play_reward()
				if name == _active_quest:
					_advance_quest()    # tracked quest done → guide the next unsurveyed body here
				if combat.guard_body == name:
					combat.clear_guardians()
			_scan = 0.0
			_scan_name = ""
	else:
		_scan = maxf(_scan - delta * 2.0, 0.0)
		if _scan <= 0.0:
			_scan_name = ""

	hud.scan_progress = _scan
	hud.scan_name = _scan_name
	if name == "" or captured:
		hud.scan_hint = ""
	elif guarded and not clear:
		var gp: Dictionary = combat.guard_progress()
		hud.scan_hint = "⚠  GUARDIANS of %s — Wave %d/%d  ·  clear the swarm, then kill the boss (capture locked)" % [name, gp.wave, gp.total]
	elif in_range and _scan <= 0.0:
		hud.scan_hint = ("» auto-capturing %s «" % name) if ship.auto_capture else ("» hold V to capture %s «" % name)
	else:
		hud.scan_hint = ""


# Open the scanner detail panel for a specific body (called by the M-map list).
func open_details_for(body_name: String) -> void:
	if planet_info != null:
		planet_info.open_for(body_name)


# Lock the nav waypoint to a body (orange; persists until cancelled). PAID navigator.
func set_nav_target(body_name: String) -> void:
	if not buy_navigator():
		return
	_nav_off = false
	_active_quest = ""        # a manual waypoint supersedes quest tracking
	_nav_locked = body_name
	if hud != null:
		hud.set_nav_stopped(false)


# Auto-pilot: locks the orange waypoint AND flies there hands-off. PAID navigator.
func start_autopilot(body_name: String) -> void:
	if not buy_navigator():
		return
	_nav_off = false
	_active_quest = ""        # autopilot supersedes quest tracking
	_nav_locked = body_name
	if hud != null:
		hud.set_nav_stopped(false)
	ship.start_autopilot(body_name)


# --- Coins / rewards ---
# A captured body's 100-coin reward isn't auto-given — the player CLAIMS it from the
# Details (G) panel. Claimable = captured but not yet claimed.
# Thin wrappers over GameState's pure economy (kept so external callers + onboarding/persistence
# side-effects stay here). See GameState.can_claim / claim_reward.
func can_claim(body_name: String) -> bool:
	return GameState.can_claim(body_name)

func claim_reward(body_name: String) -> int:
	var bounty := GameState.claim_reward(body_name)
	if bounty > 0:
		_ob_note("claim")
		_save_profile()
	return bounty

# Map Navigate / Auto-pilot is a PAID navigator service. Returns true if it could pay.
func buy_navigator() -> bool:
	if GameState.coins < GameState.NAV_COST:
		hud.toast = "Not enough coins for a navigator (%d / %d)" % [GameState.coins, GameState.NAV_COST]
		hud.toast_t = 2.5
		return false
	GameState.coins -= GameState.NAV_COST
	_save_profile()
	return true


# Wipe ALL saved progress — visited systems, codex captures, coins, ship customization, and
# HUD layout — then restart fresh from Earth. Called by the Settings "Reset Progress" button.
func reset_progress() -> void:
	var d := DirAccess.open("user://")
	if d != null:
		for f in ["profile.cfg", "codex.json", "hud_layout.cfg"]:
			if d.file_exists(f):
				d.remove(f)
	get_tree().paused = false
	get_tree().reload_current_scene()   # re-runs _ready with no save → clean slate at Earth


# --- Player profile (persisted to disk; will hold more than coins later) ---
func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		GameState.load_from(cfg)   # all persisted profile fields (coins/visited/onboarding/customization…)
		_active_quest = str(cfg.get_value("player", "active_quest", ""))
		# Where you left off last session (restored after the world is built — see
		# _restore_location). Position is only ever saved from a STABLE state.
		_saved_system = str(cfg.get_value("player", "system", ""))
		_has_saved_pos = cfg.has_section_key("player", "pos")
		_saved_pos = cfg.get_value("player", "pos", Vector3.ZERO)
		_saved_ship_index = int(cfg.get_value("player", "ship_index", -1))
	else:
		GameState.reset()    # autoload survives scene reload — clear stale memory on a fresh/reset game
		_fresh_game = true   # no save on disk → a brand-new game (drives the tutorial)
	# Home (Sol) is always known — you start there, so it's instant-travel from frame one.
	GameState.visited[SystemDB.SOL] = true

func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)            # keep any other keys we add later
	if ship != null:
		GameState.customization = ship.customization_state()
	GameState.save_into(cfg)   # all persisted profile fields
	cfg.set_value("player", "active_quest", _active_quest)
	if ship != null:
		# Persist your location + active hull — but ONLY from a stable state. Mid-wormhole
		# or mid-teleport we leave the last good values so a restore can't wedge the ship.
		if not ship.transiting and not _tp_active and not _skin_dying:
			cfg.set_value("player", "system", current_system)
			cfg.set_value("player", "pos", ship.true_pos)
			cfg.set_value("player", "ship_index", ship.current_index())
	cfg.save(PROFILE_PATH)


# True once the player has reached this system at least once (the map only
# fast-travels to KNOWN systems; unknown ones must be flown via the wormhole first).
func is_visited(id: String) -> bool:
	return GameState.visited.has(id)

# --- Star travel states (read by the map) ---------------------------------------
# "here" | "discovered" (visited → free instant fast-travel) | "nav" (navigation unlocked,
# warp-able but undiscovered) | "locked" (must pay coins or get a chest location drop).
func star_state(id: String) -> String:
	if id == current_system:
		return "here"
	if GameState.visited.has(id):
		return "discovered"
	if is_wormhole_known(id):          # nav unlocked (paid/chest) OR wormhole found by radar
		return "nav"
	return "locked"

# Coin cost to unlock navigation to a LOCKED star — scales with REAL distance from where
# you are now (the far dark is expensive to chart a lane to).
func nav_cost(id: String) -> int:
	var d: float = SystemDB.coord(current_system).distance_to(SystemDB.coord(id))
	return GameState.NAV_UNLOCK_BASE + int(d * GameState.NAV_UNLOCK_PER_LY)

# Pay to unlock navigation to a locked star (map action). Returns true if it could pay.
func unlock_nav(id: String) -> bool:
	if star_state(id) != "locked":
		return false
	var cost := nav_cost(id)
	if GameState.coins < cost:
		hud.toast = "Not enough coins to chart a lane to %s  (%d / %d)" % [SystemDB.display_name(id), GameState.coins, cost]
		hud.toast_t = 2.5
		return false
	GameState.coins -= cost
	GameState.nav_unlocked[id] = true
	_save_profile()
	hud.toast = "◇  Navigation unlocked — %s  (-%d coins)" % [SystemDB.display_name(id), cost]
	hud.toast_t = 3.0
	return true

# Free nav-unlock from a treasure-chest "star location" drop (Stage 4). No-op if already
# reachable. Returns true if it actually revealed a new lane.
func grant_nav_location(id: String) -> bool:
	if id == "" or GameState.visited.has(id) or GameState.nav_unlocked.has(id):
		return false
	GameState.nav_unlocked[id] = true
	_save_profile()
	return true

# A wormhole LINK (a,b) is KNOWN once either endpoint is a discovered system, or it's been
# charted/gifted. This auto-produces "go to Proxima first, then Alpha": the Sol→Alpha link
# doesn't exist in the graph, and Proxima→Alpha only becomes known once you've REACHED Proxima.
func is_edge_known(a: String, b: String) -> bool:
	return GameState.visited.has(a) or GameState.visited.has(b) or GameState.nav_unlocked.has(a) or GameState.nav_unlocked.has(b)

# This system's portals filtered to the links the player knows (what set_portals shows).
# Star systems: arriving in a system reveals all its exit wormholes (is_edge_known is true
# via the system you're standing in). The Interstellar HUB is the exception — it's a junction,
# not a place you "discover onward from", so it shows ONLY wormholes whose DESTINATION the
# player has actually unlocked (visited or charted). Otherwise visiting the hub would leak the
# whole network, since the hub itself counts as visited.
func _known_portals(id: String) -> Array:
	var out := []
	var hub := id == SystemDB.INTERSTELLAR
	for p in SystemDB.portals(id):
		var known: bool = (GameState.visited.has(p.dest) or GameState.nav_unlocked.has(p.dest)) if hub \
			else is_edge_known(id, p.dest)
		if known:
			out.append(p)
	return out

# A star is "reachable" (map 'nav' state) when a KNOWN multi-hop route to it exists from here.
func is_wormhole_known(id: String) -> bool:
	return id != current_system and SystemDB.next_hop(current_system, id, Callable(self, "is_edge_known")) != ""

# In the hub, flying within WORMHOLE_RADAR of an UNDISCOVERED wormhole reveals it: a happy
# notification, it's added to the known field, and the portal pops in. (Only in the hub.)
func _update_wormhole_radar() -> void:
	# Disabled pending graph-rework: wormhole links are now known via the visited frontier
	# (is_edge_known), not radar-found in a central hub. Re-add a per-system radar later.
	return

# Map "Navigate": set the orange guide toward a star. You FLY there — the guide resolves the
# next hop each frame (this star's wormhole when you're in the hub; the exit gate when you're
# in a system). Persists until toggled off (Cancel Nav button / cancel_locked_nav).
func navigate_to(id: String) -> void:
	if id == "" or id == current_system:
		return
	_nav_goal = id
	_active_quest = ""        # a map-navigate goal supersedes quest tracking
	_nav_locked = ""          # the goal-guide supersedes any old fixed waypoint
	_nav_off = false
	if hud != null:
		hud.set_nav_stopped(false)

# Survey rank = how many distinct systems you've reached. Cheap, derived stat — no
# separate counter to keep in sync. Sol counts, so a fresh player is rank 1.
func survey_rank() -> int:
	return GameState.visited.size()

# The Survey's rank titles (lore.md): the count climbs toward a name, not a gate.
func survey_rank_title() -> String:
	var n := survey_rank()
	if n >= 5:    return "Star-Marshal"
	elif n >= 4:  return "Cartographer"
	elif n >= 2:  return "Surveyor"
	return "Cadet"


# A real body you can capture: not the Interstellar hub, not a hub gate-sun (✦).
func _capturable(body_name: String) -> bool:
	return body_name != "" and current_system != SystemDB.INTERSTELLAR and not body_name.contains("✦")

# ≈80% of bodies are guarded (deterministic per name, so it's stable across visits).
func _is_guarded(body_name: String) -> bool:
	return (hash(body_name) % 5 + 5) % 5 != 0

# Survey rank from how many bodies you've captured (the reward ladder).
func _rank_title() -> String:
	var n := codex.count()
	if n >= 24: return "Star-Marshal"
	elif n >= 14: return "Cartographer"
	elif n >= 6: return "Surveyor"
	return "Cadet"


# --- Navigation waypoint (Tab) ---
# Tab steps through the up-to-4 objects the aim ray passes nearest to (1st = absolute closest
# to the line, then 2nd, 3rd, 4th, then loops). It is ALWAYS the ray's targets — never the
# ship's nearest body. Move the cursor and the ranking changes; Tab restarts from the closest.
func _cycle_nav_target() -> void:
	var ranked := _aim_ranked()
	if ranked.is_empty():
		_nav_target = ""
		_tab_index = -1
		return
	var aim: Vector3 = (-ship.transform.basis.z).normalized()
	# Moved the aim noticeably (or starting fresh)? Restart at the closest-to-the-line target.
	if _tab_index < 0 or _tab_aim.dot(aim) < 0.997:   # ~4.4° of cursor movement restarts
		_tab_index = 0
	else:
		_tab_index = (_tab_index + 1) % ranked.size()
	_tab_aim = aim
	_nav_target = ranked[_tab_index]
	if _nav_target == "Wormhole":
		_nav_wormhole = _aim_wh_dest   # remember WHICH portal the ray picked

# Up to the 4 targets the AIM RAY passes nearest to, closest-to-the-line FIRST. The ray is a
# narrow, long beam out of the nose (through the crosshair): an object qualifies only if it's
# IN FRONT, within reach, and within TAB_MAX_ANGLE of the line — so a near planet sitting off
# to the side is NOT picked. Sorted by angular offset; Tab cycles through these (see below).
const TAB_MAX_ANGLE := deg_to_rad(7.0)    # NARROW beam for bodies — must hug the line
const TAB_WH_ANGLE := deg_to_rad(28.0)    # WIDER for wormholes — key nav targets, easy to grab
func _aim_ranked() -> Array:
	var aim: Vector3 = (-ship.transform.basis.z).normalized()   # nose / crosshair direction
	var hits := []
	for c in planets.target_candidates():
		var rel: Vector3 = c.rel
		var t: float = rel.dot(aim)                 # distance ALONG the ray (>0 = in front)
		if t <= 0.0:
			continue
		if t > _tab_pick_range(String(c.kind), float(c.radius)):
			continue                                # beyond this object's reach
		var ang: float = atan2((rel - aim * t).length(), t)   # angular offset from the ray line
		if ang <= TAB_MAX_ANGLE:
			hits.append({ "name": c.name, "ang": ang })
	# Wormholes compete on the same footing — check EVERY active portal (not just the nearest)
	# so you can target whichever one the ray points at. The closest-to-line portal is the pick.
	_aim_wh_dest = ""
	var wh_ang := TAB_WH_ANGLE
	for p in wormhole.portals_rel(ship.true_pos):
		var wrel: Vector3 = p.rel
		var t2: float = wrel.dot(aim)
		if t2 <= 0.0:
			continue
		var a2: float = atan2((wrel - aim * t2).length(), t2)
		if a2 < wh_ang:
			wh_ang = a2
			_aim_wh_dest = String(p.dest)
	if _aim_wh_dest != "":
		hits.append({ "name": "Wormhole", "ang": wh_ang })   # ranked by its real angle off the ray
	hits.sort_custom(func(a, b): return a.ang < b.ang)   # closest to the line first
	var out := []
	for i in mini(4, hits.size()):                       # only the 4 closest are cyclable
		out.append(hits[i].name)
	return out

# How far the (long) ray reaches to pick a given object, by kind/size (in scene units).
func _tab_pick_range(kind: String, radius: float) -> float:
	var ly := 1.0
	match kind:
		"star":   ly = 30.0                                       # large, bright — long reach
		"planet": ly = clampf(lerpf(0.3, 2.0, radius / 18.0), 0.3, 2.0)  # by size
		"moon":   ly = 0.6
		"craft":  ly = 0.3                                        # probes — closer
		_:        ly = 1.0
	return ly * Ephemeris.UNITS_PER_LY

# NAV button: stop / resume the Survey guide and waypoint marker (the orientation
# gizmo always stays). Also clears any manual Tab target when stopping.
func toggle_nav() -> void:
	# N / NAV only toggles the FREE Survey guide. A paid locked waypoint is NOT
	# affected — it's cancelled only by the on-screen Cancel Nav button.
	_nav_off = not _nav_off
	if _nav_off:
		_nav_target = ""
	hud.set_nav_stopped(_nav_off)
	_update_navigator()


# Cancel a locked (paid) map waypoint + any autopilot + a tracked quest (the Cancel Nav button).
# True once every body in the home (Sol) system has been scanned/discovered. While false, the
# player is still a beginner, so the tutorial helper pops tips more often (see tutor.gd).
func _sol_fully_unlocked() -> bool:
	if codex == null:
		return true
	for b in MissionDB.bodies_in(SystemDB.SOL):
		if not codex.is_discovered(b):
			return false
	return true


# Hold-to-act input (checked each frame): HOLD X ≥1s locks the current Tab target as an
# orange waypoint.
func _update_holds(delta: float) -> void:
	if ship.transiting:
		_x_hold = 0.0; _x_fired = false
		return
	# X-mark works even when frozen — parked at a star (or held by a guardian) is exactly when
	# you want to mark it. Only mid-wormhole transit blocks it (handled above).
	if Input.is_physical_key_pressed(KEY_X):
		_x_hold += delta
		if _x_hold >= 1.0 and not _x_fired:
			_x_fired = true
			lock_nav_target()
	else:
		_x_hold = 0.0; _x_fired = false
	# Feed the crosshair lock ring — only fills when there's actually a Tab target to lock.
	if hud != null:
		hud.set_lock_progress(clampf(_x_hold, 0.0, 1.0) if _nav_target != "" else 0.0)


# HOLD X over the current Tab target: drop a coloured X mark (up to 3, each its own colour).
# Marking the same body again clears that mark. With 3 already placed, the oldest is replaced.
# Marks coexist with the quest marker and the live Tab marker — all show at once.
func lock_nav_target() -> void:
	if _nav_target == "":
		hud.toast = "Aim at something and press Tab first, then hold X to mark it."
		hud.toast_t = 2.0
		return
	var nm := _nav_target
	var wh := _nav_wormhole
	# Quest target? X toggles the quest tracking off (same untrack feel as a mark).
	if nm != "" and nm == _active_quest:
		_active_quest = ""
		_save_profile()
		_nav_target = ""
		_tab_index = -1
		if hud != null:
			hud.toast = "✖  QUEST UNTRACKED  ·  %s" % _tab_display_name(nm)
			hud.toast_t = 2.0
		_update_navigator()
		return
	# Already marked? Toggle it off.
	for i in _marks.size():
		if _marks[i].name == nm and (nm != "Wormhole" or _marks[i].wh == wh):
			_marks.remove_at(i)
			if hud != null:
				hud.toast = "✖  MARK CLEARED  ·  %s   (%d/%d)" % [_tab_display_name(nm), _marks.size(), MARK_MAX]
				hud.toast_t = 2.0
			_update_navigator()
			return
	_nav_off = false
	if _marks.size() >= MARK_MAX:
		_marks.pop_front()   # full — drop the oldest to make room
	_marks.append({ "name": nm, "wh": wh })
	# Hand the target OVER to the mark: drop the live Tab pick so the teal marker doesn't sit
	# on top of the new coloured one, and Tab is free to grab the next thing.
	_nav_target = ""
	_tab_index = -1
	if hud != null:
		hud.set_nav_stopped(false)
		hud.toast = "◆  MARKED  ·  %s   (%d/%d)" % [_tab_display_name(nm), _marks.size(), MARK_MAX]
		hud.toast_t = 2.2
	_update_navigator()


func cancel_locked_nav() -> void:
	_nav_locked = ""
	_nav_goal = ""            # also clear a map "Navigate" guide
	_active_quest = ""        # and stop tracking a quest
	_marks.clear()            # and wipe the player's X marks
	ship.autopilot = false
	hud.set_nav_stopped(false)
	_save_profile()
	_update_navigator()


func active_quest() -> String:
	return _active_quest

# Track a quest (free) — the nav arrow + tracker will guide you to this body until you survey
# it, routing through wormholes if it's in another system. Supersedes the map's other guides.
func track_quest(body_name: String) -> void:
	_active_quest = body_name
	_nav_goal = ""
	_nav_locked = ""
	_nav_off = false
	ship.autopilot = false
	if hud != null:
		hud.set_nav_stopped(false)
	_save_profile()
	_update_navigator()

# Nearest UN-surveyed mission body in the current system ("" if the system's fully surveyed).
func _nearest_unsurveyed_body() -> String:
	if codex == null:
		return ""
	var best := ""
	var nd := INF
	for body in MissionDB.bodies_in(current_system):
		if codex.is_discovered(body):
			continue
		var d: float = planets.rel_of(body).length()
		if d < nd:
			nd = d
			best = body
	return best

# After surveying the tracked quest, advance to the next unsurveyed body here; clear if none.
func _advance_quest() -> void:
	_active_quest = _nearest_unsurveyed_body()
	_save_profile()

# ONE router for cross-system guidance (shared by the quest guide + the map's Navigate): the
# render-space offset of THIS system's wormhole leading toward `sys`, over the KNOWN links.
# { ok=false } when no known route exists yet.
func _route_to(sys: String) -> Dictionary:
	var hop := SystemDB.next_hop(current_system, sys, Callable(self, "is_edge_known"))
	if hop == "":
		return { "ok": false }
	return { "ok": true, "hop": hop, "rel": wormhole.portal_rel_for(hop, ship.true_pos) }


# Label for a Tab target — its real name once scanned, else "Unknown <kind>" so the player
# has to fly over and scan (V) to reveal what it is.
func _tab_display_name(name: String) -> String:
	if name == "" or name == "Wormhole":
		return name
	if codex != null and codex.is_discovered(name):
		return name
	match planets.kind_of(name):
		"star":  return "Unknown Star"
		"moon":  return "Unknown Moon"
		"craft": return "Unknown Craft"
		_:       return "Unknown Planet"


# Slot of an existing X mark matching this target (-1 if not marked).
func _mark_index(name: String, wh := "") -> int:
	for i in _marks.size():
		if _marks[i].name == name and (name != "Wormhole" or _marks[i].wh == wh):
			return i
	return -1


# Resolve a waypoint entry { name, wh } to its current render-space offset.
func _waypoint_rel(name: String, wh := "") -> Vector3:
	if name == "Wormhole":
		return wormhole.portal_rel_for(wh, ship.true_pos) if wh != "" else wormhole.portal_rel(ship.true_pos)
	return planets.rel_of(name)


# Rebuild EVERY active waypoint each frame and hand the whole set to the navigator, so they
# all draw at once: the tracked QUEST (purple) + up to 3 player X marks (cyan/gold/green) +
# the live Tab target (teal) + a single guide (map Navigate / Locked / Survey, orange). The
# top objective line keeps a priority order (quest > navigate > locked > tab > survey).
func _update_navigator() -> void:
	if navigator == null:
		return
	if ship.transiting:
		navigator.set_markers(ship.camera, [])   # gizmo only
		hud.set_objective("")
		return
	var markers: Array = []
	var objective := ""
	var quest_idx := -1   # markers[] slot of the in-system quest marker (for the drop badge)

	# --- the single guide: quest / map-navigate / locked (mutually exclusive) -------------
	if _active_quest != "" and not _nav_off:
		# TRACKED QUEST guide: route to the body's system via wormholes, then point straight at
		# it once in-system. Backstop-advances if it's already surveyed.
		if codex != null and codex.is_discovered(_active_quest):
			_advance_quest()
		if _active_quest != "":
			var qbody := _active_quest
			var qsys := MissionDB.system_of(qbody)
			var qtitle := MissionDB.title_for(qbody)
			if qsys == current_system:
				var qrel := planets.rel_of(qbody)
				quest_idx = markers.size()
				markers.append({ "rel": qrel, "name": "QUEST: %s" % qbody, "dist": _fmt_nav_dist(qrel.length()), "color": QUEST_COL })
				objective = "✦  QUEST  %s  —  survey %s   %s" % [qtitle, qbody, _fmt_nav_dist(qrel.length())]
			else:
				var rt := _route_to(qsys)
				if rt.ok:
					var hopname := SystemDB.display_name(rt.hop)
					markers.append({ "rel": rt.rel, "name": "QUEST → %s" % hopname, "dist": _fmt_nav_dist(rt.rel.length()), "color": QUEST_COL })
					objective = "✦  QUEST  %s  —  %s via %s   %s" % [qtitle, SystemDB.display_name(qsys), hopname, _fmt_nav_dist(rt.rel.length())]
				else:
					objective = "✦  QUEST  %s  —  no known route yet, explore on" % qtitle
	elif _nav_goal != "":
		# Map "Navigate" guide (orange): route over KNOWN links to the next hop's wormhole.
		var gname := SystemDB.display_name(_nav_goal)
		var rg := _route_to(_nav_goal)
		if rg.ok:
			var hopname := SystemDB.display_name(rg.hop)
			var tname := ("WORMHOLE → %s" % hopname) if rg.hop == _nav_goal else ("→ %s  via %s" % [gname, hopname])
			markers.append({ "rel": rg.rel, "name": tname, "dist": _fmt_nav_dist(rg.rel.length()), "color": Navigator.LOCK_COL })
			var via := "" if rg.hop == _nav_goal else "   (next: %s)" % hopname
			objective = "◆  NAVIGATE  %s%s   %s" % [gname, via, _fmt_nav_dist(rg.rel.length())]
		else:
			objective = "◆  NAVIGATE  %s  —  no known route yet, explore on" % gname
	elif _nav_locked != "":
		# LOCKED waypoint (orange) — autopilot / map "navigate to body". Name hidden until scanned.
		var lrel := _waypoint_rel(_nav_locked, _locked_wh)
		var lname := _tab_display_name(_nav_locked)
		markers.append({ "rel": lrel, "name": lname, "dist": _fmt_nav_dist(lrel.length()), "color": Navigator.LOCK_COL })
		objective = "◆  LOCKED  %s   %s" % [lname, _fmt_nav_dist(lrel.length())]

	# --- player X marks (always on, each its own colour) ---------------------------------
	var marks_start := markers.size()
	for i in _marks.size():
		var m: Dictionary = _marks[i]
		var mrel := _waypoint_rel(String(m.name), String(m.get("wh", "")))
		markers.append({ "rel": mrel, "name": "✖ %s" % _tab_display_name(String(m.name)),
			"dist": _fmt_nav_dist(mrel.length()), "color": MARK_COLS[i % MARK_COLS.size()] })

	# --- live Tab target (teal) ----------------------------------------------------------
	if _nav_target != "" and not _nav_off:
		var midx := _mark_index(_nav_target, _nav_wormhole)
		var tn := _tab_display_name(_nav_target)
		if _nav_target == _active_quest and quest_idx >= 0:
			# Tab is on the quest target — badge the purple quest marker, no stacked teal diamond.
			markers[quest_idx]["drop"] = true
		elif midx >= 0:
			# Already marked: don't stack a teal diamond on it — just badge the existing
			# coloured mark with a water-drop so you can see Tab is sitting on a marked target.
			markers[marks_start + midx]["drop"] = true
		else:
			var trel := _waypoint_rel(_nav_target, _nav_wormhole)
			markers.append({ "rel": trel, "name": tn, "dist": _fmt_nav_dist(trel.length()), "color": Navigator.COL })
		if objective == "":
			objective = "→  %s   %s" % [tn, _fmt_nav_dist(_waypoint_rel(_nav_target, _nav_wormhole).length())]

	# --- Survey guide fallback: never leave the player lost -------------------------------
	if markers.is_empty() and not _nav_off:
		var obj := _current_objective()
		if not obj.is_empty():
			markers.append({ "rel": obj.rel, "name": obj.name, "dist": _fmt_nav_dist(obj.rel.length()), "color": Navigator.COL })
			objective = "→  %s   %s" % [obj.name, _fmt_nav_dist(obj.rel.length())]

	navigator.set_markers(ship.camera, markers)
	hud.set_objective(objective)


# The current guidance objective:
#  • In the Interstellar hub — the nearest destination gate (a system to dive into).
#  • In any normal system — the nearest UN-surveyed star to fly to. Once they're all
#    surveyed, fall back to guiding you to the exit gate so you know to move on.
func _current_objective() -> Dictionary:
	# Initial phase: onboarding's final step asks the player to reach the wormhole, so
	# point the guide arrow straight at the gate (overriding nearby-star targeting) — they
	# can't miss where to go.
	if onboarding.current_step_id() == "wormhole":
		return _nearest_gate_objective()
	# The hub has no bodies — guide to the nearest gate to dive into.
	if current_system == SystemDB.INTERSTELLAR:
		return _nearest_gate_objective()
	# QUEST FIRST: with nothing explicitly tracked, the arrow points at the nearest UNSURVEYED
	# body — the next mission to finish right here. Once the system is fully surveyed it falls
	# back to the nearest wormhole (the way onward), so the arrow's never dead.
	var best := ""
	var best_d := INF
	var best_rel := Vector3.ZERO
	for bname in planets.targetables():
		if not _capturable(bname) or codex.is_discovered(bname):
			continue
		var rel: Vector3 = planets.rel_of(bname)
		var d := rel.length()
		if d > 0.001 and d < best_d:
			best_d = d
			best = bname
			best_rel = rel
	if best != "":
		return { "name": best, "rel": best_rel }
	return _nearest_gate_objective()

func _nearest_gate_objective() -> Dictionary:
	if wormhole == null:
		return {}
	var np := wormhole.nearest_portal(ship.true_pos)
	return {} if np.is_empty() else { "name": str(np.name), "rel": np.rel }

func _fmt_nav_dist(u: float) -> String:
	# u is kilometres (1 scene unit = 1 km). Old 0.01 AU/unit made Earth read hundreds of AU.
	if u < 1_000_000.0:
		return "%.0f km" % u
	var au := u / Ephemeris.AU_TO_UNITS
	if au < 1000.0:
		return "%.3f AU" % au
	return "%.3f ly" % (au / 63241.077)


# --- First-run onboarding -----------------------------------------------------
# Onboarding API — thin wrappers over the Onboarding controller (Phase 3). External callers
# (StarMap, QuestLog) and internal gameplay-event sites keep calling these on main unchanged.
func notify_map_opened() -> void: onboarding.notify_map_opened()
func notify_log_opened() -> void: onboarding.notify_log_opened()
func _ob_note(id: String) -> void: onboarding.note(id)
func restart_onboarding() -> void: onboarding.restart()
func onboarding_state() -> Dictionary: return onboarding.state()
func _update_onboarding() -> void: onboarding.update()


# The top-center quest tracker. A TRACKED quest (chosen in the J log) takes priority and shows
# where it's guiding you; otherwise it points at the nearest UNSURVEYED body in the system
# you're in, so there's always a "next thing to scan". When the system's fully surveyed it
# shows overall progress and nudges you to the J log. The full board lives in QuestLog (J).
func _update_quests() -> void:
	if codex == null:
		return
	# A tracked quest drives the tracker (self-heal if it was already surveyed).
	if _active_quest != "" and codex.is_discovered(_active_quest):
		_advance_quest()
	if _active_quest != "":
		var qsys := MissionDB.system_of(_active_quest)
		var where: String = "here — survey it" if qsys == current_system else "→ %s" % SystemDB.display_name(qsys)
		hud.set_quest("✦  TRACKING · %s   (%s · %d coins)"
			% [MissionDB.title_for(_active_quest), where, MissionDB.reward(_active_quest)])
		return
	var next_body := ""
	var nd := INF
	for body in MissionDB.bodies_in(current_system):
		if codex.is_discovered(body):
			continue
		var d: float = planets.rel_of(body).length()
		if d < nd:
			nd = d
			next_body = body
	if next_body != "":
		hud.set_quest("✦  MISSION · %s   —  survey %s  (%d coins)"
			% [MissionDB.title_for(next_body), next_body, MissionDB.reward(next_body)])
	else:
		var total := 0
		var done := 0
		for m in MissionDB.all_missions():
			total += 1
			if codex.is_discovered(m.body):
				done += 1
		if done >= total:
			hud.set_quest("✦  EVERY BODY SURVEYED — pilot of the Survey")
		else:
			hud.set_quest("✦  %s fully surveyed   ·   %d/%d catalogue  ·  press J for the next mission"
				% [SystemDB.display_name(current_system), done, total])


# Emergency return to Sol — the panic button. Always available; runs the full ritual.
func teleport_home() -> void:
	start_teleport(SystemDB.SOL, "EMERGENCY RETURN — HOME")


# The platform network you can fast-travel between: every system with a dockable platform
# that you've already REACHED (visited), minus the one you're docked at right now.
func _unlocked_platforms() -> Array:
	var out := []
	for id in SystemDB.all():
		if id == current_system or id == SystemDB.INTERSTELLAR:
			continue
		if SystemDB.is_teleport_platform(id) and GameState.visited.has(id):
			out.append({ "id": id, "name": SystemDB.display_name(id) })
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out


# True if `id` is a valid teleport destination: has a station, you've reached it, and it's
# not where you are now. Used by the teleport-mode map to decide whether to offer "confirm".
func is_teleport_unlocked(id: String) -> bool:
	return id != current_system and id != SystemDB.INTERSTELLAR \
		and SystemDB.is_teleport_platform(id) and GameState.visited.has(id)


# Dock → "TELEPORT NETWORK" button: open the ISOLATED platform console (its own screen, not
# the star map). Bright tiles = reached platforms you can jump to; pick one, confirm, and the
# teleport ritual carries you there. Always opens (so you can see locked platforms too).
func _on_open_teleport_map() -> void:
	if _tp_active or ship.transiting:
		return
	platform_tp.open()
	_ob_note("teleport_net")


# Dock → pick a platform from the teleport map: undock, then run the (shorter) teleport
# ritual to that system (the ritual's countdown doubles as the load delay; _arrive swaps
# systems at the end). Called by StarMap's teleport-mode confirm button.
func teleport_to_platform(id: String) -> void:
	if _tp_active or ship.transiting:
		return
	_set_docked(false)
	start_teleport(id, "PLATFORM JUMP → %s" % SystemDB.display_name(id), TELEPORT_PLATFORM_TIME)
	_tp_platform = true              # platform-network jump: land right beside the dest platform


# Begin the teleport ritual to `dest`. Freezes the ship, eases the camera back, and spins
# up the RGB ring; _update_teleport drives the countdown and does the actual _arrive at the
# end. `dur` is the ritual length. No-op if already teleporting or mid-wormhole.
func start_teleport(dest: String, label: String, dur := TELEPORT_TIME) -> void:
	if _tp_active or ship.transiting:
		return
	_tp_active = true
	_tp_t = 0.0
	_tp_dur = dur
	_tp_dest = dest
	_tp_label = label
	_tp_platform = false             # teleport_to_platform re-sets this true after this call
	ship.set_frozen(true)            # hold still + slow turntable (see ship.fly frozen branch)
	ship._set_capture(false)         # free the cursor so the Cancel button is clickable
	ship._cam_zoom = TELEPORT_ZOOM   # camera eases back (smoothed in ship._update_camera)
	if _tp_ring == null:
		_build_teleport_vfx()
	_tp_ring.visible = true
	hud.tp_cancel_button.visible = true   # let the player abort the ritual
	if audio != null:
		audio.play_click()
		audio.play_teleport()          # whoosh runs the whole ritual; its volume bells in/out
		audio.set_teleport_db(-60.0)   # start silent — _update_teleport fades it in


# Abort an in-progress teleport: stop the countdown, drop the cylinder, hand control back.
# The ship stays in the current system (it was already undocked when the ritual began).
func cancel_teleport() -> void:
	if not _tp_active:
		return
	_tp_active = false
	_core_dying = false              # if this was the core's death kick, aborting just lets it re-grab you
	if _tp_ring != null:
		_tp_ring.visible = false
	hud.tp_cancel_button.visible = false
	hud.set_menu("")
	ship.set_frozen(false)
	ship._cam_zoom = 1.0
	ship._set_capture(true)
	hud.toast = "Teleport cancelled."
	hud.toast_t = 2.0
	if audio != null:
		audio.stop_teleport()
		audio.play_click()


func _update_teleport(delta: float) -> void:
	if not _tp_active:
		return
	_tp_t += delta
	# A shiny ball of light wraps the ship, then SHRINKS down to a point over the ritual —
	# the ship is squeezed into a bead of light and, when the bubble hits 0, it jumps. A slight
	# light-wave shimmer + faster spin as it tightens; the glow concentrates as it collapses.
	var prog: float = clampf(_tp_t / _tp_dur, 0.0, 1.0)
	var shimmer: float = 1.0 + 0.06 * sin(_tp_t * 7.0)        # subtle wobble on the shell
	var shrink: float = 1.0 - prog                            # 1 -> 0 across the ritual
	_tp_ring.scale = Vector3.ONE * maxf(TP_ORB_BASE * shrink * shimmer, 0.02)
	_tp_ring.rotate_y((0.6 + 2.4 * prog) * delta)             # spins faster as it tightens
	# Cool energy colour that whitens as it collapses to a bead of light.
	var col: Color = Color(0.45, 0.82, 1.0).lerp(Color(1.0, 1.0, 1.0), prog)
	_tp_ring_mat.emission = col
	_tp_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.18 + 0.45 * prog)
	# Glow concentrates as the shell shrinks — a tight bright bead by the time it hits 0.
	_tp_ring_mat.emission_energy_multiplier = 0.9 + prog * 2.6
	# Whoosh volume envelope across the whole teleport: a long fade IN, then HOLD stable at
	# full, then fade OUT — a trapezoid (not a quick peak), so it swells, sustains, settles.
	if audio != null:
		var amp: float
		if prog < 0.4:
			amp = smoothstep(0.0, 0.4, prog)            # long fade in (first 40%)
		elif prog > 0.7:
			amp = 1.0 - smoothstep(0.7, 1.0, prog)      # fade out (last 30%)
		else:
			amp = 1.0                                    # stable hold (middle 30%)
		audio.set_teleport_db(TELEPORT_SFX_DB + linear_to_db(clampf(amp, 0.001, 1.0)))
	# Countdown overlay (reuses the centered menu label).
	var rem: int = int(ceil(maxf(_tp_dur - _tp_t, 0.0)))
	hud.set_menu("◇  TELEPORT  ◇\n\n%s\n\nLocking coordinates…\n\nArriving in  %d" % [_tp_label, rem])
	if _tp_t >= _tp_dur:
		_tp_active = false
		_tp_ring.visible = false
		hud.tp_cancel_button.visible = false
		hud.set_menu("")
		ship.set_frozen(false)
		ship._cam_zoom = 1.0
		if audio != null:
			audio.stop_teleport()
		_arrive(_tp_dest)
		if _tp_platform:
			_land_beside_dock()      # platform jump → emerge right next to the dest platform
			_tp_platform = false
		ship._set_capture(true)


# A small shiny ball of light that wraps the ship during a teleport. A translucent
# additive sphere (visible from inside, so the ship shows through) that pulses in a gentle
# light-wave and flares as the jump completes — driven by _update_teleport.
func _build_teleport_vfx() -> void:
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 32
	sph.rings = 16
	_tp_ring = MeshInstance3D.new()
	_tp_ring.mesh = sph
	_tp_ring_mat = StandardMaterial3D.new()
	_tp_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tp_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tp_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tp_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED       # glow shell visible from inside too
	_tp_ring_mat.emission_enabled = true
	_tp_ring_mat.emission = Color(0.45, 0.82, 1.0)             # cool energy glow
	_tp_ring_mat.albedo_color = Color(0.45, 0.82, 1.0, 0.18)
	_tp_ring_mat.emission_energy_multiplier = 0.9
	_tp_ring.material_override = _tp_ring_mat
	_tp_ring.scale = Vector3.ONE * TP_ORB_BASE
	_tp_ring.visible = false
	ship.add_child(_tp_ring)


# The galactic core as a lethal dead-end. Inside CORE_DANGER_LY the hull takes escalating
# gravitational-shear damage AND Sgr A*'s gravity drags you inward (you can fight it at the edge,
# but the deeper you go the more it overpowers your drive). It CAPTURES you at CORE_KILL_LY —
# while it still fills your view, before you ever reach the deep cloud — and the failsafe drive
# hurls you home, hull wrecked. Only runs on the Iron Pulse voyage (nothing else gets this close).
func _update_core_hazard(rem: float, delta: float) -> void:
	if _core_dying or _tp_active or ship.transiting:
		return
	if rem >= CORE_DANGER_LY:
		if _core_warned:                 # just fled the danger zone → clear the overlay once
			hud.set_menu("")
			_core_warned = false
			_core_dmg_accum = 0.0
		return
	# 0 at the danger edge → 1 at the kill/capture line.
	var depth := clampf((CORE_DANGER_LY - rem) / (CORE_DANGER_LY - CORE_KILL_LY), 0.0, 1.0)
	_core_warned = true
	hud.set_menu("⚠   SAGITTARIUS A*   ⚠\nEVENT HORIZON   ·   %d ly\nIT HAS YOU — THE CORE DOES NOT FORGIVE" % int(rem))
	hud.flash(0.18 + 0.55 * depth)       # rising red pulse the deeper you push
	# Gravitational pull: redirect the ship inward and reel it in, harder the deeper you are.
	# At the edge it's a tug you can still escape; near the line it overpowers your drive entirely
	# — the hole takes you, you don't choose to dive. This is what kills you before the deep cloud.
	var dir_in := GalaxyModel.DIR.normalized()
	var target_v := dir_in * maxf(ship.velocity.length(), CORE_MIN_PULL * depth)
	ship.velocity = ship.velocity.lerp(target_v, clampf(CORE_PULL_GRAB * depth * delta, 0.0, 1.0))
	# Hull shred ramps with depth (player_hp is int, so carry the fraction between frames).
	_core_dmg_accum += CORE_MAX_DPS * depth * delta
	var dmg := int(_core_dmg_accum)
	if dmg > 0:
		_core_dmg_accum -= dmg
		combat.player_hp = maxi(combat.player_hp - dmg, 0)
	# Captured at the horizon line (or hull gone) → the hole takes you.
	if rem <= CORE_KILL_LY or combat.player_hp <= 0:
		_core_kill()


# Last frame's ship offset from the nearest body's centre, for the swept contact
# test. _prev_body records which body that was, so a change of nearest body does
# not sweep a segment across interplanetary space and report a false crash.
var _prev_from_centre := Vector3.ZERO
var _prev_body := ""


func _update_skin_kill(delta: float) -> void:
	if _skin_dying:
		_skin_t += delta
		ship.locked = true
		ship.velocity = Vector3.ZERO
		hud.flash(0.55, Color(0.85, 0.08, 0.06))
		if planets != null and planets.has_method("hush_surface"):
			planets.hush_surface()
		if _skin_t >= Ephemeris.SURFACE_KILL_SECS:
			_skin_finish()
		return
	if _tp_active or ship.transiting or docked or _core_dying:
		return
	if not ship.newton:
		return
	if not planets.is_physical(planets.nearest_name):
		return
	if planets.nearest_dist >= INF or planets.nearest_radius <= 0.0:
		return
	var sampler := planets.terrain_sampler_for(planets.nearest_name)
	if sampler == null:
		return
	# The sampler works in the BODY's frame. planets.rel_of() is the render-space
	# vector ship->body, so the ship's offset from that body's centre is its
	# negation. Using the sphere-relative altitude here instead would be wrong by
	# the full height of the terrain - 8.9 km over Everest.
	var from_centre: Vector3 = -planets.rel_of(planets.nearest_name)
	if from_centre.length() < 0.001:
		return
	var contact: float = Ephemeris.surface_kill_km(planets.nearest_name)
	# SWEEP the segment this frame covered, not just where it ended. Both ends of
	# one frame's travel can be clear air with a ridge standing between them, and
	# a frame-rate dip is exactly when that happens - see
	# tools/test_earth_terrain.gd, which asserts a point test WOULD have missed it.
	# _prev_body guards against sweeping across interplanetary space when the
	# nearest body changes.
	var prev: Vector3 = _prev_from_centre if _prev_body == planets.nearest_name \
		else from_centre
	_prev_from_centre = from_centre
	_prev_body = planets.nearest_name
	if sampler.swept_contact(prev, from_centre, planets.nearest_radius, contact):
		_skin_begin(planets.nearest_name)


func _skin_begin(body: String) -> void:
	_skin_dying = true
	_skin_t = 0.0
	_skin_body = body
	ship.locked = true
	ship.velocity = Vector3.ZERO
	ship.dev_speed = false
	if planets != null and planets.has_method("hush_surface"):
		planets.hush_surface()
	hud.flash(1.0, Color(0.9, 0.05, 0.04))
	hud.set_death(true, "HULL LOST\nNO LANDING  ·  %s\n\nrespawn in a moment" % body.to_upper())


func _skin_finish() -> void:
	var who := _skin_body
	var dest: Vector3 = Ephemeris.sweet_spot(who)
	hud.set_death(false)
	hud.set_menu("")
	_skin_dying = false
	_skin_t = 0.0
	_skin_body = ""
	ship.locked = false
	ship.reset_mesh_pose()
	ship.true_pos = dest
	ship.velocity = Vector3.ZERO
	ship.face_toward(-dest if who == "Earth" or who == "" else (Ephemeris.scene_pos(who) - dest))
	combat.player_hp = ship.max_hp
	hud.toast = "▲  respawn  ·  safe park above %s" % (who if who != "" else "Earth")
	hud.toast_t = 3.2


func _core_kill() -> void:
	_core_dying = true
	_core_dmg_accum = 0.0
	hud.set_menu("")
	hud.flash(1.0)                                       # hard white-hot/red kick in the teeth
	combat.player_hp = maxi(1, int(combat.player_max * 0.08))   # spat back out near-dead
	hud.show_lore("THE CORE DOES NOT FORGIVE\n\nSagittarius A* seized the ship and dragged it toward the horizon. The failsafe drive tore you back across the galaxy at the last instant. Nothing returns from there whole.")
	teleport_home()                                      # the violent kick — emergency ritual to Earth


# Emerge from a wormhole in a new system: swap bodies, hard-reset the ship to a
# small LOCAL coord (so float precision is never stressed), re-aim the portal.
func _arrive(system_id: String, at_pos := Vector3(INF, INF, INF)) -> void:
	_core_dying = false              # landed home → the core's grip is broken
	_core_warned = false
	_core_dmg_accum = 0.0
	_skin_dying = false
	_skin_t = 0.0
	_skin_body = ""
	if ship != null:
		ship.locked = false
		ship.reset_mesh_pose()
	if hud != null and hud.has_method("set_death"):
		hud.set_death(false)
	var first_visit := not GameState.visited.has(system_id)
	GameState.visited[system_id] = true       # now a KNOWN system → instant map fast-travel hereafter
	GameState.nav_unlocked.erase(system_id)   # discovered → no longer just a "nav-unlocked" lane
	current_system = system_id
	planets.load_system(SystemDB.bodies(system_id))
	planets.speed_zones = false   # Sol 1:1 slice: speed pass comes later
	ship.newton = system_id == SystemDB.SOL
	if ship.camera:
		ship.camera.far = Ephemeris.CAM_RENDER_FAR_KM
	# Fly-arrive passes your preserved local offset (no teleport); wormhole/map use the system's pad.
	ship.true_pos = at_pos if not is_inf(at_pos.x) else SystemDB.arrival_pos(system_id)
	ship.transiting = false
	galaxy.reset_distance()                   # back in a normal system → core is ~26,000 ly away again
	ship.face_toward(-ship.true_pos)          # look back toward the system's star
	# Show this system's neighbour wormholes that the player KNOWS — fly through any to
	# transit straight to that neighbour (no central hub in the loop anymore).
	wormhole.set_portals(_known_portals(system_id))
	if system_id == _nav_goal:
		_nav_goal = ""                             # reached the guided star — clear the guide
	props.set_system(system_id)                    # show this system's stations/probes
	# A large alien swarm haunts every star except peaceful Sol; Vortex (the boss)
	# still only holds the true hostile Alien zone.
	# Only the hostile Alien zone gets an always-on respawning swarm. Every other star
	# system is quiet until you approach a guarded body, which spawns ONE big boss you
	# kill once (the per-body guardians, no respawn).
	var fight := SystemDB.is_hostile(system_id)
	combat.reset(fight, SystemDB.is_hostile(system_id))
	combat.player_hp = ship.max_hp
	_nav_target = ""                               # clear the waypoint in the new system
	_marks.clear()                                 # X marks are system-local — drop them on jump
	ship.autopilot = false                         # don't keep flying to an old-system target
	if docked:
		_set_docked(false)
	hud.origin_name = SystemDB.display_name(system_id) if system_id != SystemDB.SOL else "Earth"
	# First time here = the trip paid off: coins, a rank bump, and a lore card. Re-visits
	# (fast-travel, teleport home) are silent — the reward is for discovery, not commuting.
	if first_visit and system_id != SystemDB.SOL:
		GameState.coins += GameState.ARRIVAL_REWARD
		hud.toast = "✦  NEW SYSTEM — %s   ·   +%d coins   ·   %s (%d charted)" \
			% [SystemDB.display_name(system_id), GameState.ARRIVAL_REWARD, survey_rank_title(), survey_rank()]
		hud.toast_t = 5.0
		var lore: String = SystemDB.lore(system_id)
		if lore != "":
			hud.show_lore("%s\n\n%s" % [SystemDB.display_name(system_id), lore])
	_save_profile()                                # persist visited set + any reward
	print("[wormhole] arrived at %s — ship.true_pos.length()=%.2f (must be small)"
		% [SystemDB.display_name(system_id), ship.true_pos.length()])


# Platform-network arrival: instead of the far generic arrival point, set down right beside
# the destination platform so you emerge nose-on and already in the docking ring (no long
# fly-back). props.set_system (called from _arrive) has just placed this system's dock, so
# props.dock_pos is current. We sit a short hop off it on the star-facing side and aim the
# nose at the platform. (Bodies render at true_pos - ship.true_pos, so the dock renders at
# props.dock_pos - ship.true_pos — that's what we face toward.)
func _land_beside_dock() -> void:
	if not props.has_dock:
		return
	var st: Vector3 = props.dock_pos
	var to_star: Vector3 = (-st).normalized() if st.length() > 0.001 else Vector3.FORWARD
	var gap: float = clampf(props.dock_range * 0.6, 35.0, 60.0)   # close, but inside the ring
	ship.true_pos = st + to_star * gap
	ship.velocity = Vector3.ZERO
	ship.face_toward(st - ship.true_pos)     # nose dead-on the platform (rendered position)


# --- Docking at the station + ship swap ---
# How far out (beyond dock_range) the landing zone begins force-slowing the ship.
const DOCK_SLOW_MARGIN := 40.0

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key == KEY_F:
		# One interact key: undock if docked, else open the wormhole if near it,
		# else dock if near the station.
		if docked:
			_set_docked(false)
		elif wormhole.in_range(ship.true_pos):
			wormhole.start_transit()
			ship.transiting = true
		elif _dock_in_range:
			_set_docked(true)
	elif key == KEY_TAB:
		_cycle_nav_target()
		get_viewport().set_input_as_handled()
	elif key == KEY_NUMLOCK:
		# Num Lock = auto-cruise: hold W + Shift hands-free until toggled off.
		ship.auto_cruise = not ship.auto_cruise
		hud.toast = "AUTO-CRUISE  ON  ·  hands-free W + boost" if ship.auto_cruise else "AUTO-CRUISE  OFF"
		hud.toast_t = 2.0
	elif key == KEY_N:
		toggle_nav()          # keyboard shortcut for the ⊘ NAV stop/resume button
	elif key == KEY_C and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and Input.is_physical_key_pressed(KEY_W):
		# W + C = cinematic drift-flip. A/D picks the side (default right).
		var fd := 1.0
		if Input.is_physical_key_pressed(KEY_A):
			fd = -1.0
		elif Input.is_physical_key_pressed(KEY_D):
			fd = 1.0
		ship.do_flip(fd)
	elif key == KEY_ESCAPE and not ship.transiting and not ship.frozen:
		# Esc = release the mouse; press again to re-capture (back to flight).
		ship._set_capture(Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED)
	elif key == KEY_H and not ship.transiting and not _tp_active:
		teleport_home()
	elif key == KEY_F3:
		_perf_on = not _perf_on          # toggle the perf/leak readout
		if not _perf_on:
			hud.set_debug("")
	elif key == KEY_S and ship.auto_cruise:
		# Tapping reverse drops you out of hands-free auto-cruise (don't consume the
		# event — S still applies reverse thrust this frame).
		ship.auto_cruise = false
		hud.toast = "AUTO-CRUISE  OFF"
		hud.toast_t = 2.0
	elif docked and key >= KEY_1 and key <= KEY_4:
		ship.swap_ship(key - KEY_1)
		combat.player_hp = ship.max_hp   # new hull -> its full defence


func _set_docked(d: bool) -> void:
	docked = d
	ship.set_frozen(d)
	if d:
		_ob_note("dock")


# F3 perf/leak readout (throttled to ~3 Hz so the text relayout is cheap). Watch which
# counter climbs during play: OBJ/ORPHAN rising = node/resource leak; RAM rising = memory
# leak; RENDER rising = draw-load growth (e.g. too many hub portals/stations on screen).
func _update_debug(delta: float) -> void:
	if not _perf_on:
		return
	_perf_t -= delta
	if _perf_t > 0.0:
		return
	_perf_t = 0.33
	var obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphan := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ram := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var rend := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var fps := int(Performance.get_monitor(Performance.TIME_FPS))
	hud.set_debug("FPS %d  ·  OBJ %d  ·  ORPHAN %d  ·  RAM %.0f MB  ·  RENDER %d" \
		% [fps, obj, orphan, ram, rend])


func _update_dock_ui() -> void:
	if _tp_active:
		return                       # the teleport ritual owns the centered overlay
	# Wormhole transit takes over the screen with its countdown.
	if ship.transiting:
		var rem := wormhole.transit_remaining()
		hud.set_prompt("")
		hud.set_hangar(false, PackedStringArray(), 0, "")
		hud.set_menu("— WORMHOLE TRANSIT —\n\n→ %s   ·   %.0f ly\n(light would take %.0f years)\n\nArriving in  %d:%02d"
			% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly, wormhole.dest_ly,
			int(rem) / 60, int(rem) % 60])
		return

	hud.set_menu("")
	# Dock target: in a star system it's that system's station (props). In the Interstellar
	# hub there's no props station — instead ~half the KNOWN wormholes carry a space
	# PLATFORM, so the target is the NEAREST platform (wormhole.nearest_station), letting
	# you dock/swap close to wherever you are rather than flying back home.
	var has_dock := props.has_dock
	var dock_pos := props.dock_pos
	var dock_name := props.dock_name
	var dock_range := props.dock_range
	if current_system == SystemDB.INTERSTELLAR:
		var st := wormhole.nearest_station(ship.true_pos)
		has_dock = not st.is_empty()
		if has_dock:
			dock_pos = st.pos
			dock_name = st.name
			dock_range = st.range
	var dock_dist := (dock_pos - ship.true_pos).length() if has_dock else INF
	_dock_in_range = dock_dist < dock_range
	# Force-slow the ship as it enters the landing zone (smooth, proximity-based):
	# 0 at the outer edge (dock_range + DOCK_SLOW_MARGIN), 1 once inside the pad.
	ship.dock_approach = clampf(1.0 - (dock_dist - dock_range) / DOCK_SLOW_MARGIN, 0.0, 1.0) \
		if dock_dist < INF else 0.0
	if docked:
		hud.set_prompt("")
		hud.set_hangar(true, _ship_names(), ship.current_index(), dock_name, _unlocked_platforms())
	else:
		hud.set_hangar(false, PackedStringArray(), 0, "")
		if _dock_in_range:
			hud.set_prompt("» Press F to dock at %s «" % dock_name)
		elif props.probe_in_range:
			hud.set_prompt(_probe_readout())   # drift up to a probe -> monster data
		elif wormhole.in_range(ship.true_pos):
			hud.set_prompt("» Press F to enter the wormhole to %s  (%.0f ly) «"
				% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly])
		else:
			hud.set_prompt("")


# Probe scan readout: the "monster data" a drifting probe reports for its sector
# (how many hostiles, whether Vortex is here, your kill tally). Nothing else.
func _probe_readout() -> String:
	var t := combat.threat_report()
	var out := "◇ PROBE SCAN · %s ◇\n" % SystemDB.display_name(current_system)
	if int(t.total) <= 0:
		return out + "No hostiles detected in this sector."
	out += "Hostiles: %d / %d active\n" % [t.alive, t.total]
	var boss: Dictionary = t.boss
	if boss.alive:
		out += "⚠ %s present — %d/%d HP\n" % [String(boss.get("name", "VORTEX")).to_upper(), boss.hp, boss.max]
	return out + "Confirmed kills: %d" % t.kills


func _ship_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in ship.ship_count():
		names.append(ship.ship_name_at(i))
	return names


# Clicking a hangar row swaps to that ship — only meaningful while docked.
func _on_hangar_pick(index: int) -> void:
	if docked and index >= 0 and index < ship.ship_count():
		ship.swap_ship(index)
		combat.player_hp = ship.max_hp   # new hull -> its full defence


func _on_ship_color_pick(part: String, key: String) -> void:
	if docked:
		ship.set_ship_color(part, key)
		_save_profile()


func _on_ship_finish_pick(key: String) -> void:
	if docked:
		ship.set_ship_finish(key)
		_save_profile()


# Background music (mix hierarchy: gunfire/SFX > engine > music) lives in MusicDirector now.


func _setup_environment() -> void:
	# Glow does the heavy lifting for the "dots and glow" look. No Light3D
	# anywhere — bodies are emissive, ambient fills the rest. Shadows are moot
	# without lights, so nothing to disable.
	var env := Environment.new()

	# Clean black space (no sky gradient — the Sun key light defines form now).
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.34)
	env.ambient_light_energy = 0.2    # low — key+fill lights define form now, so the
									  # hull keeps contrast/detail instead of washing pale
	# (Affects only lit objects — stars/planets are emissive, background stays black.)

	# Glow ONLY the genuinely bright things (stars, the Sun) — not lit surfaces.
	# glow_bloom>0 was haloing the lit metal hull into a "bulb"; with bloom 0 and
	# an HDR threshold, only pixels brighter than 1.0 (emissive bodies) bloom, so
	# the ship reads as shiny lit metal with a gradient, not a glowing bulb.
	# ONE GLOW LEVEL, and it is ON. There used to be a High/Low pair (High = the values
	# below, Low = glow off entirely), which is not two qualities, it is a toggle wearing
	# the wrong labels. This is the single setting that sits BETWEEN them: the same tuned
	# level weights and HDR threshold as the old High, at roughly half its amplitude.
	#   old High:  intensity 0.9, bloom 0.05   <- the "booster grew a ball" config
	#   old Low:   glow off                    <- nothing blooms at all
	#   now:       intensity 0.45, bloom 0.0   <- a halo on the plume, no frame lift
	# glow_intensity is the amplitude dial on the whole blur chain, so halving it halves
	# both the halo's brightness and the radius at which it is still visible. bloom goes
	# to 0 because it bleeds EVERY pixel regardless of the HDR threshold - harmless while
	# glow was off, a flat lift across the frame now that it ships on.
	env.glow_enabled = true
	env.glow_normalized = true     # normalize levels so the neon thruster bloom blends evenly
	env.glow_intensity = 0.45      # half of the old High; the one glow variant
	env.glow_bloom = 0.0           # no untresholded bleed — see above
	env.glow_strength = 0.85
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# THE LEVEL WEIGHTS ARE THE HALO RADIUS. Level 1 is a half-resolution blur, level 5
	# is 1/32 — whatever weight level 5 carries is smeared over an enormous area. The old
	# 1:0.2 / 3:0.4 / 5:0.7 put the MOST weight on the widest blur, which is why every
	# hot pixel grew a soft ball that swallowed the ship. Measured in the chase view, the
	# radius at which the ring-mean luminance is still visible, at full burn:
	#     old 111 px (dingo57) / 142 px (snarkrans) / 199 px (jazoone)
	#     now  77 px           /  77 px            /  87 px
	# Same core, same emissive values — halving the plume shaders' energy on top of this
	# moved the frame by less than 0.1%, so the core was never the problem, the skirt was.
	env.set_glow_level(1, 0.8)
	env.set_glow_level(2, 0.4)
	env.set_glow_level(3, 0.15)
	env.set_glow_level(5, 0.0)

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.7   # global -30% brightness (keeps colour + specular)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env   # kept so the Settings menu can toggle glow quality
