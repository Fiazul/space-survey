# CLAUDE.md — Astryx (Godot 4.6.3 GDScript)

Directives for any agent (Claude or otherwise) working in this repo.

## Architecture

```
scenes/Main.tscn (one-node stub, boots res://scripts/core/main.gd)
        │
        ▼
  core/main.gd  ── orchestrator: .new()+add_child's every subsystem in _ready(),
  │                 drives them by direct method call each frame in _process()
  │                 (NOT signals — 5 signals in ~17.9k lines of scripts/, wiring is held refs)
  │                 also owns MusicDirector (core/music_director.gd), Onboarding
  │                 (core/onboarding.gd)
  │
  ├─ autoloads (singletons, reachable by name from anywhere, no wiring):
  │    GameState   (core/game_state.gd)   — persisted profile + economy
  │    Ephemeris   (autoload/ephemeris.gd) — real Sun/planet positions, floating origin
  │    PlanetData  (autoload/planet_data.gd) — NASA fact sheets
  │    Codex       (autoload/codex.gd)    — discovery/scan progress
  │    GameAudio   (autoload/game_audio.gd) — code-gen SFX + engine voice
  │    (SystemDB, MissionDB are static RefCounted classes, NOT autoloads — global
  │     class_name only, no state, no registration needed)
  │
  ├─ flight/   Ship, ShipMesh, FlightMode, TurnCarry, TouchControls, WedgeFighterDesign
  ├─ world/    PlanetSystem, PlanetGenerator, SurfaceRecipe, SurfacePatch,
  │            TerrainSampler, Starfield, GalaxyModel, Props
  ├─ travel/   Wormhole, Navigator, PlatformTeleport
  ├─ combat/   Combat, CombatFX, EnemyFactory
  └─ ui/       HUD + panels (CodexPanel, StarMap, QuestLog, PlanetInfo, …)
```

**Why code-spawned, not scene-composed** (docs/adr/0001): the world is built at runtime
from GDScript, not authored in the editor. Every module declares a global `class_name`,
so moving files between folders never breaks a reference — `main.gd` finds everything by
type name, not by path. Stateful cross-cutting services are Godot **autoloads** (the one
idiomatic concession); static lookup tables (`SystemDB`, `MissionDB`) stay plain
`RefCounted` classes. Autoload init order is load-bearing — do not read one autoload's
state from another's `_ready()` without checking ordering in `project.godot`.

**Why one shared height function** (PLANET_GENERATOR.md): `TerrainSampler` is the ONLY
place ground height is computed. The ring mesh, the contact-kill test, and surface props
all call the same instance per body — so what you see, what kills you, and where a rock
sits always agree. `PlanetGenerator.crust_height()` mirrors `planet_cook.gdshader`'s
`sample_height()` fbm line for line — the mesh cook and the CPU-side height must match, or
the ground shown and the ground you fly through diverge. **Touch one, touch both.**

