shader_type canvas_item;

uniform vec4 burst_color : source_color = vec4(0.8, 0.4, 1.0, 0.8);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float duration : hint_range(0.1, 3.0) = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Create expanding ring effect
    float ring_width = 0.15;
    float ring_progress = progress * 0.8;
    float ring = smoothstep(ring_progress, ring_progress + ring_width, dist);
    ring *= smoothstep(dist, dist + ring_width * 0.5, ring_progress + ring_width);
    
    // Add glow center
    float glow = 1.0 - smoothstep(0.0, 0.3 * (1.0 - progress), dist);
    
    // Combine effects
    float alpha = (ring * 0.5 + glow * 0.5) * burst_color.a * intensity;
    alpha *= (1.0 - progress); // Fade out over time
    
    COLOR = vec4(burst_color.rgb, alpha);
}

void vertex() {
    // Scale the effect based on progress
    VERTEX *= (1.0 + progress * 2.0);
}
