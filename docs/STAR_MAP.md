# Star map (M) — local + global 3D

Elite-style holo chart. One UI (`StarMap` + `MapView3D`); the old 2D `MapChart` is unused.

## Modes

| Mode | What you see | Data |
|------|----------------|------|
| **GLOBAL** | Catalogue stars in real `SystemDB.coord()` space, known wormhole lanes, platform badges, you-are-here marker | `SystemDB`, `wh_edges`, `main.star_state` / `is_edge_known` |
| **LOCAL** | Current system star, planets/moons, known wormhole gates, station (if any), ship | `SystemDB.bodies`, `Ephemeris.scene_pos` for live Sol bodies, `main._known_portals`, `ship.true_pos` |

Toggle with the **LOCAL / GLOBAL** chips, or **Tab** while the map is open.

## Controls

- **M** — open / close (HUD “Navigation chart” too)
- **Esc** / click outside — close
- **Tab** — local ↔ global
- **Drag** — orbit camera
- **Wheel** — zoom
- **Click** a star (global) — select it; right column shows bodies / navigate / chart-lane / teleport

Layer chips (Stars / Wormholes / Planets / Lanes / Platforms) still filter what is drawn.

## Playtest

1. Launch the game, press **M**.
2. Confirm GLOBAL opens on Sol with cyan lanes to known neighbours.
3. Press **Tab** (or LOCAL) — Sol should show the Sun + planets (live ephemeris) and your ship marker.
4. Fly a wormhole, open the map again — LOCAL follows `current_system`; GLOBAL still shows the network.

## Tests

```bash
godot --headless --path . res://tools/test_map_view_3d.tscn
```
