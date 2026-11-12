// The path the cursor rode (ART_BIBLE.md): a thin dashed ribbon behind it, fading as it recedes.
// A small strip mesh (WattLaneTrack.path_mesh): VERTEX = (column, side), the height from `trail`
// per vertex. Premultiplied alpha.
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float trail[64];  // the path's y per column, < 0 where there is none
uniform float col_x0 = -68.0;
uniform float col_dx = 33.0;
uniform float view_x0 = -68.0;
uniform float rider_x = 520.0;
uniform float dash_scroll = 0.0;  // px, wrapped to a dash
uniform vec3 path_color : source_color = vec3(0.75, 0.9, 1.0);

varying float cover;
varying highp float dash;

void vertex() {
	int i = int(VERTEX.x + 0.5);
	float x = min(col_x0 + float(i) * col_dx, rider_x - 34.0);
	float y = trail[i];
	float next = trail[min(i + 1, 63)];
	float slope = next < 0.0 || y < 0.0 ? 0.0 : (next - y) / col_dx;
	cover = y < 0.0 ? 0.0 : smoothstep(view_x0 + 60.0, rider_x, x) * 0.85;
	dash = (x + dash_scroll) / 26.0;
	VERTEX = vec2(x, y + VERTEX.y * 2.5 * sqrt(1.0 + slope * slope));
}

void fragment() {
	float c = cover * step(fract(dash), 0.55);
	COLOR = vec4(path_color * c, c);
}
