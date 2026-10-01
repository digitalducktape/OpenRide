// Dodge Ball's sky: a horizon gradient, a sun (or moon) disc with a soft halo, hazy cloud
// bands and stars at night. No TIME, so the sky's radiance is only rebuilt when the time of
// day changes.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.25, 0.5, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_color : source_color = vec3(0.3, 0.32, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.03;
uniform float halo = 0.4;
uniform float stars = 0.0;
uniform float clouds = 0.5;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 0.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 0.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	// Sun and halo.
	float s = dot(dir, LIGHT0_DIRECTION);
	col += sun_color * halo * pow(max(s, 0.0), 8.0) * 0.6;
	col += sun_color * 0.25 * halo * pow(max(s, 0.0), 2.0) * smoothstep(0.35, 0.0, h);
	col = mix(col, sun_color * 1.6, smoothstep(1.0 - sun_size * 0.6, 1.0 - sun_size * 0.5, s));
	// Hazy cloud bands above the horizon.
	if (h > 0.0 && clouds > 0.0) {
		vec2 uv = dir.xz / (h + 0.18);
		float n = vnoise(uv * 1.3) * 0.6 + vnoise(uv * 3.1) * 0.3 + vnoise(uv * 7.0) * 0.1;
		float c = smoothstep(0.5, 0.8, n) * smoothstep(0.0, 0.15, h) * clouds;
		col = mix(col, cloud_color, c * 0.8);
	}
	// Stars.
	if (stars > 0.0 && h > 0.0) {
		vec3 cell = floor(dir * 180.0);
		float r = hash(cell);
		float star = step(0.9975, r) * smoothstep(0.02, 0.25, h);
		col += vec3(0.9, 0.92, 1.0) * star * stars * (0.5 + 0.5 * hash(cell + 3.1));
	}
	COLOR = col;
}
