shader_type canvas_item;
// CRT vector monitor phosphor simulation.
// Apply to a TextureRect overlaying the game SubViewport.
// See crt-shader-notes.md in project memory for design rationale.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float bloom_radius : hint_range(0.5, 6.0) = 2.5;
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.4;
uniform float persistence : hint_range(0.0, 0.95) = 0.82;
uniform float brightness : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	vec4 current = texture(screen_texture, SCREEN_UV);

	// 9-tap gaussian bloom approximation
	vec2 ps = SCREEN_PIXEL_SIZE * bloom_radius;
	vec4 bloom = current * 0.25;
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, 0.0)) * 0.125;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, 0.0)) * 0.125;
	bloom += texture(screen_texture, SCREEN_UV + vec2(0.0, ps.y)) * 0.125;
	bloom += texture(screen_texture, SCREEN_UV - vec2(0.0, ps.y)) * 0.125;
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, ps.y)) * 0.0625;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, ps.y)) * 0.0625;
	bloom += texture(screen_texture, SCREEN_UV + vec2(ps.x, -ps.y)) * 0.0625;
	bloom += texture(screen_texture, SCREEN_UV - vec2(ps.x, -ps.y)) * 0.0625;

	vec4 result = current * brightness + bloom * bloom_intensity;
	COLOR = result;
}
