// Balloon Pump's grade (ART_BIBLE §4: high noon, pastel and candy-bright, a faint plum lift) on
// the 3D games' shared hand light (framework/shaders/world_look.gdshaderinc). Every Balloon Pump
// world shader includes this instead of the framework file, so the grade is set once.
#define LOOK_SAT 1.08
#define LOOK_CONTRAST 1.02
#define LOOK_GAIN vec3(1.02, 1.0, 0.98)
#define LOOK_LIFT vec3(0.03, 0.02, 0.04)
// The vignette is painted into the vertex colours of the grid that draws the view on screen
// (PumpMeshes.view_image), not worked out per pixel here (Tug's tablet recipe).
#include "res://framework/shaders/world_look.gdshaderinc"

// Haze per vertex: the share of `haze_color` at a distance, passed on in a varying.
float haze_amount(float dist) {
	return min(1.0 - exp(-haze_density * dist), haze_max);
}

vec3 hazed(vec3 col, float amount) {
	return mix(col, haze_color, amount);
}

// A rubber balloon's light, per pixel (the balloons are small on screen and need the gloss):
// hemisphere ambient, a wrapped sun (rubber lets light through), a tight highlight and a broad
// sheen that grows as the rubber stretches (`taut`), and a rim from the sky.
vec3 balloon_light(vec3 base, vec3 n_world, vec3 v_world, float taut) {
	vec3 l = normalize(sun_dir);
	float ndl = dot(n_world, l);
	vec3 diff = hemi(n_world) * 0.85 + sun_color * clamp(ndl * 0.6 + 0.4, 0.0, 1.0) * 0.75;
	// Light through the rubber on the side away from the sun.
	vec3 through = base * sun_color * pow(clamp(-ndl * 0.5 + 0.5, 0.0, 1.0), 2.0) * 0.35;
	vec3 h = normalize(l + v_world);
	float nh = max(dot(n_world, h), 0.0);
	float spec = pow(nh, mix(40.0, 90.0, taut)) * mix(0.55, 1.0, taut) + pow(nh, 6.0) * 0.12 * taut;
	float rim = pow(1.0 - max(dot(n_world, v_world), 0.0), 3.0);
	return base * diff + through + vec3(spec) * sun_color + sky_color * rim * 0.35;
}
