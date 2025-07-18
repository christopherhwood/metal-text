//
//  FontAtlasGenerator.swift
//  writer
//
//  Generates efficient GPU texture atlases from fonts using Core Text
//

import Foundation
import CoreText
import Metal
import CoreGraphics

class FontAtlasGenerator {
    
    struct GlyphInfo {
        let character: Character
        let textureRect: CGRect  // UV coordinates in atlas
        let bounds: CGRect       // Glyph bounds for positioning
        let advance: CGFloat     // How far to move for next character
        let textureExpansion: CGFloat  // Amount of padding included in texture rect
    }
    
    private let device: MTLDevice
    private let atlasSize: Int = 4096  // 4K texture for high quality
    private var glyphCache: [Character: GlyphInfo] = [:]
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func generateAtlas(for font: CTFont, characters: String? = nil) throws -> (texture: MTLTexture, glyphMap: [Character: GlyphInfo]) {
        let charactersToRender = characters ?? Self.defaultCharacterSet
        
        // Scale up the font for higher quality atlas
        let scale: CGFloat = 2.0 // Render at 2x for better quality
        let fontSize = CTFontGetSize(font)
        
        // Preserve font attributes when scaling
        let scaledFont = CTFontCreateCopyWithAttributes(font, fontSize * scale, nil, nil)
        
        // Create bitmap context for drawing
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: nil,
                                     width: atlasSize,
                                     height: atlasSize,
                                     bitsPerComponent: 8,
                                     bytesPerRow: atlasSize,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw FontAtlasError.contextCreationFailed
        }
        
        // Setup for high-quality text rendering
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        // Disable font smoothing for sharper glyphs in atlas
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        
        // Use high-quality interpolation for smoother curves
        context.interpolationQuality = .high
        
        // Set rendering intent for sharper text
        context.setRenderingIntent(.absoluteColorimetric)
        
        // Flip coordinate system for Core Text
        context.translateBy(x: 0, y: CGFloat(atlasSize))
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Clear to black background
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: atlasSize, height: atlasSize))
        
        // Pack glyphs into atlas
        var glyphMap: [Character: GlyphInfo] = [:]
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        let padding: CGFloat = 4  // Padding between glyphs to prevent bleeding and allow antialiasing
        
        for char in charactersToRender {
            let cfString = NSString(string: String(char))
            let glyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: 1)
            defer { glyphs.deallocate() }
            
            guard CTFontGetGlyphsForCharacters(scaledFont, Array(String(char).utf16) as [UniChar], glyphs, 1) else {
                continue
            }
            
            let glyph = glyphs[0]
            
            // Get glyph metrics from scaled font
            let scaledBoundingBox = CTFontGetBoundingRectsForGlyphs(scaledFont, .horizontal, [glyph], nil, 1)
            let scaledAdvance = CTFontGetAdvancesForGlyphs(scaledFont, .horizontal, [glyph], nil, 1)
            
            // Scale back down for the actual font size
            let boundingBox = CGRect(x: scaledBoundingBox.minX / scale,
                                    y: scaledBoundingBox.minY / scale,
                                    width: scaledBoundingBox.width / scale,
                                    height: scaledBoundingBox.height / scale)
            let advance = scaledAdvance / scale
            
            // Calculate size with padding (use scaled box for texture)
            let glyphWidth = ceil(scaledBoundingBox.width) + padding * 2
            let glyphHeight = ceil(scaledBoundingBox.height) + padding * 2
            
            // Move to next row if needed
            if currentX + glyphWidth > CGFloat(atlasSize) {
                currentX = 0
                currentY += rowHeight + padding
                rowHeight = 0
            }
            
            // Skip if we've run out of space
            if currentY + glyphHeight > CGFloat(atlasSize) {
                print("Warning: Font atlas full, skipping character: \(char)")
                continue
            }
            
            // Draw the glyph in white
            context.saveGState()
            context.setFillColor(CGColor(gray: 1, alpha: 1)) // White text
            
            let drawX = currentX + padding - scaledBoundingBox.minX
            let drawY = currentY + padding - scaledBoundingBox.minY
            
            var position = CGPoint(x: drawX, y: drawY)
            CTFontDrawGlyphs(scaledFont, [glyph], &position, 1, context)
            
            context.restoreGState()
            
            // Store glyph info - expand texture rect to include antialiasing
            let actualGlyphX = currentX + padding
            let actualGlyphY = currentY + padding
            let actualGlyphWidth = ceil(scaledBoundingBox.width)
            let actualGlyphHeight = ceil(scaledBoundingBox.height)
            
            // Expand texture rect by 1 pixel on each side to capture antialiasing
            let expansion: CGFloat = 1.0
            let textureRect = CGRect(x: (actualGlyphX - expansion) / CGFloat(atlasSize),
                                   y: (actualGlyphY - expansion) / CGFloat(atlasSize),
                                   width: (actualGlyphWidth + expansion * 2) / CGFloat(atlasSize),
                                   height: (actualGlyphHeight + expansion * 2) / CGFloat(atlasSize))
            
            glyphMap[char] = GlyphInfo(character: char,
                                     textureRect: textureRect,
                                     bounds: boundingBox,
                                     advance: advance,
                                     textureExpansion: expansion / scale)  // Store in unscaled units
            
            // Update position
            currentX += glyphWidth
            rowHeight = max(rowHeight, glyphHeight)
        }
        
        // Create Metal texture from bitmap
        let texture = try createMetalTexture(from: context)
        
        self.glyphCache = glyphMap
        return (texture, glyphMap)
    }
    
    private func createMetalTexture(from context: CGContext) throws -> MTLTexture {
        guard let data = context.data else {
            throw FontAtlasError.noImageData
        }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,  // Single channel for grayscale
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw FontAtlasError.textureCreationFailed
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
                       mipmapLevel: 0,
                       withBytes: data,
                       bytesPerRow: atlasSize)
        
        return texture
    }
    
    // Common characters to include in atlas
    private static let defaultCharacterSet: String = {
        var chars = ""
        
        // ASCII printable characters
        for i in 32...126 {
            chars.append(Character(UnicodeScalar(i)!))
        }
        
        // Common extended characters
        chars += "\"\"''…—–°•·×÷±≈≠≤≥"
        
        // Common accented characters
        chars += "àáâäæãåāèéêëēėęîïíīįìôöòóœøōõûüùúūñńÿýçćč"
        chars += "ÀÁÂÄÆÃÅĀÈÉÊËĒĖĘÎÏÍĪĮÌÔÖÒÓŒØŌÕÛÜÙÚŪÑŃŸÝÇĆČ"
        
        return chars
    }()
}

enum FontAtlasError: Error {
    case contextCreationFailed
    case noImageData
    case textureCreationFailed
}

// MARK: - Font Creation Helper

extension FontAtlasGenerator {
    static func createFont(name: String = "SF Pro Display", size: CGFloat = 16) -> CTFont {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        
        // Enable advanced typography features
        let features: [[CFString: Any]] = [
            [
                kCTFontFeatureTypeIdentifierKey: kTypographicExtrasType,
                kCTFontFeatureSelectorIdentifierKey: kSmartQuotesOnSelector
            ],
            [
                kCTFontFeatureTypeIdentifierKey: kLigaturesType,
                kCTFontFeatureSelectorIdentifierKey: kCommonLigaturesOnSelector
            ]
        ]
        
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFeatureSettingsAttribute: features
        ] as CFDictionary)
        
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
