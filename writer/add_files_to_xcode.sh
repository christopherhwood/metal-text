#!/bin/bash

# This script provides instructions for adding files to Xcode project
# Run this manually in Xcode:

echo "Please add the following files to your Xcode project manually:"
echo ""
echo "1. In Xcode, right-click on the 'writer' folder in the project navigator"
echo "2. Select 'Add Files to \"writer\"...'"
echo "3. Add these files/folders:"
echo "   - Rendering/ (entire folder)"
echo "   - TextEngine/ (entire folder)"
echo "   - WriterTextView.swift"
echo ""
echo "4. Make sure 'Copy items if needed' is unchecked"
echo "5. Make sure 'Create groups' is selected"
echo "6. Make sure 'writer' target is checked"
echo ""
echo "Also add the Metal shader file:"
echo "   - Rendering/TextShaders.metal"
echo ""
echo "After adding files, try building again with:"
echo "xcodebuild -project writer.xcodeproj -scheme writer -configuration Debug build CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO"