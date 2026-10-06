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

Main-sequence photospheres combine filtered fine granulation with broader convection,
sparse spots and bright magnetic regions; giants emphasize broader convection.
Cool red dwarfs have warmer amber/red colors and stronger clustered prominence loops.
Brown dwarfs have dim banded surfaces, white dwarfs smooth compact surfaces,
Wolf–Rayet stars blue turbulent wind envelopes, and neutron remnants hot polar
regions and narrow polar glare. A single billboard quad adds a soft corona and
localized prominence filaments; brown dwarfs and compact remnants omit solar loops.
Surface exposure is compressed separately from halo strength to preserve resolved
texture. The Sun uses the same exposure response as other photospheres; its previous
sixfold boost is removed. Effective temperature selects a visible blackbody continuum,
integrated from 380–780 nm at 5 nm intervals through the CIE 1931 observer and converted
from XYZ to linear sRGB, normalized by peak channel, then encoded for Godot's
`source_color` uniforms. Cached colors are shared across recipes.
The solar photosphere is warm white, A/F stars white, O/B stars blue-white, and K/M
stars increasingly warm. Local surface temperature colors span ±6%; the shader no
longer replaces G/K/M colors with orange plasma. Optical corona tint tends toward
white instead of applying an orange multiplier. Star meshes are 96×48 spheres,
with no particle populations, CPU-generated textures or per-frame texture loads.
Existing dot/mesh/Sun-sky LOD remains active. Display exposure is intentionally
compressed to retain detail; these are not photometric observations. Cool brown
dwarfs retain a faint visible representation for playability.

Solar granule spacing is approximately `R_sun / (2 × cells)` = 994 km at 350 cells.
Derivative filtering suppresses unresolved fine detail and skips its expensive
noise evaluations. Hot radiative-envelope stars have reduced convection contrast,
while giant presets retain broad cells. Magnetic regions gate smaller spot groups;
their activity and coverage are display estimates, not observations of these stars.
Stars skip terrain height sampling in the shared vertex shader.

Opaque cook spheres cull far-side faces. At large scene distances, drawing both
hemispheres produced depth conflicts and large triangular patches in compatibility
rendering. In-game disc checks reproduce this with `STAR_DOUBLE_SIDED=1` and pass
with the production draw mode. `STAR_TELEPORT_SYSTEMS=sol,sirius` restricts that
capture to the two regression cases. Main space background is black; atmospheric
color still comes from the air shell around the observer.

The current travel catalogue mostly contains nearby M/K dwarfs, with G/F/A stars,
brown dwarfs and white dwarfs; it has no O/B destinations. Its warm/white balance
therefore persists despite the corrected renderer. The gallery includes O/B recipe
examples to verify blue-white support, without changing real catalogue metadata.

## Scale and hazards

Sol's Sun remains 695,700 km in radius. Catalogue destinations use generated
systems in kilometres: `GeneratedEphemeris` builds stellar radii and gravity
from the recipe, plus seeded planetary orbits. The compressed
`5 × R_solar^0.45` radius remains a display helper for distant catalogue markers;
it does not set the local primary star's radius after a system jump.

Ctrl+P's star rows jump to the selected system's primary star at four stellar
radii, face it, set circular-orbit velocity, clear time warp, and save the stellar park.
The current star can be selected again. Normal platform travel still uses its
planetary arrival. Near meshes and distant stellar spheres share the primary's
recipe and rotation; resolved stars use their recipe corona without additional
point-source glare.

For distance expressed in stellar radii `q`, incident flux is `σ T⁴ / q²` and the
zero-albedo, uniformly reradiating equilibrium temperature is `T / sqrt(2q)`.
The latter is an environmental reference, **not measured ship temperature**.
Sol returns approximately 1,361 W/m² at 1 AU. Catalogue systems evaluate the
radius ratio from their local kilometre distances.

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
giant/remnant defaults and activity are our approximations. Visible continuum colors
use the [Wyman, Sloan and Shirley CIE fit](https://cwyman.org/papers/jcgt13_xyzApprox.pdf).
Blackbody colors omit absorption lines, composition-dependent spectra, reddening and
instrument response; normalizing color does not set physical luminosity.
Family distinctions follow [NASA's stellar overview](https://science.nasa.gov/universe/stars/types/).
Brown-dwarf visibility is deliberately enhanced; their energy is predominantly
infrared, as explained by [NASA Webb](https://science.nasa.gov/mission/webb/science-overview/science-explainers/what-makes-brown-dwarfs-unique/).

Run `godot --headless --path . tools/test_star_recipes.tscn` for catalogue coverage,
classification, physical estimates, inverse-square flux, runtime warnings and
scan-panel checks. `tools/render_star_recipes.tscn` produces `/tmp/star-recipes.png`:
equal angular sizes for comparing surfaces, with physical sizes printed below.
The capture checks rendered hot-star, solar, red-dwarf and brown-dwarf palettes.
Pass `-- --details` to also capture close views of the Sun, Proxima, a red supergiant
and a Wolf–Rayet star beside the gallery image. `tools/render_sun_approach.tscn`
checks solar brightness, surface contrast and clipping from distant through
photosphere views; `tools/test_stellar_corona_clipping.tscn` checks camera-plane
clipping and foreground occlusion. These are authored visualizations, not images
of the catalogued stars or a simulation of a particular observed flare.
`tools/test_star_teleport.tscn` checks every catalogue destination through the
Ctrl+P jump path, including selected renderer, arrival state and saved position.
`tools/render_star_teleport.tscn` drives Ctrl+P and the picker buttons in the real
game, then captures Sol, Proxima, Wolf 359, Sirius, Luhman 16 and Gliese 440 in
`/tmp/star-teleport`; `STAR_TELEPORT_SHOTS` changes the output directory.

## Red dwarf colour and K2-18

K2-18 b is the planet; K2-18 is its M2.5V host star. The current spectral interpolation gives the host an estimated temperature of 3,455 K, close to the 3,457 ± 39 K solution in the [NASA Exoplanet Archive](https://exoplanetarchive.ipac.caltech.edu/overview/K2-18). This is a spectral estimate, not a per-object measured override.

Orange visible colour is consistent with the classification: [NASA's star types guide](https://science.nasa.gov/universe/stars/types/) explains that red dwarfs appear more orange than red. The renderer approximates a blackbody continuum through a standard observer and display colour space. It does not calculate full stellar atmosphere absorption spectra or human visual adaptation. Surface patterns, spots, activity and glare are procedural estimates, not observations of K2-18's surface.
