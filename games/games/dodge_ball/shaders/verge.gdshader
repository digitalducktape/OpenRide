// The grass verges either side of the road: mown stripes and noise, scrolled with the road.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float scroll = 0.0;
uniform vec3 grass_a : source_color = vec3(0.24, 0.45, 0.18);
uniform vec3 grass_b : source_color = vec3(0.3, 0.52, 0.2);
uniform vec3 dirt : source_color = vec3(0.42, 0.36, 0.26);
uniform float road_half = 6.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = world_pos.z - scroll;
	float ax = abs(world_pos.x);
	float stripe = step(0.5, fract(z / 9.0));
	vec3 col = mix(grass_a, grass_b, stripe);
	col *= 0.8 + 0.4 * vnoise(vec2(world_pos.x, z) * 1.7);
	// A dirt shoulder along the kerb.
	col = mix(dirt, col, smoothstep(road_half + 0.3, road_half + 1.1, ax + vnoise(vec2(ax, z) * 2.0) * 0.4));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
