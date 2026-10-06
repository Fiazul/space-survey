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

Every surface uses `PlanetGenerator._cook_material` and the same
`planet_cook.gdshader`. Its `kind == 3` branch calls the stellar-only calculations
in `stellar_surface.gdshaderinc`; other kinds retain their existing cook logic.
The cook binds `stellar.display_color`, `stellar.display_hot_color` and the explicit
sensor index for display while the resolved physical colors remain unchanged.
`StellarStructures` owns optional geometry, not surface materials.
`StellarStructures` creates normalized batches below the sphere's single immediate
corona child. Freeing child 0 still removes every corona/structure effect. The
corona shader's billboard affects its own vertices, not its children's transforms;
structures inherit the fixed sphere's orientation and radius. Both near and primary
sky spheres use the same resolved recipe, including authored visual options.

Main-sequence photospheres have filtered granulation, mottled magnetic networks and
spots; giants use broad convection cells and a faint diffuse shell. The granule
scale remains approximately `R_sun / (2 × cells)` = 994 km for the Sun. Hot radiative
stars retain reduced texture contrast. Brown dwarfs use fine, irregular turbulent
cloud shear adapted from the approved structure preview, with seamless cylindrical
sampling and noise-driven cloud lanes. Bare white dwarfs and neutron remnants have
compact smooth luminous surfaces, without latitude stripes, rings or winds.

`StarRecipe.color_at` still integrates a visible blackbody continuum from 380–780 nm
at 5 nm intervals through the CIE 1931 observer, converts XYZ to linear sRGB,
normalizes by peak channel, and encodes for Godot's `source_color` uniforms. Solar
color stays warm white; red dwarfs stay orange; O/B stars stay blue-white. Local
photosphere colors retain the ±6% temperature range. The physical color, luminosity
and exposure calculation are independent of sensor palettes. Surface brightness
keeps the existing compressed response `brightness / (1 + .65 × brightness)`.
These procedural patterns and exposure choices are authored approximations, not
photometric measurements or observations of individual stars. Cool brown dwarfs
remain faintly represented even though most of their emission is infrared.

The corona has faint irregular support and real clustered 3D strands and streamers;
the old billboard ellipse loops are removed. Resolved corona strength is reduced
when structures are active. Far-plane vertex clamping and per-pixel depth restoration
remain in `stellar_corona.gdshader`; structure shaders use the same depth rule.
Depth testing remains enabled for foreground occlusion. Opaque photospheres retain
back-face culling. Extended effects preserve their angular projection at the far
plane; they are not a volumetric or radiative-transfer simulation.

Geometry construction is lazy. A core angular radius of .02 radians selects low
structure LOD, .12 selects high, with 20% hysteresis; hidden or unresolved stars
release their nodes. Optional extended structures select LOD using their authored
extent, so a resolved nebula can exist around an unresolved core. Standalone paint
renders use the viewport camera; `PlanetSystem.refresh` explicitly updates the near
sphere and sky primary. The background named-star shell starts with dots and labels
and allocates a sphere only on approach, then releases it on withdrawal. No catalogue
destinations or scientific metadata are added.

| Structure | Low vertices | High vertices | Mesh surfaces |
|---|---:|---:|---:|
| Main-sequence/subdwarf/subgiant/Wolf–Rayet strands + haze | 3,240 | 25,344 | 2 |
| White-dwarf disk including batched debris | 1,200 | 4,752 | 1 |
| Brown-dwarf auroral curtain | 768 | 1,536 | 1 |
| Neutron/pulsar wind: bright tubes + haze tubes + clouds | 8,286 | 21,894 | 3 |

The sphere remains 96 × 48 (4,850 stored vertices); the existing corona is one quad. A resolved main-sequence
star therefore submits four mesh surfaces including its sphere and corona; bare
brown dwarfs and compact remnants submit two. An optional disk or aurora adds one
surface; an optional wind adds three, for five including the sphere and corona.
No structure exceeds 32,768 vertices or three batches. Seeded geometry is deterministic
and radius-relative. A FIFO cache holds at most eight normalized geometry sets across
visited stars; the physical color memo holds at most 256 colors. Neither cache grows
with travel history. No particles, downloaded textures or per-frame image builds.