**Why one recipe, one shader**: every world (Sun, planet, moon, invented exoplanet) goes
through the same `PlanetGenerator` cook and the same `shaders/planet_cook.gdshader`. A
`SurfaceRecipe` resolves per-body geology (real map path when we have evidence; invented
kind/color/heat when we don't) — `SurfacePatch` never special-cases a body by name, it
only reads the recipe.

## Commands (godot 4.6.3.stable, `godot` on PATH)

Last verified 2026-09-08: the full `test_*.gd` loop below with `timeout 120` (21 OK, 0 FAIL)
and `TERRAIN_SHOTS=moon_200m xvfb-run -a godot --path . res://tools/render_terrain.tscn`.

Parse-check a single script:
```
godot --headless --check-only --script <path/to/file.gd>
```
**Exit code is meaningless — it's 0 even on a compile failure.** Read stderr. Any script
that touches an autoload (`GameState`/`Ephemeris`/`Codex`/`PlanetData`/`GameAudio`) prints
`Identifier not found: <Autoload>` and fails to compile under this form — that's a false
positive of the check, not a real bug (autoloads aren't registered outside a running
project). Only autoload-free scripts parse clean this way (e.g. `surface_recipe.gd`).

Headless unit tests — most `tools/test_*.gd` `extends SceneTree`:
```
godot --headless --script tools/test_surface_recipes.gd
# → "surface_recipes: OK"
```
Run all SceneTree-based tests in a loop (skips the 5 scene-based ones below, `timeout 120`
per file so a hang doesn't stall the whole loop):
```
for f in tools/test_*.gd; do
  case "$f" in
    tools/test_base_basic_pbr.gd|tools/test_chase_rig.gd|tools/test_ship_roster.gd|\
    tools/test_surface_integration.gd|tools/test_wedge_fighter.gd) continue ;;
  esac
  echo "=== $f ==="; timeout 120 godot --headless --script "$f"
done
```
Removed 2026-09-08: `test_wh_network.gd` (hung — `SystemDB.arrival_pos()` reaches the
`Ephemeris` autoload, which does not exist under `--script`; wormhole hop guarantee is
currently unchecked, reinstate as a scene-based test), `test_dingo57_starship.gd`,
`test_jazoone_spaceship.gd` (ships left the roster).

Scene-based tests (`extends Node3D` / `extends Node`, need a live scene tree) — pass the
`.tscn`, not the `.gd`, as a **positional path arg** (not `--script`):
```
godot --headless tools/test_surface_integration.tscn
# → "surface_integration: OK"
```
Same form for `test_ship_roster.tscn`, `test_wedge_fighter.tscn`, `test_chase_rig.tscn`,
`test_base_basic_pbr.tscn`.

Visual review renders (offscreen captures, for a human/agent to look at, not pass/fail).
**Plain `--headless` captures nothing** — no GL context, so `get_viewport().get_texture()`
comes back null and `save_png` never runs (render_terrain then loops forever waiting on a
frame that's never delivered). Run as a real windowed scene under a virtual display instead:
```
TERRAIN_SHOTS=earth_mountains,earth_water xvfb-run -a godot --path . res://tools/render_terrain.tscn
SHOT_DIR=/tmp/shots xvfb-run -a godot --path . res://tools/render_thruster.tscn
SHOT_DIR=/tmp/shots xvfb-run -a godot --path . res://tools/render_wedge_fighter.tscn
```
Env vars actually read (grep each `render_*.gd` before assuming one applies to another):
- `render_terrain.gd`: `TERRAIN_SHOTS` only. Output is fixed at `user://terrain_%s.png` →
  `~/.local/share/godot/app_userdata/Cold Light/terrain_<name>.png` (project's registered
  name is "Cold Light", see project.godot; `SHOT_DIR` is NOT read by this script).
- `render_thruster.gd`: `SHOT_DIR`, `DETAIL`, `ISOLATE`, `VIEW`, `SHAPE`, `GLOW_ON`, `SHIP`.
- `render_wedge_fighter.gd`: `RAW`, `SHOT_DIR`.

`TERRAIN_SHOTS` values (all 19, `tools/render_terrain.gd:32-53`): `moon_rocks, moon_crater,
io_volcano, mars_volcano, europa_ice, earth_mountains, earth_water, sun_plasma,
jupiter_storms, earth_20km, earth_7km, moon_20km, moon_7km, moon_200m, coast_12km,
coast_6km, coast_2km, himalaya_12km, himalaya_9km` (see PLANET_GENERATOR.md).

Build: `./build.sh` (flatpak Godot export → `builds/{windows,linux}/`). Android: see
`BUILD-ANDROID.md`.

Lint: **none installed** (no `gdlint` on this machine) — don't invoke it, don't assume CI
runs it.

## Directives

- Scene-unit convention: 1 scene unit = 1 km for physical bodies (`ship.gd:61-64`).
  Arcade (non-Sol) systems use 1u = 0.01 AU with body radii boosted by `VISUAL_SCALE`
  (`planet_system.gd:36-42`) — never assume a bare unit count means km outside Sol.
- Every Sol feature shipped so far is a first pass. Treat none of it as finished
  (`CONTEXT.md`).
- Always keep `TerrainSampler` the single height source. Never add a second height/noise
  function for mesh, collision, or props — call the sampler.
- Always mirror `PlanetGenerator.crust_height()` and `planet_cook.gdshader`'s
  `sample_height()` together. Never edit one without the other.
- Always route new per-body look/geology through `SurfaceRecipe`. Never hardcode `if
  body_name == "Earth"` branching in `SurfacePatch`/`PlanetGenerator` — add a recipe field.
- Always `git mv` a `.gd` file WITH its sibling `.gd.uid` in the same commit. Never move
  only the `.gd` — Godot regenerates the UID and breaks every `.tscn`/preload reference to
  it (docs/restructure/NOTES.md).
- Always use held references / autoloads for cross-module calls, matching the existing
  pattern. Never introduce a signal-heavy rewrite of an area you're not already touching —
  this codebase is intentionally direct-call, not event-driven.
- Always add global `class_name` to new non-autoload scripts (enables path-independent
  refactors). Never give an autoload script both a registered autoload name and a
  `class_name` — drop `class_name` on autoload scripts per ADR-0001 (Godot forbids the
  clash).
- Always name files `snake_case(class_name)` (e.g. `class_name PlanetSystem` →
  `planet_system.gd`). Existing exception: `wedge_fighter.gd` holds `class_name
  WedgeFighterDesign` — don't "fix" that mismatch as a drive-by.
- Before any planet/terrain change: run `tools/test_surface_recipes.gd`,
  `tools/test_earth_terrain.gd`, `tools/test_surface_band.gd`, `tools/test_skin_kill.gd`,
  `tools/test_terrain_light.gd`.

## Forbidden patterns

Domain-glossary terms to avoid (full definitions + longer avoid-lists: `CONTEXT.md`):

- Never say "Godot unit"/"meter"/"old 0.1 AU unit" for the coordinate scale — say
  **scene unit** (1 km for physical bodies; see scene-unit convention above).
- Never say "world position"/"global transform" for a body's coordinate — say **true
  position** (ship stays at render origin; bodies draw at true minus ship's true).
- Never build an "arcade gravity well" / safe-zone pull / idle-release physics — Newton
  inverse-square only, no damping, no arcade 550 speed cap in Sol.
- Never add a "fat air shell" / Kerbal bubble / arcade planet spin — Earth atmosphere is a
  100 km drag-only skin; inside it the ship turns WITH the planet.
- Never build a landing game / landing gear / one mesh per planet / unique GLB per world —
  the generator explicitly stops at the skin (`Ephemeris.surface_kill_km`); see PLANET_GENERATOR.md.
- Never stream Google Earth 3D tiles / photogrammetry for the plane-band idea (still
  unbuilt) — height comes from NASA/USGS data or the recipe seed, never third-party tiles.
- Never test depth against an opaque body with depth-test disabled — every celestial body
  must occlude what's behind it (no starfield/sky-shell showing through a planet or moon).
- **Vacuum is black.** Sky/haze/glow scattering requires air AROUND THE OBSERVER along the
  view ray, lit by the sun — never render a blue/hazy sky in vacuum or deep space regardless
  of nearby bodies (`NEEDS-YOUR-EYES.md`, standing physics constraint, non-negotiable).
- Never hand-author one unique texture/mesh per star system — a billion stars stay HYG sky
  points until the player is physically there; only the nearest body ever gets a mesh.

## Generated files — do not hand-edit

| Path | Produced by |
|---|---|
| `*.gd.uid` (every `.gd` has one) | Godot editor, auto-managed |
| `*.import` | Godot editor import cache |
| `.godot/` | Godot editor (import cache, class registry) — gitignored |
| `assets/starfield_{naked,low,high,tycho}.res` | `tools/build_starfield.gd` (`godot --headless --script tools/build_starfield.gd`) |
| `assets/planets/*` | `tools/fetch_planet_maps.py` (→ /tmp) then `tools/ingest_planet_maps.py` (crop/resize into `assets/planets/`) |
| `WORMHOLE_NETWORK.png` | `tools/export_wh_graph.gd` (dumps `/tmp/wh_graph.json`) → `tools/draw_wh_network.py` |
| `TAB_TARGETING.png` | `tools/draw_tab_target.py` |
| `assets/fx/exhaust_noise.png` | `tools/gen_exhaust_noise.py` |
| `assets/{sfx_fire,laser_loop,notify,reward,teleport}.wav`, `engine_*.ogg` | `tools/gen_{fire,laser,notify,reward,teleport,engine}_audio.py`, `tools/gen_booster.py` |
| `assets/ui_click.wav` | `tools/gen_ui_click.py` |
| `tools/data/` | `tools/parse_tycho.py` (raw Tycho-2 catalogue, ~340MB, gitignored) |
| `builds/` | `build.sh` export output, gitignored |

## Documentation & comments

**Near-zero comments.** Only for genuinely non-obvious logic or an external reference
(a paper, a spec, a physical constant's source). Comments explain **why**, never **what**
— the code already says what. No docstrings on self-explanatory methods. If a subclass
method just calls the parent's behavior, reference the parent method in prose — don't
re-explain what it does.

Module purpose comments at the top of a file (the existing style — one short paragraph
under `class_name`/`extends` explaining the file's role and any real gotcha) are fine and
expected; per-line/per-function narration is not.

## Docs map

| Path | What it's for |
|---|---|
| `CONTEXT.md` | Domain glossary — the project's vocabulary + "_Avoid_" lists per term |
| `PLANET_GENERATOR.md` | The planet/terrain pipeline contract (recipe → cook → terrain) |
| `NEEDS-YOUR-EYES.md` | Standing physics/design constraints + open visual-review questions a human must judge (llvmpipe software renderer can't judge appearance) |
| `docs/SESSION-*.md` | Dated session notes across sessions (two exist: `2026-08-18-sol-first-pass.md`, `2026-09-04-skin-band.md`) |
| `CREDITS.md` | Asset credits — what's code-generated vs. free/AI-generated, and where from |
| `STARFIELD.md` | How the real-catalogue star field is built and rendered |
| `TAB_TARGETING.md` | How nose-aim Tab-targeting picks and cycles candidates |
| `WORMHOLE_NETWORK.md` | The wormhole graph's structure and routing rules |
| `lore.md` | In-universe codex — fleet, factions, setting |
| `docs/adr/` | Accepted architecture decisions (the "why" behind structural choices) |
| `docs/specs/`, `docs/superpowers/specs/` | Dated design specs for individual features (older/newer split — both are point-in-time design docs, not living contracts) |
| `docs/superpowers/plans/` | Worker execution plans for specific slices of work |
| `docs/plans/`, `docs/research/` | Misc planning/research notes |
| `docs/restructure/NOTES.md` | Living log of the 2026-06-20 domain-folder/autoload restructure — gotchas (UID pairs, autoload init order), phase history |
| Per-folder `README.md` (`scripts/*/`, `shaders/`, `tools/`) | File-by-file map of that folder for a dev/agent deciding what to read |
