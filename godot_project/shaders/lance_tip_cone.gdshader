shader_type spatial;
// Lance tip: planar V-hood with arc edges (带弧V罩), not a rotational cone.
// hard_core=1 → condensed V cut; hard_core=0 → soft cloud outside the arc-V.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, specular_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear, repeat_enable;
uniform float tip_h = 6.0;
uniform float base_r = 1.2;
uniform float tip_r = 0.04;
uniform float hard_core = 1.0;
uniform float arc_pow = 1.35;
uniform float soft_outer = 0.35;
uniform float uv_scroll = 0.0;
uniform float emission_mul = 2.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Quad UV: y=0 tip (末尾), y=1 shaft join (toward emit / 射出端).
	float y01 = clamp(v_uv.y, 0.0, 1.0);
	float nx = abs(v_uv.x - 0.5) * 2.0;
	// Arc-V half-width: bows out from tip (not linear cone).
	float t = 1.0 - pow(1.0 - y01, arc_pow);
	float half_n = mix(tip_r / max(base_r, 0.0001), 1.0, t);
	half_n = clamp(half_n, 0.0, 1.0);

	float a = 0.0;
	if (hard_core > 0.5) {
		a = nx <= half_n ? 1.0 : 0.0;
		a *= mix(1.0, 0.55, smoothstep(0.0, 0.25, y01));
	} else {
		float outer = half_n + soft_outer;
		a = 1.0 - smoothstep(half_n, max(outer, half_n + 0.001), nx);
		a *= mix(0.25, 1.0, pow(y01, 0.65));
	}
	if (a < 0.004) {
		discard;
	}

	vec2 uv = vec2(v_uv.x, y01 * 2.0 + uv_scroll);
	vec4 tex = texture(albedo_tex, uv);
	float luma = max(tex.r, max(tex.g, tex.b));
	float alpha = a * tint.a * mix(0.55, 1.0, luma);
	ALBEDO = tint.rgb * max(tex.rgb, vec3(0.35));
	EMISSION = ALBEDO * emission_mul;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
