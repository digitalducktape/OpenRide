// Watt Lane's lane (ART_BIBLE.md): an illuminated band, drawn as a strip mesh that covers only the
// lane and its glow (WattLaneTrack.lane_mesh). All the light is worked out per VERTEX, from arrays
// WattLaneTrack fills each frame: the wide glow, the lit body, the crisp edges pulsing on the beat
// and the dimming behind the cursor, with rows packed tight around the edges so they stay crisp.
// The fragment shader is one texture read (the long soft streaks) and an add: per-pixel array
// indexing and exp over two thirds of the screen held the tablet at 31 fps.
//
// A vertex is VERTEX = (column, row); UV = (t, off): its y is mix(hi, lo, t) + off px.
// Premultiplied alpha: light adds, the edges cover.
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float band_lo[64];  // the band's lower edge (larger y) per column, stage px
uniform float band_hi[64];  // its upper edge
uniform float col_x0 = -68.0;
uniform float col_dx = 33.0;
uniform float view_x0 = -68.0;  // the window's left and right edges, stage px
uniform float view_x1 = 1988.0;
uniform float rider_x = 520.0;
uniform float glow = 1.0;  // 1 in the lane, lower out, up to 2 in a catch's flash
uniform float beat = 0.0;  // 0-1, flares on the beat
uniform float streak_scroll = 0.0;  // px, wrapped to the tile
uniform vec3 band_color : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 edge_color : source_color = vec3(1.0, 0.93, 0.75);
uniform sampler2D tile_tex : repeat_enable, filter_linear;

varying vec4 light;  // premultiplied colour and cover
varying float streak_amount;
varying highp vec2 streak_uv;

void vertex() {
	int i = int(VERTEX.x + 0.5);
	float x = col_x0 + float(i) * col_dx;
	float hi = band_hi[i];
	float lo = band_lo[i];
	float y = mix(hi, lo, UV.x) + UV.y;
	float mid = (hi + lo) * 0.5;
	float half_h = max((lo - hi) * 0.5, 1.0);
	float past = 1.0 - smoothstep(rider_x - 30.0, rider_x + 30.0, x);
	float fade = smoothstep(view_x0, view_x0 + 140.0, x) * (1.0 - smoothstep(view_x1 - 260.0, view_x1, x));
	float strength = mix(1.0, 0.4, past) * glow * fade;
	float dist = max(abs(y - mid) - half_h, 0.0);
	float inside = 1.0 - step(0.5, dist);
	float across = clamp(abs(y - mid) / half_h, 0.0, 1.0);
	float sheen = 1.0 - across * across;
	float tube = 0.06 + 0.16 * (1.0 - sheen) * (1.0 - sheen) + 0.05 * sheen;
	float edge = min(abs(y - hi), abs(y - lo));
	float pulse = 1.0 + beat * 0.6;
	vec3 pm = band_color * (exp(-dist * 0.035) * 0.16 + inside * tube) * strength;
	float a = inside * 0.03 * fade;
	float core = (1.0 - smoothstep(1.2, 2.6, edge)) * min(strength, 1.0);
	pm = mix(pm, edge_color * pulse, core);
	a = mix(a, 1.0, core);
	pm += edge_color * exp(-edge * 0.22) * 0.35 * strength * pulse;
	light = vec4(pm, a);
	streak_amount = inside * (1.0 - core) * strength * 0.16;
	streak_uv = vec2(x + streak_scroll, y) / 512.0;
	VERTEX = vec2(x, y);
}

void fragment() {
	float s = texture(tile_tex, streak_uv).b;
	COLOR = vec4(light.rgb + band_color * s * streak_amount, light.a);
}
