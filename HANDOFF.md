# Astryx — AAA booster/thruster pass (2026-09-02)

## What the thruster is now

Four layers, all driven from ONE value (`Ship._propulsion_power` + `_propulsion_surge`)
so no layer can disagree with another about how hard the engine is working:

1. **Torch cones** — `shaders/cruiser_torch.gdshader`, two per socket (fog sheath +
   inner core), built by `ShipMesh._add_torch_layer`.
2. **Nozzle lights** — `OmniLight3D` per socket. The torch is emissive geometry and
   cannot light anything; this is what puts engine glow on the hull.
3. **Heat haze** — `shaders/exhaust_haze.gdshader`, a screen-space refraction shell.
4. **Glow** — unchanged; the existing `WorldEnvironment` picks up the HDR emission.

Layers 2-3 live under a separate `BoosterNozzleRig` node, NOT under the per-ship plume
root. The plume roots have a checked contract ("N sockets -> exactly 2N CylinderMesh
children") and the contract tests assert exact child counts.

**There is deliberately no ember/spark particle layer.** One was built (a single
`GPUParticles3D` per ship on `EMISSION_SHAPE_POINTS`) and removed: with the emitter in
the scene the hull region washed out warm — a 960x540 frame went from 0.2% to 12.7%
bright pixels — and shrinking the sparks ~8000x (converting their scale from model to
world units) barely moved it, 12.0% -> 10.3%. So the cause is the emitter's presence,
not the quad size, and it was not worth shipping unexplained. If you try again, gate it
on `tools/render_thruster.tscn ISOLATE=no_embers` before keeping it.

## Torch shader specifics

- **Turbulence** comes from `assets/fx/exhaust_noise.png` (baked by
  `tools/gen_exhaust_noise.py`), sampled in `(angle, axial - flow)` space so it advects
  downstream, with a domain warp so filaments curl. It replaced the old `sin()` pair.
- **Seam:** `atan()` wraps a full turn at the back of the plume; automatic mip
  selection reads that as a huge UV step and drops to the blurriest mip, drawing a grey
  line down the exhaust. `flow_sample()` fixes it with `textureGrad` + wrapped
  derivatives. Do not replace it with a plain `texture()` call.
- **Shock diamonds** (Mach disks) are the strongest "real rocket" cue. Core layers only
  (`SHOCK_TRAIN`); on the fog sheath they read as banding.
- **Temperature ramp:** cold engine = orange, hot = blue-white. Shared with the JazOone
  hull disc so the disc and its plume never disagree.
- **Throttle shaping** happens in the vertex stage (`length_scale`, `flare_scale`),
  stretched about the NOZZLE end, not the centre, so a longer flame keeps its root on
  the socket. This needs `extra_cull_margin` or the plume pops off at high throttle.
- **Depth fade** is in WORLD units (view-space depth) while the mesh is in model space,
  so `_add_torch_layer` converts through the `fit_model` scale.

## JazOone — two things were actually broken

- Its engine discs were gated on `booster_uv_a`/`booster_uv_b` UV discs AND the emissive
  mask. `tools/probe_jazoone_sockets.gd` proves **no vertex UV lands inside either
  disc**, so that branch never ran. The UV gate is gone; the emissive mask alone is
  precise (3464 of 310277 vertices, in exactly two tight clusters).
- It had no plume geometry at all. `add_jazoone_booster_plumes` now builds it on the two
  probed sockets.
- **Mind the sign:** JazOone imports with `yaw: 0`, so its rear is **+Z**. The other
  three are `yaw: 180` and vent along **-Z**. `_add_torch_layer(..., facing)` carries
  this; a sign slip buries the flame inside the hull.

## Tooling

- `tools/gen_exhaust_noise.py` — bakes the tiling noise (seeded/deterministic). Periodic
  Perlin, not value noise (value noise leaves a visible rectilinear grid), with
  histogram equalisation (plain min/max rescale leaves FBM as grey mush).
- `tools/probe_jazoone_sockets.gd` — recovers sockets from the emissive mask.
- `tools/render_thruster.tscn` + `.gd` — offscreen contact sheet, all 4 ships x 3
  throttle settings, mirroring main.gd's environment. Run as a **scene**, not
  `--script`:
  `SHOT_DIR=/tmp/shots xvfb-run -a <godot> --path <copy> res://tools/render_thruster.tscn`

## Gotchas hit

- `TAU` is a **built-in** Godot shader constant; redefining it is a compile error.
- Headless (`--headless --script`) DOES compile shaders through the dummy renderer, so
  shader errors surface in the contract tests. Use that as the fast gate.
- `assets/fx/exhaust_noise.png.import` must stay `compress/mode=0`,
  `detect_3d/compress_to=0`, `fix_alpha_border=false`. The four channels are
  independent data; block compression correlates them and alpha-border bleeding
  corrupts RGB.

---

# Astryx — Authored ship roster and propulsion handoff (2026-08-27)

## Current state

- The player roster is now four authored ships: **Class II Galactic Cruiser**
  (default), **Snarkrans Starship**, **Dingo57 Starship**, and **SpaceShip**
  (JazOone / Sketchfab CC-BY).
- SpaceShip's `Layer_1` is five `Layer_1_Material_0` chunks of the **whole hull**
  (vertex-split, not five boosters). Painting them with the additive propulsion
  shader made the ship solid white. Hull now keeps its albedo; the HDR torch
  is masked to the two emissive engine discs.
- SpaceShip yaw is `0`. The Sketchfab GLB already faces correctly; the OBJ
  ships' `yaw: 180` flipped this one so the nose sat where the engines belong.
- The previous player ships, their dedicated engine loops/music, and the random
  procedural booster-layout system were removed.
- Hull customization is restored for every non-booster surface. Propulsion
  surfaces are excluded by shader identity and always remain white-hot.
- Class II uses its six authored `propulsion` patches as exact sockets. Each has
  a nested HDR white core and longer cyan fog sheath behind the nozzle face.
- Snarkrans uses the user-identified `.000` and `.010_...018` upper-booster
  objects plus the `.005_...035` and `.001_...034` lower-pair objects. Their
  three empty centers are filled with dense emissive plugs, then extended with
  the same nested torch treatment.
- Dingo57's eight user-identified booster groups retain their authored geometry,
  get the HDR propulsion material, and now also get fog+core trails from their
  rear faces (070/109 = center pair halves).
- The shared torch shader now flows: axial wisps, radial edge fade, white core
  going cyan toward the tip. JazOone SpaceShip is left as-is.
- Dingo57 ingest now keeps the eight booster groups as dedicated surfaces
  and merges every remaining face into one opaque `hull_body` surface.
  Runtime styling forces that hull opaque and double-sided, including under
  glassy hangar finish, so thin chassis panels (including bottom groups
  `053`, `065`, `092`, `104` and the earlier outer groups) cannot vanish.
  Do not split the hull back into SketchUp glass/opaque material buckets.
- Booster materials react to throttle, boost, warp charge, and starvation
  sputter. No booster position is randomized.

## Verification and constraints

- Headless contract tests cover all three imported ships and customization.
- Codex did not launch or visually render the game; the user reviewed the visual
  result and accepted the current pass as good enough to push.
- Keep future booster work mesh-specific. Tune the authored surface/socket and
  its emissive plume; do not restore the old random booster generator.
- Do not record this personal Astryx/space-game work in monthly worklogs.

## Best next action

Continue with user-directed visual tuning. For propulsion, adjust only the named
ship's socket radius, plume width/length, or shader brightness; preserve the
other ships and keep booster meshes outside hull recoloring.

---

# Astryx — Session Handoff (Sol cook · 2026-08-20)

Private repo: `git@github.com:Fiazul/space-survey.git` (`main`).
Godot 4.6.2. Game is code-spawned. First pass. Do not treat Sol as finished.

## Start here next time

**Bug: Sun vanishes on close approach.** Player flew DEV toward the Sun
(~0.109 AU, tape `Alt 15,653,855 km Sun`). Then lost the Sun getting closer
(they described a meter-scale region — recreate, do not guess the exact
number). Likely code: sky disc hides below `max(CAM_FAR*0.5, R_sun*1.2)`
≈ 835,000 km from centre (~140,000 km above photosphere), and the cook
mesh stays off because physical stars force `too_far = true`. Both off =
no Sun. Recreate with F9 at the Sun until Zone hits SKIN/INSIDE / skin
alt drops under ~140,000 km. Fix that first. The Sun is a `kind` 3 star,
not a unique object.

## What landed this slice

- One cook. Sol maps. Other stars cook from spectral type (no `sol.obj`).
  Exoplanets invent from radius/temp. Sky = HYG points; a ball cooks on arrival.
- 2k mosaics: Phobos, Ganymede (USGS sheet crop, grid still on), Callisto,
  Cassini majors, Uranian majors, Triton, Pluto, Charon. Deimos still pending.
- Moon from GEO is a real ball (far plane 520,000 km). Spawn still faces Earth.
- Sky Sun: 0.53° photosphere + circular corona (square glare was a quad with
  leftover edge glow; discarded + angular cap).
- Kind-3 burn: granules, limb, chromosphere rim.
- Tape: `Zone CENTER|INSIDE|SKIN|AIR|SPACE` + skin alt. Earth air 100 km.
  Spec: `docs/specs/2026-08-20-sol-flight-layers-design.md`.

## Next plan (after the close-Sun vanish)

1. Recreate + fix Sun/star LOD so one path handles far disc and close ball
   (Sun = just a star). No special `_sun_sky` forever.
2. Same LOD for any star: catalog row → position → recipe → render.
3. Earth look pass. Ganymede gridless map swap. Deimos mosaic.
4. Richer 101 km-band bird view. Titan/Venus air as real shells later.

## Not done

Earth polish. 8k USGS. Landing. Vacuum RCS. Flight feel. Billion visitable
meshes (sky points only until you arrive).

# Astryx — Session Handoff (v0.11.5 · current)

> Pick-up doc for the next session. Project: `/home/fiazul/Desktop/Astryx`
> Godot 4.6.2 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main).
> The game is **all code-spawned** — `Main.tscn` is a one-node stub; `main.gd` builds the
> world, ship, camera, lights, and UI at runtime.
> ✅ **Everything through v0.11.5 is committed + pushed** to `main`.
> ~12k lines of GDScript · ~35 modules · 7 ships · ~50 real star systems · Android APK + CI.

