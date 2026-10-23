shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Burning: scorched colours with a flickering orange glow (0..1).
uniform float burn_amount : hint_range(0.0, 1.0) = 0.0;
// Badly hurt: drained colours and a red heartbeat pulse (0..1).
uniform float hurt_amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_phase = 0.0;

vec3 condition_look(vec3 rgb, float alpha) {
	if (hurt_amount > 0.0) {
		float beat_t = fract(TIME * 0.95 + pulse_phase);
		float beat = exp(-pow((beat_t - 0.1) * 22.0, 2.0)) + 0.6 * exp(-pow((beat_t - 0.28) * 22.0, 2.0));
		float luma = dot(rgb, vec3(0.3, 0.59, 0.11));
		rgb = mix(rgb, vec3(luma) * vec3(0.92, 0.84, 0.84), hurt_amount * 0.4);
		rgb = mix(rgb, rgb * vec3(1.45, 0.5, 0.45), hurt_amount * (0.18 + 0.42 * beat));
	}
	if (burn_amount > 0.0) {
		float flicker = 0.7 + 0.18 * sin(TIME * 21.0 + pulse_phase * 6.0) + 0.12 * sin(TIME * 47.0 + pulse_phase * 13.0);
		rgb = mix(rgb, rgb * vec3(0.66, 0.5, 0.42), burn_amount * 0.4);
		rgb += vec3(0.2, 0.075, 0.01) * burn_amount * flicker * alpha;
	}
	return rgb;
}

void fragment() {
	vec4 canvas_modulate = COLOR;
	vec4 color = texture(TEXTURE, UV);
	float green_excess = color.g - max(color.r, color.b);
	float green_mask = smoothstep(0.05, 0.16, green_excess) * smoothstep(0.08, 0.2, color.g);
	color.a *= 1.0 - green_mask;
	color.g = min(color.g, max(color.r, color.b) + 0.04);
	color *= canvas_modulate;
	color.rgb = condition_look(color.rgb, color.a);
	color.rgb = mix(color.rgb, flash_color.rgb, flash_amount);
	COLOR = color;
}
