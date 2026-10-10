# Astryx fleet v2

Seven modular hulls, tiers 2-8, are rebuilt for a sleek cinematic look. Tier 1 is the authored
Class II Galactic Cruiser. Contract (sockets, materials, lengths, frame):
`docs/specs/2026-09-26-ship-roster-and-modules.md`, checked by `tools/test_ship_glb_sockets.gd`.

Family language: analytic lofted hull with a knife chine (Hull_Paint above, Hull_Dark below); a blade
strake riding the chine with an Accent_Emit strip along it; raised armour plates with Hull_Steel edge
walls and dark seam lines; one faceted Glass canopy with dark rails and hoop (on the bridge deck for
T5-T7); blade wings/fins with knife edges, each tipped with an Accent_Emit light; engines inside
painted fairings (dark underside) ending in steel collars and recessed Nozzle_Emit bells.

| Tier | Slug | Design | Length (m) | Tris |
|---|---|---|---|---|
| 2 | kestrel | Needle interceptor: long knife-chined needle, tall single dorsal fin, aft swept blades, twin pods, ventral strakes | 70 | 18500 |
| 3 | swift | Blended-wing lifting body: flat lens hull flowing into crescent wings, buried flat drives, outward-canted fins | 80 | 19380 |
| 4 | harrier | Heavy twin-engine fighter: slim fuselage between two large open-intake nacelles, forward canards, twin canted tails | 95 | 19700 |
| 5 | osprey | Corvette: tall raised dorsal spine carrying the bridge, long raked ventral keel blade, anhedral stabilisers, three drives | 120 | 23014 |
| 6 | condor | Strike cruiser: flat faceted wedge, bridge tower, swept wings with tip fins, layered engine block with upper pair aft of the lower faired pair | 150 | 24528 |
| 7 | albatross | Flagship: swept hammer prow with prow fins, slim neck, three stepped armour decks up to a bridge tower, wide dark engine block with four drives | 200 | 23612 |
| 8 | sovereign | Endgame flagship: triple spear prow, matte titanium armor, small armored bridge windows, radiator banks, exposed coolant service channels, one swept wing pair, four layered octagonal drives | 240 | 25396 |

Sovereign alone has a 30,000-triangle ceiling (20% above the fleet's 25,000 ceiling).
Its four nozzle mouths lie behind all armor; the socket test enforces exhaust clearance.
Outer housings are approximately 120 m long, half the hull length. Five packed maps
(a shared 512px wear/albedo, a shared 512px normal and three 256px metallic/roughness maps)
preserve the six material surfaces and remain compatible with hangar recoloring.
Source: `tools/blender/sources/sovereign.blend`; builder: `tools/blender/sovereign.py`.
Latest AI concept and prompt: `tools/blender/concepts/sovereign-realism.png` and `sovereign-realism-prompt.txt`.

## Commands (repo root, Blender 4.2)

```
blender -b --python tools/blender/build_ships.py                    # all eight builder entries -> assets/ships/<slug>/<slug>.glb
blender -b --python tools/blender/build_ships.py -- --ship 3        # one tier; --out <dir> to redirect
ASTRYX_TRIS=1 blender -b --python tools/blender/build_ships.py -- --ship 7   # per-part tri breakdown
blender -b --python tools/blender/render_ships.py                   # all renders (Cycles CPU, 1000px; default 96 spp, delivered set used --samples 64)
blender -b --python tools/blender/render_ships.py -- --ship kestrel --samples 16 --res 600   # quick look
timeout 120 godot --headless --script tools/test_ship_glb_sockets.gd   # -> ship_glb_sockets: OK
```

Renders: `renders/<slug>_{3q,side,top,rear}.png`, `renders/roster.png` (side profiles, one scale,
labelled), `renders/fleet_3q.png` (seven 3/4 views tiled). Hull_Paint is shown steel-blue in renders
only; the game tints it per hangar swatch.

Files: `blender/sleek.py` (surface kit: Body, blade, engine, fairing-ready lofts, plate, seam, canopy),
`blender/build_ships.py` (seven designs + sockets + export), `blender/ship_common.py` (materials,
sockets, join/export), `blender/render_ships.py`. Builds are deterministic (byte-identical GLBs across runs).
Final hull length is scaled to the exact contract value after assembly.
## Runtime

`Ship.SHIP_MODELS` lists the Class II Galactic Cruiser at tier 1, then these seven modular hulls at tiers
2–8 (`"modular": true`, `length` = metres × 0.0075, so the fitted hull is the table length in metres).
`ModularHull` (`scripts/flight/modular_hull.gd`) styles the seven GLBs by material name and reads their
sockets by prefix. `assets/ships/wren/wren.glb` remains on disk but is not rostered:

- `SOCKET_BOOSTER_n` → two torch cones + a haze shell each (radius measured from the nearest `Nozzle_Emit`
  bell vertices); `Nozzle_Emit` gets the throttle-driven `cruiser_propulsion` pass.
- `SOCKET_RCS_n` → short cone puffs that fire when strafe/lift input pushes against their exhaust, and
  softly on brake.
- `SOCKET_PAD_n` / `SOCKET_WEAPON_n` → pad / weapon modules from `assets/modules/` (`ShipSystems`),
  scaled by hull length (`PAD_SCALE`, `WEAPON_SCALE`). Feet share one plane below the hull; a pad on a
  high socket is scaled up to reach it.
- `SOCKET_LANDJET_n` → one `LandingThrusters` outlet each.

Tiers unlock by `GameState.SHIP_UNLOCK` (systems reached beyond Sol: 0, 1, 2, 4, 6, 9, 12, 16);
`Ship.swap_ship` refuses a locked tier. Check: `godot --headless tools/test_ship_roster.tscn`,
`tools/test_ship_modules.tscn`; look: `SHIP=harrier SHOT_DIR=/tmp/shots xvfb-run -a godot --path . res://tools/render_thruster.tscn`.
