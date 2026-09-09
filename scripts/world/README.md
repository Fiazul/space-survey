# scripts/world/

The space around the ship: real bodies, the planet cook pipeline, ground terrain, and
backdrop/landmark dressing. See `PLANET_GENERATOR.md` for the pipeline contract.

| File | Type | Role |
|---|---|---|
| `planet_system.gd` | feature area | Real bodies as dot→LOD, gravity wells, floating-origin |
| `planet_generator.gd` | feature area | The cook: recipe → painted ball (map or invented), for Sun/planets/moons; lazy close extras |
| `surface_recipe.gd` | data | `SurfaceRecipe` — resolves per-body geology profile (world defaults + overrides) |
| `terrain_sampler.gd` | feature area | `TerrainSampler` — the ONE height function; mesh, contact kill, and props all sample it |
| `surface_patch.gd` | feature area | Local bird-view ground tile just above the kill line (hills, water, kit props) |
| `cloud_layer.gd` | feature area | `CloudLayer` — cloud deck shell alive exactly while the terrain ring is, covering the gap left when the globe's own clouds vanish with it |
| `starfield.gd` | data (baked mesh + runtime draw) | Background star field rendered from a baked real-catalogue points mesh (built offline by `tools/build_starfield.gd`) |
| `galaxy_model.gd` | feature area | Milky Way backdrop + the Sgr A* direction |
| `props.gd` | feature area | Hand-placed GLB landmarks (stations, platforms, drifting probes), floating-origin |
| `dev_sites.gd` | data | `DevSites` — static site table + lat/lon geometry helpers for the Ctrl+P dev-teleport panel (`scripts/ui/dev_sites_panel.gd`) |
