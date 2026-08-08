shader_type spatial;
// Mixed lance beam: racial tints/textures in random bands that lerp and travel toward tip (+Y / +UV.y).
render_mode unshaded, blend_add, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D tex_a : source_color, filter_linear;
uniform sampler2D tex_c : source_color, filter_linear;
uniform sampler2D tex_g : source_color, filter_linear;
uniform sampler2D tex_m : source_color, filter_linear;
uniform vec4 tint_a : source_color = vec4(1.0, 0.82, 0.28, 1.0);
uniform vec4 tint_c : source_color = vec4(0.35, 0.72, 1.0, 1.0);
uniform vec4 tint_g : source_color = vec4(0.35, 1.0, 0.55, 1.0);
uniform vec4 tint_m : source_color = vec4(1.0, 0.42, 0.12, 1.0);
uniform float time_s = 0.0;
uniform float travel_speed = 0.35;
uniform float band_scale = 5.5;
uniform float soft_width = 0.12;
uniform float alpha_mul = 0.85;
uniform float emission_mul = 2.0;
uniform float uv_scroll = 0.0;
uniform float core_mode = 0.0; // 1 = narrower/brighter core look

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

vec4 race_sample(int idx, vec2 uv) {
	vec4 tex;
	vec4 tint;
	if (idx == 0) {
		tex = texture(tex_a, uv);
		tint = tint_a;
	} else if (idx == 1) {
		tex = texture(tex_c, uv);
		tint = tint_c;
	} else if (idx == 2) {
		tex = texture(tex_g, uv);
		tint = tint_g;
	} else {
		tex = texture(tex_m, uv);
		tint = tint_m;
	}
	float luma = max(tex.r, max(tex.g, tex.b));
	vec3 rgb = tint.rgb * mix(vec3(0.45), tex.rgb, 0.75);
	return vec4(rgb, tint.a * mix(0.5, 1.0, luma) * tex.a);
}

void fragment() {
	vec2 uv = v_uv;
	uv.y += uv_scroll;
	// Travel toward tip: bands move in +Y (UV.y increases toward tip on our quads).
	float along = fract(v_uv.y * band_scale - time_s * travel_speed);
	float cell = floor(v_uv.y * band_scale - time_s * travel_speed);
	float h0 = hash11(cell + 17.0);
	float h1 = hash11(cell + 1.0 + 17.0);
	int i0 = int(floor(h0 * 4.0)) % 4;
	int i1 = int(floor(h1 * 4.0)) % 4;
	// Occasionally force a different race at mid-band for "random region switch".
	if (hash11(cell + 91.0) > 0.55) {
		i1 = (i0 + 1 + int(floor(hash11(cell + 3.0) * 3.0))) % 4;
	}
	float w = smoothstep(0.0, soft_width, along) * (1.0 - smoothstep(1.0 - soft_width, 1.0, along));
	// Prefer lerp across the whole band length for visible gradients.
	float t = smoothstep(0.0, 1.0, along);
	t = mix(t, w, 0.25);
	vec4 c0 = race_sample(i0, uv);
	vec4 c1 = race_sample(i1, uv);
	vec4 col = mix(c0, c1, t);
	if (core_mode > 0.5) {
		col.rgb = mix(col.rgb, vec3(1.0), 0.25);
		col.a *= 1.15;
	}
	ALBEDO = col.rgb;
	EMISSION = col.rgb * emission_mul;
	ALPHA = clamp(col.a * alpha_mul, 0.0, 1.0);
}
