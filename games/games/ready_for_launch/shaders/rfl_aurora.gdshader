shader_type canvas_item;
render_mode blend_add;

// The polar aurora (#82): slow curtains of green and teal hanging over the ice, additive on one
// rect, fading at every edge. From TIME only.

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float t = TIME * 0.12;
	float fold = noise(UV.x * 6.0 + t) * 0.6 + noise(UV.x * 15.0 - t * 2.0) * 0.4;
	float top = mix(0.08, 0.42, fold);
	float curtain = smoothstep(top, top + 0.12, UV.y) * (1.0 - smoothstep(top + 0.16, 0.98, UV.y));
	float rays = 0.65 + 0.35 * noise(UV.x * 90.0 + t * 8.0);
	vec3 col = mix(vec3(0.2, 1.0, 0.62), vec3(0.34, 0.5, 1.0), smoothstep(0.1, 0.7, 1.0 - UV.y));
	float fade = smoothstep(0.0, 0.1, UV.x) * (1.0 - smoothstep(0.9, 1.0, UV.x));
	COLOR = vec4(col * curtain * rays * fade * 0.34, 1.0);
}
