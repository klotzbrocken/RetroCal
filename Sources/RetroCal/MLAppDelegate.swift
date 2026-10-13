import AppKit

/// App shell for the standalone calendar: menu bar, reopen from the Dock, quit handling.
final class MLAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMenu()
        MLCustomIcon.apply()                                           // the chosen PNG, else the bundle icon
        MLController.shared.show()
    }

    /// Double-click on an .ics file or dropping it on the Dock icon.
    func application(_ sender: NSApplication, open urls: [URL]) {
        MLController.shared.show()
        MLController.shared.importICS(urls: urls.filter { $0.pathExtension.lowercased() == "ics" })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MLController.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: menu bar (FUN-13: shortcuts are shown in the menus)

    private static func makeMenu() -> NSMenu {
        let ctl = MLController.shared
        let main = NSMenu()
        func add(_ menu: NSMenu, to title: String? = nil) { let i = NSMenuItem(); i.submenu = menu; main.addItem(i) }
        func item(_ m: NSMenu, _ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, _ f: @escaping () -> Void) {
            let i = MLBlockItem(title, key: key, f); i.keyEquivalentModifierMask = mods; m.addItem(i)
        }
        func std(_ m: NSMenu, _ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = mods; m.addItem(i)
        }
        let name = L("Kalender", "Calendar")

        let app = NSMenu(title: name)
        std(app, L("Über \(name)", "About \(name)"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        item(app, L("Einstellungen…", "Settings…"), ",") { ctl.showSettings() }
        app.addItem(.separator())
        std(app, L("\(name) ausblenden", "Hide \(name)"), #selector(NSApplication.hide(_:)), "h")
        std(app, L("Andere ausblenden", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        std(app, L("Alle einblenden", "Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        std(app, L("\(name) beenden", "Quit \(name)"), #selector(NSApplication.terminate(_:)), "q")
        add(app)

        let file = NSMenu(title: L("Ablage", "File"))
        item(file, L("Neuer Termin", "New Event"), "n") { ctl.show(); ctl.newEvent() }
        item(file, L("Schnell-Termin…", "New Quick Event…"), "n", [.command, .shift]) { ctl.show(); ctl.showQuickEntry() }
        file.addItem(.separator())
        item(file, L("iCalendar importieren…", "Import iCalendar…"), "i", [.command, .shift]) { ctl.show(); ctl.importICS() }
        item(file, L("Kalender exportieren…", "Export Calendar…"), "e", [.command, .shift]) { ctl.show(); ctl.exportICS(calendar: nil) }
        file.addItem(.separator())
        std(file, L("Fenster schließen", "Close Window"), #selector(NSWindow.performClose(_:)), "w")
        add(file)

        let edit = NSMenu(title: L("Bearbeiten", "Edit"))
        std(edit, L("Widerrufen", "Undo"), Selector(("undo:")), "z")
        std(edit, L("Wiederholen", "Redo"), Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        std(edit, L("Ausschneiden", "Cut"), #selector(NSText.cut(_:)), "x")
        std(edit, L("Kopieren", "Copy"), #selector(NSText.copy(_:)), "c")
        std(edit, L("Einsetzen", "Paste"), #selector(NSText.paste(_:)), "v")
        std(edit, L("Alles auswählen", "Select All"), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, L("Termin bearbeiten", "Edit Event"), "e") { ctl.editSelected() }
        item(edit, L("Termin duplizieren", "Duplicate Event"), "d") { ctl.duplicateSelected() }
        item(edit, L("Termin löschen", "Delete Event"), "\u{8}") { ctl.deleteSelected() }
        edit.addItem(.separator())
        item(edit, L("Suchen", "Find"), "f") { ctl.focusSearch() }
        add(edit)

        let view = NSMenu(title: L("Darstellung", "View"))
        for (i, t) in [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")].enumerated() {
            item(view, t, "\(i + 1)") { ctl.setMode(MLMode(rawValue: i)!) }
        }
        view.addItem(.separator())
        item(view, L("Heute", "Today"), "t") { ctl.goToday() }
        item(view, L("Zurück", "Previous"), String(UnicodeScalar(NSLeftArrowFunctionKey)!)) { ctl.step(-1) }
        item(view, L("Vor", "Next"), String(UnicodeScalar(NSRightArrowFunctionKey)!)) { ctl.step(1) }
        view.addItem(.separator())
        item(view, L("Kalenderliste ein-/ausblenden", "Show/Hide Calendar List"), "s", [.command, .option]) { ctl.toggleSidebar() }
        std(view, L("Vollbild", "Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        add(view)

        let window = NSMenu(title: L("Fenster", "Window"))
        std(window, L("Im Dock ablegen", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        std(window, L("Zoomen", "Zoom"), #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        std(window, L("Alle nach vorne bringen", "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
        add(window)
        return main
    }
}
