# scripts/travel/

Getting between star systems and around them. No wormholes (docs/adr/0003): a star is
reached first by the interstellar drive (not built yet), then by teleport once visited.
`main.travel_to(id)` is the one gate; `ASTRYX_DEV_TRAVEL=1` opens every star for development.

| File | Type | Role |
|---|---|---|
| `navigator.gd` | feature area | On-screen orientation gizmo + always-on waypoint arrow to the current Tab target |
| `platform_teleport.gd` | feature area | The docked fast-travel console: teleport to Sol or any visited system (`SystemDB.is_teleport_platform`) |
