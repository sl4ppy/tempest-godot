shader_type canvas_item;

// WG 6100 "Tempest" Simulation with Beam Dwell & Vertex Overlap
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform float bloom_radius : hint_range(0.1, 4.0) = 1.0;
uniform float bloom_intensity : hint_range(0.0, 5.0) = 1.6;
uniform float brightness : hint_range(0.5, 5.0) = 2.0;
uniform float glow_falloff : hint_range(0.5, 4.0) = 1.5;
uniform float curvature : hint_range(0.0, 0.2) = 0.04;

// Controls the intensity of the 'Beam Dwell' (shorter lines/corners)
uniform float beam_dwell_boost : hint_range(1.0, 5.0) = 2.5;

void fragment() {
	// 1. Pincushion Distortion
	vec2 uv = SCREEN_UV;
	vec2 centered_uv = uv * 2.0 - 1.0;
	centered_uv *= 1.0 + (centered_uv.yx * centered_uv.yx) * curvature;
	uv = centered_uv * 0.5 + 0.5;

	// 2. Base Sample
	vec4 current = texture(screen_texture, uv);
	float mask = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	current *= mask;

	// 3. Beam Dwell & Overlap Logic
	// We sample 4 points further out to detect line "density".
	// If neighbors are bright, this is a corner or short line segment.
	vec2 dwell_offset = SCREEN_PIXEL_SIZE * 2.5; 
	float neighbor_density = (
		texture(screen_texture, uv + vec2(dwell_offset.x, 0.0)).r +
		texture(screen_texture, uv - vec2(dwell_offset.x, 0.0)).r +
		texture(screen_texture, uv + vec2(0.0, dwell_offset.y)).r +
		texture(screen_texture, uv - vec2(0.0, dwell_offset.y)).r
	) * 0.25;

	// Additive boost based on local density (dwell simulation)
	vec3 dwell_core = current.rgb * (1.0 + (neighbor_density * beam_dwell_boost));
	// Vertex "Hot Spot" (the sharp core overlap)
	vec3 hot_spot = pow(current.rgb, vec3(2.5)) * 5.0; 
	
	vec3 core = (dwell_core * brightness) + hot_spot;

	// 4. 13-tap Phosphor Bloom
	vec2 ps = SCREEN_PIXEL_SIZE * bloom_radius;
	vec4 bloom = current * 0.20;
	bloom += texture(screen_texture, uv + vec2(ps.x, 0.0)) * 0.10;
	bloom += texture(screen_texture, uv - vec2(ps.x, 0.0)) * 0.10;
	bloom += texture(screen_texture, uv + vec2(0.0, ps.y)) * 0.10;
	bloom += texture(screen_texture, uv - vec2(0.0, ps.y)) * 0.10;
	bloom += texture(screen_texture, uv + vec2(ps.x, ps.y)) * 0.06;
	bloom += texture(screen_texture, uv - vec2(ps.x, -ps.y)) * 0.06;
	bloom += texture(screen_texture, uv + vec2(-ps.x, ps.y)) * 0.06;
	bloom += texture(screen_texture, uv - vec2(-ps.x, -ps.y)) * 0.06;

	// 5. Final Composition & Phosphor Color Characteristic
	vec3 result = core + (bloom.rgb * bloom_intensity);
	result = pow(result, vec3(1.0 / glow_falloff));
	
	COLOR = vec4(result, 1.0);
}