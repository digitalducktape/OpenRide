shader_type canvas_item;

// The storm's rain (#81): thin slanting dashes falling on one rect, only while a storm is on.
// `amount` fades it in and out; `fall` is advanced by GridStage so it pauses with the game.

uniform float amount = 0.0;
uniform float fall = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * vec2(90.0, 12.0);
	p.x += p.y * 0.55;
	float col = floor(p.x);
	float y = p.y - fall * (0.8 + hash(vec2(col, 2.0)) * 0.5) + hash(vec2(col, 1.0)) * 9.0;
	float cell = fract(y);
	float show = step(0.62, hash(vec2(col, floor(y))));
	float across = 1.0 - abs(fract(p.x) - 0.5) * 2.0;
	float a = show * smoothstep(0.0, 0.2, cell) * smoothstep(0.62, 0.3, cell) * smoothstep(0.78, 1.0, across);
	COLOR = vec4(0.72, 0.8, 0.98, a * amount * 0.34 * smoothstep(0.0, 0.1, UV.y));
}
