shader_type canvas_item;

// Ready for Launch's smoke column (#82; ART_BIBLE §3): the exhaust trail in the air, alpha blended
// on one rect from under the flame to the bottom of the screen. It gets WIDER going down and runs
// off the frame, so the rocket never trails a tapering tail. Lumps scroll down with the climb.

uniform float amount = 0.0;  // 0-1
uniform vec4 lit : source_color = vec4(1.0, 0.95, 0.9, 1.0);
uniform vec4 shade : source_color = vec4(0.6, 0.55, 0.6, 1.0);
uniform float scroll = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float y = UV.y;  // 0 at the top, by the flame
	float half_w = mix(0.2, 0.5, pow(y, 0.7));
	float x = (UV.x - 0.5) / half_w;
	vec2 q = vec2(x * 2.4, y * 7.0 - scroll);
	float lump = noise(q) * 0.65 + noise(q * 2.3) * 0.35;
	float edge = 1.0 - smoothstep(0.55 + lump * 0.3, 1.0, abs(x));
	float top = smoothstep(0.0, 0.1, y);
	float a = edge * top * smoothstep(0.2, 0.5, lump + 0.25) * amount;
	vec3 col = mix(shade.rgb, lit.rgb, clamp(0.5 + x * 0.6 + lump * 0.4, 0.0, 1.0));
	COLOR = vec4(col, a * 0.9);
}
