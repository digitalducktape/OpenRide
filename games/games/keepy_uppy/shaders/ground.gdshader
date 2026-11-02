// Keepy Uppy's meadow floor: long grass in world space (two noise reads: patches and a fine
// grain), a few flower speckles, the rain cloud's soft shadow and the downdraft's dark band of
// flattened grass rolling toward the fan. Lit flat (the ground faces up), hazed per vertex on a
// subdivided plane, graded per pixel.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/keepy_uppy/shaders/keepy_look.gdshaderinc"

uniform vec3 grass_near : source_color = vec3(0.435, 0.749, 0.29);
uniform vec3 grass_far : source_color = vec3(0.612, 0.796, 0.42);
// The rain cloud's shadow: (x, z, radius, strength).
uniform vec4 cloud_shadow = vec4(0.0, -60.0, 9.0, 0.0);
// The downdraft's band: (z of its front, width, strength). It rolls toward the fan.
uniform vec3 downdraft = vec3(-40.0, 6.0, 0.0);
uniform float dim = 1.0;

varying vec3 v_world;
varying float v_haze;
varying float v_far;
varying vec3 v_light;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_haze = haze_amount(d);
	v_far = smoothstep(8.0, 70.0, d);
	v_light = sun_light(vec3(0.0, 1.0, 0.0)) * dim;
}

void fragment() {
	vec2 p = v_world.xz;
	float patches = vnoise(p * 0.18);
	float fine = vnoise(p * 3.1 + vec2(patches * 4.0, 0.0));
	vec3 col = mix(grass_near, grass_far, v_far * 0.8 + patches * 0.25);
	col *= 0.78 + 0.3 * mix(fine, 0.5, v_far);
	// Flower speckles near the camera.
	float spot = smoothstep(0.86, 0.9, fine) * (1.0 - v_far) * step(0.55, patches);
	col = mix(col, vec3(0.95, 0.93, 0.85), spot * 0.7);
	// The cloud's shadow: a soft ellipse, cooler and darker.
	vec2 cs = (p - cloud_shadow.xy) / vec2(cloud_shadow.z, cloud_shadow.z * 0.7);
	float shade = (1.0 - smoothstep(0.55, 1.0, length(cs))) * cloud_shadow.w;
	col *= mix(vec3(1.0), vec3(0.62, 0.68, 0.78), shade);
	// The downdraft: a dark band of flattened grass with a bright leading edge.
	float into = (v_world.z - downdraft.x) / downdraft.y;
	float band = smoothstep(-1.0, -0.2, into) * (1.0 - smoothstep(0.0, 0.25, into)) * downdraft.z;
	float edge = (1.0 - smoothstep(0.0, 0.15, abs(into))) * downdraft.z;
	col = mix(col, col * vec3(0.42, 0.5, 0.45), band);
	col += vec3(0.08, 0.1, 0.06) * edge;
	ALBEDO = grade(hazed(col * v_light, v_haze), SCREEN_UV);
}
