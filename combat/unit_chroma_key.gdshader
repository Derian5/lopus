shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 canvas_modulate = COLOR;
	vec4 color = texture(TEXTURE, UV);
	float green_excess = color.g - max(color.r, color.b);
	float green_mask = smoothstep(0.05, 0.16, green_excess) * smoothstep(0.08, 0.2, color.g);
	color.a *= 1.0 - green_mask;
	color.g = min(color.g, max(color.r, color.b) + 0.04);
	color *= canvas_modulate;
	color.rgb = mix(color.rgb, flash_color.rgb, flash_amount);
	COLOR = color;
}
