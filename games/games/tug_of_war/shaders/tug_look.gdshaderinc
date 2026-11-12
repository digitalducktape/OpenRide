// Tug of War's grade (ART_BIBLE §4: warm, sunlit timber, bark-brown shadows) on the 3D games'
// shared hand light (framework/shaders/world_look.gdshaderinc). Every Tug world shader includes
// this instead of the framework file, so the grade is set once.
#define LOOK_SAT 1.1
#define LOOK_CONTRAST 1.04
#define LOOK_GAIN vec3(1.04, 1.0, 0.94)
#define LOOK_LIFT vec3(0.03, 0.01, 0.0)
// The vignette (0.3 toward vec3(1.0, 0.9, 0.8)) is painted into the vertex colours of the grid
// that draws the view on screen (StageView3D.view_image), not worked out per pixel here.
#include "res://framework/shaders/world_look.gdshaderinc"

// Haze per vertex: the share of `haze_color` at a distance, worked out in vertex() and passed on
// in a varying (haze changes slowly with distance, so per vertex is enough and saves an exp a
// pixel on the surfaces that fill the screen). Mix it in with `hazed`.
float haze_amount(float dist) {
	return min(1.0 - exp(-haze_density * dist), haze_max);
}

vec3 hazed(vec3 col, float amount) {
	return mix(col, haze_color, amount);
}
