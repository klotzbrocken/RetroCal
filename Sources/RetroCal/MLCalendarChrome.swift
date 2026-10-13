import AppKit

// Leather header (traffic lights, title, Calendars / +, Day-Week-Month-Year, search) and the sidebar.

// MARK: - Search field

/// Text cell that centres its line vertically, so text, caret and selection sit on the pill's centre line.
final class MLCenteredCell: NSTextFieldCell {
    private func centred(_ r: NSRect) -> NSRect {
        let h = ceil((font?.ascender ?? 10) - (font?.descender ?? -3) + (font?.leading ?? 0))
        var n = r; n.origin.y += (r.height - h) / 2; n.size.height = h; return n
    }
    override func select(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, start: Int, length: Int) { super.select(withFrame: centred(r), in: v, editor: editor, delegate: d, start: start, length: length) }
    override func edit(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, event: NSEvent?) { super.edit(withFrame: centred(r), in: v, editor: editor, delegate: d, event: event) }
}

final class MLSearchField: NSView {
    unowned var ctl: MLController
    let field: NSTextField = { let f = NSTextField(); return f }()

    init(_ ctl: MLController) {
        self.ctl = ctl
        super.init(frame: .zero)
        field.isBordered = false
        field.isEditable = true            // a replaced cell is read-only by default
        field.isSelectable = true
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = mlFont(11)
        field.delegate = ctl
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(L("Suchen", "Search"))
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var focused: Bool { (window?.firstResponder as? NSTextView)?.delegate === field }

    override func layout() {
        super.layout()
        let fh = ceil(field.font.map { $0.ascender - $0.descender + $0.leading } ?? 12) + 2
        field.frame = NSRect(x: 19, y: ((bounds.height - fh) / 2).rounded(), width: bounds.width - 19 - 17, height: fh)   // one line, centred: text and caret share the pill's centre line
    }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        mlRGB(255, 255, 255).setFill(); pill.fill()
        NSGraphicsContext.saveGraphicsState(); pill.addClip()
        mlRGB(0, 0, 0, 0.18).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1.5).fill()   // inner top shadow
        NSGraphicsContext.restoreGraphicsState()
        (focused ? mlRGB(61, 120, 178) : mlRGB(104, 78, 36)).setStroke()
        pill.lineWidth = focused ? 2 : 1
        pill.stroke()
        // magnifier
        let c = NSPoint(x: 11.5, y: bounds.midY - 1)
        mlRGB(40, 40, 40).setStroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)); lens.lineWidth = 1.2; lens.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: c.x + 2.6, y: c.y + 2.6)); h.line(to: NSPoint(x: c.x + 5.4, y: c.y + 5.4)); h.lineWidth = 1.6; h.stroke()
        // clear button
        if !field.stringValue.isEmpty {
            let x = NSRect(x: bounds.width - 15, y: bounds.midY - 5, width: 10, height: 10)
            mlRGB(150, 150, 150).setFill(); NSBezierPath(ovalIn: x).fill()
            let g = NSBezierPath()
            g.move(to: NSPoint(x: x.minX + 3, y: x.minY + 3)); g.line(to: NSPoint(x: x.maxX - 3, y: x.maxY - 3))
            g.move(to: NSPoint(x: x.maxX - 3, y: x.minY + 3)); g.line(to: NSPoint(x: x.minX + 3, y: x.maxY - 3))
            NSColor.white.setStroke(); g.lineWidth = 1.3; g.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if !field.stringValue.isEmpty, p.x > bounds.width - 18 { ctl.clearSearch() } else { ctl.focusSearch() }
        needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
    override func isAccessibilityElement() -> Bool { false }
}

// MARK: - Header

final class MLHeaderView: MLView {
    /// The header view reaches 4 units below the leather bar so the paper wisps can overlap the content area.
    static let height: CGFloat = 47
    static let chromeH: CGFloat = 39
    private(set) var plusRect = NSRect.zero
    private var hover: Int?              // 0…2 traffic lights
    private var pressed: String?
    private var groupHover = false

