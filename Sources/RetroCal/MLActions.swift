import AppKit

// Event actions shared by menus: clipboard (cut / copy / paste), move to another calendar, repeat, all-day.

extension MLController {
    func copySelected() { if let o = selectedOcc { clipboard = (o.ev, o.start) } else { NSSound.beep() } }

    func cutSelected() {
        guard let o = selectedOcc else { NSSound.beep(); return }
        if store.calendar(o.ev.calID)?.readOnly == true { NSSound.beep(); return }
        clipboard = (o.ev, o.start)
        delete(o)
    }

    /// Paste as a new event. `at` sets the day (and time when given); otherwise the visible date, keeping the time of day.
    func pasteEvent(at target: Date? = nil, timed: Bool = false) {
        guard let (src, origStart) = clipboard, let cid = writableCalID else { NSSound.beep(); return }
        var e = src
        e.id = UUID(); e.exceptions = []; e.calID = store.calendar(src.calID)?.readOnly == false ? src.calID : cid
        let s = MLStore.interval(src, cal: cal)
        let len = s.1.timeIntervalSince(s.0)
        let day = cal.startOfDay(for: target ?? date)
        if src.allDay {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: src.start), to: cal.startOfDay(for: src.end)).day ?? 0
            e.start = day; e.end = cal.date(byAdding: .day, value: days, to: day)!
        } else {
            let secs = timed && target != nil ? target!.timeIntervalSince(day) : origStart.timeIntervalSince(cal.startOfDay(for: origStart))
            e.start = cal.date(byAdding: .second, value: Int(secs), to: day)!; e.end = e.start.addingTimeInterval(len)
        }
        showIfHidden(e.calID)
        let made = store.add(e, name: L("Termin einsetzen", "Paste Event"))
        date = day
        selectedKey = "\(made.id)|\(Int(MLStore.interval(made, cal: cal).0.timeIntervalSince1970))"
        refresh()
    }

    func move(_ o: MLOcc, toCalendar id: UUID) {
        guard o.ev.calID != id else { return }
        if store.calendar(o.ev.calID)?.readOnly == true { NSSound.beep(); return }
        var e = o.ev; e.calID = id
        showIfHidden(id)
        let saved = store.update(e, name: L("Kalender wechseln", "Change Calendar"), series: true)
        selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
        refresh()
    }

    func setRepeat(_ o: MLOcc, _ r: MLRepeat) {
        guard o.ev.repeatRule != r, store.calendar(o.ev.calID)?.readOnly != true else { return }
        var e = o.ev; e.repeatRule = r; e.exceptions = []
        let saved = store.update(e, name: L("Wiederholung ändern", "Change Repeat"), series: true)
        selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
        refresh()
    }

    func toggleAllDay(_ o: MLOcc) {
        guard store.calendar(o.ev.calID)?.readOnly != true else { NSSound.beep(); return }
        var e = o.ev
        if e.allDay {
            e.allDay = false; e.start = cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: o.start))!; e.end = e.start.addingTimeInterval(3600)
        } else {
            e.allDay = true; e.start = cal.startOfDay(for: o.start); e.end = cal.startOfDay(for: o.start)
        }
        let saved = store.update(e, name: L("Ganztägig ändern", "Change All-Day"), series: o.isRecurring)
        selectedKey = "\(saved.id)|\(Int(MLStore.interval(saved, cal: cal).0.timeIntervalSince1970))"
        refresh()
    }

    func newEventHere(_ start: Date?, allDay: Bool) {
        if let start { date = cal.startOfDay(for: start) }
        newEvent(start: start, allDay: allDay)
    }

    func viewMenu() -> NSMenuItem {
        let item = NSMenuItem(title: L("Ansicht", "View"), action: nil, keyEquivalent: ""); let sub = NSMenu()
        for (i, t) in [L("Tag", "Day"), L("Woche", "Week"), L("Monat", "Month"), L("Jahr", "Year")].enumerated() {
            let it = MLBlockItem(t, key: "\(i + 1)") { [weak self] in self?.setMode(MLMode(rawValue: i)!) }
            it.keyEquivalentModifierMask = .command; it.state = mode.rawValue == i ? .on : .off; sub.addItem(it)
        }
        item.submenu = sub
        return item
    }
}

extension MLMainView {
    @objc func copy(_ sender: Any?) { ctl.copySelected() }
    @objc func cut(_ sender: Any?) { ctl.cutSelected() }
    @objc func paste(_ sender: Any?) { ctl.pasteEvent() }
}

extension MLMainView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(MLMainView.copy(_:)), #selector(MLMainView.cut(_:)): return ctl.selectedOcc != nil
        case #selector(MLMainView.paste(_:)): return ctl.clipboard != nil
        default: return true
        }
    }
}
