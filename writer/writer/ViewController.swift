//
//  ViewController.swift
//  writer
//
//  Created by Chris on 7/18/25.
//

import Cocoa

class ViewController: NSViewController {
    
    override func mouseDown(with event: NSEvent) {
        // Check which view was clicked
        let clickPoint = view.convert(event.locationInWindow, from: nil)
        
        // Get the divider position
        let dividerPosition = splitView.subviews[0].frame.maxX
        
        // Check if click is in the right container (NSTextView side)
        if clickPoint.x > dividerPosition {
            // Make NSTextView first responder
            view.window?.makeFirstResponder(nsTextView)
            print("Made NSTextView first responder")
            
            // Forward the click to the NSTextView
            if let textViewWindow = nsTextView.window {
                let textViewPoint = nsTextView.convert(event.locationInWindow, from: nil)
                let newEvent = NSEvent.mouseEvent(
                    with: event.type,
                    location: event.locationInWindow,
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: textViewWindow.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: event.clickCount,
                    pressure: event.pressure
                )
                if let newEvent = newEvent {
                    nsTextView.mouseDown(with: newEvent)
                }
            }
        } else {
            super.mouseDown(with: event)
        }
    }
    
    private var splitView: NSSplitView!
    private var writerTextView: WriterTextView!
    private var writerTextViewExperimental: WriterTextView!
    private var nsTextView: NSTextView!
    private var scrollView: NSScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSplitView()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // Set window size when view appears
        if let window = view.window {
            window.setContentSize(NSSize(width: 1800, height: 600))
            window.center()
            
            // Set split positions after window resize
            splitView.setPosition(600, ofDividerAt: 0)
            splitView.setPosition(1200, ofDividerAt: 1)
            
            // Debug: Print responder chain
            print("Initial first responder: \(window.firstResponder)")
        }
        
        // Don't automatically make either view first responder - let user click to choose
    }
    
    private func setupSplitView() {
        // Create split view
        splitView = NSSplitView(frame: view.bounds)
        splitView.isVertical = true
        splitView.autoresizingMask = [.width, .height]
        splitView.dividerStyle = .thick
        
        // Create left container with label
        let leftContainer = NSView()
        leftContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let leftLabel = NSTextField(labelWithString: "Metal Text View (Original)")
        leftLabel.font = NSFont.boldSystemFont(ofSize: 14)
        leftLabel.textColor = .labelColor
        leftLabel.translatesAutoresizingMaskIntoConstraints = false
        leftContainer.addSubview(leftLabel)
        
        // Create writer text view
        writerTextView = WriterTextView(frame: .zero)
        writerTextView.translatesAutoresizingMaskIntoConstraints = false
        writerTextView.useExperimentalShader = false
        leftContainer.addSubview(writerTextView)
        
        // Create middle container with experimental Metal view
        let middleContainer = NSView()
        middleContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let middleLabel = NSTextField(labelWithString: "Metal Text View (LCD Experimental)")
        middleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        middleLabel.textColor = .labelColor
        middleLabel.translatesAutoresizingMaskIntoConstraints = false
        middleContainer.addSubview(middleLabel)
        
        // Create experimental writer text view
        writerTextViewExperimental = WriterTextView(frame: .zero)
        writerTextViewExperimental.translatesAutoresizingMaskIntoConstraints = false
        writerTextViewExperimental.useExperimentalShader = true
        middleContainer.addSubview(writerTextViewExperimental)
        
        // Create right container with label
        let rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let rightLabel = NSTextField(labelWithString: "NSTextView (Standard)")
        rightLabel.font = NSFont.boldSystemFont(ofSize: 14)
        rightLabel.textColor = .labelColor
        rightLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(rightLabel)
        
        // Create NSTextView with scroll view
        scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        nsTextView = NSTextView()
        nsTextView.isEditable = true
        nsTextView.isSelectable = true
        nsTextView.isRichText = false
        // Use the exact same font as our Metal view
        let textFont = NSFont(name: "SFProText-Regular", size: 48) ?? NSFont(name: "SF Pro Text", size: 48) ?? NSFont.systemFont(ofSize: 48)
        nsTextView.font = textFont
        print("NSTextView font: \(textFont.fontName), size: \(textFont.pointSize)")
        
        nsTextView.string = "Hello, World!"
        nsTextView.backgroundColor = NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        nsTextView.textColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        nsTextView.insertionPointColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        nsTextView.isAutomaticQuoteSubstitutionEnabled = false
        nsTextView.isAutomaticDashSubstitutionEnabled = false
        
        // Configure text container
        nsTextView.textContainer?.widthTracksTextView = true
        nsTextView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Set minimum size for text view
        nsTextView.minSize = NSSize(width: 0, height: 0)
        nsTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        nsTextView.isVerticallyResizable = true
        nsTextView.isHorizontallyResizable = false
        nsTextView.autoresizingMask = [.width]
        
        // Apply font to existing text
        let fullRange = NSRange(location: 0, length: nsTextView.string.count)
        nsTextView.textStorage?.addAttributes([
            .font: textFont,
            .foregroundColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        ], range: fullRange)
        
        // Set typing attributes for new text
        nsTextView.typingAttributes = [
            .font: textFont,
            .foregroundColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        ]
        
        // Match the Metal view positioning exactly
        // Metal view origin is at (-200, 0) in Metal coordinates, but scaled by 2x
        // So in view coordinates it's -100 from center
        // For proper centering, we need to account for the actual view width
        nsTextView.textContainerInset = NSSize(width: 200, height: 285)
        
        // Make sure NSTextView can become first responder
        nsTextView.importsGraphics = false
        
        scrollView.documentView = nsTextView
        rightContainer.addSubview(scrollView)
        
        // Set up constraints for left container
        NSLayoutConstraint.activate([
            leftLabel.topAnchor.constraint(equalTo: leftContainer.topAnchor, constant: 10),
            leftLabel.centerXAnchor.constraint(equalTo: leftContainer.centerXAnchor),
            
            writerTextView.topAnchor.constraint(equalTo: leftLabel.bottomAnchor, constant: 10),
            writerTextView.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            writerTextView.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            writerTextView.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor)
        ])
        
        // Set up constraints for middle container
        NSLayoutConstraint.activate([
            middleLabel.topAnchor.constraint(equalTo: middleContainer.topAnchor, constant: 10),
            middleLabel.centerXAnchor.constraint(equalTo: middleContainer.centerXAnchor),
            
            writerTextViewExperimental.topAnchor.constraint(equalTo: middleLabel.bottomAnchor, constant: 10),
            writerTextViewExperimental.leadingAnchor.constraint(equalTo: middleContainer.leadingAnchor),
            writerTextViewExperimental.trailingAnchor.constraint(equalTo: middleContainer.trailingAnchor),
            writerTextViewExperimental.bottomAnchor.constraint(equalTo: middleContainer.bottomAnchor)
        ])
        
        // Set up constraints for right container
        NSLayoutConstraint.activate([
            rightLabel.topAnchor.constraint(equalTo: rightContainer.topAnchor, constant: 10),
            rightLabel.centerXAnchor.constraint(equalTo: rightContainer.centerXAnchor),
            
            scrollView.topAnchor.constraint(equalTo: rightLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor)
        ])
        
        // Add containers to split view
        splitView.addSubview(leftContainer)
        splitView.addSubview(middleContainer)
        splitView.addSubview(rightContainer)
        
        view.addSubview(splitView)
        
        // Set minimum sizes for split view panes
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 2)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}