    override init(_ ctl: MLController) {
        super.init(ctl)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    /// The wisps overlap the content area; clicks there belong to the views underneath.
    override func hitTest(_ p: NSPoint) -> NSView? { p.y > Self.chromeH ? nil : super.hitTest(p) }

    private var lightCenters: [NSPoint] { (0..<3).map { NSPoint(x: 9 + CGFloat($0) * 13.4, y: 8) } }
    private var calendarsRect: NSRect { NSRect(x: 5, y: 16, width: 48, height: 15) }
    private var segW: CGFloat { 42 }
    private var segRect: NSRect { NSRect(x: (bounds.width / 2 - segW * 2).rounded(), y: 16, width: segW * 4, height: 15) }

    override func layout() {
        super.layout()
        let w: CGFloat = 130
        ctl.searchField.frame = NSRect(x: bounds.width - w - 7, y: 15.5, width: w, height: 16)
    }

    override func draw(_ dirty: NSRect) {
        hots = []
        let w = bounds.width
        MLLeather.fill(NSRect(x: 0, y: 0, width: w, height: 35))
        MLLeather.bar(width: w, y: 35)
        MLLeather.wisps(width: w, y: 35 + MLLeather.barHeight - 0.7)
        drawResizeGlyph(w)

        // title
        let title = L("Kalender", "Calendar")
        mlText(title, NSRect(x: 0, y: 1, width: w, height: 14), mlFont(13), mlRGB(48, 36, 18, ctl.isActive ? 1 : 0.55), align: .center,
               shadow: mlRGB(255, 240, 200, 0.6))

        // Calendars / +
        plusRect = NSRect(x: 59, y: 16, width: 18, height: 15)
        button(calendarsRect, L("Kalender", "Calendars"), on: false, key: "cal")
        button(plusRect, "+", on: false, key: "plus", font: mlFont(17))
        hots.append(MLHot(rect: calendarsRect, label: L("Kalenderliste ein-/ausblenden", "Show or hide calendar list")) { [weak self] in self?.ctl.toggleSidebar() })
        hots.append(MLHot(rect: plusRect, label: L("Neuer Termin (Schnelleingabe)", "New event (quick entry)")) { [weak self] in self?.ctl.showQuickEntry() })

        // Day / Week / Month / Year: one recessed group with dividers (reference crop: 3-unit corners, dark brown outline)
        let names = [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")]
        let g = segRect
        let outline = NSBezierPath(roundedRect: g.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState(); outline.addClip()
        for i in 0..<4 {
            let r = NSRect(x: g.minX + CGFloat(i) * segW, y: g.minY, width: segW, height: g.height)
            if ctl.mode.rawValue == i {
                mlGradient(r, [(0, mlRGB(104, 76, 40)), (1, mlRGB(132, 100, 58))])
                mlRGB(48, 30, 12, 0.55).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
            } else {
                Self.recessFill(r, pressed: pressed == "seg\(i)")
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        for i in 1..<4 where ctl.mode.rawValue != i && ctl.mode.rawValue != i - 1 {
            let x = g.minX + CGFloat(i) * segW
            mlRGB(132, 94, 50).setFill(); NSRect(x: x, y: g.minY + 3, width: 1, height: g.height - 6).fill()
            mlRGB(255, 232, 186, 0.45).setFill(); NSRect(x: x + 1, y: g.minY + 3, width: 0.7, height: g.height - 6).fill()
        }
        if ctl.mode.rawValue > 0 { let x = g.minX + CGFloat(ctl.mode.rawValue) * segW; mlRGB(86, 60, 30).setFill(); NSRect(x: x, y: g.minY, width: 1, height: g.height).fill() }
        if ctl.mode.rawValue < 3 { let x = g.minX + CGFloat(ctl.mode.rawValue + 1) * segW; mlRGB(86, 60, 30).setFill(); NSRect(x: x - 0.5, y: g.minY, width: 1, height: g.height).fill() }
        mlRGB(255, 232, 186, 0.4).setFill(); NSRect(x: g.minX + 2, y: g.maxY, width: g.width - 4, height: 0.8).fill()      // light lip under the group
        mlRGB(86, 60, 30).setStroke(); outline.lineWidth = 1; outline.stroke()
        for i in 0..<4 {
            let r = NSRect(x: g.minX + CGFloat(i) * segW, y: g.minY, width: segW, height: g.height)
            let on = ctl.mode.rawValue == i
            mlText(names[i], r, mlFont(11.4, bold: on), on ? .white : mlRGB(40, 24, 8), align: .center, shadow: on ? mlRGB(0, 0, 0, 0.55) : mlRGB(255, 232, 186, 0.4))
            hots.append(MLHot(rect: r, label: names[i], role: .radioButton) { [weak self] in self?.ctl.setMode(MLMode(rawValue: i)!) })
        }
    }

    /// Leather seen through a shallow recess: lighter at the top, darker toward a ridge at the bottom.
    static func recessFill(_ r: NSRect, pressed: Bool) {
        mlGradient(r, [(0, mlRGB(255, 240, 200, pressed ? 0.04 : 0.16)), (0.5, mlRGB(255, 240, 200, 0)), (1, mlRGB(70, 44, 12, pressed ? 0.30 : 0.14))])
        mlRGB(255, 240, 200, 0.4).setFill(); NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 1).fill()
        mlRGB(100, 68, 30, 0.45).setFill(); NSRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 1).fill()
    }

    /// Full-screen / resize glyph in the top-right corner (two small corner arrows).
    private var resizeRect: NSRect { NSRect(x: bounds.width - 14.5, y: 4, width: 8.5, height: 8.5) }
    /// Full-screen symbol: two compact arrowheads facing away from each other (↗ top right, ↙ bottom left) with a gap in between,
    /// dark brown with a light lip. Drawn as a vector so it is sharp at every scale.
    private func drawResizeGlyph(_ w: CGFloat) {
        let r = resizeRect
        func draw(_ dy: CGFloat, _ c: NSColor) {
            c.setFill()
            let L: CGFloat = 4.1
            let ne = NSBezierPath()                                              // right angle in the top-right corner
            ne.move(to: NSPoint(x: r.maxX, y: r.minY + dy)); ne.line(to: NSPoint(x: r.maxX - L, y: r.minY + dy)); ne.line(to: NSPoint(x: r.maxX, y: r.minY + L + dy)); ne.close()
            let sw = NSBezierPath()                                              // right angle in the bottom-left corner
            sw.move(to: NSPoint(x: r.minX, y: r.maxY + dy)); sw.line(to: NSPoint(x: r.minX + L, y: r.maxY + dy)); sw.line(to: NSPoint(x: r.minX, y: r.maxY - L + dy)); sw.close()
            ne.fill(); sw.fill()
            c.setStroke()
            for (p0, p1) in [(NSPoint(x: r.maxX - L * 0.45, y: r.minY + L * 0.45 + dy), NSPoint(x: r.midX + 0.9, y: r.midY - 0.9 + dy)),
                             (NSPoint(x: r.minX + L * 0.45, y: r.maxY - L * 0.45 + dy), NSPoint(x: r.midX - 0.9, y: r.midY + 0.9 + dy))] {
                let st = NSBezierPath(); st.lineWidth = 1.5; st.lineCapStyle = .butt; st.move(to: p0); st.line(to: p1); st.stroke()   // short stubs towards the centre
            }
        }
        draw(0.6, mlRGB(255, 232, 186, 0.5))
        draw(0, mlRGB(96, 68, 30, 0.92))
        hots.append(MLHot(rect: r.insetBy(dx: -3, dy: -3), label: L("Vollbild", "Full screen")) { [weak self] in self?.window?.toggleFullScreen(nil) })
    }

    private func button(_ r: NSRect, _ t: String, on: Bool, key: String, font: NSFont = mlFont(11.4)) {
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        Self.recessFill(r, pressed: pressed == key)
        NSGraphicsContext.restoreGraphicsState()
        mlRGB(255, 232, 186, 0.4).setFill(); NSRect(x: r.minX + 2, y: r.maxY, width: r.width - 4, height: 0.8).fill()
        mlRGB(86, 60, 30).setStroke(); path.lineWidth = 1; path.stroke()
        mlText(t, r, font, mlRGB(40, 24, 8), align: .center, shadow: mlRGB(255, 232, 186, 0.4))
    }

    private func segment(_ r: NSRect, _ t: String, on: Bool, first: Bool, last: Bool, key: String) {
        let down = pressed == key
        let rad: CGFloat = 4
        let path = NSBezierPath()
        let rr = r.insetBy(dx: 0.5, dy: 0.5)
        if first && last { path.appendRoundedRect(rr, xRadius: rad, yRadius: rad) } else {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: NSRect(x: first ? rr.minX : rr.minX - rad, y: rr.minY, width: rr.width + (first || last ? rad : 2 * rad), height: rr.height), xRadius: rad, yRadius: rad).addClip()
            path.appendRect(rr)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: first ? r.minX : r.minX - rad, y: r.minY, width: r.width + (first || last ? rad : 2 * rad), height: r.height), xRadius: rad, yRadius: rad).addClip()
        if on {
            mlGradient(r, [(0, mlRGB(104, 72, 30)), (1, mlRGB(138, 100, 48))])
            mlRGB(0, 0, 0, 0.35).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
        } else {
            let k: CGFloat = down ? 0.25 : 0
            mlGradient(r, [(0, mlMix(mlRGB(205, 168, 108), .black, k)), (1, mlMix(mlRGB(190, 152, 92), .black, k))])
            mlRGB(255, 236, 190, 0.45).setFill(); NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        // outline: the group is one rounded rect, with dividers between segments
        mlRGB(110, 76, 16).setFill()
        if first { NSRect(x: r.minX, y: r.minY + 2, width: 1, height: r.height - 4).fill() }
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        mlText(t, r, mlFont(13.2, bold: on), on ? .white : .black, align: .center,
               shadow: on ? mlRGB(0, 0, 0, 0.5) : mlRGB(255, 235, 190, 0.5))
    }

    // MARK: mouse

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let g = NSRect(x: 4, y: 1, width: 50, height: 16).contains(p)
        if g != groupHover { groupHover = g; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { groupHover = false; needsDisplay = true }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let h = hot(at: p) else { super.mouseDown(with: e); return }
        // Highlight while the button is held; fire on release inside (like an NSButton).
        let key = h.label
        pressed = h.role == .radioButton ? nil : key
        needsDisplay = true
        var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = h.rect.contains(convert(ev.locationInWindow, from: nil))
            if ev.type == .leftMouseUp { break }
        }
        pressed = nil; needsDisplay = true
        if inside { h.action() }
    }
}

// MARK: - Sidebar

final class MLSidebarView: MLView {
    static let width: CGFloat = 109.5     // reference: 164 px sidebar at 1.5 px per unit
    private var pressedDay: Date?
    private let palette: [UInt32] = [0xD9432B, 0xF08A24, 0xE8C21A, 0x4DA83B, 0x2F6FD6, 0x8A4FC0, 0x8F6B3F]

