shader_type canvas_item;
render_mode blend_add;

// Keepy Uppy's column of air (#77; ART_BIBLE §7): soft white streaks rising from the fan's grille,
// widening as they climb, faster and brighter with the lift, turning downward in a downdraft.
// Additive and faint (the art director's note: under about 0.25 at full lift, so the balloon and
// its birds read through it). One rect, from TIME and two uniforms; never a redraw.

uniform float strength = 0.5;  // 0-1: how much air the fan moves
uniform float speed = 1.0;  // the streaks' climb, in rect heights a second (negative: falling)

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	// UV.y is 0 at the top of the rect, 1 at the grille. The column widens upward.
	float up = 1.0 - UV.y;
	float half_w = mix(0.24, 0.44, up);
	float x = (UV.x - 0.5) / half_w;  // -1..1 across the column at this height
	float edge = 1.0 - smoothstep(0.7, 1.0, abs(x));
	float cols = 15.0;
	float cx = floor((x * 0.5 + 0.5) * cols);
	float h = hash(cx + 3.0);
	float y = fract(up * (1.2 + h * 0.8) - TIME * speed * (0.5 + 0.5 * h) + h * 9.0);
	float streak = smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.08, 0.38, y));
	float lane = 1.0 - smoothstep(0.08, 0.36, abs(fract((x * 0.5 + 0.5) * cols) - 0.5));
	float fade = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y) * 0.6);
	float body = (1.0 - smoothstep(0.0, 1.0, abs(x))) * fade * (0.025 + 0.015 * up);
	float a = (streak * lane * 0.2 + body) * edge * fade * strength;
	COLOR = vec4(vec3(1.0, 1.0, 0.97) * a, 1.0);
}
