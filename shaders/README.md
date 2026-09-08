# shaders/

GDShader source, all `shader_type spatial` except `hud_text.gdshader` (canvas_item).

| File | Type | Role |
|---|---|---|
| `planet_cook.gdshader` | feature area | The one shared planet/star cook shader — kind 0 rocky, 1 gas, 2 ice, 3 star. `sample_height()` must mirror `PlanetGenerator.crust_height()` (see CLAUDE.md) |
| `terrain_tile.gdshader` | feature area | Lit, hazed ground for the skin-band terrain rings |
| `surface_prop.gdshader` | feature area | Shading for kit props (rocks/ice/trees) seated on terrain |
| `air_shell.gdshader` | feature area | The sky as seen from inside an atmosphere |
| `wedge_hull.gdshader` | feature area | Hull material for the wedge-fighter ship design |
| `wedge_exhaust.gdshader` | feature area | Exhaust plume for the wedge-fighter ship design |
| `jazoone_hull_booster.gdshader` | feature area | Textured hull + HDR torch for the JazOone ship's authored emissive engine discs |
| `cruiser_propulsion.gdshader` | feature area | Exhaust seated on the Class II cruiser's authored propulsion geometry |
| `cruiser_torch.gdshader` | feature area | Shared additive plasma torch for every ship's authored booster sockets |
| `cruiser_led.gdshader` | feature area | Animated rainbow chase for the cruiser's authored window strip |
| `exhaust_haze.gdshader` | feature area | Screen-space refraction shell wrapped around a booster plume |
| `hud_text.gdshader` | feature area | Metallic linear-gradient fill for HUD glyph text |
