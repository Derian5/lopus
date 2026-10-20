shader_type canvas_item;

uniform vec2 portrait_size = vec2(172.0, 196.0);
uniform float saturation : hint_range(0.0, 1.0) = 0.68;
uniform float brightness : hint_range(0.0, 1.0) = 0.82;
uniform float dead_amount : hint_range(0.0, 1.0) = 0.0;

varying vec2 frame_uv;
varying vec4 portrait_tint;

void vertex() {
	// Atlas UVs describe the source crop; the fade belongs to the visible frame.
	frame_uv = VERTEX / max(portrait_size, vec2(1.0));
	portrait_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float color_strength = saturation * mix(1.0, 0.2, dead_amount);
	vec3 color = mix(vec3(luminance), source.rgb, color_strength);
	color *= brightness * mix(1.0, 0.65, dead_amount);
	vec2 from_center = (frame_uv - vec2(0.5)) * vec2(1.2, 0.8);
	color *= 1.0 - 0.2 * smoothstep(0.2, 0.65, length(from_center));
	float sides = smoothstep(0.0, 0.07, frame_uv.x) * (1.0 - smoothstep(0.93, 1.0, frame_uv.x));
	float top = smoothstep(0.0, 0.04, frame_uv.y);
	float bottom = 1.0 - smoothstep(0.6, 1.0, frame_uv.y);
	COLOR = vec4(color, source.a * sides * top * bottom) * portrait_tint;
}
