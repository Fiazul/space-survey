# Astryx · v0.15.0-dev.20261009.1

A potato-friendly **third-person space explorer** in Godot 4 / GDScript. Launch
from Earth, fly the **real** solar system, survey its worlds into the Codex, and
customize your ship in the hangar. The world is spawned from code: celestial-body recipes cook
mapped or deterministic procedural worlds through one shared planet shader and
a small reusable surface kit.

## ▶ Gameplay
[![Astryx — gameplay](https://img.youtube.com/vi/txmrN1_HsiM/maxresdefault.jpg)](https://www.youtube.com/watch?v=txmrN1_HsiM)

*Gameplay clips (edited together, with sound).*

## How to play the loop

A new profile starts gear-down on **Kennedy LC-39A**, engines idle
(`ASTRYX_START=pad` forces this for any profile). One flight, four moments:

1. **Lift off** — hold `Space`: the support jets take you off the pad (HUD `LIFT JETS`,
   engine voice rises). `B` raises the gear; pitch the nose to the sky with the mouse and
   hold `W` + `Shift`.
2. **Through the skin** — the air ends at 100 km: the sky goes black and the stars come
   out. About 2.3 km/s straight up at 37 km coasts you to ~320 km; cut the burn there.
3. **Look back** — turn the nose to Earth: terrain, clouds, the day/night line. Tap `.`
   for time warp (×5 … ×50) while you coast. Above the air you no longer turn with the
   planet, so the pad drifts east of you at ~0.4 km/s; a short sideways burn holds you
   over it. The blue **HOME** marker (name, distance, edge arrow when off-screen) shows
   where it is.
4. **Come home** — past the top, point the nose down, a short return burn, and dive;
   warp drops at the skin. Brake
   nose-up with `W` + `Shift` and steer over the marker (below 5 km it adds height above
   the pad). A few hundred metres up: `B` gear down, level out, hold `Ctrl` to settle onto
   the deck until the HUD reads **PAD LOCKED**. `Space` lifts off again.

What good looks like: pad to pad in about 2½ minutes of real flight with warp (the
scripted pilot in `tools/test_playable_minute` does it in ~146 s at 60 fps; a hard
re-entry reads AIR LOAD ~40%), and a first
flight under five minutes. Overshot the pad? Hover with the gear down and slide over
with `A`/`D`/`W`.

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
- **Combat** — instant **hitscan "ray bullets"** (left-click; aim by flying); alien
  ships hunt and fire dodgeable bolts.
- **Ray Tab-targeting** — **Tab** locks onto whatever your nose points at (nearest the aim
  *ray* by angle, not the nearest object), cycling the 4 closest; unscanned targets read
  "Unknown Star/Planet" until surveyed. See [`TAB_TARGETING.md`](TAB_TARGETING.md).
- **Navigation & discovery** — a real zoomable/pannable star **map** (M): star/planet/
  platform icons on toggleable layers, a live player cursor, hover read-outs, out to
  ~150 ly. The always-on nav arrow points you to the nearest unsurveyed body. Fly close
  to a body and it is surveyed automatically into the persistent **Codex** (L) with real
  NASA facts (G). A **beginner tutorial/quest** eases new pilots in.
- **Mission log** (J) — every star, planet & moon is its own mission with a crude,
  (mostly) true story. Browse the board, click a mission to read it, and track it.
  Survey the body to complete it.
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
until you arrive. Terrain contact is solid and non-lethal. A landing lock requires a slow, level
touchdown with deployed gear on a designated facility pad.

See [`PLANET_GENERATOR.md`](PLANET_GENERATOR.md) for the cook, LOD contract, and how
height/contact/props all read from the same sampler.

After five seconds without flight input, the ship assistant slowly levels planetary flight.
Any control input stops the adjustment; terrain avoidance remains automatic. Gear-supported landings can lock
onto the Kennedy and Wenchang pads. Ctrl+P also provides ISS and Tiangong rendezvous using
dated 2026 orbital data; their physical docking berths remain future work. See the
[assistant and facility notes](docs/plans/2026-09-24-ship-assistant.md) for sources and limits.

## Controls

**Flight** — `WASD` thrust/strafe · `Space`/`Ctrl` up/down · `Q`/`E` roll ·
`Shift` boost · mouse aim · `L-click` fire · `S` brake/reverse · wheel zoom ·
`Num Lock` toggle hands-free auto-cruise (W + boost) · `,`/`.` (or `[`/`]`) step time warp rate · `Esc` free
cursor / back.

**Teleport destinations** — click/tap **TELEPORT** at the top right (or `Ctrl+P`) to pick a Sol planet or landmark.
Earth landmarks show local solar time and DAY/TWILIGHT/NIGHT. Earth's rotation
starts from UTC, persists across sessions, and advances while offline. A full
day/night cycle takes **one sidereal day (1436.07 real minutes) at 1×** (8 minutes until 2026-09-29). Configure `world/day_night/cycle_minutes` in `project.godot` to change
that duration. This scales the rotation clock and surface co-rotation, not ship
gravity/thrust or weapon timing. Returning to a surface save preserves its
geographic location as the planet turns. Other bodies retain their relative spin
rates; the reference is Earth's cycle against the current ephemeris Sun.

**Interaction** — `Tab` cycle nose-aim waypoint target · `L` codex · `J` mission log ·
`G` body details · `M` star map · `F` dock / undock · `H` teleport to Earth · `N` toggle the
nav-arrow guide · hold `X` (~1s) lock the current Tab target as a waypoint.

**Debug (Sol only)** — `F3` perf/leak readout · `F4` dump a 15s flight footprint ·
`F6` circularize at current altitude · `F7` park at GEO · `F9` toggle fat
(dev-speed) engines · `\` (while DEV is on) toggle FASTAIR, weaker atmosphere
drag for touring (speed in air has no hard cap) · `Ctrl+D` (while DEV is on)
toggle NODEATH, contact kill off · `F10` face the nearest body and kill
leftover speed.

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

## Known bugs

The Sagittarius A* developer fly-through report is recorded as **BH-001** and
fixed in this test release. Entering **0.6 AU** now forces inward capture at any
speed, including DEV/NODEATH, then opens Humano at the horizon. Exiting the
arcade returns to a circular orbit at 2 AU. This boundary is a gameplay rule.
A Mobile close-core preview can still obscure the ship (**BH-002**); Android
hardware impact is unverified. See the [bug record](docs/KNOWN-BUGS.md) and [release notes](docs/releases/test-2026-10-09.md).

---
Hobby / educational project. See [`docs/SESSION-2026-09-04-skin-band.md`](docs/SESSION-2026-09-04-skin-band.md) for the most recent session's per-system notes.
