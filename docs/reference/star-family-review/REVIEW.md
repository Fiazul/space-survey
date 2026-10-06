# Star family visual review

Preview proposal for a user visual pass. Gameplay recipes, shaders and travel
destinations have not changed. Run the review scene to reproduce these materials.

[Open the comparison](review.png). Individual PNGs show the same preview without
labels. [recipes.json](recipes.json) records all 18 input specifications and their
resolved preview parameters, including the physical estimates.

| Family | Preview treatment |
| --- | --- |
| Main sequence | O, solar G and K examples; temperature colors, filtered granulation and reduced glare |
| Red giants | Three temperature examples; broader convection, stronger cell contrast and limb darkening |
| White dwarfs | Hot, cooling and old examples; smooth surfaces, subdued halos and cooling-dependent colors |
| Neutron stars | Plain remnant, pulsar and magnetar; smooth crust and tilted hot caps, without gaseous bands |
| Red dwarfs | K2-18, Proxima and TRAPPIST-1 spectral estimates; orange photospheres, spots and magnetic loops |
| Brown dwarfs | L0, L8 and T8 examples; cloud bands and faint visible emission, with false-color sensor insets |

Discs have equal angular size for visual comparison. Their labels give recipe
radii, not scaled drawing sizes. Red dwarfs are a subset of the main sequence;
they have a separate panel here to match the requested review categories.

The preview uses the game's existing CIE 1931 blackbody continuum approximation,
not a full stellar-atmosphere spectrum. Surface patterns, activity, giant sizes
and compact-remnant defaults are procedural estimates. Named dwarf examples use
spectral estimates, not individual measured overrides. The Sun is the solar
reference. The preview's giant contrast is a proposed artistic calibration.

Pulsar beam cones and magnetar magnetic field lines are schematic overlays for
recognition. They are not a claim that these structures glow visibly in vacuum.
Brown-dwarf insets use an authored false-color palette and enhanced brightness;
they are not computed infrared observations. The untreated T8 photosphere is
almost black at the shared exposure.

The compact-remnant shader branch is changed only in an independent shader
instance owned by this review scene. Other adjustments bind only to the review's
material instances. Approving these previews does not add destinations or change
the real catalog's classifications.

## Reproduce and verify

```bash
xvfb-run -a flatpak run org.godotengine.Godot --path . --rendering-method gl_compatibility tools/render_star_family_review.tscn
flatpak run org.godotengine.Godot --headless --path . --script tools/test_stellar_color.gd
flatpak run org.godotengine.Godot --headless --path . tools/test_star_recipes.tscn
```

Default captures go into this directory. `STAR_FAMILY_REVIEW_DIR` selects another
directory. The tool isolates its profile so the player's save is not changed.

Verification reached: preview implemented, existing recipe and color checks
unit-tested, and all 18 samples rendered with Godot 4.6.3's Compatibility renderer
using Mesa llvmpipe. Renderer checks reject missing photospheres. This does not
verify gameplay integration or hardware GPU performance. Both existing tests
and the review render report ObjectDB/resource cleanup warnings at exit despite
returning code 0 and completing their checks.

## Scientific references

- [NASA: Types of stars](https://science.nasa.gov/universe/stars/types/) — family properties and red-dwarf visible color.
- [NASA: Pulsars](https://science.nasa.gov/mission/hubble/science/science-behind-the-discoveries/hubble-pulsars/) — magnetic polar emission and lighthouse behavior.
- [NASA: Hubble brown-dwarf illustration](https://science.nasa.gov/asset/hubble/hubble-brown-dwarf-survey-illustration/) — cloud bands and predominantly infrared emission.
- [Harre and Heller: Digital color codes of stars](https://arxiv.org/abs/2101.06254) — differences between stellar spectra and blackbody color approximations.
