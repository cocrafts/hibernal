// The HUD's last pass (hudPost.ms): the HUD, drawn into a target at framebuffer size, averaged
// over square cells and graded towards the campfire scene, laid over it premultiplied.
@module hudPost

@vs vs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs fs
layout(binding=0) uniform texture2D hudTexture;
layout(binding=1) uniform texture2D coverageTexture;
layout(binding=0) uniform sampler hudSampler;
// grade: brightness, saturation, tint share. tint.rgb.
layout(binding=0) uniform hudPostParams {
    vec4 cell;
    vec4 grade;
    vec4 tint;
};
out vec4 fragColor;
void main() {
    if (cell.y > 0.5) {
        ivec2 size = textureSize(sampler2D(hudTexture, hudSampler), 0);
        ivec2 at = clamp(ivec2(floor((gl_FragCoord.xy + cell.zw) / cell.x)), ivec2(0), size - 1);
        vec3 rgb = texelFetch(sampler2D(hudTexture, hudSampler), at, 0).rgb;
        float alpha = texelFetch(sampler2D(coverageTexture, hudSampler), at, 0).a;
        fragColor = vec4(rgb * alpha, alpha);
        return;
    }
    if (cell.x <= 0.0) {
        fragColor = texelFetch(sampler2D(hudTexture, hudSampler), ivec2(gl_FragCoord.xy), 0);
        return;
    }
    vec2 size = vec2(textureSize(sampler2D(hudTexture, hudSampler), 0));
    vec2 corner = floor((gl_FragCoord.xy + cell.zw) / cell.x) * cell.x - cell.zw;
    // Linear taps on a 3x3 grid reach every texel of a cell up to 6 pixels wide, so a line one
    // pixel thin still lands in the average.
    float step = cell.x / 3.0;
    vec4 sum = vec4(0.0);
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 3; i++) {
            vec2 at = corner + (vec2(float(i), float(j)) + 0.5) * step;
            sum += texture(sampler2D(hudTexture, hudSampler), at / size);
        }
    }
    vec4 averaged = sum / 9.0;
    vec3 rgb = averaged.a > 0.0 ? averaged.rgb / averaged.a : vec3(0.0);
    float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
    rgb = mix(vec3(luma), rgb, grade.y) * grade.x;
    rgb = mix(rgb, rgb * tint.rgb, grade.z);
    fragColor = vec4(rgb * averaged.a, averaged.a);
}
@end

@program composite vs fs
