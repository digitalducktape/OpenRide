shader_type canvas_item;

// Balloon Pump's pier (#76; ART_BIBLE.md §6): the sea under the moon, on one ColorRect drawn under
// the baked room (the room leaves this band clear). Dark swells from the horizon down, slow
// rolling lines from TIME, and the moon's glitter path breaking up on the waves.

uniform vec4 deep : source_color = vec4(0.02, 0.05, 0.11, 1.0);
uniform vec4 near : source_color = vec4(0.05, 0.1, 0.18, 1.0);
uniform float moon_u = 0.18;  // the moon's x across the rect (0-1)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(deep.rgb, near.rgb, uv.y);
	// Rolling swells: lines that crowd toward the horizon.
	float depth_y = pow(uv.y, 1.6);
	float wave = sin(depth_y * 90.0 - TIME * 0.9 + sin(uv.x * 9.0 + TIME * 0.3) * 1.5);
	col += vec3(0.05, 0.08, 0.12) * smoothstep(0.7, 1.0, wave) * (0.4 + uv.y);
	// The glitter path: bright flecks in a column under the moon, widening toward us.
	float width = mix(0.02, 0.12, uv.y);
	float path = 1.0 - smoothstep(width * 0.4, width, abs(uv.x - moon_u));
	// Flecks: short soft dashes, one per cell, re-dealt a few times a second.
	vec2 grid = vec2(uv.x * 420.0, depth_y * 90.0);
	vec2 cell = floor(grid);
	vec2 f = fract(grid) - 0.5;
	float on = step(0.6, hash(cell + floor(TIME * 1.6 + hash(cell) * 3.0)));
	float dash = (1.0 - smoothstep(0.1, 0.45, abs(f.x))) * (1.0 - smoothstep(0.05, 0.3, abs(f.y)));
	float fleck = on * dash * smoothstep(0.2, 1.0, wave * 0.5 + 0.5);
	col += vec3(0.85, 0.88, 0.8) * fleck * path * 0.8;
	col += vec3(0.2, 0.24, 0.3) * path * 0.25;
	// A thin bright horizon line.
	col += vec3(0.25, 0.3, 0.4) * (1.0 - smoothstep(0.0, 0.03, uv.y));
	COLOR = vec4(col, 1.0);
}
