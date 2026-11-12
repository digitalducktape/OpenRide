// Watt Lane's field per frame (ART_BIBLE.md): the baked static layers, the baked tile (dot grid and
// bokeh) drifting at 0.4 of the lane's speed, and the beat lines at the lane's own speed, flaring
// on the beat. Two texture reads and a few sums a pixel; every coordinate is worked out per vertex
// in highp and the scroll wraps on the CPU, so nothing loses precision on the tablet. Opaque.
shader_type canvas_item;

uniform sampler2D static_tex : filter_linear;
uniform sampler2D tile_tex : repeat_enable, filter_linear;
uniform vec3 grid_color : source_color = vec3(0.35, 0.7, 0.75);
uniform vec3 bokeh_color : source_color = vec3(0.3, 0.6, 0.7);
uniform vec2 rect_size = vec2(2056.0, 1080.0);
uniform float tile_scroll = 0.0;  // px, wrapped to the tile
uniform float bar_scroll = 0.0;  // px, wrapped to a bar
uniform float beat_px = 80.0;
uniform float beat = 0.0;  // 0-1, flares on each beat

varying highp vec2 tile_uv;
varying highp float beats;  // 0-4 across a bar, repeating

void vertex() {
	vec2 p = UV * rect_size;
	tile_uv = vec2(p.x + tile_scroll, p.y) / 512.0;
	beats = (p.x + bar_scroll) / beat_px;
}

void fragment() {
	vec3 col = texture(static_tex, UV).rgb;
	vec3 t = texture(tile_tex, tile_uv).rgb;
	col += grid_color * t.r * 0.05 + bokeh_color * t.g * 0.13;
	float k = fract(beats * 0.25) * 4.0;  // 0-4 through the bar
	float px = abs(fract(k + 0.5) - 0.5) * beat_px;  // px to the nearest beat line
	float bar = 1.0 - step(0.5, min(k, 4.0 - k));  // the bar's first line
	float line = 1.0 - smoothstep(0.5, 1.8, px);
	col += grid_color * line * (0.04 + bar * 0.06) * (1.0 + beat * 1.8);
	COLOR = vec4(col, 1.0);
}
