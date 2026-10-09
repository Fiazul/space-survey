# Black-hole motion review

[Motion preview](motion.gif) contains five fixed-camera captures at 2 AU, spaced
0.5 simulation seconds apart. Playback uses the game's existing sensor time-lapse
×40. The preview loops after the frame at 2 seconds; that reset is not an in-game
discontinuity.

Captured on 2026-10-09 using the OpenGL compatibility software renderer:

```bash
LIBGL_ALWAYS_SOFTWARE=1 MOTION_SHOT_DIR=/tmp/astryx-black-hole-motion-resumed \
  timeout 180 xvfb-run -a godot --path . --rendering-method gl_compatibility \
  res://tools/test_black_hole_motion.tscn
```

The motion test passed. About 40% of bright plasma pixels changed per half-second;
the hotspot-light centroid moved 41.012 pixels in two seconds. At 1.2 AU, 68.5%
changed over 2.5 seconds, and 0.00% changed with the clock held fixed.

The default Vulkan renderer also passed on llvmpipe: the hotspot-light centroid
moved 33.528 pixels in two seconds; at 1.2 AU, 72.7% of flow pixels changed over
2.5 seconds and 0.00% changed with the clock held fixed. Run it with:

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json \
  MOTION_SHOT_DIR=/tmp/astryx-black-hole-motion-vulkan-resumed \
  timeout 180 xvfb-run -a godot --path . res://tools/test_black_hole_motion.tscn
```

The renderer stretches hotspots into arcs near the shadow. Software-renderer
colours and these image checks do not establish the frame rate or appearance on
the player's AMD GPU.
