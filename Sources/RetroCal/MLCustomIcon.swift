import AppKit

/// User-chosen app icon: a PNG of exactly 256 × 256 px. The file is copied to Application Support, loaded at launch and shown
/// as the Dock icon while RetroCal runs (the icon of the app file in Finder stays the built-in one).
enum MLCustomIcon {
    static let size = 256

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroCal")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("AppIcon.png")
    }

    static var isSet: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// nil = fine, otherwise the reason in the user's language.
    static func validate(_ data: Data) -> String? {
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            return L("Das ist keine PNG-Datei.", "This is not a PNG file.")
        }
        guard let rep = NSBitmapImageRep(data: data) else { return L("Die PNG-Datei lässt sich nicht lesen.", "The PNG file cannot be read.") }
        guard rep.pixelsWide == size, rep.pixelsHigh == size else {
            return L("Das Bild ist \(rep.pixelsWide) × \(rep.pixelsHigh) Pixel groß, erwartet sind genau \(size) × \(size).",
                     "The image is \(rep.pixelsWide) × \(rep.pixelsHigh) px; exactly \(size) × \(size) is required.")
        }
        return nil
    }

    /// Validates, stores and applies. Returns an error message or nil.
    @discardableResult
    static func set(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return L("Die Datei lässt sich nicht lesen.", "The file cannot be read.") }
        if let e = validate(data) { return e }
        do { try data.write(to: fileURL, options: .atomic) } catch { return L("Speichern fehlgeschlagen: ", "Saving failed: ") + error.localizedDescription }
        apply()
        return nil
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        apply()
    }

    /// Dock icon: the chosen PNG, or (nil) the one from the app bundle. A broken stored file is ignored.
    static func apply() {
        let app = NSApplication.shared
        if isSet, let data = try? Data(contentsOf: fileURL), validate(data) == nil, let img = NSImage(data: data) {
            app.applicationIconImage = img
        } else {
            app.applicationIconImage = nil
        }
    }

    /// What the settings preview shows.
    static var current: NSImage {
        _ = NSApplication.shared
        if isSet, let d = try? Data(contentsOf: fileURL), validate(d) == nil, let i = NSImage(data: d) { return i }
        return NSImage(named: "NSApplicationIcon") ?? NSApp?.applicationIconImage ?? NSImage()
    }
}
