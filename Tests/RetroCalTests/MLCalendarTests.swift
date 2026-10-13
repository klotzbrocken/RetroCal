import XCTest
import AppKit
@testable import RetroCal

/// Date logic (DAT-02/03, FUN-08, FUN-10) and a snapshot renderer for the visual comparison (§10.1).
/// Snapshots go to $ML_SNAP_DIR (default /tmp/mlsnap); they are inspected, not asserted.
final class MLCalendarTests: XCTestCase {
    private var cal: Calendar!
    private var store: MLStore!

    override func setUp() {
        MLPrefs.lang = "en"; MLPrefs.weekStart = 1; MLPrefs.hour24 = true; MLPrefs.timeZoneID = "Europe/Berlin"
        cal = MLPrefs.calendar
        store = MLStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json"))
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
    }

    func testMonthlyOn31stClampsAndReturns() {
        let e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2024, 1, 31, 10), end: d(2024, 1, 31, 11), repeatRule: .monthly)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2024, 1, 1), to: d(2024, 5, 1), cal: cal, into: &out)
        XCTAssertEqual(out.map { cal.component(.day, from: $0.start) }, [31, 29, 31, 30])      // Feb 29 (leap year), Mar 31, Apr 30
    }

    func testDailyAcrossDSTKeepsWallClock() {
        let e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2026, 3, 27, 9), end: d(2026, 3, 27, 10), repeatRule: .daily)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2026, 3, 27), to: d(2026, 4, 2), cal: cal, into: &out)
        XCTAssertEqual(out.count, 6)
        XCTAssertTrue(out.allSatisfy { cal.component(.hour, from: $0.start) == 9 })
    }

    func testAllDayIsWholeDaysAndExceptionRemovesOne() {
        var e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2026, 10, 12), end: d(2026, 10, 13), allDay: true, repeatRule: .weekly)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2026, 10, 1), to: d(2026, 11, 1), cal: cal, into: &out)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0].end.timeIntervalSince(out[0].start), 2 * 86400, accuracy: 3700)   // 12th and 13th
        e.exceptions = [Int(out[1].start.timeIntervalSince1970)]
        out = []; MLStore.expand(e, from: d(2026, 10, 1), to: d(2026, 11, 1), cal: cal, into: &out)
        XCTAssertEqual(out.count, 2)
    }

    func testUndoRestoresAndPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json")
        let s = MLStore(url: url)
        s.undoManager.groupsByEvent = false
        s.add(MLEvent(calID: s.calendars[0].id, title: "Zahnärztin Müller", start: d(2026, 10, 12, 9), end: d(2026, 10, 12, 10)))
        XCTAssertEqual(MLStore(url: url).state.events.first?.title, "Zahnärztin Müller")      // survives a restart
        s.undoManager.undo()
        XCTAssertTrue(s.state.events.isEmpty)
        s.undoManager.redo()
        XCTAssertEqual(s.state.events.count, 1)
    }

    func testQuickParser() {
        let now = d(2026, 10, 12, 8)          // Monday
        var q = MLQuickParser.parse("Zahnarzt morgen 15:30", now: now, cal: cal)
        XCTAssertEqual(q.title, "Zahnarzt"); XCTAssertEqual(q.start, d(2026, 10, 13, 15, 30)); XCTAssertFalse(q.allDay)
        q = MLQuickParser.parse("Lunch am 31.12. um 12 Uhr", now: now, cal: cal)
        XCTAssertEqual(q.title, "Lunch"); XCTAssertEqual(q.start, d(2026, 12, 31, 12))
        XCTAssertEqual(MLQuickParser.parse("Film Freitag 19 Uhr", now: now, cal: cal).title, "Film")      // case is kept
        q = MLQuickParser.parse("Urlaub", now: now, cal: cal)
        XCTAssertTrue(q.allDay); XCTAssertFalse(q.hasDate)
        q = MLQuickParser.parse("Meeting 31.02. 10:00", now: now, cal: cal)
        XCTAssertTrue(q.title.contains("31.02."))                                              // invalid date is not guessed
    }

    // MARK: snapshots

    @MainActor func testSnapshots() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ML_SNAP_DIR"] ?? "/tmp/mlsnap")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctl = MLController.shared
        ctl.store = store
        let now = d(2012, 7, 22, 12)
        ctl.now = { now }
        let home = store.calendars[0].id, work = store.calendars[1].id
        store.add(MLEvent(calID: home, title: "New Event", start: d(2012, 7, 22), end: d(2012, 7, 22), allDay: true))
        store.add(MLEvent(calID: work, title: "Design review", location: "Room 4", start: d(2012, 7, 24, 10), end: d(2012, 7, 24, 11, 30)))
        store.add(MLEvent(calID: home, title: "Dinner", start: d(2012, 7, 24, 10, 30), end: d(2012, 7, 24, 12)))
        store.add(MLEvent(calID: work, title: "Conference", start: d(2012, 7, 25), end: d(2012, 7, 27), allDay: true))
        store.add(MLEvent(calID: home, title: "Run", start: d(2012, 7, 23, 7), end: d(2012, 7, 23, 8), repeatRule: .daily))
        ctl.defaultCalID = home
        ctl.date = d(2012, 7, 22)
        let w = ctl.makeWindow()
        ctl.query = "e"; ctl.searchField.field.stringValue = "e"
        ctl.mode = .week
        do {
            let w2 = ctl.makeWindow(); w2.setContentSize(NSSize(width: 1086, height: 735)); w2.contentView!.layoutSubtreeIfNeeded()
            let v = w2.contentView!; let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!; v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-search.png"))
        }
        ctl.query = ""; ctl.searchField.field.stringValue = ""
        for (name, mode) in [("month", MLMode.month), ("week", .week), ("day", .day), ("year", .year)] {
            ctl.mode = mode
            ctl.main.scrollToDayStart()
            w.setContentSize(NSSize(width: 1086, height: 735))
            w.contentView!.layoutSubtreeIfNeeded()
            let v = w.contentView!
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-\(name).png"))
        }
    }

    @MainActor func testPanelSnapshots() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ML_SNAP_DIR"] ?? "/tmp/mlsnap")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctl = MLController.shared
        ctl.store = store
        let ev = MLEvent(calID: store.calendars[0].id, title: "New Event", start: d(2012, 7, 22), end: d(2012, 7, 22), allDay: true)
        let occ = MLOcc(ev: ev, start: d(2012, 7, 22), end: d(2012, 7, 23))
        let tmp = MLEvent(calID: store.calendars[0].id, title: "Zahnarzt", location: "Praxis Dr. Müller", start: d(2012, 7, 22, 9), end: d(2012, 7, 22, 10), repeatRule: .weekly)
        for (name, vc) in [("editor", MLEditorVC(ctl, occ: MLOcc(ev: tmp, start: tmp.start, end: tmp.end), isNew: false) as NSViewController), ("quick", MLQuickVC(ctl))] {
            let v = vc.view
            v.appearance = NSAppearance(named: .aqua)
            v.layoutSubtreeIfNeeded()
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-\(name).png"))
        }
        let dd = MLCalDropdown(cal: cal, selected: d(2012, 7, 12))
        let drep = dd.bitmapImageRepForCachingDisplay(in: dd.bounds)!
        dd.cacheDisplay(in: dd.bounds, to: drep)
        try drep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-dropdown.png"))
        let prefs = MLPrefsController(); prefs.show()
        let pv = prefs.window!.contentView!
        for i in 0..<3 {
            prefs.select(i)
            let rep = pv.bitmapImageRepForCachingDisplay(in: pv.bounds)!
            pv.cacheDisplay(in: pv.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("ml-prefs\(i).png"))
        }
    }
}

