// Watt Lane's two light rails (ART_BIBLE.md §3): one strip mesh (WattLaneWorld.rails_mesh) bent
// in the vertex shader to the lane's future course (`offsets`), so a jump shows as an S-bend
// ahead. Each rail is a low fence of light (UV2.x = 0; UV.y 0 at the road to 1 at its top) over a
// white-hot core on the road (UV2.x = 1; UV2.y -1..1 across it). UV.x is the side, -1 or +1.
// Additive, so it costs nothing where it isn't.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, cull_disabled, depth_draw_never;

#define WL_ADDITIVE
#include "res://games/watt_lane/shaders/wl_look.gdshaderinc"

uniform float flash = 0.0;  // 0-1, the "caught it" flash

varying float dist;
varying float part;

void vertex() {
	float d = -VERTEX.z;
	VERTEX.x += lane_x(d) + UV.x * half_w;
	dist = d;
	part = UV2.x;
}

void fragment() {
	float fw = max(fwidth(UV.y), 1e-3);
	vec3 c;
	if (part < 0.5) {
		float h = UV.y;
		float base = 1.0 - smoothstep(0.0, 0.12 + fw, h);
		c = lane_color * pow(1.0 - h, 2.2) * 0.75 + core_color * base * 0.9;
	} else {
		float a = abs(UV2.y);
		c = core_color * (1.0 - smoothstep(0.35, 1.0, a)) * 1.4 + lane_color * 0.3;
	}
	c *= glow;
	c = mix(c, core_color * 1.6, flash * 0.6);
	// Nearest the rider the fence passes the camera's side: fade it in so it never fills the edge.
	c *= smoothstep(1.5, 6.0, dist);
	ALBEDO = grade(haze(c, dist), SCREEN_UV);
}
