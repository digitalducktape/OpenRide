// Dodge Ball's road: asphalt grain, lane lines and kerbs, scrolled by `scroll` (metres
// travelled, wrapped at 450 m, a multiple of every pattern period) so one static plane reads
// as an endless road. At night the bike's headlight and the street lamps light pools on it
// as added light, so no real lights are needed (each one is an extra pass in Compatibility).
shader_type spatial;
render_mode unshaded, fog_disabled;

// Lit and fogged by hand (unshaded, fog_disabled): these two planes cover most of the screen,
// and the engine's per-pixel light and fog cost the tablet about a third of its frame time.
// DodgeWorld sets them from the time of day.
uniform vec3 light_color = vec3(1.0);
uniform vec3 fog_color : source_color = vec3(0.7, 0.8, 0.9);
uniform float fog_density = 0.006;


uniform float scroll = 0.0;
uniform float road_half = 6.0;
uniform vec3 asphalt : source_color = vec3(0.16, 0.16, 0.18);
uniform vec3 line_color : source_color = vec3(0.95, 0.93, 0.85);
uniform vec3 kerb_a : source_color = vec3(0.85, 0.2, 0.18);
uniform vec3 kerb_b : source_color = vec3(0.92, 0.92, 0.92);
uniform float rider_x = 0.0;
uniform float headlight = 0.0;  // 0 by day, 1 at night
uniform float lamp_glow = 0.0;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float lamp_side_x = 7.0;
uniform float lamp_spacing = 25.0;
uniform float lamp_phase = 0.0;  // where the left lamps sit along the period
uniform float pulse = 0.0;  // streak pulse on the lines, 0-1

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
	float x = world_pos.x;
	// Road-space z: fixed to the road surface as it moves past.
	float z = world_pos.z - scroll;
	float ax = abs(x);
	float fw = 0.03;
	vec3 col = asphalt * (0.85 + 0.3 * vnoise(vec2(x, z) * 3.0)) * (0.92 + 0.16 * vnoise(vec2(x * 0.3, z * 0.05)));
	// Tyre-worn bands, a touch lighter.
	col *= 1.0 + 0.06 * smoothstep(1.4, 0.6, abs(ax - 3.0));
	// Centre dashes: 3 m on, 6 m off. Edge lines: solid.
	float dash = step(fract(z / 9.0), 0.333);
	float centre = smoothstep(0.08 + fw, 0.08, ax) * dash;
	float edge = smoothstep(0.07 + fw, 0.07, abs(ax - (road_half - 0.45)));
	vec3 lines = line_color * (1.0 + pulse * 0.8);
	col = mix(col, lines, max(centre, edge));
	// Kerbs: alternating 1 m blocks.
	float kerb = step(road_half - 0.25, ax);
	vec3 kc = mix(kerb_a, kerb_b, step(0.5, fract(z / 2.0)));
	col = mix(col, kc, kerb);

	// Night lighting, added on top.
	vec3 glow = vec3(0.0);
	if (headlight > 0.0) {
		float d = length(vec2((x - rider_x) * 1.6, (world_pos.z + 9.0) * 0.18));
		glow += vec3(0.95, 0.95, 0.85) * headlight * 0.5 * exp(-d * d * 0.9) * col * 1.8;
	}
	if (lamp_glow > 0.0) {
		float zl = mod(z - lamp_phase, lamp_spacing);
		float zr = mod(z - lamp_phase - lamp_spacing * 0.5, lamp_spacing);
		zl = min(zl, lamp_spacing - zl);
		zr = min(zr, lamp_spacing - zr);
		float l = exp(-(pow(x + lamp_side_x - 2.2, 2.0) * 0.12 + zl * zl * 0.035));
		float r = exp(-(pow(x - lamp_side_x + 2.2, 2.0) * 0.12 + zr * zr * 0.035));
		glow += lamp_color * lamp_glow * (l + r) * (col * 2.5 + 0.04);
	}
	vec3 lit = col * light_color + glow;
	float fog = 1.0 - exp(-fog_density * length(VERTEX));
	ALBEDO = mix(lit, fog_color, fog);
}
