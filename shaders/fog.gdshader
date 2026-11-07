shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
void fragment() {
	float hidden = texture(visibility_map, UV).a;
	ALBEDO = vec3(0.065, 0.145, 0.16);
	ALPHA = hidden;
}
