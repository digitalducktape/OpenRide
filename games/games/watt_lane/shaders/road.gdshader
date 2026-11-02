// Watt Lane's road and the ground around it (ART_BIBLE.md §6): wet dark asphalt with the watt
// scale painted on it (a dashed line every 25% of FTP, solid edges), the lane's faint fill and its
// rails' glow on the wet surface, amber chevrons leading into an announced jump, the rider's
// headlight beam and the street lamps' pools. One plane, everything in this shader: the road
// scrolls (`scroll`, metres), the lane comes from `offsets` (wl_look.gdshaderinc). Opaque.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/watt_lane/shaders/wl_look.gdshaderinc"

uniform float scroll = 0.0;
uniform float road_half = 10.2;  // the road's edges, x = ±this (15% and 100% of FTP)
uniform vec4 scale_lines = vec4(-7.8, -1.8, 4.2, 99.0);  // the dashed lines' x: 25, 50, 75% of FTP
uniform vec3 asphalt : source_color = vec3(0.043, 0.07, 0.086);
uniform vec3 ground : source_color = vec3(0.03, 0.045, 0.05);
uniform vec3 beam_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 sodium : source_color = vec3(1.0, 0.54, 0.24);
uniform float bike_x = 0.0;
uniform float beam_warn = 0.0;  // 0-1: the beam's tip turns amber while out of the lane
uniform float jump_d = -100.0;  // metres ahead to the announced jump's bend (< 0: none)
uniform float jump_dir = 1.0;  // +1: the lane jumps right (up), -1 left (down)
uniform float chevrons = 0.0;  // 0-1, pulsing with the countdown
uniform float lamp_spacing = 40.0;
uniform float lamp_x = 12.0;
uniform float trail = 0.0;  // 1 in the showcase view: the bike's light trail on the road behind it

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A line `w` metres wide at x = `at`, antialiased.
float stripe(float x, float at, float w, float fw) {
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, abs(x - at));
}

void fragment() {
	float x = world.x;
	float d = -world.z;
	float s = d + scroll;
	float fw = max(fwidth(x), 0.002);
	float grain = vnoise(vec2(x * 3.0, s * 3.0));
	bool on_road = abs(x) < road_half + 0.6;
	vec3 col = on_road ? asphalt * (0.8 + 0.4 * grain) : ground * (0.7 + 0.6 * vnoise(vec2(x * 0.4, s * 0.4)));
	// The painted watt scale: dashed lines inside, solid edges.
	float dash = step(fract(s / 12.0), 0.45);
	float paint = 0.0;
	for (int k = 0; k < 3; k++) {
		paint = max(paint, stripe(x, scale_lines[k], 0.14, fw) * dash);
	}
	paint = max(paint, stripe(abs(x), road_half, 0.2, fw));
	col = mix(col, vec3(0.62, 0.66, 0.66), paint * 0.42 * smoothstep(160.0, 20.0, d));
	// The lane: a faint fill, and the rails' glow on the wet asphalt (a soft streak each side).
	float lx = lane_x(d);
	float off = x - lx;
	float u = off / half_w;
	float inside = 1.0 - smoothstep(0.96, 1.0, abs(u));
	float edge = abs(abs(off) - half_w);
	float sheen = 0.7 + 0.6 * vnoise(vec2(x * 5.0, s * 0.35));
	col += lane_color * (inside * 0.05 + exp(-edge * 2.6) * 0.32 * sheen) * glow;
	// Chevrons into the bend, pointing the way the lane goes.
	if (jump_d > 0.0 && d > jump_d - 34.0 && d < jump_d - 1.0) {
		float zl = (fract(s / 6.0) - 0.5) * 6.0;
		float px = off * jump_dir;
		float v = px * 0.9 + abs(zl) * 1.1;
		float stroke = 1.0 - smoothstep(0.32 - fw * 2.0, 0.32 + fw * 2.0, abs(v));
		stroke *= 1.0 - smoothstep(half_w * 0.7, half_w * 0.85, abs(px));
		float fade = smoothstep(jump_d - 34.0, jump_d - 26.0, d) * smoothstep(jump_d - 1.0, jump_d - 5.0, d);
		col = mix(col, warn_color * 1.2, stroke * fade * chevrons);
	}
	// The headlight beam: the rider's line straight ahead, warm white, amber at the tip when out.
	float bw = 0.45 + d * 0.035;
	float beam = exp(-pow((x - bike_x) / bw, 2.0)) * smoothstep(1.0, 3.0, d) * smoothstep(34.0, 8.0, d);
	vec3 bc = mix(beam_color, warn_color, beam_warn * smoothstep(8.0, 26.0, d));
	col += bc * beam * 0.42 * (0.85 + 0.3 * grain);
	// The bike's light trail behind it (the showcase view only).
	float tr = exp(-pow((x - bike_x) / 0.22, 2.0)) * step(d, -0.2) * smoothstep(-9.0, -0.4, d);
	col += mix(beam_color, lane_color, 0.35) * tr * 1.4 * trail;
	// Sodium pools under the lamp posts on both shoulders.
	float lz = (fract(s / lamp_spacing) - 0.5) * lamp_spacing;
	float pool = exp(-(pow(abs(x) - lamp_x + 1.5, 2.0) * 0.18 + lz * lz * 0.04));
	col += sodium * pool * 0.16;
	ALBEDO = grade(haze(col, d), SCREEN_UV);
}
