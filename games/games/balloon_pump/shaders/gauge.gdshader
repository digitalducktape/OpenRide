// The pump's pressure gauge (ART_BIBLE §2, the in-world dial): a cream face with ticks, the push
// line as a gold-to-red wedge from the line to the end of the scale, and the needle in the ink.
// Drawn on a quad in its UV (0-1), so it is one draw call and no redraw: the game sets `needle`
// and `line` (0-1 along the scale) each frame.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/balloon_pump/shaders/pump_look.gdshaderinc"

uniform float needle = 0.0;
uniform float line = 0.5;
uniform float filling = 0.0;  // 0-1: the hub glows green while the balloon takes air

const float START = 3.927;  // the scale's start (radians from +x, counter-clockwise): 225°
const float SWEEP = 4.712;  // 270°, clockwise

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5;
	vec3 face = vec3(1.0, 0.957, 0.871);
	vec3 ink = vec3(0.169, 0.059, 0.165);
	vec3 col = face;
	// Where this pixel sits along the scale (0 at the start, 1 at the end).
	float a = atan(p.y, p.x);
	float t = (START - a) / SWEEP;
	if (t < 0.0) {
		t += 6.2831 / SWEEP;
	}
	bool on_scale = t >= 0.0 && t <= 1.0;
	// The push wedge, gold at the line to red at the end, in a band.
	float band = smoothstep(0.56 - aa, 0.56, r) * (1.0 - smoothstep(0.8, 0.8 + aa, r));
	if (on_scale && t >= line) {
		vec3 wedge = mix(vec3(1.0, 0.77, 0.19), vec3(0.88, 0.2, 0.18), clamp((t - line) / max(1.0 - line, 0.05), 0.0, 1.0));
		col = mix(col, wedge, band);
	}
	// Ten ticks round the outside of the band.
	if (on_scale) {
		float tick = abs(fract(t * 10.0 + 0.5) - 0.5) / 10.0 * SWEEP * r;
		float tk = (1.0 - smoothstep(0.014, 0.014 + aa, tick)) * smoothstep(0.82, 0.84, r) * (1.0 - smoothstep(0.92, 0.94, r));
		col = mix(col, ink, tk);
	}
	// The needle: a tapered line from the hub toward its angle.
	float na = START - SWEEP * clamp(needle, 0.0, 1.03);
	vec2 dir = vec2(cos(na), sin(na));
	float along = dot(p, dir);
	float across = abs(dot(p, vec2(-dir.y, dir.x)));
	float width = mix(0.07, 0.015, clamp(along / 0.85, 0.0, 1.0));
	float nd = (1.0 - smoothstep(width, width + aa, across)) * step(-0.12, along) * (1.0 - smoothstep(0.86, 0.86 + aa, along));
	col = mix(col, ink, nd);
	// The hub: green while filling, the ink otherwise.
	float hub = 1.0 - smoothstep(0.11, 0.11 + aa, r);
	col = mix(col, mix(ink, vec3(0.25, 0.8, 0.35), filling), hub);
	// The bezel's inner shadow.
	col *= mix(1.0, 0.72, smoothstep(0.88, 1.0, r));
	ALBEDO = grade(col * mix(vec3(1.0), sun_color * 0.3 + sky_color * 0.8, 0.3), SCREEN_UV);
}