## What changed in v0.11.5 (latest)

- **Codebase modularization** — split the god-files into domain folders
  (`core/flight/world/travel/combat/ui` + `autoload/`) behind autoload singletons
  (`GameState`/`Ephemeris`/`Codex`/`PlanetData`/`GameAudio`); `main.gd` 2093→1780,
  `combat.gd` 1352→1031 (CombatFX + EnemyFactory split out). Map in
  [`ARCHITECTURE.md`](ARCHITECTURE.md), rationale in `docs/adr/0001-*`.
- **Galactic core cleanup** — removed the experimental Sgr A\* black-hole visual; the
  Milky Way galaxy backdrop + looming approach remain (`scripts/world/galaxy_model.gd`).
- **Ship music** — **Vela Iron Pulse** & **Lyra** now fly to the dedicated interstellar
  theme (`bgm_hani.ogg`), alongside HaniNebula & Raptor 2 Neo.

## What changed in v0.11.4

- **Realistic star field** — background sky is now a **baked real-catalogue points-mesh**
  (`scripts/starfield.gd` + `tools/build_starfield.gd`): default **HYG naked-eye, ~15,598 real
  stars** (mag ≤ 7), real sky positions, real B-V→RGB colour, magnitude-driven size/glow.
  Tiers `naked` / `tycho` / `high` / `low`. Full report: [`STARFIELD.md`](STARFIELD.md).
