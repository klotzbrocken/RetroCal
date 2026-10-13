import AppKit

/// The list under the search field (classic Mac style): events, places and people that match what is typed.
/// Up/Down move the highlight, Return takes it (or runs a full search when nothing is highlighted), Esc closes.
final class MLSuggestView: MLView {
    private let rowH: CGFloat = 17, headH: CGFloat = 15
    private enum Row { case head(String), item(Int, NSImage?, String, String) }   // index into ctl.suggestions

    private var rows: [Row] {
        var out: [Row] = []
        var last = ""
        for (i, s) in ctl.suggestions.enumerated() {
            let (sec, title, detail): (String, String, String)
            switch s {
            case .event(let o): (sec, title, detail) = (L("Termine", "Events"), o.title, MLPrefs.fmt(o.start, "yMMMd"))
            case .place(let p): (sec, title, detail) = (L("Orte", "Locations"), p, "")
            case .person(let p): (sec, title, detail) = (L("Personen", "People"), p, "")
            case .notes(let q): (sec, title, detail) = (L("Notizen", "Notes"), L("Notizen mit „\(q)“", "Notes containing “\(q)”"), "")
            }
            if sec != last { out.append(.head(sec)); last = sec }
            out.append(.item(i, nil, title, detail))
        }
        return out
    }

    var neededHeight: CGFloat {
        rows.reduce(CGFloat(6)) { acc, r in if case .head = r { return acc + headH } else { return acc + rowH } }
    }

    override func draw(_ dirty: NSRect) {
        hots = []
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        mlRGB(252, 252, 253).setFill(); path.fill()
        mlRGB(150, 150, 154).setStroke(); path.lineWidth = 1; path.stroke()
        var y: CGFloat = 3
        for row in rows {
            switch row {
            case .head(let t):
                mlText(t, NSRect(x: 8, y: y, width: bounds.width - 16, height: headH), mlFont(9.5, bold: true), mlRGB(150, 150, 154))
                y += headH
            case .item(let i, _, let title, let detail):
                let rect = NSRect(x: 3, y: y, width: bounds.width - 6, height: rowH)
                let sel = ctl.suggestIndex == i
                if sel { mlGradient(rect, [(0, mlRGB(110, 150, 215)), (1, mlRGB(70, 115, 200))], radius: 3) }
                let dw = detail.isEmpty ? 0 : mlTextWidth(detail, mlFont(9.5)) + 8
                mlText(title, NSRect(x: 12, y: y, width: rect.width - 16 - dw, height: rowH), mlFont(10.8), sel ? .white : .black)
                if !detail.isEmpty { mlText(detail, NSRect(x: rect.maxX - dw - 4, y: y, width: dw, height: rowH), mlFont(9.5), sel ? .white : mlRGB(130, 130, 134), align: .right) }
                hots.append(MLHot(rect: rect, label: title, role: .row) { [weak self] in self?.ctl.pickSuggestion(i) })
                y += rowH
            }
        }
    }

    override func mouseDown(with e: NSEvent) { hot(at: convert(e.locationInWindow, from: nil))?.action() }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        var y: CGFloat = 3
        for row in rows {
            switch row {
            case .head: y += headH
            case .item(let i, _, _, _):
                if p.y >= y && p.y < y + rowH, ctl.suggestIndex != i { ctl.suggestIndex = i; needsDisplay = true }
                y += rowH
            }
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
}
