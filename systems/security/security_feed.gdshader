// NEW 2026-11-10 (floor generation step 4e): a security monitor's screen. Shows a camera feed (or the map)
// like old security footage: grain, scan lines and a green-grey tint. `broken` shows moving static instead.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D feed : source_color, filter_linear;
uniform bool broken = false;
uniform vec3 tint : source_color = vec3(0.75, 0.95, 0.8);
uniform float grain = 0.08;
uniform float scan_lines = 140.0;
uniform float brightness = 1.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float noise = hash(uv * 400.0 + vec2(TIME * 37.0, TIME * 11.0));
	vec3 color;
	if (broken) {
		float bands = step(0.5, fract(uv.y * 6.0 - TIME * 1.7)) * 0.08;
		color = vec3(noise * 0.8 + bands);
	} else {
		color = texture(feed, uv).rgb;
		float grey = dot(color, vec3(0.299, 0.587, 0.114));
		color = mix(color, vec3(grey), 0.55) * tint * brightness;
		color += (noise - 0.5) * grain;
	}
	color *= 0.85 + 0.15 * sin(uv.y * scan_lines * 6.2832);
	ALBEDO = clamp(color, 0.0, 1.0);
}
