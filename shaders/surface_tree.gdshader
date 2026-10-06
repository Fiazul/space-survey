shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float foliage = 0.0;
uniform float far_card = 0.0;
uniform vec3 sun_dir = vec3(.72, .28, .63);
uniform vec3 color_air : source_color = vec3(.3, .56, 1.0);
uniform float air_amount = 0.0;
uniform float haze_density = 1.0;
uniform float exposure = 1.0;
uniform float stream_fade = 1.0;
varying vec3 normal_world;
varying vec3 up_world;
void vertex() {
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	up_world = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
void fragment() {
	vec4 tex = texture(albedo_map, UV) * tint;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = .45;
	vec3 n = normalize(normal_world);
	vec3 up = normalize(up_world);
	vec3 light = normalize(sun_dir);
	float day = smoothstep(-.04, .28, dot(up, light));
	float diffuse = mix(max(dot(n, light), 0.0), .32 + .48 * abs(dot(n, light)), foliage);
	diffuse = mix(diffuse, .58, far_card);
	float lit = .025 + day * (diffuse * .92 + air_amount * (.18 + .14 * max(dot(n, up), 0.0)));
	float haze = clamp((1.0 - exp(-length(VERTEX) / 70.0)) * air_amount * haze_density, 0.0, 1.0);
	ALBEDO = mix(tex.rgb * lit * exposure, color_air * lit, haze) * stream_fade;
}
