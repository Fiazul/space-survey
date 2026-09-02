# Astryx · v0.11.5

A potato-friendly **third-person space explorer** in Godot 4 / GDScript. Launch
from Earth, fly the **real** solar system, wormhole across a tested interstellar
network to real exoplanets, dogfight aliens and their bosses, and customize your
ship in the hangar. The world is spawned from code: celestial-body recipes cook
mapped or deterministic procedural worlds through one shared planet shader and
a small reusable surface kit.

## ▶ Gameplay
[![Astryx — gameplay](https://img.youtube.com/vi/txmrN1_HsiM/maxresdefault.jpg)](https://www.youtube.com/watch?v=txmrN1_HsiM)

*Gameplay clips (edited together, with sound) — warp out to real stars, fight the guardian waves defending a world, and capture it.*

## Features
- **Real positions** — Sun + planets from live **JPL Horizons**, **~50 of the nearest
  real star systems** from the J2000 catalog. Earth is the origin (floating-origin
  engine for AU↔ly scale).
- **Four authored ships** — **Class II Galactic Cruiser** (default), **Snarkrans
  Starship**, **Dingo57 Starship**, and **SpaceShip**. Dock with **F** and swap
  with **1–4**. Each model keeps its own booster meshes, rendered as extremely
  bright, speed-reactive, edge-faded propulsion—no random procedural booster layouts.
- **Editable HUD** — drag-place and scale HUD widgets in a layout editor; placement
  persists to your profile (defaults are the shipped layout).
- **Flight feel** — sublight "space drift" that carries momentum through turns,
  weighted strafe, eased mouse-steer, and living animated authored propulsion.
- **Recipe-cooked worlds** — one generator paints stars, planets, and moons from
  observed maps when available and stable seeded properties otherwise. Close LODs
  add height, water, clouds, rocks, and other recipe-selected surface details.
- **Wormhole network** — a **5-hub** graph (Prim's MST + extra edges, BFS routing) with a
  *tested* guarantee: **Earth → anywhere ≤ 2 hops, any → any ≤ 3 hops** — you're never more
  than 3 jumps from a star. Fly to a portal, press **F**, transit the tunnel, arrive.
  See [`WORMHOLE_NETWORK.md`](WORMHOLE_NETWORK.md).
- **Combat** — instant **hitscan "ray bullets"** (left-click; aim by flying); alien
  ships hunt and fire dodgeable bolts. Guarded bodies are defended by
  a **named boss** + finite **guardian waves** — clear the swarm, break the boss, capture the
  body for **coins** (with a capture-celebration payout).
- **Ray Tab-targeting** — **Tab** locks onto whatever your nose points at (nearest the aim
  *ray* by angle, not the nearest object), cycling the 4 closest; unscanned targets read
  "Unknown Star/Planet" until you **scan (V)**. See [`TAB_TARGETING.md`](TAB_TARGETING.md).
- **Navigation & discovery** — a real zoomable/pannable star **map** (M): star/wormhole/
  planet icons on toggleable layers, a live player cursor, hover read-outs, wormhole lanes,
  out to ~150 ly. Wormholes show live on the **corner radar** and the always-on nav arrow
  points you to the nearest wormhole first. **Scan (V)** → persistent **Codex** (L) with real
  NASA facts (G). A **beginner tutorial/quest** eases new pilots in.
- **Mission log** (J) — every star, planet & moon is its own mission with a crude,
  (mostly) true story and a coin bounty. Browse the board, click a mission to read it,
  and **Navigate** straight to it. Survey the body to complete it and claim the bounty.
- **Star gravity & teleport** — stars gently pull you in (and let go once you thrust away, so
  you're never trapped). A rare, theatrical **teleport ritual** handles emergency-home and
  station→station jumps; a **platform-network console** fast-travels between unlocked stations.
- **Audio** — engine voice + script-generated SFX + background music.

## Planetary flight and surfaces

Planetary flight is being expanded into four automatic regimes. A craft uses
**supercruise** where gravity and atmosphere are negligible, **gravity cruise**
inside a body's gravity region, **hypersonic flight** during atmospheric entry,
and **survey flight** in the lower atmosphere or close to an airless surface.
Airless bodies skip the hypersonic regime. Transitions will blend instead of
carrying supercruise velocity into terrain.

Atmosphere boundaries are not fixed constants copied into each planet recipe.
Known bodies use observed physical inputs; invented bodies generate stable,
plausible inputs from their type and seed. The environment cook derives gravity,
escape velocity, scale height, atmospheric extent, and density by altitude from
properties such as:

```gdscript
"physical": {
    "radius_km": 6371.0,
    "mass_earth": 1.0,
    "temperature_k": 288.0,
    "surface_pressure_bar": 1.0,
    "molar_mass": 0.029,
}
```

Pressure and composition cannot be inferred honestly from radius alone, so they
come from observations or deterministic procedural assumptions. Flight responds
to local gravity, atmospheric density, dynamic pressure, speed, and terrain
proximity rather than a universal altitude cutoff.

The visual path has three scales: the cooked globe from orbit, regional displaced
terrain during descent, and a local survey patch for mountains, coastlines, water,
rocks, clouds, and biome props. The generator recipe is the shared source of truth
for physics, flight transitions, atmosphere rendering, and surface generation.
See [`PLANET_GENERATOR.md`](PLANET_GENERATOR.md) for the current cook and LOD contract.

## Controls
`WASD` thrust · `Space/Ctrl` up·down · `Q/E` roll · `Shift` boost · `mouse` aim ·
**`L-click` fire** ·
`Num Lock` auto-cruise · `W+C` drift-flip · **`Tab`** waypoint · **`V`** scan · **`L`** codex ·
**`J`** mission log · **`G`** details · **`M`** map · **`F`** dock / wormhole · **`H`** teleport to Earth ·
wheel zoom · **`1–4`** swap ships (docked) · `Esc` free cursor / back

## Run
Install **Godot 4** (GDScript, no C#), open this folder as a project, press **F5**.
No keys or build steps. *(Open it in the editor once after pulling so it imports
any new `.obj` / audio assets.)*

## Layout
~12k lines of GDScript across ~35 code-spawned modules:
`main.gd` orchestrator · `ephemeris.gd` real data + Horizons fetch ·
`systems.gd` star systems · `planet_system.gd` body LOD + gravity · `wormhole.gd` graph +
transit · `combat.gd` dogfight/bosses · `ship.gd` flight/visuals · `ship_mesh.gd`
mesh/material helpers · `props.gd` stations/platforms · `platform_teleport.gd` fast-travel
console · `hud.gd` + `minimap.gd` + `crosshair.gd` UI · `map.gd`/`map_chart.gd` star map ·
`missions.gd`/`quest_log.gd` quests · `codex.gd`/`codex_panel.gd` discovery · `tutor.gd`
tutorial · `reward_card.gd` payouts · `navigator.gd` routing · `audio.gd` sound ·
`starfield.gd` backdrop · `touch.gd` mobile controls · `tools/` verifiers + asset/SFX
generators.

## Data
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (solar system) · HYG/SIMBAD (stars).

## Assets
World, effects and SFX are code/script-generated. 3D ship & prop models are free assets
([Poly Pizza](https://poly.pizza/), [Free3D](https://free3d.com/)); music is AI-generated.
See [`CREDITS.md`](CREDITS.md).

---
Hobby / educational project. See `HANDOFF.md` for the full per-system breakdown.
