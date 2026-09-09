# Astryx · v0.11.4

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
- **Real positions** — Sun + planets from live **JPL Horizons**, **~45 of the nearest
  real star systems** from the J2000 catalog. Earth is the origin (floating-origin
  engine for AU↔ly scale).
- **Five authored ships** — **Class II Galactic Cruiser** (default), **Snarkrans
  Starship**, **Base Basic PBR**, **Vanguard**, and **Selene**. Dock with **F**;
  swap with **1–4** (first four) or click any of the five in the hangar list.
  Each model keeps its own booster meshes, rendered as extremely bright,
  speed-reactive, edge-faded propulsion — no random procedural booster layouts.
- **Editable HUD** — drag-place and scale HUD widgets in a layout editor; placement
  persists to your profile (defaults are the shipped layout).
- **Flight feel** — sublight "space drift" that carries momentum through turns,
  weighted strafe, eased mouse-steer, and living animated authored propulsion.
- **Recipe-cooked worlds** — one generator paints stars, planets, and moons from
  observed maps when available and stable seeded properties otherwise. Close-range
  flight adds height, water, clouds, rocks, and other recipe-selected surface
  details under the hull.
- **Wormhole network** — a **5-hub** graph (Prim's MST + extra edges, BFS routing)
  designed for **Earth → anywhere ≤ 2 hops, any → any ≤ 3 hops** — you're never more
  than 3 jumps from a star (see [`WORMHOLE_NETWORK.md`](WORMHOLE_NETWORK.md) for the
  recorded check). Fly to a portal, press **F**, transit the tunnel, arrive.
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
  points you to the nearest unsurveyed body first, falling back to the nearest wormhole
  once the system's fully surveyed. **Scan (V)** → persistent **Codex** (L) with real
  NASA facts (G). A **beginner tutorial/quest** eases new pilots in.
- **Mission log** (J) — every star, planet & moon is its own mission with a crude,
  (mostly) true story and a coin bounty. Browse the board, click a mission to read it,
  and **Navigate** straight to it. Survey the body to complete it and claim the bounty.
- **Star gravity & teleport** — in arcade (non-Sol) systems stars gently pull you in and let
  go once you thrust away, so you're never trapped; Sol uses real Newtonian gravity instead,
  no damping or release. A rare, theatrical **teleport ritual** handles emergency-home and
  station→station jumps; a **platform-network console** fast-travels between unlocked stations.
- **Audio** — engine voice + script-generated SFX + background music.

## Planetary flight and surfaces

Close to a solid body (currently ~35 km above ground on Earth and the Moon — measured
terrain peaks 9.49 km / 1.97 km respectively), the coarse cooked globe is replaced by a
local, recipe-driven ground patch: mapped or procedural height, water where the recipe
calls for it, and kit props (rock/ice/tree) seated on the surface. The patch works in the
body's own rotating frame, so the Moon isn't anchored to Earth's centre. Above that
ceiling you fly the cooked mesh (bird's-eye globe); farther out, bodies are sky points
until you arrive. Contact with the ground starts hull-loss and a respawn at the nearest
safe park; there is no landing.

See [`PLANET_GENERATOR.md`](PLANET_GENERATOR.md) for the cook, LOD contract, and how
height/contact/props all read from the same sampler.

## Controls

**Flight** — `WASD` thrust/strafe · `Space`/`Ctrl` up/down · `Q`/`E` roll ·
`Shift` boost · mouse aim · `L-click` fire · `S` brake/reverse · wheel zoom ·
`Num Lock` toggle hands-free auto-cruise (W + boost) · `W`+`C` cinematic drift-flip
(`A`/`D` picks the side) · `,`/`.` (or `[`/`]`) step time warp rate · `Esc` free
cursor / back.

**Interaction** — `Tab` cycle nose-aim waypoint target · `V` scan / hold to
capture · `L` codex · `J` mission log · `G` body details · `M` star map ·
`F` dock / undock / enter wormhole · `H` teleport to Earth · `N` toggle the
nav-arrow guide · hold `X` (~1s) lock the current Tab target as a paid waypoint.

**Debug (Sol only)** — `F3` perf/leak readout · `F4` dump a 15s flight footprint ·
`F6` circularize at current altitude · `F7` park at GEO · `F9` toggle fat
(dev-speed) engines · `\` (while DEV is on) toggle FASTAIR, weaker atmosphere
drag for touring (speed in air has no hard cap) · `F10` face the nearest body
and kill leftover speed.

## Run

Install **Godot 4.6.3** (GDScript, no C#), open this folder as a project, press
**F5**. No keys or build steps. *(Open it in the editor once after pulling so it
imports any new `.obj` / audio assets.)* For release exports (Windows/Linux) see
`./build.sh`; for Android see [`BUILD-ANDROID.md`](BUILD-ANDROID.md). Touch
controls auto-enable on mobile, or force them on desktop with `godot -- --touch`
(user args must follow `--`; `OS.get_cmdline_user_args()` won't see them otherwise).

## Data
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (solar system) · HYG/SIMBAD (stars).

## Assets
World, effects and SFX are code/script-generated. 3D ship & prop models are free assets
([Poly Pizza](https://poly.pizza/), [Free3D](https://free3d.com/)); music is AI-generated.
See [`CREDITS.md`](CREDITS.md).

## Developers

See `CLAUDE.md` and the per-folder `README.md`s under `scripts/` for architecture
and code layout.

---
Hobby / educational project. See [`docs/SESSION-2026-09-04-skin-band.md`](docs/SESSION-2026-09-04-skin-band.md) for the most recent session's per-system notes.