extension MLCalendarTests {
    private func find<T: NSView>(_ type: T.Type, in v: NSView, label: String? = nil) -> T? {
        for s in v.subviews {
            if let t = s as? T, label == nil || t.accessibilityLabel() == label { return t }
            if let r = find(type, in: s, label: label) { return r }
        }
        return nil
    }

    /// The editor writes its changes back (FUN-04/05): title, location, calendar, times.
    @MainActor func testEditorSavesChanges() throws {
        MLPrefs.lang = "en"
        let ctl = MLController.shared
        let st = MLStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json"))
        ctl.store = st
        let ev = MLEvent(calID: st.calendars[0].id, title: "Old", start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600))
        st.add(ev)
        let occ = MLOcc(ev: ev, start: ev.start, end: ev.end)
        let vc = MLEditorVC(ctl, occ: occ, isNew: false)
        let v = vc.view
        let t = try XCTUnwrap(find(NSTextField.self, in: v, label: "Title"))
        t.stringValue = "New title"
        let loc = try XCTUnwrap(find(NSTextField.self, in: v, label: "Location"))
        loc.stringValue = "Berlin"
        let to = try XCTUnwrap(find(MLDatePicker.self, in: v, label: "Ends"))
        _ = to   // times stay the same: only text fields change, the case that was silently dropped before
        vc.popoverClosed()                          // what clicking away does
        let saved = try XCTUnwrap(st.event(ev.id))
        XCTAssertEqual(saved.title, "New title")
        XCTAssertEqual(saved.location, "Berlin")
        XCTAssertEqual(saved.end, ev.end)
    }
}

