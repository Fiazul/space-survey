# Humano portal

[Arcade](arcade.png), [cubic mist](cubic_mist.png), [portrait layout](portrait.png).
[Return at 2 AU](return_2au.png) also verifies the scene-authored astronaut no
longer appears beside the ship in the core.

Ctrl+P → search **Humano** → **through the horizon → Humano** previews the full
entry. Ordinary horizon crossing enters it too. Ctrl+D no-death bypasses entry.

Space, Up, click or Jump starts/jumps. A collision offers a restart. Esc or
Return to ship exits at a circular 2 AU orbit, with the original hull and progress.

Captured using software OpenGL on 2026-10-09. The portrait preview uses
`TOUCH_SCALE=1.6`; it is a layout check, not a test on an Android device.
Reproduce with `res://tools/render_black_hole_portal.tscn` under `xvfb-run`,
`LIBGL_ALWAYS_SOFTWARE=1` and a timeout. Captures go to `/tmp/astryx-humano`.

`mobile_capture.png` shows the forced-capture HUD from 0.585 AU using software
Vulkan Mobile. The accretion layer covering the foreground hull is tracked as
BH-002; this is evidence of a remaining bug, not a clean visual approval.
