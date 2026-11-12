shader_type canvas_item;

// The push line on the pump's gauge (#76; ART_BIBLE.md §2): a band from the line to the end of the
// scale, gold at the line shading to red, on a ColorRect over the gauge's face (the face's ticks
// sit outside the band). One uniform moves it; nothing redraws. `filling` (0-1) lights the band
// while the balloon takes air.

uniform float line = 0.5;  // 0-1 along the scale
uniform float filling = 0.0;
const float FROM = 2.356194;  // PumpArt.GAUGE_FROM (135°, canvas angles: y down)
const float SWEEP = 4.712389;  // 270°, clockwise on screen
const float R0 = 0.42;  // the band, as shares of the rect's half-size (wide: read at 1 m)
const float R1 = 0.75;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = (a - FROM) / SWEEP;
	t = t < 0.0 ? t + 6.2831853 / SWEEP : t;
	float aa = fwidth(r) * 1.5;
	float band = smoothstep(R0 - aa, R0, r) * (1.0 - smoothstep(R1, R1 + aa, r));
	float on = step(line, t) * step(t, 1.0);
	// Soft ends along the arc.
	// A pixel's share of the scale, from r: t wraps at the scale's start, so fwidth(t) spikes along
	// that ray and the marker drew a stray line there.
	float ta = fwidth(r) / max(r, 0.05) / SWEEP * 2.4;
	on *= smoothstep(line - ta, line + ta, t);
	vec3 col = mix(vec3(1.0, 0.72, 0.05), vec3(0.85, 0.08, 0.06), clamp((t - line) / max(1.0 - line, 0.08), 0.0, 1.0));
	col *= 0.9 + 0.2 * filling;
	// A dark edge round the band, so it stands off the cream face.
	float edge = smoothstep(R0 - aa, R0 + 0.025, r) * (1.0 - smoothstep(R1 - 0.025, R1 + aa, r));
	col *= mix(0.55, 1.0, edge);
	// The line itself: a bold ink marker across the band and past it, with a gold tip outside.
	float tick = 1.0 - smoothstep(ta * 0.8, ta * 2.2, abs(t - line));
	float marker = tick * smoothstep(R0 - 0.08 - aa, R0 - 0.08, r) * (1.0 - smoothstep(R1 + 0.06, R1 + 0.06 + aa, r));
	float tip = (1.0 - smoothstep(ta * 2.0, ta * 3.5, abs(t - line))) * smoothstep(R1 + 0.06, R1 + 0.07, r) * (1.0 - smoothstep(R1 + 0.13, R1 + 0.14, r));
	vec3 out_col = mix(col, vec3(0.1, 0.04, 0.08), marker);
	out_col = mix(out_col, vec3(1.0, 0.8, 0.2), tip);
	COLOR = vec4(out_col, max(max(band * on, marker), tip));
}