extension MLCalendarTests {
    func testExtendedQuickParser() {
        let now = d(2026, 10, 12, 8)          // Monday
        func p(_ t: String) -> MLQuick { MLQuickParser.parse(t, now: now, cal: cal) }
        var q = p("Mittagessen mit Anna in Berlin nächsten Freitag 12:30")
        XCTAssertEqual(q.title, "Mittagessen mit Anna"); XCTAssertEqual(q.location, "Berlin"); XCTAssertEqual(q.start, d(2026, 10, 16, 12, 30))
        q = p("Workshop in 3 Tagen von 14 bis 16 Uhr")
        XCTAssertEqual(q.title, "Workshop"); XCTAssertEqual(q.start, d(2026, 10, 15, 14)); XCTAssertEqual(q.end, d(2026, 10, 15, 16))
        q = p("Yoga jeden Mittwoch 18 Uhr")
        XCTAssertEqual(q.repeatRule, .weekly); XCTAssertEqual(q.start, d(2026, 10, 14, 18)); XCTAssertEqual(q.title, "Yoga")
        q = p("Geburtstag Oma am 5. März")
        XCTAssertEqual(q.start, d(2027, 3, 5)); XCTAssertTrue(q.allDay); XCTAssertEqual(q.title, "Geburtstag Oma")
        q = p("Dentist March 5th 2027 at 3pm for 90 minutes")
        XCTAssertEqual(q.start, d(2027, 3, 5, 15)); XCTAssertEqual(q.end, d(2027, 3, 5, 16, 30)); XCTAssertEqual(q.title, "Dentist")
        q = p("Call tomorrow 2-3pm")
        XCTAssertEqual(q.start, d(2026, 10, 13, 14)); XCTAssertEqual(q.end, d(2026, 10, 13, 15))
        q = p("Kino halb acht übermorgen")
        XCTAssertEqual(q.start, d(2026, 10, 14, 7, 30)); XCTAssertTrue(q.warnings.isEmpty)
        q = p("Treffen halb drei morgen")
        XCTAssertEqual(q.start, d(2026, 10, 13, 14, 30)); XCTAssertFalse(q.warnings.isEmpty)        // 2:30 vs 14:30 is reported, not hidden
        q = p("Lager 10-12 morgen")
        XCTAssertTrue(q.allDay); XCTAssertTrue(q.title.contains("10-12"))                         // no unit: not read as a time
        q = p("Standup every day 9:15")
        XCTAssertEqual(q.repeatRule, .daily); XCTAssertEqual(q.start, d(2026, 10, 12, 9, 15))
        q = p("Pause @ Café Luise heute 15 Uhr")
        XCTAssertEqual(q.location, "Café Luise")
    }

