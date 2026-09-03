shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float beam_arc_deg = 5.0;
uniform float fade_arc_deg = 2.0;
uniform float beam_alpha_outer = 0.45;
uniform float play_radius = 19.5;
uniform bool ring_tick = false;
uniform vec4 beam_color : source_color = vec4(0.15, 0.95, 0.7, 1.0);

varying vec3 v_local_pos;
varying vec2 v_uv;

void vertex() {
	v_local_pos = VERTEX;
	v_uv = UV;
}

void fragment() {
	if (ring_tick) {
		float along = smoothstep(0.08, 0.22, v_uv.x) * (1.0 - smoothstep(0.78, 0.92, v_uv.x));
		ALBEDO = beam_color.rgb;
		ALPHA = beam_alpha_outer * along;
		return;
	}

	vec2 xz = v_local_pos.xz;
	float half_arc = radians(beam_arc_deg) * 0.5;
	float signed_a = atan(xz.x, xz.z);
	float trail_t = (signed_a + half_arc) / max(radians(beam_arc_deg), 1e-5);
	float fade_u = clamp(fade_arc_deg / max(beam_arc_deg, 0.001), 0.15, 1.0);
	float along_angle = smoothstep(0.0, fade_u, trail_t);
	float along_uv = smoothstep(0.0, fade_u, clamp(v_uv.x, 0.0, 1.0));
	float along = max(along_angle, along_uv * 0.9);

	ALBEDO = beam_color.rgb;
	ALPHA = clamp(beam_alpha_outer * max(along, 0.35), 0.0, 1.0);
}
