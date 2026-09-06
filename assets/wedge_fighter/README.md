# Selene

Source model: user-supplied `wedge_fighter.glb`, copied unchanged from Downloads.
The redesign is applied at runtime by `scripts/flight/wedge_fighter.gd`.

The fifth hangar ship keeps the authored Hull, Wing_L/R, Canopy, Engine_L/R,
and Exhaust_L/R meshes. It adds ceramic livery with mirrored ice-blue top accents, graphite framing,
cooling louvers, swept fins, status lights, and Selene identification. The underside
retains copper trim and has segmented armor, a circular service hatch, radiator cassettes, landing pads,
and approach lights. Authored
exhaust geometry uses a throttle-driven shader and a narrow inner core.
Exhaust is excluded from hull fitting, and the fixed livery bypasses the generic
paint pass.

Design preview: run `res://tools/render_wedge_fighter.tscn` with Godot.
Set `RAW=1` to render the source appearance; `SHOT_DIR` selects an output directory.
Game-lighting preview: `SHIP=wedge` with `res://tools/render_thruster.tscn`.
Runtime regression: `godot --headless --path . res://tools/test_wedge_fighter.tscn`.
