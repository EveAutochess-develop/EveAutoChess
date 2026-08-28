shader_type spatial;
// Shell heat shimmer around existing VFX — low alpha so beams stay visible.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength : hint_range(0.0, 0.02, 0.0005) = 0.003;
uniform vec2 noise_speed = vec2(0.08, 0.14);
uniform float noise_scale = 2.4;
uniform float edge_soft : hint_range(0.02, 0.5, 0.01) = 0.18;
/// 0 = cone_shell (rim band only); 1 = radial_point.
uniform float mask_mode = 0.0;
uniform float intensity = 1.0;
/// Peak coverage of distorted screen (keep low so underlying FX show through).
uniform float cover_alpha : hint_range(0.0, 0.35, 0.01) = 0.14;

void fragment() {
	vec2 n_uv = UV * max(noise_scale, 0.01) + TIME * noise_speed;
	vec2 n = texture(noise_tex, n_uv).rg * 2.0 - 1.0;
	float mask = 1.0;
	if (mask_mode < 0.5) {
		// Thin rim around the cylinder — hollow interior so lance beams stay visible.
		float around = abs(fract(UV.x) - 0.5) * 2.0;
		float rim = smoothstep(0.55, 0.78, around) * (1.0 - smoothstep(0.92, 1.0, around));
		float along = smoothstep(0.0, edge_soft, UV.y) * (1.0 - smoothstep(1.0 - edge_soft, 1.0, UV.y));
		mask = rim * along;
	} else {
		vec2 d = UV - vec2(0.5);
		float r = length(d) * 2.0;
		// Soft ring, not solid disc.
		float ring = smoothstep(0.35, 0.55, r) * (1.0 - smoothstep(0.85, 1.0, r));
		mask = ring;
	}
	float w = clamp(strength * intensity * mask, 0.0, 0.012);
	vec2 offset = n * w;
	vec3 col = texture(SCREEN_TEXTURE, SCREEN_UV + offset).rgb;
	ALBEDO = col;
	ALPHA = clamp(mask * intensity * cover_alpha, 0.0, 0.35);
}
