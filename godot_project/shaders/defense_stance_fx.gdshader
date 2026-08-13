shader_type spatial;
// depth_draw_never: see far-side hit glow through near face (double-sided shield).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D tex_shell : source_color, hint_default_white;
uniform sampler2D tex_flow : source_color, hint_default_white;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 0.65);
uniform float scroll_speed = 0.55;
uniform float flow_mix = 0.45;
uniform float pulse = 1.0;
// Idle shell opacity multiplier (near 0 = almost invisible).
uniform float visibility = 0.04;
uniform float emission_boost = 2.2;
uniform vec2 uv_scale = vec2(2.0, 2.0);
uniform float rim_power = 2.4;
// Hit hemisphere: direction in mesh-local unit sphere space (normalize VERTEX).
uniform vec3 hit_dir_obj = vec3(0.0, 1.0, 0.0);
// 0..1 strength of the hit flash (temporal).
uniform float hit_glow = 0.0;
// Peak alpha at impact center; equator of hit hemisphere always -> 0.
uniform float hit_peak_alpha = 0.36;
// Peak emission multiplier at impact center (hand-tune, no hard cap in preview).
uniform float hit_emit_boost = 8.0;

void fragment() {
	vec2 uv = UV * uv_scale;
	uv.x += TIME * scroll_speed * 0.35;
	uv.y -= TIME * scroll_speed;
	vec4 shell = texture(tex_shell, uv);
	vec4 flow = texture(tex_flow, uv * vec2(1.6, 1.2) + vec2(TIME * 0.12, -TIME * scroll_speed * 0.5));
	vec3 rgb = mix(shell.rgb, flow.rgb, clamp(flow_mix, 0.0, 1.0)) * tint.rgb;
	// abs(N·V): same rim on both faces so back-side glow stays readable through the near shell.
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), rim_power);

	// Idle shell: barely there.
	float idle_a = max(shell.a, flow.a * flow_mix) * tint.a * pulse * clamp(visibility, 0.0, 1.0);
	idle_a = clamp(idle_a * (0.25 + fres * 0.5), 0.0, 1.0);

	// Hit hemisphere: peak at impact, adaptive fade → fully clear at equator.
	vec3 p = normalize(VERTEX);
	vec3 hd = normalize(hit_dir_obj);
	float hemi = max(dot(p, hd), 0.0);
	float peak_a = clamp(hit_peak_alpha, 0.0, 1.0);
	// Higher peak → steeper spatial fade so equator still hits exact 0.
	float fade_pow = mix(1.2, 2.6, peak_a);
	float hemi_w = pow(hemi, fade_pow);
	float glow = clamp(hit_glow, 0.0, 1.0);
	float hit_a = hemi_w * glow * peak_a;

	float a = max(idle_a, hit_a);
	float emit_hit = hit_a * max(hit_emit_boost, 0.0);
	float emit_k = max(clamp(visibility, 0.0, 1.0) * (0.35 + fres * 0.4), emit_hit);
	ALBEDO = rgb;
	EMISSION = rgb * emission_boost * emit_k;
	ALPHA = a;
}
