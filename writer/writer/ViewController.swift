//
//  ViewController.swift
//  writer
//
//  Created by Chris on 7/18/25.
//

import Cocoa

class ViewController: NSViewController {
    
    private var textView: WriterTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTextView()
        
        // Set a nice window size
        view.window?.setContentSize(NSSize(width: 800, height: 600))
        view.window?.center()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // Make text view first responder when view appears
        view.window?.makeFirstResponder(textView)
    }
    
    private func setupTextView() {
        textView = WriterTextView(frame: view.bounds)
        textView.autoresizingMask = [.width, .height]
        
        view.addSubview(textView)
        
        // Make text view first responder
        view.window?.makeFirstResponder(textView)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}

