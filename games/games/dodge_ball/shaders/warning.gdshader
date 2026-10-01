// A ball's warning (one MultiMesh of flat quads on the road): a glowing lane strip at the
// rider's line where the ball will arrive, with chevrons running towards the rider. It
// brightens as the ball nears (INSTANCE_CUSTOM.r = urgency 0-1). Unshaded and additive, so it
// reads in every light.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.35, 0.15);

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	// UV.x across the lane, UV.y from the far end (0) to the rider's line (1).
	float urgency = custom.r;
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.0, 0.25, across);
	float along = smoothstep(0.0, 0.7, UV.y);
	float chevron = step(0.5, fract(UV.y * 6.0 - abs(UV.x - 0.5) * 2.0 - custom.g * 3.0));
	float a = edge * along * (0.25 + 0.35 * chevron) * (0.35 + 0.65 * urgency);
	// A bright bar at the arrival line.
	a += smoothstep(0.9, 0.97, UV.y) * smoothstep(1.0, 0.97, UV.y) * (0.6 + 0.4 * urgency) * edge;
	ALBEDO = tint * a * custom.a;
}