- **The galactic core** — the Milky Way is now visible as a textured **galaxy backdrop**
  (`scripts/galaxy_model.gd`, `assets/galaxy.glb`, CC-BY): placed toward the **real Sgr A\***
  direction, laid edge-on in the real galactic plane, additive glow + a radial-fade disc
  shader (no hard polygon edge), no occlusion of the starfield. Backdrop only — not a
  destination (~26k ly is past float32's reach). See [`STARFIELD.md`](STARFIELD.md).
- **Mars's moons** — added **Phobos & Deimos** (`ephemeris.gd`) with codex fact-sheets
  (`planet_data.gd`) and missions (`missions.gd`); fixed a **moon-detachment bug** where
  moons orbited their parent's raw Horizons position instead of its revolved scene position
  (`planet_system.gd` `frame_pos` cache, in both `refresh()` and `gravity_at()`).

## What changed in v0.11.1 → v0.11.3

- **v0.11.1** — dark, dramatic **wormhole transit visual** (the *style* pass promised in the
  v0.11.0 next-plan: ship holds facing the portal, slight shake, dark + cinematic).
- **v0.11.2** — **boss fights** + a **combat HUD target** readout; **drift-flip** (W+C) flight
  move; teleport / UX fixes.
- **v0.11.3** — **beginner quest** onboarding; **finite guardian waves** (swarms now end);
  **escape leap**; **capture ring** VFX; star-**gravity fixes**.
- **Docs/assets** — added [`CREDITS.md`](CREDITS.md) (models = Poly Pizza / Free3D, SFX =
  scripts, music = AI-generated) + README **Assets** section.

## What changed in v0.11.0

### Camera / controls
- **Free-look is HOLD again** (`ship.gd`): hold **T** (or RMB) to orbit the camera; full **360°**
  (yaw clamp removed); wider zoom (`ZOOM_MIN 0.2 … ZOOM_MAX 6.0`).
- **Crosshair pinned to the nose** (`hud.gd _draw`/`set_lock_progress`): the reticle is projected
  from the ship's forward ray each frame, so it sits exactly on the shot line through camera sway.
- **Muzzle moved to the nose tip** (`ship.gd muzzle = box.size.z * 0.42`).

### Weapons → hitscan "ray bullets"
- Player fire is now an **instant hitscan ray** (`combat.gd _fire_ray` / `_show_shot_beam`), not a
  projectile: no float-precision blob, no drift, no bloom-bar. A bright tracer **pulse** flashes per
  shot (`SHOT_*` consts). Aliens still fire dodgeable projectiles.
- New laser-zap **fire SFX** (`tools/gen_fire_audio.py` → `sfx_fire.wav`); bolt bloom tamed
  (`_bolt_material` emission 20→4, HaniStar 36→8). The `Smg Bullet.glb` projectile path is retired.

### Tab targeting — ray raycast (see `TAB_TARGETING.md` / `.png`)
- `main._aim_ranked()` returns the **up-to-4 objects the aim ray passes nearest to** (smallest
  ANGLE off the line); `_cycle_nav_target()` steps 1st→2nd→3rd→4th→loop; moving the cursor
  re-ranks. **Narrow ~7° beam** for bodies, **wide 28° for wormholes** (key nav targets); per-kind
  long reach (`_tab_pick_range`: star 30 ly, planet 0.3–2, moon 0.6, probe 0.3). NOT nearest-to-ship.
- Wormholes check **every** active portal (`portals_rel`), track which (`_nav_wormhole` / `_locked_wh`).
- **Undiscovered targets read "Unknown Planet/Star/…"** until scanned (`_tab_display_name`).
- **Hold X ≥1s** → locks the Tab target as an **orange** waypoint (`lock_nav_target`); a radial
  **lock ring** fills around the crosshair (`hud._draw_lock_ring`). Orange persists through aim/Tab
  changes — only the **✖ CANCEL NAV** button clears it. **Raptor form swap moved off X → hold RMB ≥1s**
  (`main._update_holds`).

### Gravity & slow-zones (`planet_system.gd`)
- **Star gravity ON** (`STAR_GRAVITY_ENABLED`) — stars pull the ship (planets/bolts stay off). It
  **fades as you thrust away** so it never traps you (`ship.gd` gravity block). Sol unaffected.
- **Stars slow you slightly more on entry**: `STAR_ZONE_MULT 90→120`, new `STAR_EDGE_SPEED 64`.

### Teleport (`main.gd`) + audio
- Teleport is a **small light-ball that shrinks to 0 → you jump** (`TELEPORT_TIME 8s`, `TP_ORB_BASE`);
  camera pulled back so it frames from outside. The **"voooouuu" whoosh fades in → holds → fades out**
  across the ritual (`tools/gen_teleport_audio.py` → 11s `teleport.wav`, volume bell in `_update_teleport`).
- Crisp **click** SFX (`gen_ui_click.py`). ⚠️ audio assets must be re-imported into the real tree
  (`godot --headless --import`) — running the game does NOT re-import changed WAVs.

### Wormhole network (multi-hub) — see `WORMHOLE_NETWORK.md` / `.png`
- `SystemDB._ensure_graph()` rebuilt: **5 spread hubs**, each linked to Earth + to each other; every
  other system spokes off its nearest hub (capped/balanced). **Earth→anywhere ≤2 hops, any→any ≤3.**
  Verified by `tools/test_wh_network.gd`. Diagram via `export_wh_graph.gd` + `draw_wh_network.py`.

### Platforms, teleport console, UI
- **Platforms everywhere promised**: `props.gd` spawns a single reusable **generic dockable platform**
  in every `has_station` system without a hand-placed station (fixes "teleported, no station"). Lazy
  (one node, re-homed per system).
- **Isolated platform-teleport console** (`platform_teleport.gd`): own screen (NOT the star map);
  unlocked platforms bright, locked dark grey; click → confirm → teleport ritual.
- **Quest log (J)** closes on outside-click.
- **New-game tutorial notifications** (`tutor.gd`): small left-of-middle tip boxes, ting-tong chime
  (`gen_notify_audio.py` → `notify.wav`), click-for-detail, drag-off to dismiss; **pops faster while
  Sol isn't fully scanned** (`main._sol_fully_unlocked`).
- **Capture celebration** (`reward_card.gd`): semi-transparent top-centre card, **auto-grants** the
  reward (no more "press G"), happy fanfare (`gen_reward_audio.py` → `reward.wav`), fades out in ~5s.
- **Reset Progress** button in Settings (two-tap confirm) → `main.reset_progress()` wipes the save +
  reloads. (Save lives in `user://`, not the repo.)

## ⭐ NEXT PLAN

Sol 1:1 first pass lives in this repo (`Fiazul/space-survey`). Full dump: [`docs/SESSION-2026-08-18-sol-first-pass.md`](docs/SESSION-2026-08-18-sol-first-pass.md). Rule: every Sol feature is a first cut and needs a perfection pass.

**First:** recreate Sun vanish on close approach (see top of this file). Then fold Sol Sun into the generic star LOD.

After that: Earth look, Deimos mosaic, Ganymede gridless swap, 101 km bird view. Layers spec: `docs/specs/2026-08-20-sol-flight-layers-design.md`.

Older carried list (still valid, not this Sol slice):
1. **Rudder finder**
2. **"New item found" → notification**
3. **A Notification TAB**
4. **Wormhole STYLE** transit visual

## Tooling notes (this session)
- All SFX are **pure-Python `wave` generators** in `tools/gen_*.py` (no deps). Regenerate then
  **re-import the real tree** so the running game picks them up.
- Parse-check on a COPY: `cp -r . /tmp/c && rm -rf /tmp/c/.godot && godot --headless --path /tmp/c --import`.
- Run: `DISPLAY=:1 <godot-bin> --path /home/fiazul/Desktop/Astryx`. Godot binary lives at
  `/home/fiazul/Desktop/Godot_v4.6.2-stable_linux.x86_64`.

---

# Astryx — Session Handoff (v0.10.0)

> Project: `/home/fiazul/Desktop/Astryx`
> Godot 4.6.2 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main). Everything
> below is committed + pushed. The game is **all code-spawned** — `Main.tscn` is a
> one-node stub; `main.gd` builds the world, ship, camera, lights, and UI at runtime.

