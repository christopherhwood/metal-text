//
//  TextLayoutEngine.swift
//  writer
//
//  Converts text strings into vertex data for Metal rendering
//

import Foundation
import CoreGraphics
import CoreText

class TextLayoutEngine {
    
    struct TextVertex {
        let position: SIMD2<Float>
        let texCoord: SIMD2<Float>
    }
    
    struct TextQuad {
        let vertices: [TextVertex]
        let character: Character
    }
    
    static func layoutText(_ text: String, 
                          at origin: CGPoint,
                          with glyphMap: [Character: FontAtlasGenerator.GlyphInfo],
                          font: CTFont? = nil) -> [TextQuad] {
        
        var quads: [TextQuad] = []
        let baselineY = Float(origin.y)
        
        // Use Core Text to get proper glyph positions with kerning
        if let font = font {
            let attrString = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ])
            let line = CTLineCreateWithAttributedString(attrString)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            
            var currentX = Float(origin.x)
            
            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = Array<CGGlyph>(repeating: 0, count: glyphCount)
                var positions = Array<CGPoint>(repeating: .zero, count: glyphCount)
                
                CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)
                
                let runAttributes = CTRunGetAttributes(run) as! [String: Any]
                let runFont = runAttributes[kCTFontAttributeName as String] as! CTFont
                
                // Get string indices for this run
                var stringIndices = Array<CFIndex>(repeating: 0, count: glyphCount)
                CTRunGetStringIndices(run, CFRangeMake(0, glyphCount), &stringIndices)
                
                for i in 0..<glyphCount {
                    let charIndex = stringIndices[i]
                    let character = text[text.index(text.startIndex, offsetBy: charIndex)]
                    
                    guard let glyphInfo = glyphMap[character] else { continue }
                    
                    // Use the position from Core Text for proper spacing/kerning
                    let x = currentX + Float(positions[i].x) + Float(glyphInfo.bounds.minX)
                    let y = baselineY + Float(glyphInfo.bounds.minY)
                    let width = Float(glyphInfo.bounds.width)
                    let height = Float(glyphInfo.bounds.height)
                    
                    // Get texture coordinates from the glyph info
                    let u1 = Float(glyphInfo.textureRect.minX)
                    let v1 = Float(glyphInfo.textureRect.minY)
                    let u2 = Float(glyphInfo.textureRect.maxX)
                    let v2 = Float(glyphInfo.textureRect.maxY)
                    
                    // Create vertices for this character quad
                    // y is at the bottom of the glyph (baselineY + minY)
                    // We need to flip the V coordinates because texture Y=0 is at top
                    let vertices = [
                        TextVertex(position: SIMD2<Float>(x, y), 
                                  texCoord: SIMD2<Float>(u1, v1)),         // Bottom left
                        TextVertex(position: SIMD2<Float>(x + width, y), 
                                  texCoord: SIMD2<Float>(u2, v1)),         // Bottom right
                        TextVertex(position: SIMD2<Float>(x + width, y + height), 
                                  texCoord: SIMD2<Float>(u2, v2)),         // Top right
                        TextVertex(position: SIMD2<Float>(x, y + height), 
                                  texCoord: SIMD2<Float>(u1, v2))          // Top left
                    ]
                    
                    quads.append(TextQuad(vertices: vertices, character: character))
                }
            }
            
            return quads
        } else {
            // Fallback to simple layout without kerning
            var currentX = Float(origin.x)
            let characters = Array(text)
            
            for character in characters {
                guard let glyphInfo = glyphMap[character] else {
                    currentX += 10
                    continue
                }
                
                let x = currentX + Float(glyphInfo.bounds.minX)
                let y = baselineY + Float(glyphInfo.bounds.minY)
                let width = Float(glyphInfo.bounds.width)
                let height = Float(glyphInfo.bounds.height)
                
                // Get texture coordinates from the glyph info
                let u1 = Float(glyphInfo.textureRect.minX)
                let v1 = Float(glyphInfo.textureRect.minY)
                let u2 = Float(glyphInfo.textureRect.maxX)
                let v2 = Float(glyphInfo.textureRect.maxY)
                
                // Create vertices for this character quad
                let vertices = [
                    TextVertex(position: SIMD2<Float>(x, y), 
                              texCoord: SIMD2<Float>(u1, v1)),         // Bottom left
                    TextVertex(position: SIMD2<Float>(x + width, y), 
                              texCoord: SIMD2<Float>(u2, v1)),         // Bottom right
                    TextVertex(position: SIMD2<Float>(x + width, y + height), 
                              texCoord: SIMD2<Float>(u2, v2)),         // Top right
                    TextVertex(position: SIMD2<Float>(x, y + height), 
                              texCoord: SIMD2<Float>(u1, v2))          // Top left
                ]
                
                quads.append(TextQuad(vertices: vertices, character: character))
                
                // Advance to next character position
                currentX += Float(glyphInfo.advance)
            }
            
            return quads
        }
    }
    
    static func createVertexBuffer(from quads: [TextQuad]) -> ([Float], [UInt16]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        for (quadIndex, quad) in quads.enumerated() {
            let baseIndex = UInt16(quadIndex * 4)
            
            // Add vertices
            for vertex in quad.vertices {
                vertices.append(vertex.position.x)
                vertices.append(vertex.position.y)
                vertices.append(vertex.texCoord.x)
                vertices.append(vertex.texCoord.y)
            }
            
            // Add indices for two triangles
            indices.append(baseIndex + 0)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
            
            indices.append(baseIndex + 2)
            indices.append(baseIndex + 3)
            indices.append(baseIndex + 0)
        }
        
        return (vertices, indices)
    }
}