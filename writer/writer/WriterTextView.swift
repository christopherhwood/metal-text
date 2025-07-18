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
private func createFont(name: String = "SFProText-Regular", size: CGFloat = 16) -> CTFont {
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
    
    private var font: CTFont = createFont(name: "SFProText-Regular", size: 48)
    private var needsTextLayout = true
    private var glyphMap: [Character: FontAtlasGenerator.GlyphInfo] = [:]
    private var characterPositions: [CGFloat] = [] // Store actual character positions from layout
    
    // Input handling
    private var insertionPoint: Int = 0
    private var isFirstResponder = false
    
    // Cursor properties
    private var cursorPosition: CGPoint = .zero
    private var showCursor = true
    private var cursorBlinkTimer: Timer?
    
    // Scale factor for coordinate conversion
    private var currentScaleFactor: CGFloat {
        // Try window first, then main screen, then default to 1.0
        return window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }
    
    // Public property to control which shader to use
    var useExperimentalShader: Bool = false {
        didSet {
            renderer?.useExperimentalShader = useExperimentalShader
        }
    }
    
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
        
        // Apply experimental shader setting if it was set before renderer was created
        renderer?.useExperimentalShader = useExperimentalShader
        
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
            let fontName = CTFontCopyPostScriptName(font) as String
            print("WriterTextView font: \(fontName), size: \(CTFontGetSize(font))")
            
            // Also try to get the display name
            let displayName = CTFontCopyDisplayName(font) as String
            print("WriterTextView display name: \(displayName)")
            
            // Debug: Check actual glyph sizes
            if let hGlyph = map["H"] {
                print("H glyph bounds: \(hGlyph.bounds)")
                print("H texture rect: \(hGlyph.textureRect)")
                print("Texture rect in pixels: x=\(hGlyph.textureRect.minX * 4096), y=\(hGlyph.textureRect.minY * 4096), w=\(hGlyph.textureRect.width * 4096), h=\(hGlyph.textureRect.height * 4096)")
            }
            
            // Update cursor height based on font size and scale factor
            let fontSize = CTFontGetSize(font)
            let scaleFactor = currentScaleFactor
            let cursorHeight = Float(fontSize * scaleFactor * 1.2) // 1.2x font size for proper coverage
            renderer?.updateCursorHeight(cursorHeight)
            
            // Layout initial text
            layoutText()
            
            // Initialize with some demo text after font atlas is ready
            // Set insertion point AFTER setting text to avoid it being reset
            text = "Hello, World!"
            insertionPoint = text.count
            
            // Force layout with correct insertion point
            layoutText()
        } catch {
            print("Failed to generate font atlas: \(error)")
        }
    }
    
    private func layoutText() {
        guard !glyphMap.isEmpty else { return }
        
        // Layout text starting from left side of screen
        let scaleFactor = currentScaleFactor
        let metalOrigin = CGPoint(x: -200, y: 0)
        let viewOrigin = CGPoint(x: metalOrigin.x / scaleFactor, y: metalOrigin.y / scaleFactor)
        
        let quads = TextLayoutEngine.layoutText(text, at: metalOrigin, with: glyphMap, font: font, scaleFactor: scaleFactor)
        let (vertices, indices) = TextLayoutEngine.createVertexBuffer(from: quads)
        
        // Update renderer with new text geometry
        renderer?.updateText(vertices: vertices, indices: indices)
        
        // Store character positions for hit testing (in view coordinates)
        calculateCharacterPositions(origin: viewOrigin)
        
        // Calculate cursor position based on insertion point
        updateCursorPosition(origin: viewOrigin)
        
        needsTextLayout = false
    }
    
    private func calculateCharacterPositions(origin: CGPoint) {
        characterPositions = []
        var currentX = origin.x
        
        // Get scale factor from window or screen
        let scaleFactor = currentScaleFactor
        
        // Add position before first character
        characterPositions.append(currentX)
        
        // Calculate position after each character (advance is already in points, no need to scale)
        for char in text {
            if let glyphInfo = glyphMap[char] {
                let advance = glyphInfo.advance
                currentX += advance
                characterPositions.append(currentX)
            }
        }
    }
    
    // MARK: - Text Input
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            isFirstResponder = true
            needsDisplay = true
            startCursorBlink()
        }
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isFirstResponder = false
            needsDisplay = true
            stopCursorBlink()
        }
        return result
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
        // Only handle clicks within our bounds
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else {
            // Not our click - don't handle it
            return
        }
        
        // Calculate insertion point from click position
        let textOrigin = CGPoint(x: -200, y: 0) // Must match layoutText origin
        
        // Convert click point to Metal coordinate space
        // Metal uses center as origin, view uses top-left
        let viewCenter = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let scaleFactor = currentScaleFactor
        let metalX = point.x - viewCenter.x
        
        
        // Find which character position is closest to the click
        var newInsertionPoint = 0
        
        // Find the closest insertion point
        for (index, position) in characterPositions.enumerated() {
            if metalX < position {
                // Click is before this position
                if index > 0 {
                    // Check if click is closer to previous position
                    let prevPosition = characterPositions[index - 1]
                    let distToPrev = abs(metalX - prevPosition)
                    let distToCurrent = abs(metalX - position)
                    
                    newInsertionPoint = distToPrev < distToCurrent ? index - 1 : index
                } else {
                    newInsertionPoint = 0
                }
                break
            }
        }
        
        // If we didn't find a position, cursor goes at the end
        if metalX >= characterPositions.last ?? 0 {
            newInsertionPoint = text.count
        }
        
        // Update insertion point and cursor
        insertionPoint = min(newInsertionPoint, text.count)
        
        // Use view origin for cursor position update
        let viewOrigin = CGPoint(x: textOrigin.x / scaleFactor, y: textOrigin.y / scaleFactor)
        updateCursorPosition(origin: viewOrigin)
        
        // Reset cursor blink
        showCursor = true
        renderer?.updateCursorVisibility(true)
        startCursorBlink()
        
        // Make first responder
        window?.makeFirstResponder(self)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only return self if the point is within our bounds
        if bounds.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        metalView.frame = bounds
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Recalculate positions when moving to a different window (scale factor might change)
        if window != nil && !text.isEmpty {
            layoutText()
        }
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
        // Use stored character positions for accurate cursor placement
        let scaleFactor = currentScaleFactor
        let y = origin.y
        let x: CGFloat
        
        if insertionPoint < characterPositions.count {
            x = characterPositions[insertionPoint]
        } else if let lastPosition = characterPositions.last {
            x = lastPosition
        } else {
            x = origin.x
        }
        
        // Convert back to Metal coordinates for rendering
        let metalX = x * scaleFactor
        let metalY = y * scaleFactor
        
        cursorPosition = CGPoint(x: metalX, y: metalY)
        renderer?.updateCursorPosition(cursorPosition)
    }
}