    func testICalRoundTripAndErrors() {
        let home = store.calendars[0].id
        var a = MLEvent(calID: home, title: "Zahnarzt, Dr. Müller; Raum 2", location: "Praxis", start: d(2026, 10, 14, 9, 30), end: d(2026, 10, 14, 10, 15))
        a.notes = "Zeile 1\nZeile 2"
        var b = MLEvent(calID: home, title: "Urlaub", start: d(2026, 12, 24), end: d(2026, 12, 27), allDay: true)
        b.repeatRule = .yearly; b.exceptions = [Int(d(2027, 12, 24).timeIntervalSince1970)]
        let text = MLICal.export([a, b], calendarName: "Home")
        XCTAssertTrue(text.contains("DTEND;VALUE=DATE:20261228"))                                  // exclusive end
        XCTAssertTrue(text.split(separator: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        let r = MLICal.parse(text, calendarID: home)
        XCTAssertTrue(r.problems.isEmpty, "\(r.problems)")
        XCTAssertEqual(r.events.count, 2)
        XCTAssertEqual(r.events[0].title, a.title); XCTAssertEqual(r.events[0].start, a.start); XCTAssertEqual(r.events[0].end, a.end); XCTAssertEqual(r.events[0].notes, a.notes)
        XCTAssertEqual(r.events[1].allDay, true); XCTAssertEqual(r.events[1].end, d(2026, 12, 27)); XCTAssertEqual(r.events[1].repeatRule, .yearly); XCTAssertEqual(r.events[1].exceptions, b.exceptions)

        let bad = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Ohne Datum\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nSUMMARY:Komplex\r\nDTSTART:20261001T100000Z\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nSUMMARY:Gut\r\nDTSTART;TZID=Europe/Berlin:20261001T100000\r\nDURATION:PT2H\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let r2 = MLICal.parse(bad, calendarID: home)
        XCTAssertEqual(r2.events.count, 1); XCTAssertEqual(r2.events[0].end.timeIntervalSince(r2.events[0].start), 7200)
        XCTAssertEqual(r2.problems.count, 2); XCTAssertTrue(r2.problems[0].contains("Ohne Datum") || r2.problems[0].contains("1"))
        XCTAssertEqual(MLICal.parse("hallo", calendarID: home).problems.count, 1)
    }
}

extension MLCalendarTests {
    func testQuickParserLocationAtEnd() {
        let now = d(2026, 10, 12, 8)
        let q = MLQuickParser.parse("Yoga jeden Mittwoch 18 Uhr in Studio Nord", now: now, cal: cal)
        XCTAssertEqual(q.title, "Yoga"); XCTAssertEqual(q.location, "Studio Nord"); XCTAssertEqual(q.repeatRule, .weekly)
        let q2 = MLQuickParser.parse("Essen in Berlin morgen 19 Uhr", now: now, cal: cal)
        XCTAssertEqual(q2.location, "Berlin"); XCTAssertEqual(q2.title, "Essen")
    }
}

extension MLCalendarTests {
    func testLeapDayYearly() {
        let e = MLEvent(calID: store.calendars[0].id, title: "x", start: d(2024, 2, 29, 10), end: d(2024, 2, 29, 11), repeatRule: .yearly)
        var out: [MLOcc] = []
        MLStore.expand(e, from: d(2024, 1, 1), to: d(2029, 1, 1), cal: cal, into: &out)
        XCTAssertEqual(out.map { cal.dateComponents([.year, .month, .day], from: $0.start) }.map { "\($0.year!)-\($0.month!)-\($0.day!)" },
                       ["2024-2-29", "2025-2-28", "2026-2-28", "2027-2-28", "2028-2-29"])
    }

    /// QUA-05 / QUA-06: 10,000 stored events, ≤ 500 occurrences visible; p95 limits 200 ms (view) and 300 ms (search).
    func testPerformance10kEvents() {
        let home = store.calendars[0].id
        var evs: [MLEvent] = []
        let base = d(2026, 1, 1, 8)
        for i in 0..<10_000 {
            var e = MLEvent(calID: home, title: "Termin \(i) Müller", start: base.addingTimeInterval(Double(i) * 3 * 3600), end: base.addingTimeInterval(Double(i) * 3 * 3600 + 3600))
            if i % 50 == 0 { e.repeatRule = .weekly }
            if i % 7 == 0 { e.location = "Ort \(i % 100)" }
            evs.append(e)
        }
        store.mutate("bulk") { $0.events = evs }
        func p95(_ f: () -> Void) -> Double {
            var t: [Double] = []
            for _ in 0..<30 { let s = Date(); f(); t.append(Date().timeIntervalSince(s) * 1000) }
            return t.sorted()[28]
        }
        let month = p95 { _ = self.store.occurrences(from: self.d(2026, 7, 1), to: self.d(2026, 8, 1)) }
        let year = p95 { _ = self.store.occurrences(from: self.d(2026, 1, 1), to: self.d(2027, 1, 1)) }
        let search = p95 { _ = self.store.search("müller 77") }
        print("PERF month \(month) ms, year \(year) ms, search \(search) ms")
        XCTAssertLessThan(month, 200); XCTAssertLessThan(search, 300)
    }
}

extension MLCalendarTests {
    /// README screenshots: invented demo data only (never real calendars). Output: $ML_README_DIR (default docs/screenshots).
    @MainActor func testReadmeScreenshots() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ML_README_DIR"] ?? "docs/screenshots")
        guard ProcessInfo.processInfo.environment["ML_README_DIR"] != nil else { return }     // only when asked for
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        MLPrefs.lang = "de"; MLPrefs.weekStart = 2; MLPrefs.hour24 = true; MLPrefs.timeZoneID = "Europe/Berlin"; MLPrefs.dayStart = 8; MLPrefs.dayEnd = 18
        let cal = MLPrefs.calendar
        func dd(_ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: mi))! }
        let ctl = MLController.shared
        let st = MLStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("ml-\(UUID()).json"))
        ctl.store = st
        let home = st.calendars[0].id, work = st.calendars[1].id, bday = st.calendars[2].id
        func add(_ c: UUID, _ t: String, _ loc: String, _ s: Date, _ e: Date, allDay: Bool = false, rule: MLRepeat = .none) {
            var ev = MLEvent(calID: c, title: t, location: loc, start: s, end: e, allDay: allDay); ev.repeatRule = rule; st.add(ev)
        }
        add(work, "Team-Standup", "Raum 2", dd(10, 12, 9), dd(10, 12, 9, 30), rule: .daily)
        add(work, "Design-Review", "Atelier", dd(10, 14, 10), dd(10, 14, 11, 30))
        add(home, "Mittagessen mit Anna", "Café Luise", dd(10, 14, 12, 30), dd(10, 14, 13, 30))
        add(work, "Workshop", "Hamburg", dd(10, 15, 9), dd(10, 15, 12))
        add(home, "Zahnarzt", "Dr. Müller", dd(10, 15, 10, 30), dd(10, 15, 11, 15))
        add(home, "Yoga", "Studio Nord", dd(10, 15, 18), dd(10, 15, 19), rule: .weekly)
        add(work, "Konferenz", "", dd(10, 16), dd(10, 18), allDay: true)
        add(bday, "Geburtstag Oma", "", dd(10, 18), dd(10, 18), allDay: true, rule: .yearly)
        add(home, "Urlaub", "", dd(10, 26), dd(10, 30), allDay: true)
        for m in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] { add(home, "Notiz \(m)", "", dd(m, 3 + m, 10), dd(m, 3 + m, 11)); if m % 2 == 0 { add(work, "Meeting \(m)", "", dd(m, 17, 14), dd(m, 17, 15)) } }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/ml-demo-store.json"))
        let demoStore = MLStore(url: URL(fileURLWithPath: "/tmp/ml-demo-store.json")); demoStore.mutate("demo") { $0 = st.state }     // for live window screenshots
        ctl.now = { dd(10, 14, 11, 20) }
        ctl.defaultCalID = home
        ctl.date = dd(10, 14); ctl.mode = .week

        let w = ctl.makeWindow(size: NSSize(width: 1086, height: 735))
        w.setContentSize(NSSize(width: 1086, height: 735))
        func shot(_ v: NSView, _ name: String, scale: Int = 2) throws {
            v.layoutSubtreeIfNeeded()
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.frame.width) * scale, pixelsHigh: Int(v.frame.height) * scale, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = v.bounds.size
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name + ".png"))
        }
        let root = w.contentView!
        for (name, mode) in [("woche", MLMode.week), ("tag", .day), ("monat", .month), ("jahr", .year)] {
            ctl.mode = mode; ctl.main.scrollToHour(8)
            try shot(root, name)
        }
        ctl.mode = .week; ctl.main.scrollToHour(8)
        ctl.query = "ber"; ctl.searchField.field.stringValue = "ber"
        // suggestions need matching data: use the title search of the demo set
        ctl.query = "zahn"; ctl.searchField.field.stringValue = "zahn"; ctl.searchCommitted = true
        try shot(root, "suche")
        ctl.query = ""; ctl.searchField.field.stringValue = ""; ctl.searchCommitted = false

        let ev = st.state.events.first { $0.title == "Design-Review" }!
        let occ = MLOcc(ev: ev, start: ev.start, end: ev.end)
        let vc = MLEditorVC(ctl, occ: occ, isNew: false)
        func bubble(_ content: NSView, footer: CGFloat, top: Bool) -> NSView {
            let aw = MLBubble.arrowW
            let b = MLBubble(frame: NSRect(x: 0, y: 0, width: content.frame.width + (top ? 0 : aw) + 24, height: content.frame.height + (top ? aw : 0) + 24))
            let holder = MLFlip(frame: b.frame); holder.addSubview(b)
            b.frame = NSRect(x: 12, y: 12, width: content.frame.width + (top ? 0 : aw), height: content.frame.height + (top ? aw : 0))
            b.arrowTop = top; b.arrowX = 40; b.arrowY = 40; b.footerH = footer
            content.frame.origin = NSPoint(x: top ? 0 : aw, y: top ? aw : 0)
            b.addSubview(content)
            return holder
        }
        try shot(bubble(vc.view, footer: MLEditorVC.footerH, top: false), "termin-popover")
        let q = MLQuickVC(ctl); _ = q.view
        try shot(bubble(q.view, footer: 0, top: true), "schnell-termin")
        let prefs = MLPrefsController(); prefs.show()
        try shot(prefs.window!.contentView!, "einstellungen")
    }
}


