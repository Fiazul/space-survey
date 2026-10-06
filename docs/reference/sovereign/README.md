# Sovereign final review

`sovereign_3q.png` and `sovereign_rear.png` render the final exported game GLB.
The side/top and gameplay captures show the earlier hull pass. The concept and original prompt are in
`tools/blender/concepts/sovereign-direction.png` and `sovereign-prompt.txt`.

`sovereign_chase_rest.png` and `sovereign_chase_boost.png` are captures from Godot's
Forward+ renderer; close chase exhaust check passed with no flow pixels at the bottom edge.
`sovereign_game_front.png` shows the shortened housings and both ventilators in Godot.

Final hull: 240 m, 18,168 triangles, 34 sockets. One swept wing pair and no central
underside stern keel. Tier 8 unlocks at 16 systems beyond
Sol; 440 HP, 250 energy, 8 weapon mounts, 4 main engines, 6 landing pads, 8 belly jets.
The hull ceiling increases from 25k to 30k only for this ship.

Player revisions: continuous faceted silver armor with swept, tapered black ray
inlays; square tile grids, dense seam lines and raised rounded bumps removed.
Stepped upper engine hoods and shaped lower cradles follow the octagonal boosters;
recessed joints and metal lips create the stern layers. All armor ends before the nozzle
mouths. `tools/test_ship_glb_sockets.gd` checks that no armor extends behind them.
The outer housings measure approximately 120.24 m including trim, half the ship length.
Their forward ends have recessed ventilators, chamfered frames and three swept louvers.
Narrow steel bevels, weighted normals, tapered inner-engine transitions and lower bridge
aprons improve the joins and edge highlights while keeping the faceted body.

Editable source: `tools/blender/sources/sovereign.blend`.
Builder: `tools/blender/sovereign.py`, invoked by `build_ships.py -- --ship 8`.

Validated: ship GLB sockets/materials/budget/exhaust clearance; roster and unlock
thresholds; module swaps; ship systems; color/finish customization; Sovereign's full
Earth landing cycle at 60 and 20 fps. Godot's headless runs report existing dummy
renderer/material and resource-cleanup warnings alongside successful test results.

Optimization: ray surface subdivisions remain reduced. The final GLB contains one mesh,
six material surfaces and 19,434 exported vertices in 1,101,336 bytes (approximately
1.05 MiB). The 30k triangle cap is unchanged. Four packed maps provide a shared 512px
brushed normal and three 256px metallic/roughness maps. Godot's loaded RGB image payload
including mipmaps is approximately 1.75 MiB; actual GPU allocation and device FPS were
not benchmarked. Godot extracts the packed images beside the GLB on import.
Recoloring preserves authored texture factors; metallic and opaque lacquer options
still work, verified by the customization test. No new per-frame mesh generation or
runtime lights were added. Studio lights show highlights more strongly than the game
camera, so review the Godot captures alongside the studio views.
