shader_type canvas_item;
render_mode blend_add;

// Keepy Uppy's seaside (#77): the sun's glitter on the sea, sparkling along the sun's path and
// thinning away from it, with slow swell lines. Additive on one rect over the painted sea band;
// from TIME, never a redraw.

uniform float sun_x = 0.75;  // the sun's path across the rect (0-1)
uniform vec4 sun_col : source_color = vec4(1.0, 0.9, 0.65, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// Depth into the sea band: 0 at the horizon, 1 at its foot; glints grow toward the shore.
	float d = uv.y;
	vec2 cell = vec2(floor(uv.x * mix(240.0, 90.0, d)), floor(uv.y * mix(40.0, 14.0, d)));
	float h = hash(cell);
	float blink = 0.5 + 0.5 * sin(TIME * (2.0 + 4.0 * h) + h * 40.0);
	float path = exp(-pow((uv.x - sun_x) * mix(9.0, 4.0, d), 2.0));
	float glint = step(0.82, h) * smoothstep(0.75, 1.0, blink) * (0.25 + 0.75 * path);
	float swell = 0.5 + 0.5 * sin(uv.x * 40.0 + TIME * 0.6 + d * 20.0);
	float lines = smoothstep(0.96, 1.0, swell) * 0.06 * (1.0 - d * 0.5);
	float fade = smoothstep(0.0, 0.06, d) * (1.0 - smoothstep(0.85, 1.0, d));
	COLOR = vec4(sun_col.rgb * (glint * 0.85 + lines + path * 0.05) * fade, 1.0);
}
