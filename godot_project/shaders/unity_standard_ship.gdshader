shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

/// Godot port of Unity Custom/StandardShipShader (DUST_243).
/// Do NOT write ALPHA — assigning ALPHA forces transparent pass and reads as 镂空.

uniform sampler2D albedo_tex : source_color;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D pmwo_tex : source_color; // R = material ID (PC *_m)
uniform sampler2D rg_tex : source_color; // R = roughness/gloss map, G = glow (*_g)

uniform vec4 color1 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color3 : source_color = vec4(0.1981132, 0.1981132, 0.1981132, 1.0);
uniform vec4 color4 : source_color = vec4(1.0, 0.84931314, 0.0, 1.0);
uniform vec4 color_light : source_color = vec4(0.0, 0.9270375, 1.0, 1.0);

uniform float threshold1 = -0.1;
uniform float threshold2 = 0.35;
uniform float threshold3 = 0.68;
uniform float metallic_threshold = 0.75;
uniform float normal_scale = 1.0;
uniform float glow_mul = 1.0;
uniform float intensity_floor = 0.04;
uniform float combat_emission_strength : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec4 ad = texture(albedo_tex, UV);
	float intensity = max(ad.r, max(ad.g, ad.b));
	intensity = max(intensity, intensity_floor);
	vec4 pmwo = texture(pmwo_tex, UV);
	vec4 rg = texture(rg_tex, UV);

	float mat_id = pmwo.r;
	if (mat_id < 0.001) {
		mat_id = intensity;
	}

	vec4 clr1 = color1 * (1.0 - step(threshold1, mat_id));
	vec4 clr2 = color2 * step(threshold1, mat_id) * step(mat_id, threshold2);
	vec4 clr3 = color3 * step(threshold2, mat_id) * step(mat_id, threshold3);
	vec4 clr4 = color4 * step(threshold3, mat_id);
	vec3 band = (clr1 + clr2 + clr3 + clr4).rgb;
	band = max(band, vec3(0.06));

	ALBEDO = intensity * band;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	float metallic = step(metallic_threshold, mat_id);
	METALLIC = metallic;
	float gloss = mix(0.5, 1.0, metallic) * rg.r;
	ROUGHNESS = clamp(1.0 - gloss, 0.04, 0.97);
	SPECULAR = 0.5;
	AO = clamp(dot(ad.rgb, vec3(0.333)), 0.35, 1.0);

	vec3 glow = rg.g * color_light.rgb * glow_mul;
	EMISSION = glow + vec3(combat_emission_strength);
}
