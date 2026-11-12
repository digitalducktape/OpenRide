shader_type canvas_item;

// The fuel hose (#82): bright dashes running along it while fuel flows. UV.x runs along the hose
// (SafeMesh's `depth`). One uniform.

uniform float flow = 0.0;  // 0-1

void fragment() {
	float d = fract(UV.x * 7.0 - TIME * (0.6 + flow * 1.4));
	float dash = smoothstep(0.0, 0.1, d) * (1.0 - smoothstep(0.34, 0.5, d));
	vec3 col = mix(COLOR.rgb, vec3(1.0, 0.82, 0.36), dash * flow);
	COLOR = vec4(col, COLOR.a);
}
