shader_type canvas_item;

uniform vec2 player_world_pos = vec2(-9999.0, -9999.0);
uniform float fade_radius = 34.0;
uniform float min_alpha = 0.32;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex_col = texture(TEXTURE, UV) * COLOR;
	float dist = distance(world_pos, player_world_pos);
	float t = smoothstep(fade_radius * 0.45, fade_radius, dist);
	float alpha_mult = mix(min_alpha, 1.0, t);
	COLOR = vec4(tex_col.rgb, tex_col.a * alpha_mult);
}
