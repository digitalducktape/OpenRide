// Watt Lane's grade (ART_BIBLE.md §4) on the shared world look
// (framework/shaders/world_look.gdshaderinc), and the lane every world shader reads.
//
// The lane: `offsets[i]` is the lane centre's x (metres) at `i * row_len` metres ahead of the
// rider, i = 0..63 (WattLaneWorld fills it from the course each frame, so the rails bend where
// the course will jump). `half_w` is the lane's half-width in metres.
//
// Two flavours, as Cadence's: opaque surfaces get the full grade; additive layers (define
// WL_ADDITIVE first) only its linear parts, so stacked light adds up.

#define LOOK_SAT 1.08
#ifndef WL_ADDITIVE
#define LOOK_CONTRAST 1.06
#define LOOK_LIFT vec3(0.0, 0.012, 0.016)
#endif
#define LOOK_VIGNETTE 0.4
#define LOOK_VIGNETTE_TINT vec3(0.75, 0.95, 1.0)

#include "res://framework/shaders/world_look.gdshaderinc"

uniform float offsets[64];
uniform float row_len = 2.2;
uniform float half_w = 3.0;
uniform vec3 lane_color : source_color = vec3(0.78, 1.0, 0.24);
uniform vec3 core_color : source_color = vec3(0.96, 1.0, 0.88);
uniform vec3 warn_color : source_color = vec3(1.0, 0.69, 0.13);
uniform float glow = 1.0;  // 1 in the lane, ~0.55 out of it, up to 2 in a "caught" flash

// The lane centre's x at `d` metres ahead (interpolated between rows; held past the last).
float lane_x(float d) {
	float r = clamp(d / row_len, 0.0, 62.999);
	int i = int(r);
	return mix(offsets[i], offsets[i + 1], r - float(i));
}
