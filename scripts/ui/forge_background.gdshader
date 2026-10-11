shader_type canvas_item;
// The forge behind every screen: charcoal from top to bottom, with an ember glow rising from the
// floor that breathes slowly. `pulse` 0 stills the breathing (embers off / reduced motion).

uniform vec4 top_color : source_color = vec4(0.106, 0.082, 0.071, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.051, 0.039, 0.035, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.353, 0.078, 0.35);
uniform float pulse = 1.0;

void fragment() {
	vec3 base = mix(top_color.rgb, bottom_color.rgb, UV.y);
	// An ellipse centred below the bottom edge: brightest at the floor, gone by mid-screen.
	vec2 p = vec2((UV.x - 0.5) * 1.4, (UV.y - 1.15) * 1.6);
	float glow = clamp(1.0 - length(p), 0.0, 1.0);
	// 8 s period, 10% amplitude.
	float breathe = 1.0 + 0.1 * pulse * sin(TIME * 6.2831853 / 8.0);
	base += glow_color.rgb * glow_color.a * glow * glow * breathe;
	COLOR = vec4(base, 1.0);
}
