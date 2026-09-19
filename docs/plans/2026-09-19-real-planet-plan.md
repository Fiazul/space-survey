# Real planet generator — execution plan (2026-09-19)

**Goal image first.** Target = the reference shot: ship low over a real mountain range,
valley floor with rock detail, distant ridges fading into haze, an outpost on the plain.
Every slice is judged against that picture on Earth (himalaya_9km, earth_mountains,
coast_2km renders). Landing and gameplay data come only after the picture reads right.

Workers: Cursor `cursor-grok-4.6-high` (xhigh for slice 1). Orchestrator writes briefs,
runs tests, reads flight diffs only. Codex Astra reserved for slice 6 when quota resets.
Cap: 3 concurrent. One brief, one worktree, one commit per slice after tests + user review.

## Slice 1 — Tectonic base + erosion  (Grok xhigh, tonight = draft, visual rounds tomorrow)
- `PlanetGenerator.crust_height()` and `planet_cook.gdshader sample_height()` — mirror, both.
- Layer A: Voronoi plates seeded from recipe. Convergent edges → ranges 3–8 km, divergent → rifts.
- Layer B: ridged multifractal + domain warp toward downhill → valleys, cliffs, channels.
- Mapped bodies: both layers band-limited below DEM texel via existing `_below_texel_weight`.
- Recipe fields: `plate_count`, `range_m`, `rift_m`, `erosion`, `ridge_sharpness`. Defaults keep
  current look for gas/star/liquid (zero amplitude).
- Tests: `test_surface_recipes`, `test_earth_terrain`, `test_surface_band`, `test_skin_kill`,
  `test_terrain_light`, `test_dem_calibration.tscn` (CPU/GPU mirror gate).
- Acceptance is visual: all 19 `TERRAIN_SHOTS`; user judges Earth first, then moon_200m,
  io_volcano, europa_ice.
- Potato: height fn ≤ 4× current cost; ring rebuild stays threaded; no new textures.

## Slice 2 — Near-ground look  (Grok high, tonight, independent of slice 1's height math)
- Fragment-side detail in `planet_cook.gdshader` close block: triplanar rock normal/detail
  noise below ~50 m so cliffs and scree read without more triangles. Slope-based material
  (rock on steep; soil/grass/snow by altitude + latitude on flat).
- In-air haze: distance fog + horizon brightening only when the observer is inside the
  atmosphere skin (`test_terrain_light` rule). Vacuum stays black.
- Ring LOD: cap total tris (existing `_recount_tris`), one draw call per ring, shadows off
  on mobile. No new textures over 2k.
- Acceptance: same 19 renders; coast_2km + earth_mountains must show rock detail and haze.

## Slice 3 — Biomes + props  (Grok high, after slice 1 fields exist; needs kit assets)
- Fields from slice 1: slope, altitude, moisture (liquid + latitude), heat → biome id per sample.
- Replace primitive kit with ~12 GLB meshes (CC0 pack, see
  `docs/specs/2026-08-22-universal-planet-asset-kit-design.md`); MultiMesh per ring cell,
  billboard impostors past ~2 km. Trees 20–40 m real scale, boulders, ice spires, one
  outpost/ruin set for the plain.
- Kit sourcing + ingest can start tonight as the third worker (assets only, no placement).
- Ore/scannable placement later reads slice 5's element abundance against the same fields.

## Design change (record with slice 4)
- Ships may land. Player never leaves the ship. Surface contact != death.
- Generator still stops at the skin: no walking, no gear game, no unique mesh per world.
- Update: CLAUDE.md forbidden patterns, PLANET_GENERATOR.md (lines 16, 99, 277),
  NEEDS-YOUR-EYES.md, CONTEXT.md glossary ("landing").

## Slice 4 — Landing rule  (Grok high, after the picture reads right)
- `ship.gd` contact path + `main._update_skin_kill`: kill → `land | damage`. Land when
  vertical speed < ~5 m/s AND tilt < ~15° → snap to `TerrainSampler` height at 3–4 hull
  points, zero velocity, turn WITH the planet, "LANDED" HUD.
- Else hull damage ∝ impact speed; respawn only at zero hull. DEV NODEATH still works.
- Take-off = thrust; leaves landed state above ~2 m AGL.
- Tests: extend `test_skin_kill.gd` (land / damage / takeoff); `test_surface_integration.tscn` OK.
- Orchestrator reads the diff (flight code).

## Slice 5 — Gameplay data layer  (Grok high, independent, can run alongside 4)
- Move `~/Downloads/astryx-gameplay-spec.md` → `docs/specs/2026-09-19-gameplay-layer.md`.
- New `scripts/gameplay/`: `MaterialClass` enum, `ElementDef`, `RecipeDef`, `RecipeSlot`
  Resources; `data/elements/*.tres` (~12 elements), element→class table; `grade()` =
  base_quality × environment modifier from recipe fields (heat, liquid, seed metallicity).
- Headless `tools/test_material_classes.gd`. README rows. No UI, no inventory yet.

## Slice 6 — Feature stamps  (after slice 1; Codex Astra or Grok xhigh)
- Analytic stamps in recipe: `volcano`, `caldera`, `impact_basin`, `canyon`, `dune_field`,
  `ice_fracture` (Europa lineae). Named table: Olympus Mons, Everest, Valles Marineris, lineae.
- Same mirror rule. Stamps are named places → scannable, quest targets.

## Order + gates
1. Tonight: slice 1 (height math) + slice 2 (look) in parallel, two worktrees; slice 3 kit
   sourcing/ingest as the third worker.
2. Tests green → 19 renders → user judges Earth shots against the reference image → iterate.
3. Slice 3 placement once slice 1 fields exist. **Gate: the picture reads right.**
4. Then slices 4 (landing), 5 (data), 6 (stamps). Then spec steps 2+.

## Not doing
- Landing gear, EVA, per-planet meshes, Google Earth tiles, arcade gravity, blue sky in vacuum.
