shader_type canvas_item;
uniform vec4 dust_color : source_color = vec4(1.0);
varying vec4 sprite_color;

void vertex() {
	sprite_color = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float brightness = max(source.r, max(source.g, source.b));
	float sparkle = smoothstep(0.8, 1.0, brightness) * 0.65;
	vec3 dust = mix(dust_color.rgb, vec3(1.0), sparkle) * brightness;
	COLOR = sprite_color * vec4(dust, source.a);
}
