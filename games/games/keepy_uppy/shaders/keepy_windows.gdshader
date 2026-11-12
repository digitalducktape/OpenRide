shader_type canvas_item;
render_mode blend_add;

// Keepy Uppy's rooftop (#77): far windows lighting up and going dark as the city settles into
// the evening, a few at a time. Small warm squares on a grid, each on its own slow clock, added
// over the baked towers' lower half; from TIME, never a redraw.

uniform vec4 warm : source_color = vec4(1.0, 0.8, 0.48, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = UV * vec2(2240.0, 150.0);
	vec2 cell = floor(px / vec2(24.0, 30.0));
	vec2 in_cell = fract(px / vec2(24.0, 30.0));
	float h = hash(cell);
	float on = step(0.86, fract(h * 7.0 + TIME * (0.02 + 0.03 * h)));
	float pane = step(0.25, in_cell.x) * step(in_cell.x, 0.75) * step(0.2, in_cell.y) * step(in_cell.y, 0.75);
	COLOR = vec4(warm.rgb * on * pane * 0.55 * step(0.5, h), 1.0);
}
