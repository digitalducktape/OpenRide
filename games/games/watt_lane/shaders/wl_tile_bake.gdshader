// Watt Lane's moving texture tile, rendered ONCE into a 512x512 repeating texture
// (WattLaneBackdrop): R the dot grid (32 px), G soft bokeh discs (one per 128 px cell, kept inside
// the cell so the tile wraps), B the lane's long soft streaks of light (whole sine cycles across,
// so it wraps). The per-frame shaders only read it: no noise thresholds per pixel, which is what
// speckled the lane at the tablet's precision.
shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_nearest;

float hash(vec2 c) {
	return texture(noise_tex, (c + 0.5) / 64.0).r;
}

void fragment() {
	vec2 p = UV * 512.0;
	float dots = smoothstep(4.0, 1.5, length(mod(p, 32.0) - 16.0));
	vec2 cell = floor(p / 128.0);
	vec2 f = mod(p, 128.0) - 64.0;
	vec2 off = (vec2(hash(cell + 7.0), hash(cell + 13.0)) - 0.5) * 50.0;
	float size = mix(12.0, 34.0, hash(cell + 21.0));
	float disc = smoothstep(size, size * 0.4, length(f - off)) * step(0.6, hash(cell));
	float streak = 0.0;
	for (int k = 0; k < 10; k++) {
		float fk = float(k);
		float y = 26.0 + fk * 51.0;
		float cycles = 1.0 + floor(hash(vec2(fk, 3.0)) * 3.0);
		float wave = 0.5 + 0.5 * sin(UV.x * 6.28318 * cycles + hash(vec2(fk, 5.0)) * 6.28);
		streak += exp(-pow((p.y - y) / 5.0, 2.0)) * wave * wave;
	}
	COLOR = vec4(dots, disc, clamp(streak, 0.0, 1.0), 1.0);
}