    override func draw(_ dirty: NSRect) {
        hots = []; localRows = []; sysRows = []
        let w = bounds.width
        mlRGB(245, 245, 245).setFill(); bounds.fill()
        mlLine(NSRect(x: w - 1, y: 0, width: 1, height: bounds.height), mlRGB(190, 190, 190))

        let miniH = 14 + 12 + CGFloat(miniWeeks(ctl.cal.dateInterval(of: .month, for: ctl.date)!.start)) * 16 + 6
        let listBottom = bounds.height - miniH - 4
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: listBottom)).addClip()
        var y: CGFloat = 8 - listScroll
        section(L("Auf meinem Mac", "On My Mac"), ctl.store.calendars, system: false, y: &y)
        let add = NSRect(x: 0, y: y, width: w - 1, height: 14)
        mlText("+ " + L("Neuer Kalender…", "New Calendar…"), NSRect(x: 10, y: y, width: w - 14, height: 14), mlFont(10.4), mlRGB(130, 130, 130))
        hots.append(MLHot(rect: add, label: L("Neuer Kalender", "New Calendar")) { [weak self] in self?.newCalendar() })
        y += 18
        if !MLSystem.shared.isActive {
            let r = NSRect(x: 0, y: y, width: w - 1, height: 14)
            let denied = MLSystem.shared.enabled && MLSystem.shared.status != .notDetermined
            mlText("+ " + (denied ? L("Zugriff erlauben…", "Allow Access…") : L("Systemkalender…", "System Calendars…")),
                   NSRect(x: 10, y: y, width: w - 14, height: 14), mlFont(10.4), mlRGB(130, 130, 130))
            hots.append(MLHot(rect: r, label: L("Systemkalender verbinden", "Connect system calendars")) { [weak self] in
                if denied { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
                else { MLSystem.shared.setEnabled(true) { self?.ctl.refresh() } }
            })
            y += 18
        }
        if MLSystem.shared.isActive {
            var groups: [(String, [MLCal])] = []
            for c in MLSystem.shared.calendars {
                let g = c.group ?? L("Systemkalender", "System Calendars")
                if let i = groups.firstIndex(where: { $0.0 == g }) { groups[i].1.append(c) } else { groups.append((g, [c])) }
            }
            groups.sort { ($0.0 == "\u{1}subs" ? 1 : 0) < ($1.0 == "\u{1}subs" ? 1 : 0) }
            for (title, cals) in groups { section(title == "\u{1}subs" ? L("Abonnements", "Subscriptions") : title, cals, system: true, y: &y) }
        }
        listContentH = y + listScroll + 8
        NSGraphicsContext.restoreGraphicsState()
        hots.removeAll { $0.rect.maxY > listBottom && $0.rect.minY >= listBottom - 1 }
        // one mini month, pinned to the bottom of the sidebar (as in the reference)
        let month = ctl.cal.dateInterval(of: .month, for: ctl.date)!.start
        let h = 14 + 12 + CGFloat(miniWeeks(month)) * 16 + 6
        drawMini(month, y: max(y + 6, bounds.height - h), withArrows: true)
    }

