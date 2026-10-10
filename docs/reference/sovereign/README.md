# Sovereign realism review — 2026-10-09

The four studio images (`sovereign_3q.png`, `sovereign_rear.png`, `sovereign_side.png`,
`sovereign_top.png`) render the current game GLB using its authored materials, without
fleet preview color/finish overrides. Rendered with Cycles, 32 samples, 1400px.

The latest GPT Image concept and exact prompt are
`tools/blender/concepts/sovereign-realism.png` and `sovereign-realism-prompt.txt`.
The concept is a modeling reference; the studio images show the actual exported model.

The 2026-10-09 pass keeps the triple spear prow, swept wing pair, half-length outer
housings and four octagonal engines. Scale comes from a smaller armored command bridge
with individual 1.72 × 0.62 m windows, inspection covers and latches, sparse expansion
joints, layered flank armor, radiator banks and exposed coolant service channels.
Continuous glowing prow edges have been replaced by short navigation lamps. The finish
uses rougher grey titanium, dark thermal surfaces and a shared wear/albedo map.
Engine collars now have heat-shield bands, feed lines, fasteners and internal liner ribs.

Editable source: `tools/blender/sources/sovereign.blend`.
It contains 225 separate mesh parts in six named collections, 34 gameplay sockets,
unapplied mirror/bevel modifiers and five packed texture images. One Blender unit is one
metre, nose +Y, up +Z. The game export remains one mesh with six material surfaces.

Builder: `tools/blender/sovereign.py`, via `build_ships.py -- --ship 8`.
The source can also be reopened, edited and exported with `--export-current`.
The final hull is 240 m long and 25,396 triangles, within Sovereign's 30,000 limit.
The GLB is 1,819,696 bytes (approximately 1.74 MiB), with 32,572 exported vertices.
Texture images are a shared 512px wear/albedo map, a shared 512px brushed normal,
and three 256px metallic/roughness maps. Hangar tinting preserves the wear map;
both metallic and opaque lacquer options work.

Verified: source reopen/export, GLB length/material/socket/budget/exhaust clearance,
color and finish customization, weapon/pad module swaps, and Sovereign's Earth landing
cycle at 60 and 20 fps. Godot headless checks pass with the repository's existing dummy
renderer/material and resource-cleanup warnings. No runtime lights were added.

`sovereign_game_front.png` is the current GLB in Godot's Forward+ renderer.
`sovereign_chase_rest.png` and `sovereign_chase_boost.png` remain older gameplay captures.
The optional new close-chase capture at CAM_ZOOM=0.45 completed and flagged boosted
exhaust cropped at the bottom edge (4,713 flow pixels, 195 edge pixels). Geometry/socket
exhaust clearance passed; whether the zoomed-frame result is a regression was not
established. No camera or exhaust shader changes were made for this asset update.
Studio lights show materials differently from gameplay; GPU memory and device FPS
were not benchmarked.
