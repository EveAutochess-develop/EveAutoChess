shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

/// Godot port of Unity Custom/StandardShipShader (DUST_243).
/// Albedo intensity × Material-map 4-band colors + glow emission + metallic threshold.
/// Opaque + cull_disabled: prevents GLB-alpha / backface “镂空”.

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
	// Match Unity StandardShipShader: intensity from albedo.r only.
	float intensity = max(ad.r, intensity_floor);
	vec4 pmwo = texture(pmwo_tex, UV);
	vec4 rg = texture(rg_tex, UV);

	// Material ID layout:
	//   PC bake (_pack_pmwo): R = Material
	//   Echoes _pmwo.ktx:     R = Paint (often empty), G = Material
	// Never fall back to albedo intensity — that turns panel noise into camo bands.
	float mat_id = pmwo.r;
	if (mat_id < 0.02) {
		mat_id = pmwo.g;
	}
	if (mat_id < 0.02) {
		mat_id = 0.5; // neutral gray band; no speckled color switching
	}

	vec4 clr1 = color1 * (1.0 - step(threshold1, mat_id));
	vec4 clr2 = color2 * step(threshold1, mat_id) * step(mat_id, threshold2);
	vec4 clr3 = color3 * step(threshold2, mat_id) * step(mat_id, threshold3);
	vec4 clr4 = color4 * step(threshold3, mat_id);
	vec3 band = (clr1 + clr2 + clr3 + clr4).rgb;
	// Avoid pure-black panels (reads as 镂空 against space sky).
	band = max(band, vec3(0.06));

	ALBEDO = intensity * band;

	// BC5 normals often land as RG-only (B≈0). Reconstruct Z so lighting is not blotchy.
	vec3 nrm = texture(normal_tex, UV).rgb;
	vec2 nxy = nrm.xy * 2.0 - 1.0;
	if (nrm.b < 0.02) {
		float nz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));
		nrm = vec3(nxy * 0.5 + 0.5, nz * 0.5 + 0.5);
	}
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_scale;

	float metallic = step(metallic_threshold, mat_id);
	METALLIC = metallic;
	// Unity: Smoothness = lerp(0.5, 1.0, metallic) * roughness_tex
	float gloss = mix(0.5, 1.0, metallic) * rg.r;
	ROUGHNESS = clamp(1.0 - gloss, 0.04, 0.97);
	SPECULAR = 0.5;
	// Mild AO only — raw albedo-as-AO reintroduces mottling under lights.
	AO = mix(1.0, clamp(intensity, 0.35, 1.0), 0.25);

	vec3 glow = rg.g * color_light.rgb * glow_mul;
	EMISSION = glow + vec3(combat_emission_strength);
}