## State of the game (v0.10.0)
A real-solar-system third-person explorer with light combat, navigation, a
discovery loop, a coin economy, an **in-hangar ship customizer**, a **mission log**,
and a **zoomable star map**. ~10.5k lines of GDScript across 25 modules; 51 real
star systems; Android APK + touch controls; CI release builds.

## What changed since v0.8

### v0.9.0 — wormhole graph + quests + full resume
- **Wormhole graph travel**: Prim's MST + extra edges; BFS `next_hop()` routing over
  *known* edges (`is_edge_known`); the Interstellar hub only lists **unlocked** wormholes.
- **Full state resume**: position, system, hull, coins, discoveries, onboarding step,
  and active quest all persist to `user://profile.cfg` (saved from stable states only).

### v0.10.0 (this session)
- **Mission Log (J)** — `missions.gd` (`MissionDB`): every star/planet/moon is a mission
  with a crude/savage (mostly-true) story + coin bounty (`STORIES` keyed by body name).
  `quest_log.gd` (`QuestLog`, CanvasLayer) is the board: list grouped by system, detail
  pane, **★ Track** → `main.track_quest()` drives the nav arrow; survey to complete/claim.
- **Zoomable / pannable map** — `map_chart.gd` (`MapChart`, custom `_draw`): wheel-zoom,
  drag-pan out to ~150 ly, star/wormhole/planet icons on **toggleable filter layers**, a
  live animated **player cursor**, hover read-outs, wormhole lanes. `map.gd` hosts it +
  filter chips + a right-side system body list. Wormholes are live on the corner radar
  (`wormhole.portals_rel`, `minimap.gd` swirl blips); the nav arrow prioritises wormholes.
