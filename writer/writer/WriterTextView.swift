//
//  WriterTextView.swift
//  writer
//
//  High-performance text view using Metal rendering
//

import Cocoa
import MetalKit
import CoreText

// Helper function to create fonts
private func createFont(name: String = "SF Pro Display", size: CGFloat = 16) -> CTFont {
    return CTFontCreateWithName(name as CFString, size, nil)
}

class WriterTextView: NSView, NSTextInputClient {
    
    // MARK: - Properties
    
    private var metalView: MTKView!
    private var renderer: MetalTextRenderer?
    private var fontAtlasGenerator: FontAtlasGenerator?
    
    // Text properties
    private var text: String = "" {
        didSet {
            needsTextLayout = true
            layoutText()
        }
    }
    
    private var font: CTFont = createFont(name: "SF Pro Text", size: 48)
    private var needsTextLayout = true
    private var glyphMap: [Character: FontAtlasGenerator.GlyphInfo] = [:]
    
    // Input handling
    private var insertionPoint: Int = 0
    private var isFirstResponder = false
    
    // Cursor properties
    private var cursorPosition: CGPoint = .zero
    private var showCursor = true
    private var cursorBlinkTimer: Timer?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }
    
    private func setupMetal() {
        metalView = MTKView(frame: bounds)
        metalView.autoresizingMask = [.width, .height]
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        
        addSubview(metalView)
        
        renderer = MetalTextRenderer(metalView: metalView)
        metalView.delegate = renderer
        
        if let device = metalView.device {
            fontAtlasGenerator = FontAtlasGenerator(device: device)
            generateFontAtlas()
        }
        
        // Make view focusable
        self.acceptsTouchEvents = true
    }
    
    private func generateFontAtlas() {
        guard let generator = fontAtlasGenerator else { return }
        
        do {
            let (texture, map) = try generator.generateAtlas(for: font)
            self.glyphMap = map
            // Pass texture to renderer
            renderer?.updateGlyphAtlas(texture)
            print("Generated font atlas with \(map.count) glyphs")
            
            // Debug: Check actual glyph sizes
            if let hGlyph = map["H"] {
                print("H glyph bounds: \(hGlyph.bounds)")
                print("H texture rect: \(hGlyph.textureRect)")
                print("Texture rect in pixels: x=\(hGlyph.textureRect.minX * 4096), y=\(hGlyph.textureRect.minY * 4096), w=\(hGlyph.textureRect.width * 4096), h=\(hGlyph.textureRect.height * 4096)")
            }
            
            // Layout initial text
            layoutText()
            
            // Initialize with some demo text after font atlas is ready
            // Set insertion point AFTER setting text to avoid it being reset
            text = "Hello, World!"
            insertionPoint = text.count
            
            // Force layout with correct insertion point
            layoutText()
            
            // Make sure we become first responder to show cursor
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        } catch {
            print("Failed to generate font atlas: \(error)")
        }
    }
    
    private func layoutText() {
        guard !glyphMap.isEmpty else { return }
        
        // Layout text starting from left side of screen
        let origin = CGPoint(x: -200, y: 0)
        let quads = TextLayoutEngine.layoutText(text, at: origin, with: glyphMap, font: font)
        let (vertices, indices) = TextLayoutEngine.createVertexBuffer(from: quads)
        
        // Update renderer with new text geometry
        renderer?.updateText(vertices: vertices, indices: indices)
        
        // Calculate cursor position based on insertion point
        updateCursorPosition(origin: origin)
        
        needsTextLayout = false
    }
    
    // MARK: - Text Input
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        isFirstResponder = true
        needsDisplay = true
        startCursorBlink()
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        isFirstResponder = false
        needsDisplay = true
        stopCursorBlink()
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }
    
    override func deleteBackward(_ sender: Any?) {
        guard insertionPoint > 0 else { return }
        
        let index = text.index(text.startIndex, offsetBy: insertionPoint - 1)
        text.remove(at: index)
        insertionPoint -= 1
        
        needsTextLayout = true
        layoutText()
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        // Convert point to text position
        let point = convert(event.locationInWindow, from: nil)
        // TODO: Implement hit testing to set insertion point
        
        // Make first responder
        window?.makeFirstResponder(self)
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        metalView.frame = bounds
    }
    
    // MARK: - NSTextInputClient Protocol
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let str = string as? String else { return }
        
        text.insert(contentsOf: str, at: text.index(text.startIndex, offsetBy: insertionPoint))
        insertionPoint += str.count
        
        needsTextLayout = true
        layoutText()
        
        // Reset cursor blink on typing
        showCursor = true
        renderer?.updateCursorVisibility(true)
        startCursorBlink()
    }
    
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // TODO: Implement marked text for IME support
    }
    
    func unmarkText() {
        // TODO: Implement marked text for IME support
    }
    
    func selectedRange() -> NSRange {
        return NSRange(location: insertionPoint, length: 0)
    }
    
    func markedRange() -> NSRange {
        return NSRange(location: NSNotFound, length: 0)
    }
    
    func hasMarkedText() -> Bool {
        return false
    }
    
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }
    
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }
    
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        return NSRect.zero
    }
    
    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
    
    // MARK: - Cursor Management
    
    private func startCursorBlink() {
        stopCursorBlink()
        showCursor = true
        renderer?.updateCursorVisibility(showCursor)
        
        // Blink at 120 fps means we can control precise blink timing
        // For a smooth blink, toggle every 0.5 seconds (60 frames at 120fps)
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.showCursor.toggle()
            self?.renderer?.updateCursorVisibility(self?.showCursor ?? false)
        }
    }
    
    private func stopCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
        showCursor = false
        renderer?.updateCursorVisibility(false)
    }
    
    private func updateCursorPosition(origin: CGPoint) {
        // Calculate cursor position based on text before insertion point
        var x = origin.x
        let y = origin.y
        
        // Get text up to insertion point
        let textBeforeCursor = String(text.prefix(insertionPoint))
        
        // Calculate width of text before cursor using advance width
        for char in textBeforeCursor {
            if let glyphInfo = glyphMap[char] {
                // Use advance width for proper spacing
                x += glyphInfo.advance
            }
        }
        
        cursorPosition = CGPoint(x: x, y: y)
        renderer?.updateCursorPosition(cursorPosition)
    }
}