# Production stellar integration

[Comparison sheet](production-sheet.png) uses the production `PlanetGenerator`
cook and automatic structure LOD, without the preview surface shader. Ten
individual 960 × 640 captures and [capture settings](captures.json) accompany it.

Visible-light defaults retain temperature-based colors: [Sun](solar-visible.png),
[red dwarf](red-dwarf.png), [giant](red-giant.png), [bare white dwarf](white-dwarf-bare.png),
[bare neutron star](neutron-star-bare.png) and [brown dwarf](brown-dwarf-visible.png).
The sheet also shows explicit UV, enhanced visible and X-ray display options.
Its wind panel is an authored 45-core-radius scale demonstration; the separate
[production gallery](catalog-gallery/gallery.png) includes a wind with an authored
2.6e11-core-radius extent. The core is unresolved in that astronomical frame.
Disks, auroras and wind nebulae are optional and absent by default.

These are procedural visualizations, not observed surface or magnetic-field maps.
The enhanced brown palette follows the approved artist reference; it does not
change temperature, physical continuum color, luminosity or exposure.
The scientific reference interpretations remain in the
[approved preview notes](../stellar-structure-review/REVIEW.md).

Verification level: implemented, unit-tested and rendered through the game.
Ten relevant headless suites passed, including the five required surface
regressions. Rendered palette checks, halo/optional-effect clipping and foreground
occlusion passed. [Gameplay captures](gameplay) came from real Ctrl+P picker
arrivals for six catalog stars, with arrival-state read-back and solar/Sirius disc
integrity assertions. Independent code review approved the final implementation.
This does not establish a photosphere clipping fix, hardware performance or
Forward+/mobile rendering. Existing Godot resource cleanup diagnostics remain.

Godot 4.6.3 rendered these captures with the Compatibility renderer and Mesa
llvmpipe on 2026-10-06. Each scene isolates its profile to protect game saves.

## Reproduce

Run from the repository root with a display or Xvfb:

```sh
xvfb-run -a godot --path . --rendering-method gl_compatibility tools/render_stellar_integration.tscn
python3 tools/build_stellar_integration_sheet.py
STELLAR_PRODUCTION_SHOTS="$PWD/docs/reference/stellar-integration/catalog-gallery" xvfb-run -a godot --path . --rendering-method gl_compatibility tools/render_stellar_production.tscn
STAR_TELEPORT_SHOTS="$PWD/docs/reference/stellar-integration/gameplay" xvfb-run -a godot --path . --rendering-method gl_compatibility tools/render_star_teleport.tscn
CORONA_SHOT_DIR="$PWD/docs/reference/stellar-integration/clipping" xvfb-run -a godot --path . --rendering-method gl_compatibility tools/test_stellar_corona_clipping.tscn
STAR_RECIPE_SHOT="$PWD/docs/reference/stellar-integration/palette.png" xvfb-run -a godot --path . --rendering-method gl_compatibility tools/render_star_recipes.tscn
```

For Flatpak, replace `godot` with `flatpak run org.godotengine.Godot`, passing
output variables with Flatpak's `--env=NAME=value` option. Run windowed checks
sequentially to avoid virtual-display allocation races. The sheet builder uses Pillow.
