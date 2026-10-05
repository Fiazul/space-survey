# Blender ship authoring

The six modular fleet hulls have inset engines beneath their upper hulls, with sloped
armor shoulders, raised wing panels and radiator banks. Engine mouths sit forward under
the stern overhang so the full-boost exhaust stays visible in the close chase view.
The Class II cruiser is the reference for this layered arrangement.

| File | Role |
|---|---|
| `build_ships.py` | Builds editable sources and exports fleet hulls |
| `ship_common.py`, `sleek.py` | Shared modelling helpers |
| `sources/*.blend` | Editable hull parts, engine shoulders, armor and sockets |
| `render_ships.py` | Side, rear, top and three-quarter views of game exports |
| `concepts/fleet-direction.png`, `concepts/prompt.txt` | GPT Image reference and generation prompt |
| `test_ship_export.py` | Checks nozzle/socket alignment after manual transforms and parenting |
| `build_modules.py`, `module_common.py` | Builds weapon and landing pad modules |
| `render_modules.py` | Module previews |

Open a file such as `sources/kestrel.blend` in Blender. Parts remain separate, with mirror
and bevel modifiers intact. Authoring axes are nose +Y and up +Z; one Blender unit is one metre.
Move each booster socket with its nozzle when editing an engine.

After saving a manual edit, export that source into the game without regenerating it:

```bash
blender -b tools/blender/sources/kestrel.blend --python-exit-code 1 --python tools/blender/build_ships.py -- --export-current
```

The exporter joins the game mesh, centres it, normalizes its roster length, checks the
25,000-triangle limit and writes `assets/ships/kestrel/kestrel.glb`. The source stays editable.

Regenerate a source from its procedural definition (this replaces manual source edits):

```bash
blender -b --python-exit-code 1 --python tools/blender/build_ships.py -- --ship 2
```

Ship tiers 2–7 are Kestrel, Swift, Harrier, Osprey, Condor and Albatross. Tier 1 in this
builder is the unrostered Wren; the playable first ship is the authored Class II cruiser.

Render the exported geometry:

```bash
blender -b --python tools/blender/render_ships.py -- --ship kestrel --views side,rear,3q --out /tmp/ship-review
```

Check exports after transformed-part edits:

```bash
blender -b --python-exit-code 1 --python tools/blender/test_ship_export.py
```

Check close chase-view exhaust visibility in the game's Forward+ renderer:

```bash
VIEW=chase CAM_ZOOM=0.45 CHECK_EXHAUST_FRAME=1 SHOT_DIR=/tmp/fleet-chase xvfb-run -a godot --path . tools/render_thruster.tscn
```
