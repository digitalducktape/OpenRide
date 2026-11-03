shader_type canvas_item;

// Keepy Uppy's falling streaks (#77; ART_BIBLE §7), alpha blended on one rect: the rain under the
// rain cloud, and the downdraft's curtain of dark, slanting air that sweeps in from the right on its
// warning and passes over the column. `amount` fades it, `reach` (0-1 across the rect) is where
// the curtain's leading edge is (1 covers it all), and the rest set its look. From TIME only.

uniform float amount = 0.0;
uniform float reach = 1.0;
uniform float soft_edge = 0.12;  // the leading edge's width, as a share of the rect
uniform vec4 tint : source_color = vec4(0.78, 0.84, 0.92, 1.0);
uniform float fall = 1.6;  // rect heights a second
uniform float columns = 70.0;
uniform float slant = 0.0;  // streaks lean this far across over the rect's height
uniform float density = 0.6;  // 0-1: the share of columns with a streak
uniform float opacity = 0.5;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float sx = UV.x + UV.y * slant;
	float cx = floor(sx * columns);
	float h = hash(cx);
	float y = fract(UV.y * 1.3 - TIME * fall * (0.7 + 0.6 * h) + h * 11.0);
	float streak = smoothstep(0.0, 0.05, y) * (1.0 - smoothstep(0.05, 0.3, y));
	streak *= 1.0 - smoothstep(0.1, 0.35, abs(fract(sx * columns) - 0.5));
	streak *= step(1.0 - density, h);
	// The curtain's leading edge comes in from the right: covered where UV.x > 1 - reach.
	float covered = smoothstep(1.0 - reach - soft_edge, 1.0 - reach, UV.x);
	float fade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	COLOR = vec4(tint.rgb, (streak + 0.12) * covered * fade * amount * opacity);
}
