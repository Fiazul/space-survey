# Stellar recipes

`scripts/world/star_recipe.gd` supplies every star rendered by PlanetGenerator.
Recipes are deterministic: a name seeds surface variation, spectral type selects
a family, and explicit `stellar` fields override physical estimates. No downloaded
models or new texture assets are required.

Supported families: O/B/A/F/G/K/M main sequence, luminosity classes VI (subdwarf),
IV (subgiant), III (giant), II (bright giant), I (supergiant), L/T/Y brown dwarfs,
D white dwarfs (including DA/DQ/DZ labels), W Wolf–Rayet, C carbon stars, and
explicit neutron-star, pulsar and magnetar presets. Rare presets are available to
generation; this pass does not insert fictional counterparts into the real-star
catalogue. Black holes remain a separate renderer/system.

## Authoring

```gdscript
{
    "name": "Survey star", "star": true, "spectral": "M5.5V",
    "stellar": {
        "temperature_k": 2930.0,
        "radius_solar": 0.156,
        "mass_solar": 0.123,
        "activity": 0.65
    }
}
```

Use `stellar_type: "pulsar"` (or `neutron_star` / `magnetar`) for remnants.
`stellar.type` also accepts the family identifiers in `StarRecipe.resolve`.
Temperature, radius and mass overrides must be finite and positive. Activity is
clamped to 0–1. These example values are spectral estimates, not measurements of
an individual object. The details panel labels non-solar values as model estimates.

The resolved `stellar` dictionary includes physical radius in km and solar radii,
mass, effective temperature, bolometric luminosity, activity, composition and
visual parameters. Stellar composition is informational; stars provide no surface
mining, atmosphere gathering or landing surface. Crafting extraction is not implied.

## Appearance and cost

Main-sequence photospheres have seeded granulation and spots; giants have broader
convection patterns. Cool dwarfs have dim banded surfaces, white dwarfs smoother
compact surfaces, and neutron remnants hot polar regions. A single billboard quad
adds the corona and pulsar modulation. Spectral temperature controls the palette;
the old shader's universal orange cast is removed. Star meshes are 96×48 spheres,
with no particle populations, CPU-generated textures or per-frame texture loads.
Existing dot/mesh/Sun-sky LOD remains active. Display exposure is intentionally
compressed to retain detail; these are not photometric observations. Cool brown
dwarfs retain a faint visible representation for playability.

## Scale and hazards

Sol's Sun remains 695,700 km in radius. Extrasolar arenas still use the project's
compressed layouts. There the rendered radius follows `5 × R_solar^0.45`, bounded
to 0.12–16 scene units; hub destination spheres use a further 4.4 display factor.
Planet layout and existing orbital/gravity models are not migrated in this pass.
This is not yet a physically scaled extrasolar flight simulation.

For distance expressed in stellar radii `q`, incident flux is `σ T⁴ / q²` and the
zero-albedo, uniformly reradiating equilibrium temperature is `T / sqrt(2q)`.
The latter is an environmental reference, **not measured ship temperature**.
Sol returns approximately 1,361 W/m² at 1 AU. Compressed arenas use the same
radius ratio, not a claim that their scene units are real kilometres.

PlanetSystem exposes `stellar_hazard` and the flight tape shows heat/radiation
warnings on approach. Withdrawal and system changes clear the warning. Radiation
is a gameplay index based on temperature/activity, not a dose in sieverts. There
is no hull damage or death from these warnings. This foundation does not yet model
ship heat capacity, shielding, flares as timed gameplay events, atmosphere/eclipsing
attenuation, radiation transport or neutron-star relativity. Those belong with
the roadmap's equipment and environment mechanics.

## Calibration and checks

Representative dwarf anchors are rounded from the
[Pecaut–Mamajek stellar sequence](https://www.pas.rochester.edu/~emamajek/EEM_dwarf_UBVIJHK_colors_Teff.txt),
with extra late-M anchors to avoid oversizing nearby red dwarfs. Interpolation,
giant/remnant defaults, activity and display colours are our approximations.
Family distinctions follow [NASA's stellar overview](https://science.nasa.gov/universe/stars/types/).
Brown-dwarf visibility is deliberately enhanced; their energy is predominantly
infrared, as explained by [NASA Webb](https://science.nasa.gov/mission/webb/science-overview/science-explainers/what-makes-brown-dwarfs-unique/).

Run `godot --headless --path . tools/test_star_recipes.tscn` for catalogue coverage,
classification, physical estimates, inverse-square flux, runtime warnings and
scan-panel checks. `tools/render_star_recipes.tscn` produces `/tmp/star-recipes.png`:
equal angular sizes for comparing surfaces, with physical sizes printed below.
