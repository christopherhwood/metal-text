//
//  MetalTextRenderer.swift
//  writer
//
//  Core Metal rendering engine for beautiful text display
//

import Foundation
import Metal
import MetalKit
import simd

class MetalTextRenderer: NSObject, MTKViewDelegate {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var cursorPipelineState: MTLRenderPipelineState!
    private var blurPipelineState: MTLComputePipelineState!
    
    // Buffers
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    
    // Textures
    private var glyphAtlasTexture: MTLTexture!
    private var renderTargetTexture: MTLTexture!
    
    // Display properties
    private var viewportSize: CGSize = .zero
    private var projectionMatrix: float4x4 = .identity
    
    // Animation
    private var startTime: TimeInterval = CACurrentMediaTime()
    
    // Rendering state
    private var indexCount: Int = 6 // Default for test quad
    
    // MARK: - Initialization
    
    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        super.init()
        
        metalView.device = device
        metalView.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0) // Light gray background
        metalView.colorPixelFormat = .bgra8Unorm
        
        // Enable 120Hz if available
        if #available(macOS 12.0, *) {
            metalView.preferredFramesPerSecond = 120
        } else {
            metalView.preferredFramesPerSecond = 60
        }
        
        do {
            try setupPipeline()
            setupBuffers()
            createPlaceholderTexture()
        } catch {
            print("Failed to setup Metal pipeline: \(error)")
            return nil
        }
        
        // Set initial viewport size if available
        if metalView.drawableSize.width > 0 {
            viewportSize = metalView.drawableSize
            updateProjectionMatrix()
        }
    }
    
    // MARK: - Pipeline Setup
    
    private func setupPipeline() throws {
        // Load shaders
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.libraryCreationFailed
        }
        
        // Text rendering pipeline
        let textVertexFunction = library.makeFunction(name: "textVertexShader")
        let textFragmentFunction = library.makeFunction(name: "textFragmentShader")
        
        let textPipelineDescriptor = MTLRenderPipelineDescriptor()
        textPipelineDescriptor.vertexFunction = textVertexFunction
        textPipelineDescriptor.fragmentFunction = textFragmentFunction
        textPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Enable blending for text
        textPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        textPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        textPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        textPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        textPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        textPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        textPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Configure vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2 // texCoord
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        textPipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        pipelineState = try device.makeRenderPipelineState(descriptor: textPipelineDescriptor)
        
        // Cursor pipeline
        let cursorVertexFunction = library.makeFunction(name: "cursorVertexShader")
        let cursorFragmentFunction = library.makeFunction(name: "cursorFragmentShader")
        
        let cursorPipelineDescriptor = textPipelineDescriptor.copy() as! MTLRenderPipelineDescriptor
        cursorPipelineDescriptor.vertexFunction = cursorVertexFunction
        cursorPipelineDescriptor.fragmentFunction = cursorFragmentFunction
        
        cursorPipelineState = try device.makeRenderPipelineState(descriptor: cursorPipelineDescriptor)
        
        // Blur compute pipeline
        let blurFunction = library.makeFunction(name: "gaussianBlur")
        blurPipelineState = try device.makeComputePipelineState(function: blurFunction!)
    }
    
    // MARK: - Buffer Setup
    
    private func createPlaceholderTexture() {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 256,
            height: 256,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        glyphAtlasTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // Create a simple test pattern - a black circle on white background
        let width = 256
        let height = 256
        var data = [UInt8](repeating: 255, count: width * height) // White background
        
        let centerX = width / 2
        let centerY = height / 2
        let radius = 50
        
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - centerX
                let dy = y - centerY
                let distance = sqrt(Double(dx * dx + dy * dy))
                
                if distance < Double(radius) {
                    data[y * width + x] = 0 // Black circle
                }
            }
        }
        
        glyphAtlasTexture?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &data,
            bytesPerRow: width
        )
    }
    
    private func setupBuffers() {
        // Create a simple quad for testing (will be replaced with actual text geometry)
        // For now, show a small portion of the atlas (where 'A' might be)
        let size: Float = 30.0  // Approximate glyph size
        let x: Float = -200.0   // Offset from center
        let y: Float = 100.0    // Offset from center
        
        // UV coordinates to show just a small portion of the atlas
        // These would normally come from the glyph info
        let u1: Float = 0.0
        let v1: Float = 0.0
        let u2: Float = 0.05  // Show 5% of the texture width
        let v2: Float = 0.05  // Show 5% of the texture height
        
        let vertices: [Float] = [
            // Position X, Y, Texture U, V
            x,        y,        u1, v2,  // Bottom left
            x + size, y,        u2, v2,  // Bottom right
            x + size, y + size, u2, v1,  // Top right
            x,        y + size, u1, v1   // Top left
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,  // First triangle
            2, 3, 0   // Second triangle
        ]
        
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                       length: vertices.count * MemoryLayout<Float>.size,
                                       options: [])
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                      length: indices.count * MemoryLayout<UInt16>.size,
                                      options: [])
        
        // Uniform buffer
        var uniforms = Uniforms()
        uniformBuffer = device.makeBuffer(bytes: &uniforms,
                                        length: MemoryLayout<Uniforms>.size,
                                        options: [])
    }
    
    // MARK: - MTKViewDelegate
    
    func draw(in view: MTKView) {
        // Update viewport size if needed
        if viewportSize.width == 0 && view.drawableSize.width > 0 {
            viewportSize = view.drawableSize
            updateProjectionMatrix()
        }
        
        guard viewportSize.width > 0 && viewportSize.height > 0 else {
            print("Invalid viewport size: \(viewportSize)")
            return
        }
        
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to create render encoder")
            return
        }
        
        
        // Update uniforms
        updateUniforms()
        
        // Draw text
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        if let atlas = glyphAtlasTexture {
            renderEncoder.setFragmentTexture(atlas, index: 0)
        }
        
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: indexCount,
                                          indexType: .uint16,
                                          indexBuffer: indexBuffer,
                                          indexBufferOffset: 0)
        
        // Draw cursor
        renderEncoder.setRenderPipelineState(cursorPipelineState)
        // Cursor drawing would go here
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Updates
    
    private func updateUniforms() {
        let currentTime = CACurrentMediaTime() - startTime
        
        var uniforms = Uniforms()
        uniforms.projectionMatrix = projectionMatrix
        uniforms.textColor = SIMD4<Float>(0.1, 0.1, 0.1, 1.0) // Dark gray text
        uniforms.time = Float(currentTime)
        uniforms.cursorPosition = SIMD2<Float>(0.0, 0.0)
        uniforms.cursorIntensity = 1.0
        uniforms.padding = SIMD2<Float>(0.0, 0.0)
        
        uniformBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        updateProjectionMatrix()
    }
    
    private func updateProjectionMatrix() {
        let width = Float(viewportSize.width)
        let height = Float(viewportSize.height)
        
        // Orthographic projection for 2D rendering
        projectionMatrix = float4x4(orthographicProjectionWithLeft: -width/2,
                                   right: width/2,
                                   bottom: -height/2,
                                   top: height/2,
                                   near: -1.0,
                                   far: 1.0)
    }
    
    // MARK: - Public Methods
    
    func updateGlyphAtlas(_ texture: MTLTexture) {
        glyphAtlasTexture = texture
    }
    
    func updateText(vertices: [Float], indices: [UInt16]) {
        // Create new buffers for the text geometry
        if !vertices.isEmpty {
            vertexBuffer = device.makeBuffer(bytes: vertices,
                                           length: vertices.count * MemoryLayout<Float>.size,
                                           options: [])
            
            indexBuffer = device.makeBuffer(bytes: indices,
                                          length: indices.count * MemoryLayout<UInt16>.size,
                                          options: [])
            
            indexCount = indices.count
        }
    }
}

// MARK: - Supporting Types

private struct Uniforms {
    var projectionMatrix: float4x4 = .identity
    var textColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    var time: Float = 0
    var cursorPosition: SIMD2<Float> = SIMD2<Float>(0, 0)
    var cursorIntensity: Float = 1.0
    var padding: SIMD2<Float> = SIMD2<Float>(0, 0) // Add padding to match Metal struct size
}

private enum RendererError: Error {
    case libraryCreationFailed
}

// MARK: - Matrix Extensions

extension float4x4 {
    static var identity: float4x4 {
        return float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
    
    init(orthographicProjectionWithLeft left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let width = right - left
        let height = top - bottom
        let depth = far - near
        
        self.init(columns: (
            SIMD4<Float>(2/width, 0, 0, 0),
            SIMD4<Float>(0, 2/height, 0, 0),
            SIMD4<Float>(0, 0, -2/depth, 0),
            SIMD4<Float>(-(right+left)/width, -(top+bottom)/height, -(far+near)/depth, 1)
        ))
    }
}