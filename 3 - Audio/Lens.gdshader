shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float event_horizon_size : hint_range(0.0, 0.4) = 0.15;
uniform float lens_strength : hint_range(0.0, 100.0) = 25;
uniform float animation_speed : hint_range(0.0, 10.0) = 3.0; // Controls how fast it ripples/breathes

void fragment() {
    vec2 dir = UV - vec2(0.5);
    float dist = length(dir);

    if (dist < 0.5) {
        if (dist < event_horizon_size) {
            // Pure black core
            COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            // --- ADDED MOVEMENT: Pulsing event horizon & lens breathing ---
            float time_pulse = sin(TIME * animation_speed) * 0.015;
            float active_horizon = event_horizon_size + time_pulse;
            
            // --- ADDED MOVEMENT: Slow swirling rotation matrix ---
            float angle = TIME * (animation_speed * 0.5);
            float cos_a = cos(angle);
            float sin_a = sin(angle);
            mat2 rotation = mat2(vec2(cos_a, -sin_a), vec2(sin_a, cos_a));
            vec2 rotated_dir = rotation * normalize(dir);

            // Standard gravitational lens warp (using animated horizon and rotated direction)
            float denominator = dist - active_horizon + 0.02;
            float warp_force = (lens_strength * active_horizon) / denominator;
            vec2 offset = rotated_dir * warp_force * 0.1;
            
            // --- SMOOTH EDGE FALLOFF ---
            float edge_fade = smoothstep(0.5, event_horizon_size, dist);
            
            // Apply the fade to the offset so distortion vanishes smoothly at the boundary
            offset *= edge_fade;
            
            // Render the animated, feathered background
            COLOR = texture(screen_texture, SCREEN_UV + offset);
        }
    } else { 
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    }
}