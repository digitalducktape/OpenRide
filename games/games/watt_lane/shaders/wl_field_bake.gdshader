// Watt Lane's field, the layers that never move: the night-teal gradient, the far washes of
// colour, the horizon of light, the two ribbons, the watt scale's guides, the vignette and the
// dither. Rendered ONCE into a texture (WattLaneBackdrop), never per frame: the tablet is
// fill-bound, and all this per pixel per frame held it at 31 fps.
shader_type canvas_item;

uniform vec3 top_color : source_color = vec3(0.02, 0.05, 0.08);
uniform vec3 bottom_color : source_color = vec3(0.03, 0.09, 0.12);
uniform vec3 grid_color : source_color = vec3(0.35, 0.7, 0.75);
uniform vec3 bokeh_color : source_color = vec3(0.3, 0.6, 0.7);
uniform vec3 warm_color : source_color = vec3(1.0, 0.7, 0.35);
uniform vec2 origin = vec2(-68.0, 0.0);  // the rect's top left, stage px
uniform vec2 rect_size = vec2(2056.0, 1080.0);
uniform float guide_top = 400.0;
uniform float guide_gap = 110.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	vec2 p = origin + UV * rect_size;
	vec3 col = mix(top_color, bottom_color, UV.y);
	// Farthest: two huge soft washes of colour (from the noise's low mip: broad, never mottled).
	vec2 q = p / 2400.0;
	float n1 = textureLod(noise_tex, q * 0.25, 4.0).r;
	float n2 = textureLod(noise_tex, q * 0.2 + vec2(0.37, 0.61), 4.0).r;
	col += bokeh_color * smoothstep(0.35, 0.75, n1) * 0.06;
	col += warm_color * smoothstep(0.45, 0.8, n2) * 0.035;
	// A horizon of light behind the top of the scale, and two ribbons of light above the lane.
	col += bokeh_color * exp(-pow((p.y - 380.0) / 160.0, 2.0)) * 0.06;
	for (int r = 0; r < 2; r++) {
		float fr = float(r);
		float x = p.x / (420.0 + 140.0 * fr);
		float y0 = 345.0 + 95.0 * fr + 34.0 * sin(x + fr * 2.1) + 14.0 * sin(x * 2.7);
		float w = 26.0 + 22.0 * fr;
		col += mix(bokeh_color, warm_color, fr) * exp(-pow((p.y - y0) / w, 2.0)) * (0.08 - 0.03 * fr);
	}
	// The watt scale's guides, thin and faint.
	float gy = mod(p.y - guide_top + guide_gap * 0.5, guide_gap) - guide_gap * 0.5;
	float in_scale = step(guide_top - 30.0, p.y) * step(p.y, guide_top + guide_gap * 4.0 + 30.0);
	col += grid_color * (1.0 - smoothstep(0.6, 1.6, abs(gy))) * 0.07 * in_scale;
	// The vignette, then dither against banding in the long gradient.
	vec2 v = (UV - 0.5) * vec2(1.2, 1.0);
	col *= 1.0 - smoothstep(0.4, 0.95, length(v)) * 0.55;
	col += (texture(noise_tex, FRAGCOORD.xy / 64.0).r - 0.5) / 160.0;
	COLOR = vec4(col, 1.0);
}
