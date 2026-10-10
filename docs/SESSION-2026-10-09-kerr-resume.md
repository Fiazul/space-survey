# Kerr hotspot inspection resumed

Recovered Claude session `90d2e9f5-94e0-4097-a0e5-50932a05dac8` after its hotspot
worker was stopped. Its final shader adjustment was already saved: white-hot
spots, a 60% flow brightness ceiling, and cooling wakes reduced to 6% of the
hotspot peak. Kept that implementation and verified it rather than restarting
the feature. No commits or resets; the existing uncommitted core work remains.

The shared sensor clock remains ×40. Ship motion, gravity and capture use the
simulation clock. Hotspots near the shadow appear as moving lensed arcs.

Fresh checks:

- `test_galactic_core.tscn`: OK, including deterministic hotspots, Kerr recipe
  values, orbital arrivals, flare scheduling and system transitions.
- `test_black_hole_motion.tscn`: OK on software OpenGL and default Vulkan.
  Hotspot-light centroid shifts in two seconds: 41.012 and 33.528 pixels.
  Clock-held controls: 0.00% changing flow pixels on both renderers.
- `test_black_hole_views.tscn`: OK on software OpenGL, including outward/rolled
  flow, transparent foregrounds, background occlusion and Kerr shadow edges.
- `test_black_hole_plunge.tscn`: OK. A start at 0.95 ISCO crosses the horizon
  after 470 seconds; the circular-orbit and escape-warning checks also pass.
- `test_star_recipes.tscn`: OK. This is a scene-based test; do not run its `.gd`
  with `--script`, which omits autoload registration and fails to compile.
- `render_galactic_core.tscn`: OK on software OpenGL. Captures in
  `/tmp/astryx-core-resumed`; reviewed the close, polar and outward views. The
  polar view shows distinct white hotspots; the close view shows an asymmetric
  dark shadow and a white approaching side, and the outward flow reaches the
  screen edge without a cut-off. The 60-second comparison changed 73,229 pixels.

[Animated motion preview](reference/black-hole-motion/motion.gif) and its
[capture notes](reference/black-hole-motion/README.md) are stored in the repo.
Updated `GALACTIC_CORE.md` to match the actual spot colour, brightness ceiling
and pseudo-Newtonian circular arrival velocity.

Run Godot sequentially with timeouts. For captures use CPU rendering:
`LIBGL_ALWAYS_SOFTWARE=1` for OpenGL, or
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json` for Vulkan.
Previous sessions reported two PC crashes while several Godot GPU processes were
running. Their cause was not established. Do not repeat the full test loop;
the resumed task explicitly limited verification to the relevant core tests.

Software-renderer checks establish motion and rendering behavior, not the
player's AMD frame rate or final colour quality. Test processes still print
ObjectDB/resource cleanup warnings on exit. No runtime script or shader errors
occurred in the successful checks above.
