// Keepy Uppy's balloon (ART_BIBLE §4, the hero): coral latex lit per pixel by hand (it's small on
// screen, so per-pixel light is cheap here), a soft sky-blue rim so it reads against sky and cloud,
// a broad sheen and a tight window highlight, and a little translucency where the sun comes through.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/keepy_uppy/shaders/keepy_look.gdshaderinc"

uniform float dim = 1.0;
uniform float flash = 0.0;  // a white flash on a pop or a gust

varying vec3 v_normal;
varying vec3 v_view;

void vertex() {
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view = normalize(CAMERA_POSITION_WORLD - wp);
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 v = normalize(v_view);
	vec3 l = normalize(sun_dir);
	vec3 base = COLOR.rgb;
	float ndl = dot(n, l);
	vec3 light = hemi(n) * 0.9 + sun_color * max(ndl, 0.0) * 0.85 + vec3(0.18);
	// Sun glowing through the latex on the shadow side.
	light += sun_color * vec3(1.0, 0.45, 0.35) * pow(max(-ndl, 0.0), 2.0) * 0.25;
	vec3 col = base * light * dim;
	float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
	col += sky_color * fres * 0.45;
	vec3 h = normalize(l + v);
	float sheen = pow(max(dot(n, h), 0.0), 18.0);
	float spot = pow(max(dot(n, h), 0.0), 220.0);
	col += sun_color * (sheen * 0.22 + spot * 1.4) * dim;
	col = mix(col, vec3(1.0), flash);
	ALBEDO = grade(col, SCREEN_UV);
}
