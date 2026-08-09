shader_type spatial;
render_mode unshaded, blend_add, depth_draw_opaque, cull_disabled;

uniform sampler2D tex_beam : source_color, hint_default_white;
uniform sampler2D tex_grid : source_color, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float scroll_speed = 1.8;
uniform float grid_mix = 0.55;
uniform float pulse = 1.0;
uniform float emission_boost = 2.4;
uniform vec2 uv_scale = vec2(1.0, 3.0);

void fragment() {
	vec2 uv = UV * uv_scale;
	uv.y -= TIME * scroll_speed;
	vec4 beam = texture(tex_beam, uv);
	vec4 grid = texture(tex_grid, uv * vec2(2.0, 1.5) + vec2(0.0, TIME * scroll_speed * 0.35));
	vec3 rgb = mix(beam.rgb, grid.rgb, clamp(grid_mix, 0.0, 1.0)) * tint.rgb;
	float a = max(beam.a, grid.a * grid_mix) * tint.a * pulse;
	ALBEDO = rgb;
	EMISSION = rgb * emission_boost;
	ALPHA = clamp(a, 0.0, 1.0);
}
