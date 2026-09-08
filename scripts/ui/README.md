# scripts/ui/

Everything the player reads/clicks: HUD readouts and every overlay panel.

| File | Type | Role |
|---|---|---|
| `hud.gd` | feature area | Main HUD (readouts, tip/quest banners, layout editor) |
| `mini_map.gd` | feature area | Corner radar (ship-relative blips) |
| `crosshair.gd` | feature area | The aiming reticle |
| `star_map.gd` | feature area | The zoomable star map (M) |
| `map_chart.gd` | feature area | Star-map drawing/projection, used by `star_map.gd` |
| `settings_menu.gd` | feature area | Settings overlay (audio, reset progress…) |
| `codex_panel.gd` | feature area | The Codex logbook (L) |
| `planet_info.gd` | feature area | The Details panel (G) |
| `quest_log.gd` | feature area | The Mission Log (J) |
| `reward_card.gd` | feature area | The capture-celebration payout card |
| `tutor.gd` | feature area | Non-blocking new-game tip notifications |
