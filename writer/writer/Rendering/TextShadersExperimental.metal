//
//  TextShadersExperimental.metal
//  writer
//
//  Experimental shaders for improved text rendering
//

#include <metal_stdlib>
using namespace metal;

// Copy struct definitions from main shader
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
    float2 padding;
};

// Alternative fragment shader with different anti-aliasing approaches
fragment float4 textFragmentShaderSharper(VertexOut in [[stage_in]],
                                         texture2d<float> glyphAtlas [[texture(0)]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                   min_filter::linear);
    
    float4 textSample = glyphAtlas.sample(textureSampler, in.texCoord);
    float alpha = textSample.r;
    
    // Approach 1: Step function for crisper edges
    // Adjust threshold to control weight (lower = bolder)
    const float threshold = 0.4;
    alpha = smoothstep(threshold - 0.1, threshold + 0.1, alpha);
    
    float4 color = float4(in.color.rgb * alpha, alpha);
    return color;
}

// Simulated LCD subpixel rendering (experimental)
fragment float4 textFragmentShaderLCD(VertexOut in [[stage_in]],
                                     texture2d<float> glyphAtlas [[texture(0)]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
    // Try nearest neighbor for the sharpest possible rendering
    constexpr sampler nearestSampler(mag_filter::nearest,
                                    min_filter::nearest);
    
    float4 textSample = glyphAtlas.sample(nearestSampler, in.texCoord);
    float alpha = textSample.r;
    
    // Very minimal anti-aliasing - just smooth the extremes
    if (alpha > 0.5) {
        alpha = 1.0;
    } else if (alpha > 0.1) {
        // Linear interpolation for edge pixels only
        alpha = (alpha - 0.1) / 0.4;
    } else {
        alpha = 0.0;
    }
    
    float4 color = float4(in.color.rgb * alpha, alpha);
    return color;
}