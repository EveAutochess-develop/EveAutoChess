shader_type spatial;
// Mixed lance icon: four racial icons share one center; four 90° wedges, boundaries sweep.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D icon_a : source_color, filter_linear;
uniform sampler2D icon_c : source_color, filter_linear;
uniform sampler2D icon_g : source_color, filter_linear;
uniform sampler2D icon_m : source_color, filter_linear;
uniform float sweep_rad = 0.0;
uniform float soft_edge = 0.04;
uniform float highlight_boost = 0.35;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

vec4 sample_icon(int idx, vec2 uv) {
	if (idx == 0) {
		return texture(icon_a, uv);
	}
	if (idx == 1) {
		return texture(icon_c, uv);
	}
	if (idx == 2) {
		return texture(icon_g, uv);
	}
	return texture(icon_m, uv);
}

void fragment() {
	vec2 p = v_uv - vec2(0.5);
	float r = length(p);
	if (r > 0.5) {
		discard;
	}
	// Mask to circular disc (keep icon square content centered).
	float ring = 1.0 - smoothstep(0.47, 0.5, r);
	float ang = atan(p.y, p.x); // -PI..PI
	float u = fract((ang + 3.14159265) / 6.2831853 + sweep_rad / 6.2831853);
	float sector_f = u * 4.0;
	int idx0 = int(floor(sector_f)) % 4;
	int idx1 = (idx0 + 1) % 4;
	float edge = fract(sector_f);
	float blend = smoothstep(0.0, soft_edge, edge) * (1.0 - smoothstep(1.0 - soft_edge, 1.0, edge));
	// Mostly hard wedges; tiny soft seam so sweep reads continuous.
	float w = mix(0.0, 1.0, smoothstep(1.0 - soft_edge * 2.0, 1.0, edge));
	vec4 c0 = sample_icon(idx0, v_uv);
	vec4 c1 = sample_icon(idx1, v_uv);
	vec4 col = mix(c0, c1, w);
	// Sweep highlight: brighter quarter following the leading edge.
	float lead = fract(u - 0.0);
	float hi = 1.0 - smoothstep(0.0, 0.25, lead);
	col.rgb *= 1.0 + highlight_boost * hi;
	ALBEDO = col.rgb;
	ALPHA = col.a * ring;
	EMISSION = col.rgb * 0.15;
}
