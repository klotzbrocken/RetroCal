import AppKit

// Standalone entry point. The calendar itself lives in MLController; this file only starts the app.
let app = NSApplication.shared
let delegate = MLAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
