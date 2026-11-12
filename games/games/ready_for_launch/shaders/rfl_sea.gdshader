shader_type canvas_item;
render_mode blend_add;

// The dawn sea (#82): the low sun's glitter along its path, with slow swell lines. Additive on one
// rect over the painted sea; from TIME, never a redraw.

uniform float sun_x = 0.75;
uniform vec4 sun_col : source_color = vec4(1.0, 0.85, 0.6, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float d = UV.y;
	vec2 cell = vec2(floor(UV.x * mix(260.0, 110.0, d)), floor(UV.y * mix(26.0, 12.0, d)));
	float h = hash(cell);
	float blink = 0.5 + 0.5 * sin(TIME * (2.0 + 4.0 * h) + h * 40.0);
	float path = exp(-pow((UV.x - sun_x) * mix(10.0, 5.0, d), 2.0));
	float glint = step(0.8, h) * smoothstep(0.72, 1.0, blink) * (0.14 + 0.86 * path);
	float swell = 0.5 + 0.5 * sin(UV.x * 44.0 + TIME * 0.6 + d * 18.0);
	float lines = smoothstep(0.96, 1.0, swell) * 0.05;
	float fade = smoothstep(0.0, 0.12, d) * (1.0 - smoothstep(0.7, 1.0, d));
	COLOR = vec4(sun_col.rgb * (glint * 0.9 + lines + path * 0.06) * fade, 1.0);
}
