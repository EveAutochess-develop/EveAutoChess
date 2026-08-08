shader_type spatial;
// Mixed lance shaft: continuous column + V-arc MASK at BOTH ends (emit + tip).
// Flow: energy travels from emit (along=0, 无畏) toward tip (along=1).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, specular_disabled;

uniform sampler2D tex_beam : source_color, filter_linear, repeat_enable;
uniform vec4 tint_a : source_color = vec4(1.0, 0.82, 0.28, 1.0);
uniform vec4 tint_c : source_color = vec4(0.35, 0.72, 1.0, 1.0);
uniform vec4 tint_g : source_color = vec4(0.35, 1.0, 0.55, 1.0);
uniform vec4 tint_m : source_color = vec4(1.0, 0.42, 0.12, 1.0);
uniform float time_s = 0.0;
uniform float travel_speed = 0.55;
uniform float uv_tile_y = 6.0;
uniform float uv_scroll = 0.0;
uniform float alpha_mul = 0.8;
uniform float emission_mul = 2.0;
uniform float core_boost = 0.0;
// Dual V-arc: along 0=射出端(无畏) … 1=末端. Tip mask from mask_start→1; muzzle from 0→muzzle_end.
uniform float mask_enable = 1.0;
uniform float mask_start = 0.85;
uniform float muzzle_end = 0.15;
uniform float mask_arc = 1.35;
uniform float mask_tip_frac = 0.03;
uniform float mask_soft = 0.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

vec3 race_tint(float t) {
	float x = fract(t / 4.0) * 4.0;
	vec3 c0;
	vec3 c1;
	float u;
	if (x < 1.0) {
		c0 = tint_a.rgb;
		c1 = tint_c.rgb;
		u = x;
	} else if (x < 2.0) {
		c0 = tint_c.rgb;
		c1 = tint_g.rgb;
		u = x - 1.0;
	} else if (x < 3.0) {
		c0 = tint_g.rgb;
		c1 = tint_m.rgb;
		u = x - 2.0;
	} else {
		c0 = tint_m.rgb;
		c1 = tint_a.rgb;
		u = x - 3.0;
	}
	u = smoothstep(0.0, 1.0, u);
	return mix(c0, c1, u);
}

float cone_half(float t01) {
	// t01=0 at pointed tip, t01=1 at full-width join.
	return mix(mask_tip_frac, 1.0, pow(clamp(t01, 0.0, 1.0), mask_arc));
}

float apply_cone(float along, float a_in, float nx) {
	float a = a_in;
	// Far tip: along > mask_start → narrow toward along=1.
	if (along > mask_start) {
		float span = max(1.0 - mask_start, 0.0001);
		float t = clamp((along - mask_start) / span, 0.0, 1.0);
		float half_n = cone_half(1.0 - t);
		if (mask_soft < 0.001) {
			if (nx > half_n) {
				return -1.0;
			}
		} else {
			a *= 1.0 - smoothstep(half_n, half_n + mask_soft, nx);
		}
	}
	// Muzzle tip: along < muzzle_end → narrow toward along=0 (无畏端).
	if (along < muzzle_end) {
		float span_m = max(muzzle_end, 0.0001);
		float t_m = clamp(along / span_m, 0.0, 1.0);
		float half_m = cone_half(t_m);
		if (mask_soft < 0.001) {
			if (nx > half_m) {
				return -1.0;
			}
		} else {
			a *= 1.0 - smoothstep(half_m, half_m + mask_soft, nx);
		}
	}
	return a;
}

void fragment() {
	float along = v_uv.y;
	// Outward flow: texture scrolls toward tip (+along) from dread emit.
	vec2 uv = vec2(v_uv.x, along * uv_tile_y + uv_scroll);
	vec4 tex = texture(tex_beam, uv);
	float luma = max(tex.r, max(tex.g, tex.b));
	float phase = along * 3.0 + time_s * travel_speed;
	vec3 tint = race_tint(phase);
	vec3 rgb = tint * mix(vec3(0.55), max(tex.rgb, vec3(0.25)), 0.7);
	rgb = mix(rgb, vec3(1.0), core_boost * 0.35);
	float a = mix(0.62, 1.0, luma) * alpha_mul;
	float edge = smoothstep(0.0, 0.08, v_uv.x) * smoothstep(1.0, 0.92, v_uv.x);
	a *= mix(0.55, 1.0, edge);

	if (mask_enable > 0.5) {
		float nx = abs(v_uv.x - 0.5) * 2.0;
		float a2 = apply_cone(along, a, nx);
		if (a2 < 0.0) {
			discard;
		}
		a = a2;
	}

	ALBEDO = rgb;
	EMISSION = rgb * emission_mul;
	ALPHA = clamp(a, 0.0, 1.0);
}