- **Warp-speed rebalance** — top hulls ≈ 23–24 s/ly, mid ≈ 28–30 s, others ≈ 40 s. Tuned
  via per-hull `warp` (terminal velocity = `THRUST × warp / DAMPING`, NOT the `MAX_SPEED`
  cap). `UNITS_PER_LY = 6,324,107.7`; `warp ≈ 2874.6 / target_seconds`.
- **HaniStar customizer** — now `color_pick` like HaniNebula: body + wing swatches, bell
  toggle, metallic/glassy finish. Wings = **GLB surface 4** (verified by rendering each
  surface). Added `wing_surfs` (list) + `wing_role` options for multi-surface wings
  (HaniNebula's single `wing_surf` couldn't express it). `current_has_wing_pick()` now
  recognises all three (`wing_surf`/`wing_surfs`/`wing_role`).
- **Champagne Gold** palette — new `champagne` swatch + `recolor` role (polished gold:
  metallic 0.85, roughness 0.16). Palette is now **10** colours.
- **Editable Cancel Nav** (and HUD declutter) — `cancel_nav` is a registered movable HUD
  widget (drag-place + wheel-scale, persists to `user://hud_layout.cfg`); default baked
  into `DEFAULT_LAYOUT`/`DEFAULT_SCALE`. Centre-screen clutter (objective/quest/tip lines,
  bottom help strip) moved off to the free right side (`rx = SCREEN.x - 300`).
