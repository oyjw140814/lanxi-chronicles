shader_type spatial;
render_mode cull_disabled;
uniform vec4 shallow_color : source_color = vec4(0.24, 0.53, 0.53, 1.0);
uniform vec4 deep_color : source_color = vec4(0.055, 0.23, 0.28, 1.0);
uniform float visual_time = 0.0;
uniform float wave_strength = 0.11;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.30 + visual_time * 0.55) * cos(world_pos.z * 0.24 + visual_time * 0.35) * wave_strength;
}
void fragment() {
	float island_dist = max(abs(world_pos.x - 40.0), abs(world_pos.z - 40.0));
	float deep = smoothstep(39.0, 67.0, island_dist);
	float waves = sin(world_pos.x * 0.8 + world_pos.z * 0.18 + visual_time * 0.45) * sin(world_pos.z * 0.59 - visual_time * 0.28);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, deep);
	col += smoothstep(0.81, 0.99, waves) * vec3(0.11, 0.14, 0.12) * (1.0 - deep * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.34;
	METALLIC = 0.18;
	SPECULAR = 0.55;
}
