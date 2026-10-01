// The balls (one MultiMesh): a glossy rubber ball in the instance colour with two dark seams,
// a rim light so it reads against any sky, and a warm glow as it nears the rider
// (INSTANCE_CUSTOM.r, 0-1). INSTANCE_CUSTOM.g lights it up at night.
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
	EMISSION = base * (rim * (0.35 + custom.g) + near * 0.5 + custom.g * 0.25);
}