- **Guardian "phantom boss" bugfix** — a guardian boss parked at a body kept summoning/
  firing with no distance gate → `in_combat()` stayed true → warp bled to sublight →
  player stranded with a stuck "100%" bar. Fixes: a **leash** in `_update_scan` abandons
  the fight (`combat.abandon_combat()`, zeroes `_combat_t`) once you're > `GUARD_RANGE×2.5`
  from the guarded body; `reset()` clears stale `guard_body`/`zone_kills`/`_combat_t`.
- **Named bosses** — `combat.BOSS_NAMES` (crude/savage), deterministic per body via hash;
  `boss_state()` returns `name`; HUD bar + probe scan show it (Alien-zone boss = "Vortex").

### Ships (`ship.gd`, `SHIP_MODELS`)
Seven hulls. Each entry tunes hp / fire / warp / booster / surface roles.
- **Lyra** tanky red laser-bolts (`raw` look) · **Stella** glass-cannon machine-gun ·
  **Raptor** dual-booster bruiser (X = warp/combat form fork) · **Vela** FTL, spools over
  ~9s, **R** air-brake · **HaniStar** pink support that fights (`bolt_strong`), now
  colour-pickable · **Raptor 2 Neo** mother-ship with nose **laser** (2 GLB surfaces:
  `silver` hull + `glass` strips) · **HaniNebula** evolved pro form, fully colour-pickable,
  boosters snapped to her model's real engine holes (`BOOSTER_NO_RING`), own music track.

### In-hangar customizer (`hud.gd set_hangar` → `main.gd` → `ship.gd`)
- **BODY / WING COLOUR** swatches from `Ship.SHIP_PALETTES` (10: rosegold, blush, navy,
  teal, charcoal, emerald, burgundy, silver=SteelBlue, gold=Silver, **champagne**=gold).
- **ENGINE BELL** add/remove · **FINISH** metallic/glassy (`ShipMesh.set_glassy`).
- Opt in with `"color_pick": true`. Surface mapping styles in `_build_ship_model`:
  **whole-hull** (HaniNebula: body everywhere except `wing_surf`) vs **template**
  (Raptor 2 / HaniStar: replace `body_role` surfaces, paint `wing_surf`/`wing_surfs`/
  `wing_role` with wing colour, keep glass).
