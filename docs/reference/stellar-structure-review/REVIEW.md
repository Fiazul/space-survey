# Stellar structure review 02

Preview revision responding to the supplied solar corona, dusty white dwarf,
Vela pulsar and auroral brown-dwarf references. Gameplay has not changed.

[Comparison sheet](comparison-02.png) and [brown-dwarf reference comparison](brown-dwarf-comparison.png).
Individual captures are 960 × 640. [structures.json](structures.json) records the
ten rendered variants. The six original family recipes remain available in the
previous review directory.

The review constructs plasma bundles as 3D curve meshes with emissive material,
a layered annular dust disk with debris geometry, toroidal wind arcs, curved
particle jets and a continuous polar auroral curtain. The brown-dwarf surface
uses uneven broad cloud belts, sheared finer streaks and a darker red display
palette. These are proposed procedural visualizations, not observed maps.

The main comparison uses an enhanced gold solar sensor palette. `solar-visible.png`
supplies a warm-white visible-light alternative. The wind nebula uses an
X-ray-inspired blue palette and compressed geometry ratios. White-dwarf disks,
pulsar wind nebulae and aurorae are optional system variants. Bare white-dwarf,
bare neutron-star and brown-dwarf-without-aurora captures are included.
Brown-dwarf brightness is enhanced for visual assessment; it is not a predicted
visible-light flux or a full atmosphere-spectrum calculation.

Godot creates and renders these meshes directly. No Blender executable was found
on PATH, in the checked standard installation locations, or among installed
Flatpak applications in this session. No Blender render or export is claimed.
Materials and geometry are isolated in `tools/stellar_preview` and the review
scene; production recipes and shaders have not been edited.

## Reproduce

```bash
xvfb-run -a flatpak run org.godotengine.Godot --path . --rendering-method gl_compatibility tools/render_stellar_structure_review.tscn
python3 tools/build_stellar_review_sheet.py
```

Verification level: implemented as a preview and rendered with Godot 4.6.3,
Compatibility renderer, Mesa llvmpipe. Ten capture existence, size and image
brightness checks completed. No live gameplay integration, GPU performance or
cross-renderer verification is claimed. The engine reports the same resource
cleanup warnings seen in the earlier baseline tests at exit.

## Reference interpretation

- [NASA wavelength comparison](https://science.nasa.gov/photojournal/comparing-wavelengths/): gold 171 Å images reveal extreme-ultraviolet coronal plasma structures; the gold is an assigned display color.
- [NASA white-dwarf illustration](https://svs.gsfc.nasa.gov/13147): the supplied image depicts LSPM J0207+3331 with dust from crumbling asteroids. It does not establish disks as a property of every white dwarf.
- [Chandra Vela pulsar](https://chandra.cfa.harvard.edu/photo/2013/vela/): the supplied blue image is an X-ray image of the pulsar and its particle outflow on a vastly larger scale than the stellar surface.
- [NASA brown-dwarf aurora](https://science.nasa.gov/resource/brown-dwarf-aurora/): the supplied artist concept depicts LSR J1835+3259 and its auroral display. Credit: Chuck Carter and Gregg Hallinan, Caltech.

The reference comparison reproduces the user-supplied brown-dwarf illustration
solely as a labeled design reference. It is not included in gameplay assets.
