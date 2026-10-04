// The grass verges either side of the road: mown stripes and noise, scrolled with the road.
shader_type spatial;
render_mode unshaded, fog_disabled;

// Lit and fogged by hand (unshaded, fog_disabled): these two planes cover most of the screen,
// and the engine's per-pixel light and fog cost the tablet about a third of its frame time.
// DodgeWorld sets them from the time of day.
uniform vec3 light_color = vec3(1.0);
uniform vec3 fog_color : source_color = vec3(0.7, 0.8, 0.9);
uniform float fog_density = 0.006;


uniform float scroll = 0.0;
uniform vec3 grass_a : source_color = vec3(0.24, 0.45, 0.18);
uniform vec3 grass_b : source_color = vec3(0.3, 0.52, 0.2);
uniform vec3 dirt : source_color = vec3(0.42, 0.36, 0.26);
uniform float road_half = 6.0;

varying vec3 world_pos;

// Value noise from a 64x64 random texture, filtered by the GPU: far cheaper on the tablet's
// PowerVR than hashing with sin() per pixel. One unit of `p` is one texel.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float vnoise(vec2 p) {
	return texture(noise_tex, p / 64.0).r;
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
	float fog = 1.0 - exp(-fog_density * length(VERTEX));
	ALBEDO = mix(col * light_color * 0.85, fog_color, fog);
}
