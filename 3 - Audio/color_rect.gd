shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec2 dir = UV - vec2(0.5);
	float dist = length(dir);
	if (dist < 0.5) {
		float strength = 0.2; // How much space "bends"
		vec2 offset = dir * (pow(dist, 2.0) * strength);
		COLOR = texture(screen_texture, SCREEN_UV - offset);
	} else { discard; }
}
