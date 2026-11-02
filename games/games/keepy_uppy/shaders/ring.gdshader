// Keepy Uppy's pop ring: a white ring on a camera-facing card, growing and fading as `progress`
// runs 0 → 1 (a tween). Additive.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float progress = 1.0;

void vertex() {
	// Billboard: keep the card facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float radius = mix(0.15, 0.95, sqrt(progress));
	float ring = 1.0 - smoothstep(0.0, 0.08, abs(r - radius));
	float a = ring * (1.0 - progress);
	ALBEDO = vec3(1.0, 0.95, 0.9) * a;
}
