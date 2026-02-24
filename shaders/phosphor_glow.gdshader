shader_type canvas_item;
// CRT vector monitor phosphor glow simulation.
// Applied to a ColorRect overlaying the game SubViewport.
// Simulates the bloom/glow characteristic of vector monitor phosphor tubes.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float bloom_radius : hint_range(0.5, 8.0) = 3.0;
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float brightness : hint_range(0.5, 3.0) = 1.6;
uniform float glow_falloff : hint_range(0.5, 4.0) = 1.8;

void fragment() {
	vec4 current = texture(screen_texture, SCREEN_UV);
	vec2 ps = SCREEN_PIXEL_SIZE * bloom_radius;

	// 13-tap cross + diagonal bloom for wider glow
	vec4 bloom = current * 0.20;
	// Cardinal directions (weight 0.10 each)
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, 0.0)) * 0.10;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, 0.0)) * 0.10;
	bloom += texture(screen_texture, SCREEN_UV + vec2(0.0, ps.y)) * 0.10;
	bloom += texture(screen_texture, SCREEN_UV - vec2(0.0, ps.y)) * 0.10;
	// Diagonals (weight 0.06 each)
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, ps.y)) * 0.06;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, ps.y)) * 0.06;
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, -ps.y)) * 0.06;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, -ps.y)) * 0.06;
	// Extended cardinal (2x radius, weight 0.025 each)
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x * 2.0, 0.0)) * 0.025;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x * 2.0, 0.0)) * 0.025;
	bloom += texture(screen_texture, SCREEN_UV + vec2(0.0, ps.y * 2.0)) * 0.025;
	bloom += texture(screen_texture, SCREEN_UV - vec2(0.0, ps.y * 2.0)) * 0.025;

	// Combine: bright core + soft glow halo
	vec4 result = current * brightness + bloom * bloom_intensity;

	// Subtle color boost: vector monitors had slightly saturated phosphors
	result.rgb = pow(result.rgb, vec3(1.0 / glow_falloff));

	COLOR = vec4(result.rgb, 1.0);
}
