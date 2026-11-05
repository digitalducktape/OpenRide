// Watt Lane's field (ART_BIBLE.md): the abstract dark space the lane runs through, in depth
// layers that move at different speeds so the flat screen reads as deep.
//   - far: a deep night-teal gradient and slow, soft bokeh drifting at a third of the lane's speed;
//   - mid: a fine dot grid at half speed;
//   - near: the watt scale's faint horizontal guides (one every 12.5% of FTP), and a vertical
//     beat line every beat at the lane's own speed, brighter on the bar's first beat, flaring on
//     each beat of the music (`beat`).
// A vignette and a pixel of dither finish it. One full-window rect, opaque.
shader_type canvas_item;

uniform vec3 top_color : source_color = vec3(0.02, 0.05, 0.08);
uniform vec3 bottom_color : source_color = vec3(0.03, 0.09, 0.12);
uniform vec3 grid_color : source_color = vec3(0.35, 0.7, 0.75);
uniform vec3 bokeh_color : source_color = vec3(0.3, 0.6, 0.7);
uniform vec3 warm_color : source_color = vec3(1.0, 0.7, 0.35);
uniform vec2 origin = vec2(-68.0, 0.0);  // the rect's top left, stage px
uniform vec2 rect_size = vec2(2056.0, 1080.0);
uniform float scroll = 0.0;  // px the lane has moved
uniform float beat_px = 80.0;  // px between beat lines
uniform float beat = 0.0;  // 0-1, flares on each beat and decays
uniform float bar_offset = 0.0;  // which beat line starts a bar (0-3)
uniform float guide_top = 400.0;  // the first guide's y
uniform float guide_gap = 110.0;
uniform float lane_mid = 620.0;  // the lane's middle near the cursor: the field warms around it
uniform float warmth = 0.0;  // 0-1: in the lane, the field warms a little around it
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float hash(vec2 c) {
	return texture(noise_tex, (c + 0.5) / 64.0).r;
}

void fragment() {
	vec2 p = origin + UV * rect_size;
	vec3 col = mix(top_color, bottom_color, UV.y);
	// Farthest: two huge soft clouds of colour, teal and copper, drifting very slowly.
	// (Sampled from the noise's lowest mip, so each is a broad, smooth wash, never mottled.)
	vec2 q = vec2(p.x + scroll * 0.08, p.y) / 2400.0;
	float n1 = textureLod(noise_tex, q * 0.25 + vec2(TIME * 0.001, 0.0), 4.0).r;
	float n2 = textureLod(noise_tex, q * 0.2 + vec2(0.37, 0.61) - vec2(TIME * 0.0008, 0.0), 4.0).r;
	col += bokeh_color * smoothstep(0.35, 0.75, n1) * 0.06;
	col += warm_color * smoothstep(0.45, 0.8, n2) * 0.035;
	// Far: a horizon of light behind the top of the scale, and two slow ribbons of light (teal and
	// copper) in the upper field, drifting at a tenth of the lane's speed: depth above the lane,
	// never brighter than it.
	col += bokeh_color * exp(-pow((p.y - 380.0) / 160.0, 2.0)) * 0.06;
	for (int r = 0; r < 2; r++) {
		float fr = float(r);
		float x = (p.x + scroll * (0.08 + 0.05 * fr)) / (420.0 + 140.0 * fr);
		float y0 = 345.0 + 95.0 * fr + 34.0 * sin(x + fr * 2.1 + TIME * 0.07) + 14.0 * sin(x * 2.7 + TIME * 0.11);
		float w = 26.0 + 22.0 * fr;
		float shimmer = 0.65 + 0.35 * texture(noise_tex, vec2(x * 3.0, fr * 9.0 + TIME * 0.02) / 4.0).r;
		col += mix(bokeh_color, warm_color, fr) * exp(-pow((p.y - y0) / w, 2.0)) * (0.09 - 0.03 * fr) * shimmer;
	}
	// Far: soft bokeh discs, one per cell, drifting slowly left.
	vec2 bp = vec2(p.x + scroll * 0.33, p.y) / 180.0;
	vec2 cell = floor(bp);
	vec2 f = fract(bp) - 0.5;
	float h = hash(cell);
	vec2 off = vec2(hash(cell + 7.0), hash(cell + 13.0)) - 0.5;
	float size = mix(0.08, 0.22, hash(cell + 21.0));
	float disc = smoothstep(size, size * 0.4, length(f - off * 0.6)) * step(0.55, h);
	col += bokeh_color * disc * 0.16 * (0.6 + 0.4 * sin(TIME * 0.7 + h * 40.0));
	// Mid: a fine dot grid at half speed.
	vec2 gp = vec2(p.x + scroll * 0.5, p.y) / 36.0;
	float dot = smoothstep(0.12, 0.04, length(fract(gp) - 0.5));
	col += grid_color * dot * 0.05;
	// Near: the watt scale's guides, thin and faint.
	float gy = mod(p.y - guide_top + guide_gap * 0.5, guide_gap) - guide_gap * 0.5;
	float in_scale = step(guide_top - 30.0, p.y) * step(p.y, guide_top + guide_gap * 4.0 + 30.0);
	col += grid_color * (1.0 - smoothstep(0.6, 1.6, abs(gy))) * 0.07 * in_scale;
	// Near: beat lines at the lane's speed, the bar's first one brighter, all flaring on the beat.
	float bx = p.x + scroll;
	float k = floor(bx / beat_px);
	float lx = abs(bx - (k + 0.5) * beat_px) - beat_px * 0.5;
	float bar = step(abs(mod(k - bar_offset, 4.0)), 0.5);
	float line = 1.0 - smoothstep(0.5, 1.8, abs(lx));
	col += grid_color * line * (0.04 + bar * 0.06) * (1.0 + beat * 1.8);
	// Around the lane near the cursor, a faint warm light when riding in it.
	col += warm_color * exp(-pow((p.y - lane_mid) / 260.0, 2.0)) * exp(-abs(p.x - 520.0) / 900.0) * 0.06 * warmth;
	// Vignette, then dither against banding in the long gradient.
	vec2 v = (UV - 0.5) * vec2(1.2, 1.0);
	col *= 1.0 - smoothstep(0.4, 0.95, length(v)) * 0.55;
	col += (texture(noise_tex, FRAGCOORD.xy / 64.0).r - 0.5) / 160.0;
	COLOR = vec4(col, 1.0);
}
