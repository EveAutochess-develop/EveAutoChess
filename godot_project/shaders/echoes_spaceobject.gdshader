shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D pmwo_tex : source_color;
uniform sampler2D rg_tex : source_color;
uniform sampler2D reduction_tex : source_color;

uniform vec4 hull_tint : source_color = vec4(0.95, 0.78, 0.40, 1.0);
uniform vec4 team_tint : source_color = vec4(0.42, 0.62, 1.0, 1.0);
uniform float team_mix : hint_range(0.0, 1.0) = 0.18;
uniform float normal_scale = 0.92;
uniform float reduction_strength : hint_range(0.0, 1.0) = 0.65;
uniform float rg_colorize : hint_range(0.0, 1.0) = 0.55;
uniform float pmwo_metallic : hint_range(0.0, 1.0) = 0.55;
uniform float pmwo_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float combat_emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec3 combat_emission_color = vec3(1.0);

void fragment() {
	vec4 ad = texture(albedo_tex, UV);
	vec3 base_gray = ad.rgb;
	vec3 tint = mix(hull_tint.rgb, team_tint.rgb, team_mix);
	vec4 pmwo = texture(pmwo_tex, UV);
	vec4 rg = texture(rg_tex, UV);
	vec4 reduction = texture(reduction_tex, UV);

	float lum = dot(base_gray, vec3(0.299, 0.587, 0.114));
	float dark_mask = smoothstep(0.05, 0.40, lum);
	float bright_mask = smoothstep(0.45, 0.90, lum);
	float panel_variation = mix(0.78, 1.18, rg.r);
	float reduction_mask = mix(1.0, reduction.r, reduction_strength);
	vec3 colored = base_gray * tint;
	colored = mix(colored * 0.78, colored, dark_mask);
	colored *= mix(0.92, panel_variation, rg_colorize);
	colored = mix(colored, vec3(1.0), bright_mask * reduction.g * 0.35);
	colored *= reduction_mask;

	ALBEDO = clamp(colored, vec3(0.0), vec3(1.0));
	NORMAL_MAP = texture(normal_tex, UV).rgb;	NORMAL_MAP_DEPTH = normal_scale;
	METALLIC = clamp(pmwo.r * pmwo_metallic + rg.g * 0.15, 0.02, 0.92);
	ROUGHNESS = clamp(1.0 - pmwo.g * pmwo_roughness + (1.0 - reduction.r) * 0.12, 0.06, 0.97);
	SPECULAR = 0.22;
	AO = clamp(mix(1.0, reduction.r, 0.55), 0.35, 1.0);
	vec3 emit_tint = combat_emission_color;
	if (dot(emit_tint, emit_tint) < 0.0001) {
		emit_tint = team_tint.rgb;
	}
	EMISSION = emit_tint * combat_emission_strength + rg.bbb * 0.03;
}
