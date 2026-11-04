shader_type canvas_item;

// Balloon Pump's balloons (#76, the 2D rework; ART_BIBLE.md §4): one quad per balloon (the
// nozzle's, the one flying up, and every balloon of the bunch, a MultiMesh), the shape and the
// light worked out per pixel so the edge stays smooth at any size. The quad's UV runs 0-1 across
// and from the top (v 0) to the knot (v 1); PumpStage sizes it BALLOON_TALL half-widths tall.
//
// The balloon's colour is COLOR (the node's modulate, or the MultiMesh's instance colour).
// INSTANCE_CUSTOM.y (or `gold`) marks a gold balloon; `taut` (0-1) stretches the sheen as it
// fills; `wobble` (0-1) shakes it while it leaks; `light_dir` points at the place's key light
// (canvas axes: x right, y down); `light_color` tints the highlight.

uniform float taut = 0.6;
uniform float wobble = 0.0;
uniform float gold = 0.0;
uniform vec2 light_dir = vec2(-0.5, -0.8);
uniform vec3 light_color : source_color = vec3(1.0, 0.92, 0.8);

const float TALL = 2.3;   // PumpArt.BALLOON_TALL
const float CY = 1.22;    // the body's centre, half-widths above the knot
const float RY = 1.02;    // the body's vertical radius

varying float v_gold;

void vertex() {
	v_gold = max(gold, INSTANCE_CUSTOM.y);
}

void fragment() {
	// Balloon space: x -1..1 across, y up from the knot (0) to the top (TALL).
	float x = UV.x * 2.0 - 1.0;
	float y = (1.0 - UV.y) * TALL;
	if (wobble > 0.0) {
		x *= 1.0 + 0.035 * wobble * sin(TIME * 11.0 + y * 3.0);
	}
	// The body: an ellipse whose lower half narrows to the knot (a teardrop).
	float below = clamp((CY - y) / RY, 0.0, 1.0);
	// Gold foil balloons are rounder (a foil sphere), latex ones a teardrop.
	float k = mix(1.0, v_gold > 0.5 ? 0.7 : 0.42, below * below);
	vec2 q = vec2(x / k, (y - CY) / RY);
	float d = length(q) - 1.0;
	// The knot: a small rounded tab under the body, slightly darker.
	vec2 kq = vec2(x / 0.11, (y - 0.13) / 0.12);
	float dk = (length(kq) - 1.0) * 0.11;
	float aa = fwidth(d) * 1.2;
	float body = 1.0 - smoothstep(-aa, aa, d);
	float knot = 1.0 - smoothstep(-0.012, 0.012, dk);
	float alpha = max(body, knot);
	if (alpha <= 0.0) {
		discard;
	}
	vec3 base = COLOR.rgb;
	// A sphere's normal from the position in the body.
	vec2 qn = q / max(length(q), 1.0);
	vec3 n = normalize(vec3(qn.x, qn.y, sqrt(max(1.0 - dot(qn, qn), 0.0)) + 0.05));
	vec3 l = normalize(vec3(light_dir.x, -light_dir.y, 0.9));
	float ndl = dot(n, l);
	// Rubber: wrapped diffuse, deeper and more saturated toward the rim, light glowing through on
	// the side away from the light, a tight hot highlight and a broad soft sheen.
	vec3 col = base * (0.42 + 0.58 * clamp(ndl * 0.65 + 0.35, 0.0, 1.0));
	float rim = pow(1.0 - n.z, 2.0);
	col = mix(col, base * base * 0.75, rim * 0.6);
	col += base * light_color * 0.35 * pow(clamp(-ndl * 0.6 + 0.35, 0.0, 1.0), 2.0) * (1.0 - rim);
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float nh = max(dot(n, h), 0.0);
	col += light_color * (pow(nh, mix(60.0, 140.0, taut)) * mix(0.75, 1.0, taut) + pow(nh, 8.0) * 0.16 * (0.4 + taut));
	// A reflected window of the room on the shadow side.
	col += vec3(0.08) * smoothstep(0.75, 0.95, dot(n, normalize(vec3(-l.x, -l.y, 0.6))));
	if (v_gold > 0.5) {
		// Gold foil: a metallic ramp from the normal, and a glint sweeping across.
		float m = 0.5 + 0.5 * dot(n, l);
		col = mix(vec3(0.55, 0.35, 0.06), vec3(1.0, 0.86, 0.42), m) + light_color * pow(nh, 30.0) * 0.8;
		// A soft glint drifting round the upper body (no seam across it, which read as a lemon).
		vec2 g = vec2(sin(TIME * 0.9) * 0.45, 0.35 + 0.1 * cos(TIME * 0.7));
		col += vec3(1.0, 0.95, 0.75) * smoothstep(0.35, 0.0, length(qn - g)) * 0.5 * body;
	}
	// The knot: thicker, darker rubber with a pinch line.
	if (knot > body) {
		col = base * (0.5 + 0.25 * clamp(-kq.x * 0.4 + 0.5, 0.0, 1.0));
	}
	COLOR = vec4(col, alpha * COLOR.a);
}
