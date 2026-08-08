shader_type canvas_item;
// Mixed lance 2D icon — four racial icons, 90° wedges, sweeping seams (CAPITAL §4.1).

uniform sampler2D icon_a : source_color, filter_linear;
uniform sampler2D icon_c : source_color, filter_linear;
uniform sampler2D icon_g : source_color, filter_linear;
uniform sampler2D icon_m : source_color, filter_linear;
uniform float sweep_rad = 0.0;
uniform float soft_edge = 0.04;
uniform float highlight_boost = 0.35;

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
	vec2 uv = UV;
	vec2 p = uv - vec2(0.5);
	float r = length(p);
	if (r > 0.5) {
		discard;
	}
	float ring = 1.0 - smoothstep(0.47, 0.5, r);
	float ang = atan(p.y, p.x);
	float u = fract((ang + 3.14159265) / 6.2831853 + sweep_rad / 6.2831853);
	float sector_f = u * 4.0;
	int idx0 = int(floor(sector_f)) % 4;
	int idx1 = (idx0 + 1) % 4;
	float edge = fract(sector_f);
	float w = mix(0.0, 1.0, smoothstep(1.0 - soft_edge * 2.0, 1.0, edge));
	vec4 c0 = sample_icon(idx0, uv);
	vec4 c1 = sample_icon(idx1, uv);
	vec4 col = mix(c0, c1, w);
	float lead = fract(u);
	float hi = 1.0 - smoothstep(0.0, 0.25, lead);
	col.rgb *= 1.0 + highlight_boost * hi;
	COLOR = vec4(col.rgb, col.a * ring);
}
