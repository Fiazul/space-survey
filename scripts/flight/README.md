# scripts/flight/

The player ship: physics, visuals, controls, and hull-specific design data.

| File | Type | Role |
|---|---|---|
| `ship.gd` | feature area | Flight physics, visuals (boosters/streaks), warp, autopilot, customization; `SHIP_MODELS` = tier-1 Class II Galactic Cruiser plus seven tiered modular hulls, tier-gated `swap_ship`, `set_weapon_set`/`set_pad_set` |
| `modular_hull.gd` | feature area | `ModularHull` — static socket-driven styler for the GLB hulls/modules: maps materials by name (`Hull_Paint` tint, `Glass`, `Accent_Emit`, `Nozzle_Emit` → throttle shader), collects `SOCKET_*` empties by prefix, builds booster plumes and RCS puffs |
| `ship_systems.gd` | feature area | Landing pads, weapon mounts and belly support jets. Modular hulls: pad/weapon GLB modules (`assets/modules/`, mk1/mk2) on the hull's sockets, feet on one shared plane, `MUZZLE`/`FOOT` driven. Primitive fallback ship: procedural legs + `PlasmaMountMesh` guns |
| `landing_thrusters.gd` | feature area | Belly support outlets (one per `SOCKET_LANDJET_n`), canted from each outlet's own position |
| `plasma_mount_mesh.gd` | geometry | Procedural cannon housing for the primitive fallback ship only |
| `ship_mesh.gd` | feature area | Stateless mesh/FX helpers: fit/AABB, torch/haze/nozzle-light plume layers, fill-light layer tagging |
| `anchor_frame.gd` | data | `AnchorFrame` — 64-bit arithmetic for the anchored ship frame (docs/adr/0002); static, autoload-free |
| `black_hole_gravity.gd` | data | `BlackHoleGravity` — pseudo-Newtonian Kerr force (Artemova et al. 1996) the ship integrates near a black hole, plus orbit/plunge/clock-rate analysis for the HUD and fear cues; static, autoload-free |
| `flight_mode.gd` | feature area | Zone (CENTER/INSIDE/SKIN/AIR/SPACE) vs mode (LOCAL/CRUISE/AIR) + exclusion-zone math |
| `turn_carry.gd` | feature area | Sol steering assist carries forward flight; backward falls and lateral drift keep their direction |
| `touch_controls.gd` | feature area | Mobile multi-touch control overlay, landscape/two-thumb (`--touch` to test on desktop) |

Touch controls: left thumb is a fixed movement-joystick zone (forward + turn only, no
reverse — pushing into the back cone brakes); right thumb has FIRE + stacked UP/DOWN
nose-pitch buttons plus BOOST/CAP/THRUST/INTERACT/MAP/HOME and hold-to-zoom ZOOM+/ZOOM−,
and a free-drag look area — two fingers in that look area pinch the chase-camera zoom
instead of steering the look (mobile boots at max zoom-in, `Ship.default_zoom()`). A
top-right DEV tap button reveals NODEATH/FASTAIR when dev mode is on. The stick→command
mapping is the pure static `TouchControls.stick_to_cmd()`, and the pinch and hold-zoom
math are the pure static `TouchControls.pinch_zoom()` and `TouchControls.zoom_step()`,
both unit-tested in `tools/test_touch_controls.gd`.

Ship uses an explicit gameplay capture rule inside 0.6 AU of the black hole: radial infall overrides speed/thrust/NODEATH and reaches the horizon within four simulation seconds from the boundary. Outside it, pseudo-Newtonian gravity remains in force. See `tools/test_black_hole_capture.tscn`.