## Optional structures and sensor views

All options default OFF; `sensor_mode` defaults to `visible`. Author visual options
inside `stellar.visual`:

```gdscript
{"name": "Disk-bearing white dwarf", "star": true, "spectral": "DA3",
 "stellar": {"visual": {"debris_disk": true,
                         "disk_inner_radii": 4.0, "disk_outer_radii": 26.0}}}

{"name": "Auroral brown dwarf", "star": true, "spectral": "L4",
 "stellar": {"visual": {"aurora": true, "sensor_mode": "enhanced_visible"}}}

{"name": "Authored wind example", "star": true, "stellar_type": "pulsar",
 "stellar": {"visual": {"wind_nebula": true, "sensor_mode": "xray",
                         "wind_extent_radii": 2.6e11}}}

{"name": "Sun", "star": true,
 "stellar": {"visual": {"sensor_mode": "uv"}}}
```

`aurora` is valid only for brown dwarfs; `debris_disk` only for white dwarfs;
`wind_nebula` only for neutron stars, pulsars or magnetars. A wind additionally
requires explicit `xray` mode and a finite authored extent greater than one and
at most 1e13 core radii. There is no silently assigned compressed nebula scale.
At a 12 km core radius, the example extends 3.12e12 km, roughly .1 parsec: it is an
enormous X-ray wind reference, not structure on a neutron-star surface. The layout
is a procedural wind approximation, not a reconstruction of Vela. Emission is
batched into bright toroidal arcs/jets, wider haze tubes and noisy soft cloud quads.
Low/high LOD uses 37/65 quads in a single cloud mesh, rather than per-cloud nodes.
All three batches retain the authored extent; camera framing or a parent transform
can compress their display without changing the recipe or geometry scale. Disk defaults
span 4–26 core radii; overrides require `1 < inner < outer <= 10000`. Invalid family,
sensor or scale combinations stay disabled and appear in `stellar.visual.validation`.

`uv` is an explicitly enhanced golden palette for photospheres/Wolf–Rayet envelopes.
`xray` is an explicitly enhanced blue palette for neutron remnants and their requested
winds. `enhanced_visible` strengthens optical structures and brown cloud visibility;
its brown-dwarf palette uses the approved dark red artist-reference treatment,
separate from the temperature-derived physical continuum color.
These modes are authored visualizations, not calibrated passband integrations.
They never replace `color_a`, bolometric luminosity, temperature, mass or hazards.
Optional aurora approximates red emission and is fainter in plain visible mode.
Optional dust disk colors approximate heated dust. Neither option is universal.

## Authored giant and neutron-star destinations

Ctrl+P accepts `red giant`, `neutron`, and `pulsar`, as well as names and IDs.
The family label comes from the shared recipe; only cool giant-family stars
(temperature ≤ 5,000 K) receive the Red Giant label. Hot giants and carbon stars
keep their own labels. These four rows live in `SystemDB.AUTHORED`, outside the
regenerable nearest-star list. Authored `stellar_type` and nested `stellar`
metadata are copied through generation and body specs into the live shared recipe.
Their planetary systems remain seeded inventions, not claims of observed planets.

