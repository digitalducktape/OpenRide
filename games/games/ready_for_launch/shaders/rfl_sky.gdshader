shader_type canvas_item;

// Ready for Launch's sky (#82; ART_BIBLE §7): one opaque rect, a two-colour gradient the climb
// sets, with faint vertical rush lines in the air at speed. From TIME and three uniforms.

uniform vec4 top_col : source_color = vec4(0.1, 0.2, 0.5, 1.0);
uniform vec4 low_col : source_color = vec4(0.1, 0.2, 0.5, 1.0);
uniform float rush = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec3 col = mix(top_col.rgb, low_col.rgb, UV.y * UV.y);
	if (rush > 0.01) {
		float cx = floor(UV.x * 90.0);
		float h = hash(cx);
		float y = fract(UV.y * 0.7 - TIME * (1.2 + h * 1.6) + h * 7.0);
		float streak = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(0.03, 0.26, y));
		streak *= step(0.72, h) * (1.0 - smoothstep(0.06, 0.3, abs(fract(UV.x * 90.0) - 0.5)));
		col += vec3(0.9, 0.95, 1.0) * streak * 0.11 * rush;
	}
	COLOR = vec4(col, 1.0);
}
