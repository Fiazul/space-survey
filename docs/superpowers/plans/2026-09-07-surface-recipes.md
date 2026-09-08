# Surface Recipes Implementation Plan

> **For agentic workers:** Execute inline, task-by-task; the user approved the feature pass and explicitly excluded optimization.

**Goal:** Give worlds recipe-selected geological geometry and surface materials without changing terrain streaming.

**Architecture:** A surface-profile module resolves named-world defaults and explicit overrides. TerrainSampler consumes the profile for solid geometry; the tile/prop and globe shaders consume its visual parameters. Mountains, crater bowls and volcanic cones are sampled by the same height function used for collision.

**Tech Stack:** Godot 4.6, GDScript, spatial shaders, existing planet maps.

**Spec:** User-approved design in conversation: Earth rock/mountains/water; Moon/Mercury craters; Mars dry relief; volcanic cones/lava; ice fractures; stellar plasma and gas bands. Optimization explicitly deferred.

## Global Constraints

- Preserve existing maps and unrelated dirty changes, including ship colouring.
- No streaming, threading, LOD-budget or optimization changes.
- Procedural details are not claimed to be measured real-world geology.
- Stars and gas giants do not receive solid ground or liquid oceans.
- Retain contact death and the common geometry/collision height sampler.

### Task 1: Recipe-driven geology

Files: create `scripts/world/surface_recipe.gd`; modify `scripts/world/terrain_sampler.gd`, `scripts/world/planet_generator.gd`; create `tools/test_surface_recipes.gd`.

Interface: `SurfaceRecipe.resolve(recipe: Dictionary) -> Dictionary`, `SurfaceRecipe.height_offset_m(dir: Vector3, profile: Dictionary) -> float`, `SurfaceRecipe.max_offset_m(profile: Dictionary) -> float`.

- [x] Add tests asserting Earth enables water, Moon excludes water/lava, Io enables lava, Europa excludes liquid water, and stars/gas exclude all ground features.
- [x] Run the test against current code and record failure (`/tmp/recipe-red2.log`: nine expected failures).
- [x] Add deterministic crater and volcano profiles, constrained overrides and height evaluation; integrate into TerrainSampler height and its maximum bound.
- [x] Check crater centre below rim, volcanic rim above flank, repeatable seeds, height-bound safety, water flatness, and contact at generated relief.

### Task 2: Visible surface materials and props

Files: modify `shaders/terrain_tile.gdshader`, `scripts/world/surface_patch.gd`, `shaders/planet_cook.gdshader`, `scripts/world/planet_generator.gd`; create `shaders/surface_prop.gdshader`.

- [x] Test built material parameters for each profile, including no water/volcanism on airless and icy worlds.
- [x] Bind rock strata/grain, water ripples and glints, fractured ice and volcanic basalt/lava parameters. Use slope/height/region masks rather than colouring every surface alike.
- [x] Replace the placeholder rock octahedron with irregular multi-ring boulders and use a lit/hazed prop material. Keep prop roots seated.
- [x] Expose stellar granulation and gas storm strengths in the same profile while excluding solid terrain for both.

### Task 3: Verification and handoff

Files: extend `tools/render_terrain.gd`; update `PLANET_GENERATOR.md`.

- [x] Render Moon crater, volcanic Io, icy Europa, Earth coast and mountain, Mars relief, Sun and Jupiter.
- [x] Inspect screenshots for geometry, material separation, seams and unintended water.
- [x] Run `test_surface_recipes.gd`, `test_earth_terrain.gd`, `test_surface_band.gd`, `test_terrain_light.gd`, `test_skin_kill.gd`, and `test_surface_integration.tscn` headlessly with `/tmp` log files.
- [x] Document profile controls, procedural-data limits and unchanged optimization scope; leave changes uncommitted.