| Destination | Adopted physics and source |
|---|---|
| Arcturus (`arcturus`) | K1.5III; 4,286 K, 25.4 solar radii, 1.08 solar masses from [Ramírez & Allende Prieto (2011)](https://arxiv.org/abs/1109.4425). [SIMBAD](https://simbad.cds.unistra.fr/simbad/sim-id?Ident=Arcturus) supplies coordinates, class and 88.83 mas parallax (36.7 ly). |
| Aldebaran (`aldebaran`) | K5III; 44 solar radii and a rounded 3,900 K from the reported 3,874 ± 100 K in [A&A 553 A3 (2013)](https://www.aanda.org/articles/aa/pdf/2013/05/aa21207-13.pdf). The adopted 1.2 solar masses is a rounded modeling estimate. [SIMBAD](https://simbad.cds.unistra.fr/simbad/sim-id?Ident=Aldebaran) supplies coordinates, K5+III class and 48.94 mas parallax (66.6 ly). |
| Vela Pulsar (`vela_pulsar`) | [Chandra (2013)](https://chandra.harvard.edu/photo/2013/vela/) gives 1,000 ly, RA 08h35m20.60s / Dec −45°10′35″, and more than 11 rotations per second. |
| Crab Pulsar (`crab_pulsar`) | Approximate nebula-center coordinates from [Chandra (2008)](https://chandra.harvard.edu/photo/2008/crab/), and 6,500 ly from [NASA SVS](https://svs.gsfc.nasa.gov/13737/). |

Both pulsars use the existing family's generic **12 km radius, 1.4 solar masses,
600,000 K** estimates; these are not measured values for either object. They load
bare visible cores with no authored wind nebula or false-color sensor mode.
Surface patterns and glare are procedural approximations. Spin periods are not
authored here; rotation retains the generator's existing estimate.

## Scale and hazards

Sol's Sun remains 695,700 km in radius. Catalogue destinations use generated
systems in kilometres: `GeneratedEphemeris` builds stellar radii and gravity
from the recipe, plus seeded planetary orbits. The compressed
`5 × R_solar^0.45` radius remains a display helper for distant catalogue markers;
it does not set the local primary star's radius after a system jump.

Ctrl+P's star rows jump to the selected system's primary star at
`max(4R, cbrt(GM × (60s / TAU)²))`, face it, set circular-orbit velocity,
clear time warp, and save the stellar park. The 60-second minimum orbital period
keeps compact-star arrivals stable with the ship's 0.25-second integration steps;
ordinary stars and white dwarfs retain their four-radius park. Physical radii stay
unchanged: a 12 km neutron core appears as a tiny bright point from this distance.
The current star can be selected again. Normal platform travel still uses its
planetary arrival. Near meshes and distant stellar spheres share the primary's
recipe and rotation; resolved stars use their recipe corona without additional
point-source glare.

Bare local stars below 0.001 rad in angular core radius use a soft, depth-tested
body sprite with a 0.010 rad display diameter (about 3 pixels at 800×450 and 70°
vertical field of view). This unresolved-source glare is a display PSF approximation;
the physical sphere, radius, gravity, arrival and hazard calculations retain their
true values. Resolved stars hide this sprite. Authored wind nebulae and debris disks
are excluded so their extent and resolution rules remain authoritative.

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
Set `STAR_TELEPORT_SYSTEMS=arcturus,aldebaran,vela_pulsar,crab_pulsar` to capture the
new destinations. Pulsar checks compare the projected center against a frame with
only its glare hidden: 2–20 changed pixels within 6 pixels, including blue-white
light, with no changes in the surrounding 12-pixel region. The final PNG restores
the glare; resolved giants must keep their dot hidden. Headless checks verify state
and scale, while these pixel checks require the parent's windowed renderer.

## Red dwarf colour and K2-18

K2-18 b is the planet; K2-18 is its M2.5V host star. The current spectral interpolation gives the host an estimated temperature of 3,455 K, close to the 3,457 ± 39 K solution in the [NASA Exoplanet Archive](https://exoplanetarchive.ipac.caltech.edu/overview/K2-18). This is a spectral estimate, not a per-object measured override.

Orange visible colour is consistent with the classification: [NASA's star types guide](https://science.nasa.gov/universe/stars/types/) explains that red dwarfs appear more orange than red. The renderer approximates a blackbody continuum through a standard observer and display colour space. It does not calculate full stellar atmosphere absorption spectra or human visual adaptation. Surface patterns, spots, activity and glare are procedural estimates, not observations of K2-18's surface.

## Production integration checks

Run from the repository root with the installed Godot 4.6.3:

```sh
godot --headless --path . --check-only --script scripts/world/star_recipe.gd
godot --headless --path . --check-only --script scripts/world/stellar_structures.gd
godot --headless --path . tools/test_stellar_structures.tscn
godot --headless --path . tools/test_star_recipes.tscn
godot --headless --path . --script tools/test_stellar_color.gd
godot --headless --path . tools/test_star_teleport.tscn
for f in test_surface_recipes test_earth_terrain test_surface_band test_skin_kill test_terrain_light test_planet_generator; do
  timeout 120 godot --headless --path . --script tools/$f.gd
done
```

`test_stellar_structures` checks family validation/defaults, explicit enormous wind
scales, physics/palette separation, deterministic finite normalized geometry,
vertex/surface budgets at both LODs, explicit cached construction through more than
eight seeds, cache filling/bounds, identity reuse, FIFO eviction and deterministic
regeneration, lazy construction, and the actual near/sky handoff. It also checks
shared cook identity and near/sky uniform agreement, including display palettes. These are logic checks; headless passes do not prove shader compilation,
clipping or visual approval. The clipping scene freezes only its duplicated corona
shader's `TIME`, selects a lit halo pixel outside the core, and verifies foreground
blocker depth. It separately captures the tilted disk, aurora, both wind tube batches
and cloud batch at reference/limited far planes and behind an opaque blocker. Wind
geometry retains its authored 2.6e11-core-radius extent, framed by the parent scale.
The original .001 changed-fraction and 50-pixel grazing limits remain in force.
Render checks completed on 2026-10-06 with Godot 4.6.3, Compatibility rendering
and Mesa llvmpipe. The corona, disk, aurora and all three wind batches passed the
limited-far-plane and foreground-occlusion comparisons; isolated grazing halo
pixels had zero differences. This checks effect clipping, not photosphere clipping.
Production captures use automatic LOD, including the authored astronomical wind
extent. Real Ctrl+P picker captures passed for Sun, Proxima, Wolf 359, Sirius,
Luhman 16 and Gliese 440. Hardware performance and other rendering backends
have not been measured. Captures and details: [integration review](reference/stellar-integration/README.md).
Existing stellar tests have exit resource-leak warnings;
an OK assertion summary should not be described as clean shutdown.

Windowed production captures and the existing pixel occlusion regression:

```sh
STELLAR_PRODUCTION_SHOTS=/tmp/stellar-production xvfb-run -a godot --path . res://tools/render_stellar_production.tscn
STAR_RECIPE_SHOT=/tmp/star-recipes.png xvfb-run -a godot --path . res://tools/render_star_recipes.tscn -- --details
STAR_TELEPORT_SHOTS=/tmp/star-teleport xvfb-run -a godot --path . res://tools/render_star_teleport.tscn
CORONA_SHOT_DIR=/tmp/corona-clipping xvfb-run -a godot --path . res://tools/test_stellar_corona_clipping.tscn
xvfb-run -a godot --path . res://tools/render_sun_approach.tscn
```

When using the installed Flatpak, replace `godot` with
`flatpak run org.godotengine.Godot`. Run these windowed commands from the parent
session if sandbox display access is unavailable. The new production gallery writes
12 per-family/variant captures, `gallery.png` and a scale/sensor manifest. Frames
normalize by the core radius; the disk and wind frames widen to their full authored
extent. The neutron core is consequently unresolved in the enormous wind frame.
These captures call production `PlanetGenerator.paint` and its lazy structures,
not the separate preview renderer. Every new scene tool isolates its profile with
`ProfileDir.isolate`; choose a separate `ASTRYX_PROFILE_DIR` for repeated runs.


For the current `/tmp/astryx-godot` wrapper, the parent can run the blocked
windowed checks without installing anything:

```sh
STELLAR_PRODUCTION_SHOTS=/tmp/stellar-production-fixed xvfb-run -a /tmp/astryx-godot --path /home/fiazul/Desktop/space-survey res://tools/render_stellar_production.tscn
CORONA_SHOT_DIR=/tmp/corona-clipping-fixed xvfb-run -a /tmp/astryx-godot --path /home/fiazul/Desktop/space-survey res://tools/test_stellar_corona_clipping.tscn
```

Inspect the captures and complete logs. Exit zero with `SCRIPT ERROR`, a shader
compilation error, or a missing assertion summary is not a passing check.
