shader_type spatial;
// Off-axis elliptical "witch-stone" lens: soft rim, reveals one racial tint of the mixed lance.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, specular_disabled;

uniform sampler2D tex_beam : source_color, filter_linear, repeat_enable;
uniform sampler2D tex_soft : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float time_s = 0.0;
uniform float uv_scroll = 0.0;
uniform float soft_power = 1.6;
uniform float alpha_mul = 0.75;
uniform float emission_mul = 2.4;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Ellipse in quad UV: soft falloff to rim (巫婆石透镜边缘淡出).
	vec2 p = (v_uv - vec2(0.5)) * 2.0;
	float e = length(p);
	if (e > 1.0) {
		discard;
	}
	float soft = pow(1.0 - e, soft_power);
	vec2 buv = vec2(v_uv.x, v_uv.y * 2.0 + uv_scroll);
	vec4 beam = texture(tex_beam, buv);
	vec4 soft_tex = texture(tex_soft, v_uv);
	float luma = max(beam.r, max(beam.g, beam.b));
	vec3 rgb = tint.rgb * mix(0.5, 1.15, luma) * mix(0.65, 1.0, soft_tex.r);
	float a = soft * alpha_mul * mix(0.55, 1.0, luma) * tint.a;
	ALBEDO = rgb;
	EMISSION = rgb * emission_mul * soft;
	ALPHA = clamp(a, 0.0, 1.0);
}
