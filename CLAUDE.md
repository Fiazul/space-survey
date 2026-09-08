# CLAUDE.md — Astryx (Godot 4.6.3 GDScript)

Directives for any agent (Claude or otherwise) working in this repo. Terse, actionable, verified.

## Architecture

```
scenes/Main.tscn (one-node stub, boots res://scripts/core/main.gd)
        │
        ▼
  core/main.gd  ── orchestrator: .new()+add_child's every subsystem in _ready(),
  │                 drives them by direct method call each frame in _process()
  │                 (NOT signals — 6 signals in ~14k lines, wiring is held refs)
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

## Commands (verified 2026-09-08, godot 4.6.3.stable, `godot` on PATH)

Parse-check a single script:
```
godot --headless --check-only --script <path/to/file.gd>
```
No output on stdout past the engine banner = clean. (Project-wide `--check-only` with no
`--script` hangs waiting on the main scene — don't use that form.)

Headless unit tests — most `tools/test_*.gd` `extends SceneTree`:
```
godot --headless --script tools/test_surface_recipes.gd
# → "surface_recipes: OK"
```
Run all SceneTree-based tests in a loop (skips the 5 scene-based ones below):
```
for f in tools/test_*.gd; do
  case "$f" in
    tools/test_base_basic_pbr.gd|tools/test_chase_rig.gd|tools/test_ship_roster.gd|\
    tools/test_surface_integration.gd|tools/test_wedge_fighter.gd) continue ;;
  esac
  echo "=== $f ==="; godot --headless --script "$f"
done
```
Scene-based tests (`extends Node3D` / `extends Node`, need a live scene tree) — pass the
`.tscn`, not the `.gd`, as a **positional path arg** (not `--script`):
```
godot --headless tools/test_surface_integration.tscn
# → "surface_integration: OK"
```
Same form for `test_ship_roster.tscn`, `test_wedge_fighter.tscn`, `test_chase_rig.tscn`,
`test_base_basic_pbr.tscn`.

Visual review renders (offscreen captures, for a human/agent to look at, not pass/fail):
```
TERRAIN_SHOTS=earth_mountains,earth_water godot --headless tools/render_terrain.tscn
godot --headless tools/render_thruster.tscn
godot --headless tools/render_wedge_fighter.tscn
```
`TERRAIN_SHOTS` values: `moon_rocks,moon_crater,io_volcano,mars_volcano,europa_ice,
earth_mountains,earth_water,sun_plasma,jupiter_storms` (see PLANET_GENERATOR.md).

Build: `./build.sh` (flatpak Godot export → `builds/{windows,linux}/`). Android: see
`BUILD-ANDROID.md`.

Lint: **none installed** (no `gdlint` on this machine) — don't invoke it, don't assume CI
runs it.

## Directives

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
  `planet_system.gd`).
- Before any planet/terrain change: run `tools/test_surface_recipes.gd`,
  `tools/test_earth_terrain.gd`, `tools/test_surface_band.gd`, `tools/test_skin_kill.gd`,
  `tools/test_terrain_light.gd`.

## Forbidden patterns

Domain-glossary terms to avoid (full definitions + longer avoid-lists: `CONTEXT.md`):

- Never say "Godot unit"/"world position"/"global transform" for game-space coordinates —
  say **true position** (ship stays at render origin; bodies draw at true minus ship's true).
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
| `assets/starfield_naked/low/high/tycho.res` | `tools/build_starfield.gd` (`godot --headless --script tools/build_starfield.gd`) |
| `assets/planets/*` | `tools/fetch_planet_maps.py` (→ /tmp) then `tools/ingest_planet_maps.py` (crop/resize into `assets/planets/`) |
| `WORMHOLE_NETWORK.png` | `tools/export_wh_graph.gd` (dumps `/tmp/wh_graph.json`) → `tools/draw_wh_network.py` |
| `TAB_TARGETING.png` | `tools/draw_tab_target.py` |
| `assets/fx/exhaust_noise.png` | `tools/gen_exhaust_noise.py` |
| `assets/{sfx_fire,laser_loop,notify,reward,teleport,ui_click}.wav`, `engine_*.ogg` | `tools/gen_{fire,laser,notify,reward,teleport,ui_click,engine}_audio.py`, `tools/gen_booster.py` |
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
| `HANDOFF.md` | Living project status/handoff log across sessions |
| `docs/adr/` | Accepted architecture decisions (the "why" behind structural choices) |
| `docs/specs/`, `docs/superpowers/specs/` | Dated design specs for individual features (older/newer split — both are point-in-time design docs, not living contracts) |
| `docs/superpowers/plans/` | Worker execution plans for specific slices of work |
| `docs/plans/`, `docs/research/` | Misc planning/research notes |
| `docs/restructure/NOTES.md` | Living log of the 2026-06-20 domain-folder/autoload restructure — gotchas (UID pairs, autoload init order), phase history |
| Per-folder `README.md` (`scripts/*/`, `shaders/`, `tools/`) | File-by-file map of that folder for a dev/agent deciding what to read |
