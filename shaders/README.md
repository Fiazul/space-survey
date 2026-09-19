# shaders/

GDShader source, all `shader_type spatial` except `hud_text.gdshader` (canvas_item).

| File | Type | Role |
|---|---|---|
| `planet_cook.gdshader` | feature area | The one shared planet/star cook shader — kind 0 rocky, 1 gas, 2 ice, 3 star. `sample_height()` must mirror `PlanetGenerator.crust_height()` (see CLAUDE.md) |
| `terrain_tile.gdshader` | feature area | Lit, hazed ground for the skin-band terrain rings; `stream_fade` instance uniform (default 1) |
| `surface_prop.gdshader` | feature area | Lit Lambert + sky/sun shading for kit props; sky term only when air is present; `stream_fade` (default 1) |
| `air_shell.gdshader` | feature area | The sky as seen from inside an atmosphere |
| `cloud_layer.gdshader` | feature area | Cloud deck shell (`CloudLayer`) covering the gap between the globe's clouds vanishing and the skin band's ground |
| `wedge_hull.gdshader` | feature area | Hull material for the wedge-fighter ship design |
| `wedge_exhaust.gdshader` | feature area | Exhaust plume for the wedge-fighter ship design |
| `jazoone_hull_booster.gdshader` | feature area | Textured hull + HDR torch for the JazOone ship's authored emissive engine discs |
| `cruiser_propulsion.gdshader` | feature area | Exhaust seated on the Class II cruiser's authored propulsion geometry |
| `cruiser_torch.gdshader` | feature area | Shared additive plasma torch for every ship's authored booster sockets |
| `cruiser_led.gdshader` | feature area | Animated rainbow chase for the cruiser's authored window strip |
| `vanguard_vent.gdshader` | feature area | Curved luminous glass inserts in Vanguard's rectangular rear housings |
| `base_basic_wing_glass.gdshader` | feature area | Shape-conforming blue-white glass overlay for Base Basic PBR's paired wings |
| `exhaust_haze.gdshader` | feature area | Screen-space refraction shell wrapped around a booster plume |
| `hud_text.gdshader` | feature area | Metallic linear-gradient fill for HUD glyph text |
