# scripts/ui/

Everything the player reads/clicks: HUD readouts and every overlay panel.

| File | Type | Role |
|---|---|---|
| `hud.gd` | feature area | Main HUD (readouts, tip/quest banners, layout editor) |
| `hud_scale.gd` | helper | `HudScale` (static): touch-target scale from screen dpi, display-cutout safe insets, and re-docking 1280x720-authored positions onto the real canvas; TouchControls uses it for its bottom-right controls and top-right MENU pill, converting raw input through the viewport transform before hit-testing or drawing the joystick |
| `mini_map.gd` | feature area | Corner radar (ship-relative blips) |
| `crosshair.gd` | feature area | The aiming reticle |
| `star_map.gd` | feature area | The zoomable star map (M) |
| `map_chart.gd` | feature area | Star-map drawing/projection, used by `star_map.gd` |
| `settings_menu.gd` | feature area | Settings overlay (audio, reset progress…) |
| `codex_panel.gd` | feature area | The Codex logbook (L) |
| `planet_info.gd` | feature area | The Details panel (G) |
| `quest_log.gd` | feature area | The Mission Log (J) |
| `tutor.gd` | feature area | Non-blocking new-game tip notifications |
| `dev_sites_panel.gd` | feature area | Dev-teleport overlay (Ctrl+P) — jump to any `DevSites` row |
