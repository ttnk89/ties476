shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
    vec2 uv = SCREEN_UV;
    vec2 dir = (uv - center) * aspect;
    float dist = length(dir);
    float pull_strength = progress * 0.35;
    float falloff = 1.0 - smoothstep(0.0, 0.8, dist);
    vec2 distorted_uv = uv - normalize(uv - center) * pull_strength * falloff;
    vec4 pixel_color = texture(screen_texture, distorted_uv);
    float void_radius = progress * 1.5;
    float void_mask = smoothstep(void_radius - 0.08, void_radius, dist);
    COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), pixel_color, void_mask);
}