//
//  TextShaders.metal
//  writer
//
//  Text rendering shaders for beautiful, performant text display
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4 textColor;
    float time;
    float2 cursorPosition;
    float cursorIntensity;
    float2 padding; // Match Swift struct alignment
};

vertex VertexOut textVertexShader(VertexIn in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = uniforms.textColor;
    return out;
}

fragment float4 textFragmentShader(VertexOut in [[stage_in]],
                                  texture2d<float> glyphAtlas [[texture(0)]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                   min_filter::linear);
    
    float4 textSample = glyphAtlas.sample(textureSampler, in.texCoord);
    
    // Font atlas has white glyphs on black background
    float alpha = textSample.r;
    
    // For better anti-aliasing, apply a slight adjustment
    alpha = smoothstep(0.0, 1.0, alpha);
    
    // Apply text color with premultiplied alpha
    float4 color = float4(in.color.rgb * alpha, alpha);
    
    return color;
}

// Cursor rendering
vertex VertexOut cursorVertexShader(VertexIn in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Position cursor at text insertion point
    float2 position = in.position + uniforms.cursorPosition;
    
    out.position = uniforms.projectionMatrix * float4(position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = uniforms.textColor;
    return out;
}

fragment float4 cursorFragmentShader(VertexOut in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    // Simple solid cursor with slight fade at edges
    float alpha = uniforms.cursorIntensity;
    
    // Fade edges slightly for anti-aliasing
    float edgeFade = smoothstep(0.0, 0.1, in.texCoord.x) * 
                     smoothstep(1.0, 0.9, in.texCoord.x) *
                     smoothstep(0.0, 0.05, in.texCoord.y) * 
                     smoothstep(1.0, 0.95, in.texCoord.y);
    
    alpha *= edgeFade;
    
    // Use text color for cursor
    return float4(uniforms.textColor.rgb * alpha, alpha);
}

// Background blur for focus mode
kernel void gaussianBlur(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        constant float &blurRadius [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    
    const int kernelSize = 9;
    const float weights[9] = {
        0.000229, 0.005977, 0.060598, 0.241732, 0.382928,
        0.241732, 0.060598, 0.005977, 0.000229
    };
    
    float4 color = float4(0.0);
    
    for (int i = -4; i <= 4; i++) {
        uint2 samplePos = uint2(gid.x + i, gid.y);
        if (samplePos.x < inTexture.get_width()) {
            color += inTexture.read(samplePos) * weights[i + 4];
        }
    }
    
    outTexture.write(color, gid);
}