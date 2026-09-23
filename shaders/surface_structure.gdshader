shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 sun_dir = vec3(0.7, 0.3, 0.6);
uniform vec3 color_air : source_color = vec3(0.3, 0.56, 1.0);
uniform float air_amount = 1.0;
uniform float haze_density = 1.0;
varying vec3 point;
varying vec3 normal_world;
varying vec3 up_world;
varying float wall;
void vertex() {
	point = VERTEX * 1000.0;
	wall = abs(NORMAL.y) < 0.5 ? 1.0 : 0.0;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	up_world = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
void fragment() {
	float grain = fract(sin(dot(floor(point * 2.0), vec3(12.9, 78.2, 41.7))) * 43758.5);
	float horizontal = wall;
	// Dark, powerless windows and exposed storey bands. No city lights.
	float floors = smoothstep(.16, .22, fract(point.y / 3.5)) * (1.0 - smoothstep(.68, .78, fract(point.y / 3.5)));
	float bays = step(.22, fract((point.x + point.z) / 3.0));
	float detail = 1.0 - smoothstep(.5, 2.5, length(fwidth(point)));
	float windows = mix(.30, floors * bays, detail) * horizontal * step(4.5, point.y) * (1.0 - step(.25, COLOR.a));
	float stain = .5 + .5 * sin(point.x * .27 + point.z * .31 + sin(point.y * .06));
	float rust = smoothstep(.55, .9, stain) * .22;
	vec3 concrete = mix(vec3(.32, .30, .26), vec3(.22, .17, .11), rust) * COLOR.rgb;
	concrete *= .80 + grain * .08 * detail + stain * .16;
	concrete = mix(concrete, vec3(.027, .035, .037), windows * .86);
	vec3 n = normalize(normal_world);
	vec3 up = normalize(up_world);
	vec3 l = normalize(sun_dir);
	float day = smoothstep(-0.04, 0.28, dot(up, l));
	float lit = .04 + day * (max(dot(n, l), 0.0) * .95 + air_amount * (.22 + .18 * max(dot(n, up), 0.0)));
	float fog = clamp((1.0 - exp(-length(VERTEX) / 50.0)) * air_amount * haze_density, 0.0, 1.0);
	ALBEDO = mix(concrete * lit, color_air * (.04 + .61 * day), fog);
}