    private let rowH: CGFloat = 14
    private var listScroll: CGFloat = 0
    private var listContentH: CGFloat = 0
    override func scrollWheel(with e: NSEvent) {
        let miniH: CGFloat = 14 + 12 + 6 * 16 + 6
        let maxScroll = max(0, listContentH - (bounds.height - miniH - 4))
        listScroll = min(max(0, listScroll - e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 8) / MLRootView.scale), maxScroll)
        needsDisplay = true
    }
    private var localRows: [(NSRect, MLCal)] = []
    private var sysRows: [(NSRect, MLCal)] = []

    /// Account heading and its calendars, like the reference: grey heading, tinted checkbox when visible, grey when hidden.
    private func section(_ title: String, _ cals: [MLCal], system: Bool, y: inout CGFloat) {
        let w = bounds.width
        guard !cals.isEmpty || !system else { return }
        mlText(title, NSRect(x: 7, y: y, width: w - 12, height: 13), mlFont(10, bold: true), mlRGB(150, 150, 150))
        y += 14
        for c in cals {
            let selected = ctl.defaultCalID == c.id
            if selected {
                let row = NSRect(x: 0, y: y, width: w - 1, height: rowH)
                mlGradient(row, [(0, mlRGB(168, 180, 198)), (1, mlRGB(132, 148, 170))])
                mlRGB(100, 112, 134).setFill(); NSRect(x: 0, y: row.minY, width: row.width, height: 1).fill()
            }
            if system { sysRows.append((NSRect(x: 0, y: y, width: w, height: rowH), c)) } else { localRows.append((NSRect(x: 0, y: y, width: w, height: rowH), c)) }
            checkbox(NSRect(x: 12, y: y + 2.5, width: 9, height: 9), on: c.visible, tint: c.color)
            mlText(c.name + (c.readOnly ? " 🔒" : ""), NSRect(x: 26, y: y, width: w - 30, height: rowH), mlFont(11, bold: selected),
                   selected ? .white : mlRGB(30, 30, 30), shadow: selected ? mlRGB(0, 0, 0, 0.35) : nil)
            hots.append(MLHot(rect: NSRect(x: 6, y: y, width: 18, height: rowH), label: "\(c.name), " + L("sichtbar", "visible"), role: .checkBox) { [weak self] in
                if system { MLSystem.shared.toggle(c.id) } else { var n = c; n.visible.toggle(); self?.ctl.store.updateCalendar(n) }
            })
            if !c.readOnly {
                hots.append(MLHot(rect: NSRect(x: 24, y: y, width: w - 25, height: rowH), label: c.name, role: .row) { [weak self] in
                    self?.ctl.defaultCalID = c.id; self?.needsDisplay = true
                })
            }
            y += rowH
        }
        y += 4
    }

    /// Reference style (measured on the 2012 screenshot): the box always carries the calendar's normal, pastel tone
    /// (calendar colour about half-way to white); a black check marks a visible calendar.
    private func checkbox(_ r: NSRect, on: Bool, tint: NSColor) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.2, yRadius: 2.2)
        mlGradient(r, [(0, mlMix(tint, .white, 0.62)), (1, mlMix(tint, .white, 0.38))], radius: 2.2)
        mlMix(tint, .black, 0.28).setStroke(); p.lineWidth = 1; p.stroke()
        if on {
            let c = NSBezierPath()
            c.move(to: NSPoint(x: r.minX + 1.8, y: r.midY + 0.3)); c.line(to: NSPoint(x: r.minX + 3.8, y: r.maxY - 1.8)); c.line(to: NSPoint(x: r.maxX - 1.0, y: r.minY + 0.4))
            mlRGB(10, 10, 12).setStroke(); c.lineWidth = 1.5; c.lineCapStyle = .round; c.lineJoinStyle = .round; c.stroke()
        }
    }

    private func miniWeeks(_ first: Date) -> Int {
        let cal = ctl.cal
        let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return (off + cal.range(of: .day, in: .month, for: first)!.count + 6) / 7
    }

    private func drawMini(_ first: Date, y: CGFloat, withArrows: Bool) {
        let cal = ctl.cal
        let w = bounds.width
        let cw: CGFloat = 14, x0 = (w - cw * 7) / 2
        mlText(MLPrefs.fmt(first, "yMMMM"), NSRect(x: 0, y: y, width: w - 1, height: 14), mlFont(11, bold: true), mlRGB(120, 120, 120), align: .center)
        if withArrows {
            for (dir, x) in [(-1, CGFloat(8)), (1, w - 16)] {
                let tri = NSBezierPath()
                if dir < 0 { tri.move(to: NSPoint(x: x + 4, y: y + 3.5)); tri.line(to: NSPoint(x: x + 4, y: y + 10.5)); tri.line(to: NSPoint(x: x, y: y + 7)) }
                else { tri.move(to: NSPoint(x: x, y: y + 3.5)); tri.line(to: NSPoint(x: x, y: y + 10.5)); tri.line(to: NSPoint(x: x + 4, y: y + 7)) }
                tri.close(); mlRGB(110, 110, 110).setFill(); tri.fill()
                hots.append(MLHot(rect: NSRect(x: x - 3, y: y, width: 12, height: 14), label: dir < 0 ? L("Vorheriger Monat", "Previous month") : L("Nächster Monat", "Next month")) { [weak self] in
                    guard let s = self else { return }
                    s.ctl.date = cal.date(byAdding: .month, value: dir, to: s.ctl.date)!; s.ctl.refresh()
                })
            }
        }
        // weekday initials
        let sym = cal.veryShortStandaloneWeekdaySymbols, short = cal.shortStandaloneWeekdaySymbols
        for i in 0..<7 {
            let wd = (cal.firstWeekday - 1 + i) % 7
            let t = MLPrefs.isDE ? String(short[wd].prefix(2)) : String(short[wd].prefix(2))
            _ = sym
            mlText(t, NSRect(x: x0 + CGFloat(i) * cw, y: y + 13, width: cw, height: 11), mlFont(9.5, bold: true), mlRGB(140, 140, 140), align: .center)
        }
        mlLine(NSRect(x: x0 - 2, y: y + 24, width: cw * 7 + 4, height: 1), mlRGB(215, 215, 215))
        let off = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -off, to: first)!
        let thisMonth = cal.component(.month, from: first)
        for i in 0..<(miniWeeks(first) * 7) {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let r = NSRect(x: x0 + CGFloat(i % 7) * cw, y: y + 26 + CGFloat(i / 7) * 16, width: cw, height: 16)
            let isToday = cal.isDate(d, inSameDayAs: ctl.today), sel = cal.isDate(d, inSameDayAs: ctl.date)
            let inMonth = cal.component(.month, from: d) == thisMonth
            if sel {
                mlRGB(70, 130, 215, isToday ? 1 : 0.22).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            }
            let col: NSColor = isToday ? (sel ? .white : mlRGB(20, 100, 220)) : inMonth ? mlRGB(105, 105, 105) : mlRGB(195, 195, 195)
            mlText("\(cal.component(.day, from: d))", r, mlFont(10.4, bold: isToday), col, align: .center)
            hots.append(MLHot(rect: r, label: MLPrefs.fmt(d, "yMMMMEEEEd"), role: .button) { [weak self] in self?.ctl.select(date: d) })
        }
    }

    // MARK: calendar management (FUN-03)

    /// Two-step confirmation: this removes the calendar and every event in it from the account and cannot be undone here.
    private func deleteSystem(_ c: MLCal) {
        let a = mlAlert()
        a.alertStyle = .critical
        a.messageText = L("„\(c.name)“ endgültig löschen?", "Permanently delete “\(c.name)”?")
        a.informativeText = L("Der Kalender und alle seine Termine werden beim Konto (\(c.group ?? "System")) gelöscht, auch auf deinen anderen Geräten. Das lässt sich hier nicht rückgängig machen.",
                              "The calendar and all of its events are deleted from the account (\(c.group ?? "System")), including on your other devices. This cannot be undone here.")
        a.addButton(withTitle: L("Abbrechen", "Cancel"))
        a.addButton(withTitle: L("Löschen", "Delete"))
        a.buttons[1].hasDestructiveAction = true
        guard a.runModal() == .alertSecondButtonReturn else { return }
        let b = mlAlert()
        b.messageText = L("Wirklich löschen?", "Really delete?")
        b.informativeText = L("Zur Sicherheit noch einmal: „\(c.name)“ wird samt allen Terminen gelöscht.", "To be sure: “\(c.name)” will be deleted with all its events.")
        b.addButton(withTitle: L("Abbrechen", "Cancel"))
        b.addButton(withTitle: L("Endgültig löschen", "Delete Permanently"))
        b.buttons[1].hasDestructiveAction = true
        guard b.runModal() == .alertSecondButtonReturn else { return }
        MLSystem.shared.deleteCalendar(c.id)
        if ctl.defaultCalID == c.id { ctl.defaultCalID = ctl.store.calendars.first?.id }
    }

    private func renameSystem(_ c: MLCal) {
        if let n = prompt(L("Neuer Name", "New name"), c.name), n != c.name { MLSystem.shared.updateCalendar(c.id, name: n) }
    }

    private func newCalendar() {
        guard let name = prompt(L("Name des neuen Kalenders", "Name of the new calendar"), "") else { return }
        let n = ctl.store.calendars.count
        ctl.defaultCalID = ctl.store.addCalendar(name: name, colorHex: palette[n % palette.count])
    }

    private func prompt(_ message: String, _ initial: String) -> String? {
        let a = mlAlert()
        a.messageText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22)); f.stringValue = initial
        a.accessoryView = f
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let s = f.stringValue.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if e.clickCount == 2, p.x > 24 {
            if let (_, c) = sysRows.first(where: { $0.0.contains(p) }), !c.readOnly { renameSystem(c); return }
            if let (_, c) = localRows.first(where: { $0.0.contains(p) }), !c.readOnly,
               let n = prompt(L("Neuer Name", "New name"), c.name) { var u = c; u.name = n; ctl.store.updateCalendar(u); return }
        }
        hot(at: p)?.action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let m = NSMenu()
        for (rect, c) in localRows {
            guard rect.contains(p) else { continue }
            func item(_ t: String, _ f: @escaping () -> Void) { let i = MLBlockItem(t, f); m.addItem(i) }
            item(L("Umbenennen…", "Rename…")) { [weak self] in
                if let n = self?.prompt(L("Neuer Name", "New name"), c.name) { var u = c; u.name = n; self?.ctl.store.updateCalendar(u) }
            }
            let colors = NSMenuItem(title: L("Farbe", "Color"), action: nil, keyEquivalent: ""); let sub = NSMenu()
            for hex in palette {
                let i = MLBlockItem(String(format: "#%06X", hex)) { [weak self] in var u = c; u.colorHex = hex; self?.ctl.store.updateCalendar(u) }
                i.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
                    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).setFill(); NSBezierPath(ovalIn: r).fill(); return true
                }
                i.title = ""; sub.addItem(i)
            }
            colors.submenu = sub; m.addItem(colors)
            item(c.readOnly ? L("Schreibschutz aufheben", "Allow Editing") : L("Schreibschützen", "Make Read-Only")) { [weak self] in var u = c; u.readOnly.toggle(); self?.ctl.store.updateCalendar(u) }
            item(L("Als iCalendar-Datei sichern…", "Export as iCalendar…")) { [weak self] in self?.ctl.exportICS(calendar: c) }
            m.addItem(.separator())
            item(L("Kalender löschen…", "Delete Calendar…")) { [weak self] in
                guard let s = self else { return }
                let a = mlAlert(); a.messageText = L("„\(c.name)“ und alle Termine darin löschen?", "Delete “\(c.name)” and all its events?")
                a.informativeText = L("Das lässt sich mit „Rückgängig“ wiederherstellen.", "You can bring it back with Undo.")
                a.addButton(withTitle: L("Löschen", "Delete")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
                if a.runModal() == .alertFirstButtonReturn { s.ctl.store.deleteCalendar(c.id) }
            }
            return m
        }
        for (rect, c) in sysRows where rect.contains(p) {
            if c.readOnly {
                let i = NSMenuItem(title: L("Schreibgeschützt", "Read-Only"), action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i)
                return m
            }
            m.addItem(MLBlockItem(L("Umbenennen…", "Rename…")) { [weak self] in self?.renameSystem(c) })
            let colors = NSMenuItem(title: L("Farbe", "Color"), action: nil, keyEquivalent: ""); let sub = NSMenu()
            for hex in palette {
                let i = MLBlockItem("") { MLSystem.shared.updateCalendar(c.id, colorHex: hex) }
                i.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
                    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).setFill(); NSBezierPath(ovalIn: r).fill(); return true
                }
                sub.addItem(i)
            }
            colors.submenu = sub; m.addItem(colors)
            m.addItem(.separator())
            m.addItem(MLBlockItem(L("Kalender löschen…", "Delete Calendar…")) { [weak self] in self?.deleteSystem(c) })
            return m
        }
        let i = MLBlockItem(L("Neuer Kalender…", "New Calendar…")) { [weak self] in self?.newCalendar() }
        m.addItem(i)
        return m
    }

    override func isAccessibilityElement() -> Bool { false }
}

/// NSMenuItem that runs a closure.
final class MLBlockItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, key: String = "", _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { block() }
}
