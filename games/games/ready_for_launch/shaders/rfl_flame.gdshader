shader_type canvas_item;
render_mode blend_add;

// Ready for Launch's exhaust (#82; ART_BIBLE §3 and §7): a wide flat curtain of separate tongues
// with a ragged foot and shock bands, one per engine. Never a teardrop: the outline stays as wide
// at the foot as at the nozzle, and each tongue ends blunt. In vacuum (`space`) it is shorter,
// bluer and fans out. From TIME and three uniforms.

uniform float power = 1.0;  // 0-1.3
uniform float space = 0.0;  // 0 in air, 1 in vacuum
uniform float tongues = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float y = UV.y;  // 0 at the nozzle, 1 at the foot
	float x = (UV.x - 0.5) * 2.0;
	float widen = mix(0.62, 0.98, y);
	float xc = x / widen;
	float tn = max(tongues, 1.0);
	float lane = fract((xc * 0.5 + 0.5) * tn);
	float idx = floor((xc * 0.5 + 0.5) * tn);
	float ragged = 0.8 + 0.2 * noise(idx * 5.0 + TIME * 11.0);
	float foot = 1.0 - smoothstep(ragged - 0.1, ragged, y);
	float core = 1.0 - smoothstep(0.1, 0.5, abs(lane - 0.5));
	float side = 1.0 - smoothstep(0.84, 1.0, abs(xc));
	float flicker = 0.85 + 0.15 * noise(TIME * 23.0 + idx * 3.0);
	float bands = 0.5 + 0.5 * sin(y * 26.0 - TIME * 16.0);
	bands = smoothstep(0.62, 0.95, bands) * (1.0 - y) * (1.0 - space);
	vec3 hot = vec3(1.0, 0.96, 0.82);
	vec3 warm = mix(vec3(1.0, 0.62, 0.2), vec3(0.55, 0.75, 1.0), space);
	vec3 cool = mix(vec3(0.95, 0.25, 0.08), vec3(0.3, 0.45, 1.0), space);
	vec3 col = mix(hot, warm, smoothstep(0.05, 0.45, y));
	col = mix(col, cool, smoothstep(0.45, 0.95, y));
	float body = (0.34 + 0.66 * core) * side * foot;
	float a = clamp(body * flicker + bands * core * 0.5 * foot, 0.0, 1.0) * clamp(power * 1.4, 0.0, 1.0);
	COLOR = vec4(col * a, 1.0);
}
