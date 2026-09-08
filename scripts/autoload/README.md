# scripts/autoload/

Globally-reachable services & data. Mixes true Godot autoloads (stateful nodes,
registered in `project.godot`, `class_name` dropped per ADR-0001) with plain static
`RefCounted` data classes that any module reaches by type name without registration.

| File | Type | Role |
|---|---|---|
| `ephemeris.gd` | feature area (autoload) | Real Sun/planet positions (live JPL Horizons + cache), floating-origin, Earth-anchored geocentric frame |
| `codex.gd` | feature area (autoload) | Which bodies the player has scanned/discovered, persisted to `user://codex.json` |
| `planet_data.gd` | feature area (autoload) | Real planet fact-sheets for the Details panel (bundled + NASA Exoplanet Archive cache) |
| `game_audio.gd` | feature area (autoload) | Code-generated SFX + per-ship engine voice |
| `system_db.gd` | data (static, not autoload) | `SystemDB` — the ~50 real star systems, portals, coords |
| `mission_db.gd` | data (static, not autoload) | `MissionDB` — per-body mission title/story/bounty |
