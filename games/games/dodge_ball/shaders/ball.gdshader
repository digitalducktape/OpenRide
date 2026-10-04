// The balls (one MultiMesh): a glossy rubber ball in the instance colour with two dark seams,
// a rim light so it reads against any sky, and a warm glow as it nears the rider
// (INSTANCE_CUSTOM.r, 0-1). INSTANCE_CUSTOM.g lights it up at night; INSTANCE_CUSTOM.b is 1 for
// Catch mode's gold balls, which shimmer.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

varying vec3 local_pos;
varying vec4 custom;

void vertex() {
	local_pos = VERTEX;
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 n = normalize(local_pos);
	float seam = min(abs(n.x), abs(n.y * 0.7 + n.z * 0.7));
	float line = smoothstep(0.035, 0.06, seam);
	vec3 base = COLOR.rgb;
	ALBEDO = mix(base * 0.25, base, line);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float near = custom.r;
	float reward = custom.b;  // 1 in Catch mode: a shimmering gold prize, not a threat
	float shimmer = reward * (0.35 + 0.25 * sin(TIME * 7.0 + local_pos.y * 9.0));
	// Dodge balls flush hotter red as they close in; Catch balls glow gold all the way.
	EMISSION = base * (rim * (0.35 + custom.g + reward * 0.4) + near * 0.5 * (1.0 - reward) + custom.g * 0.25 + shimmer);
}