extension MLCalendarTests {
    private func png(_ px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testCustomIconValidation() {
        MLPrefs.lang = "en"
        XCTAssertNil(MLCustomIcon.validate(png(256)))
        XCTAssertTrue(MLCustomIcon.validate(png(128))!.contains("128 × 128"))
        XCTAssertNotNil(MLCustomIcon.validate(Data("not a png".utf8)))
        let jpg = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .jpeg, properties: [:])!
        XCTAssertNotNil(MLCustomIcon.validate(jpg))                              // right size, wrong format
    }
}

extension MLCalendarTests {
    /// Stores, applies and resets a custom icon through the real code path (uses the real support folder and cleans up).
    @MainActor func testCustomIconRoundTrip() throws {
        MLPrefs.lang = "en"
        let had = MLCustomIcon.isSet
        try XCTSkipIf(had, "a custom icon is set on this machine; not touching it")
        let dir = FileManager.default.temporaryDirectory
        let ok = dir.appendingPathComponent("ok-\(UUID()).png"), small = dir.appendingPathComponent("small-\(UUID()).png")
        try png(256).write(to: ok); try png(128).write(to: small)
        defer { MLCustomIcon.reset(); try? FileManager.default.removeItem(at: ok); try? FileManager.default.removeItem(at: small) }
        XCTAssertNotNil(MLCustomIcon.set(from: small)); XCTAssertFalse(MLCustomIcon.isSet)       // rejected, nothing stored
        XCTAssertNil(MLCustomIcon.set(from: ok)); XCTAssertTrue(MLCustomIcon.isSet)
        XCTAssertEqual(NSBitmapImageRep(data: try Data(contentsOf: MLCustomIcon.fileURL))?.pixelsWide, 256)     // the stored file
        XCTAssertNotNil(NSApplication.shared.applicationIconImage)
        MLCustomIcon.reset(); XCTAssertFalse(MLCustomIcon.isSet)
    }
}