- Persisted per-ship: `ship.customization_state()`/`load_customization()` ↔
  `user://profile.cfg` `[player] customization`.
- ⚠️ **Metallic gotcha:** in this probe-less scene `metallic = 1.0` has no diffuse and
  only mirrors the empty starfield → reads as *clear glass*. Palette roles use
  `metallic ≈ 0.55` + `emission = albedo` so colours stay solid (see `ship_mesh.gd recolor`).

### Flight feel, VFX, audio
- **Sublight drift** (`DRIFT_DAMPING` 0.32) glides through turns; blends to `DAMPING`
  (0.75) as warp spools so FTL times stay tuned. Heavy A/D + up/down low-passed.
- Living booster flame (layered sines on a smoothed base) + motion streaks.
- Per-ship engine voice ducks under music after ~8s; **HaniNebula** has her own track.

## Controls
WASD thrust · **Shift** boost · **Q/E** roll · **Space/Ctrl** up·down ·
**L-click** fire · **R-click** laser (Raptor 2) · **Tab** waypoint · **V** scan/capture ·
**L** codex · **W+C** drift-flip · **J** mission log · **G** details · **M** map · **F** dock/wormhole ·
**R** Vela brake · **Num Lock** auto-cruise · **H** teleport Earth · **Esc** cursor/back ·
wheel zoom · **1–7** swap ship (docked).

## ⭐ NEXT — planned TODO (carried over)
1. **Bullet "bloat" fix** (combat.gd) — the fat cyan bar in fast dogfights. Root cause
   diagnosed: a 51-unit additive trail + hard bloom (emission 10) near the ~1u chase cam.
   Levers: cap `reach` to ~20 + drop emission to ~4. **Reverted twice** — must NOT change
   shooting speed/gating; only the trail/bloom. Get a screenshot to confirm.
2. **Platform F-interaction** — at a platform, **F** lets you choose ship AND quick-teleport
   to another unlocked platform. (Platforms = wormhole-attached now + player-placed later.)
3. **Show platforms on the map** (each platform's position).
4. **Confirm warp boost fork** — is the 23 s/ly the W-cruise terminal or boosted? If boosted,
   divide `warp` by ~3.
5. **Unify interaction on F** — drop **V** capture (hold-F to capture; F context chain:
   dock/platform/wormhole/capture); repurpose **V** → auto-navigate to the tracked quest.
   (Do NOT change shooting.)
6. **Right-side quest box** — boxed/table tracker on the right; click or key → navigate.
   Replaces the old top-centre tracker.
7. **Guide/prompts as side notifications** — boxed, clickable for detail (currently plain
   right-side labels).
- Background long-shot: **double-precision build** (`precision=double`) to kill float32
  jitter at ly-scale → real planet sizes + landable surfaces; combat stakes (Hull 0 is a
  no-op today → death/respawn).

## Headless / verification workflow (assistant can't see a live GPU)
- **Parse check** — never `--import` the real tree (the importer re-tabs `ship.gd`
  comments). Validate on a **copy**: `cp -r . /tmp/acheck && rm -rf /tmp/acheck/.godot &&
  godot --headless --path /tmp/acheck --import` then grep stderr for errors.
- **Render a model surface-by-surface** (to identify wings etc.) — the real Godot binary
  (`/home/fiazul/Desktop/space_craft/Godot_v4.6.2-stable_linux.x86_64`) under
  `xvfb-run` renders with hardware GL: load the GLB into a `Node3D` scene, tint each
  surface a distinct colour, position a `Camera3D`, `await` a few `process_frame`s, then
  `get_viewport().get_texture().get_image().save_png(...)`. Run as a real scene
  (`godot --path COPY res://render.tscn`), NOT `--script` (a SceneTree `--script` won't
  pump render frames and hangs).
- Visual changes need the user's eyes — get a screenshot before declaring done.

## Profile / saves
`user://profile.cfg` (progress + per-ship customization), `user://codex.json`
(captures), `user://hud_layout.cfg` (HUD layout). Flatpak userdata:
`~/.var/app/org.godotengine.Godot/data/godot/app_userdata/Cold Light/`.
