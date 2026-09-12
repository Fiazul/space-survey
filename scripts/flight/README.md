# scripts/flight/

The player ship: physics, visuals, controls, and hull-specific design data.

| File | Type | Role |
|---|---|---|
| `ship.gd` | feature area | Flight physics, visuals (boosters/streaks), warp, autopilot, customization |
| `ship_mesh.gd` | feature area | Stateless mesh/material/FX build helpers for the hulls, split out of `ship.gd` |
| `anchor_frame.gd` | data | `AnchorFrame` — 64-bit arithmetic for the anchored ship frame (docs/adr/0002); static, autoload-free |
| `flight_mode.gd` | feature area | Zone (CENTER/INSIDE/SKIN/AIR/SPACE) vs mode (LOCAL/CRUISE/AIR) + exclusion-zone math |
| `turn_carry.gd` | feature area | Sol flight assist: a turn carries velocity with the hull |
| `touch_controls.gd` | feature area | Mobile multi-touch control overlay, landscape/two-thumb (`--touch` to test on desktop) |
| `wedge_fighter.gd` | data | `WedgeFighterDesign` — one hull's shader/geometry design constants |

Touch controls: left thumb is a fixed movement-joystick zone (forward + turn only, no
reverse — pushing into the back cone brakes); right thumb has FIRE + stacked UP/DOWN
nose-pitch buttons plus BOOST/CAP/THRUST/INTERACT/MAP/HOME, and a free-drag look area —
two fingers in that look area pinch the chase-camera zoom instead of steering the look
(mobile boots at max zoom-in, `Ship.default_zoom()`). A top-right DEV tap button reveals
NODEATH/FASTAIR when dev mode is on. The stick→command mapping is the pure static
`TouchControls.stick_to_cmd()`, and the pinch math is the pure static
`TouchControls.pinch_zoom()`, both unit-tested in `tools/test_touch_controls.gd`.
