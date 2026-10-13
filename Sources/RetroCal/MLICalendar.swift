import AppKit
import UniformTypeIdentifiers

// iCalendar (RFC 5545) import and export for local events (UM-06, FUN-16).
// Scope: VEVENT with SUMMARY, LOCATION, DESCRIPTION, URL, DTSTART/DTEND (date, UTC, TZID, floating), DURATION,
// RRULE (FREQ DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL 1) and EXDATE. Anything else is reported per entry, not dropped silently.
// ponytail: export writes timed events in UTC (no VTIMEZONE); import understands TZID through the system time-zone database.

struct MLICalResult {
    var events: [MLEvent] = []
    /// One line per problem, naming the affected entry ("Eintrag 3 „Zahnarzt“: …").
    var problems: [String] = []
}

enum MLICal {
    // MARK: export

    static func export(_ events: [MLEvent], calendarName: String) -> String {
        var out: [String] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//RetroMac//RetroCal//EN", "CALSCALE:GREGORIAN"]
        if !calendarName.isEmpty { out.append("X-WR-CALNAME:" + escape(calendarName)) }
        let cal = MLPrefs.calendar
        let stamp = utc(Date())
        for e in events {
            out.append("BEGIN:VEVENT")
            out.append("UID:\(e.id.uuidString)@mountainlioncalendar")
            out.append("DTSTAMP:\(stamp)")
            if e.allDay {
                let s = cal.startOfDay(for: e.start), last = cal.startOfDay(for: e.end)
                out.append("DTSTART;VALUE=DATE:\(dateOnly(s, cal))")
                out.append("DTEND;VALUE=DATE:\(dateOnly(cal.date(byAdding: .day, value: 1, to: max(s, last))!, cal))")   // end is exclusive
            } else {
                out.append("DTSTART:\(utc(e.start))")
                out.append("DTEND:\(utc(max(e.end, e.start)))")
            }
            out.append("SUMMARY:" + escape(e.title))
            if !e.location.isEmpty { out.append("LOCATION:" + escape(e.location)) }
            if !e.notes.isEmpty { out.append("DESCRIPTION:" + escape(e.notes)) }
            if !e.url.isEmpty { out.append("URL:" + e.url) }
            if e.repeatRule != .none {
                let f: String
                switch e.repeatRule { case .daily: f = "DAILY"; case .weekly: f = "WEEKLY"; case .monthly: f = "MONTHLY"; case .yearly: f = "YEARLY"; case .none: f = "" }
                out.append("RRULE:FREQ=\(f)")
                for x in e.exceptions {
                    let d = Date(timeIntervalSince1970: TimeInterval(x))
                    out.append(e.allDay ? "EXDATE;VALUE=DATE:\(dateOnly(d, cal))" : "EXDATE:\(utc(d))")
                }
            }
            out.append("END:VEVENT")
        }
        out.append("END:VCALENDAR")
        return out.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: import

    static func parse(_ text: String, calendarID: UUID) -> MLICalResult {
        var res = MLICalResult()
        let lines = unfold(text)
        var props: [(name: String, params: [String: String], value: String)] = []
        var inEvent = false
        var index = 0
        var sawCalendar = false
        for raw in lines {
            let (name, params, value) = splitLine(raw)
            switch name {
            case "BEGIN" where value.uppercased() == "VCALENDAR": sawCalendar = true
            case "BEGIN" where value.uppercased() == "VEVENT": inEvent = true; props = []; index += 1
            case "END" where value.uppercased() == "VEVENT":
                inEvent = false
                switch build(props, calendarID: calendarID) {
                case .success(let e): res.events.append(e)
                case .failure(let err):
                    let title = props.first { $0.name == "SUMMARY" }.map { unescape($0.value) } ?? ""
                    res.problems.append(L("Eintrag \(index)", "Entry \(index)") + (title.isEmpty ? "" : " „\(title)“") + ": " + err.message)
                }
            default: if inEvent { props.append((name, params, value)) }
            }
        }
        if !sawCalendar { res.problems.insert(L("Die Datei enthält keinen iCalendar-Kalender (BEGIN:VCALENDAR fehlt).", "The file contains no iCalendar data (BEGIN:VCALENDAR is missing)."), at: 0) }
        return res
    }

    struct Failure: Error { var message: String }

    private static func build(_ props: [(name: String, params: [String: String], value: String)], calendarID: UUID) -> Result<MLEvent, Failure> {
        func first(_ n: String) -> (params: [String: String], value: String)? { props.first { $0.name == n }.map { ($0.params, $0.value) } }
        guard let ds = first("DTSTART") else { return .failure(Failure(message: L("DTSTART fehlt", "DTSTART is missing"))) }
        guard let (s, allDay) = date(ds.value, ds.params) else { return .failure(Failure(message: L("Beginn „\(ds.value)“ nicht lesbar", "Cannot read start “\(ds.value)”"))) }
        let cal = MLPrefs.calendar
        var end = s
        if let de = first("DTEND") {
            guard let (e, _) = date(de.value, de.params) else { return .failure(Failure(message: L("Ende „\(de.value)“ nicht lesbar", "Cannot read end “\(de.value)”"))) }
            end = allDay ? cal.date(byAdding: .day, value: -1, to: e)! : e                // stored inclusive for all-day
        } else if let du = first("DURATION"), let secs = duration(du.value) {
            end = allDay ? cal.date(byAdding: .second, value: Int(secs) - 86400, to: s)! : s.addingTimeInterval(secs)
        } else if !allDay { end = s.addingTimeInterval(3600) }
        if end < s { return .failure(Failure(message: L("Ende liegt vor dem Beginn", "End is before the start"))) }

        var rule = MLRepeat.none
        if let rr = first("RRULE") {
            let parts = Dictionary(uniqueKeysWithValues: rr.value.split(separator: ";").compactMap { p -> (String, String)? in
                let kv = p.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (kv[0].uppercased(), String(kv[1])) : nil })
            switch parts["FREQ"] {
            case "DAILY": rule = .daily
            case "WEEKLY": rule = .weekly
            case "MONTHLY": rule = .monthly
            case "YEARLY": rule = .yearly
            default: return .failure(Failure(message: L("Wiederholung „\(rr.value)“ wird nicht unterstützt", "Repeat rule “\(rr.value)” is not supported")))
            }
            if let i = parts["INTERVAL"], i != "1" { return .failure(Failure(message: L("Intervall „\(i)“ wird nicht unterstützt", "Interval “\(i)” is not supported"))) }
            if parts["COUNT"] != nil || parts["UNTIL"] != nil || parts["BYDAY"] != nil || parts["BYMONTHDAY"] != nil || parts["BYSETPOS"] != nil {
                return .failure(Failure(message: L("Regel „\(rr.value)“ enthält Teile (Ende, Wochentage …), die nicht unterstützt werden", "Rule “\(rr.value)” has parts (end, weekdays …) that are not supported")))
            }
        }
        var ex: [Int] = []
        for p in props where p.name == "EXDATE" {
            for v in p.value.split(separator: ",") {
                guard let (d, _) = date(String(v), p.params) else { return .failure(Failure(message: L("Ausnahme „\(v)“ nicht lesbar", "Cannot read exception “\(v)”"))) }
                ex.append(Int(d.timeIntervalSince1970))
            }
        }
        var e = MLEvent(calID: calendarID, title: first("SUMMARY").map { unescape($0.value) } ?? "", start: s, end: end, allDay: allDay)
        e.location = first("LOCATION").map { unescape($0.value) } ?? ""
        e.notes = first("DESCRIPTION").map { unescape($0.value) } ?? ""
        e.url = first("URL")?.value ?? ""
        e.repeatRule = rule; e.exceptions = ex
        return .success(e)
    }

    // MARK: low level

    static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for l in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if (l.hasPrefix(" ") || l.hasPrefix("\t")), !out.isEmpty { out[out.count - 1] += l.dropFirst() } else if !l.isEmpty { out.append(String(l)) }
        }
        return out
    }

    static func fold(_ line: String) -> String {
        var out = "", count = 0
        for ch in line {
            let n = String(ch).utf8.count
            if count + n > 73 { out += "\r\n "; count = 1 }                        // 75 octets incl. CRLF + leading space
            out.append(ch); count += n
        }
        return out
    }

    private static func splitLine(_ l: String) -> (String, [String: String], String) {
        // name[;param=value]*:value — the first colon outside quotes ends the head
        var inQ = false, idx = l.endIndex
        for i in l.indices { let c = l[i]; if c == "\"" { inQ.toggle() } else if c == ":" && !inQ { idx = i; break } }
        guard idx != l.endIndex else { return (l.uppercased(), [:], "") }
        let head = l[..<idx].split(separator: ";", omittingEmptySubsequences: false)
        var params: [String: String] = [:]
        for p in head.dropFirst() { let kv = p.split(separator: "=", maxSplits: 1); if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) } }
        return (String(head[0]).uppercased(), params, String(l[l.index(after: idx)...]))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
    }
    static func unescape(_ s: String) -> String {
        var out = "", esc = false
        for ch in s {
            if esc { out.append(ch == "n" || ch == "N" ? "\n" : ch); esc = false } else if ch == "\\" { esc = true } else { out.append(ch) }
        }
        return out
    }

    private static func utc(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }
    private static func dateOnly(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }

    /// Returns the instant and whether the value was a plain date.
    private static func date(_ v: String, _ params: [String: String]) -> (Date, Bool)? {
        let cal = MLPrefs.calendar
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        if v.count == 8, params["VALUE"] == "DATE" || !v.contains("T") {
            f.timeZone = cal.timeZone; f.dateFormat = "yyyyMMdd"
            guard let d = f.date(from: v) else { return nil }
            return (cal.startOfDay(for: d), true)
        }
        if v.hasSuffix("Z") { f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'" }
        else { f.timeZone = params["TZID"].flatMap { TimeZone(identifier: $0) } ?? cal.timeZone; f.dateFormat = "yyyyMMdd'T'HHmmss" }
        guard let d = f.date(from: v) else { return nil }
        return (d, false)
    }

    private static func duration(_ v: String) -> TimeInterval? {
        guard let re = try? NSRegularExpression(pattern: #"^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#),
              let m = re.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) else { return nil }
        func n(_ i: Int) -> Double { Range(m.range(at: i), in: v).flatMap { Double(v[$0]) } ?? 0 }
        return n(1) * 604800 + n(2) * 86400 + n(3) * 3600 + n(4) * 60 + n(5)
    }
}

// MARK: - UI

extension MLController {
    /// Import into the default calendar; reports every entry that could not be read.
    func importICS(urls: [URL]? = nil) {
        let list: [URL]
        if let urls { list = urls } else {
            let p = NSOpenPanel()
            p.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
            p.allowsMultipleSelection = true
            p.message = L("iCalendar-Dateien auswählen", "Choose iCalendar files")
            guard p.runModal() == .OK else { return }
            list = p.urls
        }
        guard let cid = writableCalID else { alert(L("Es gibt keinen beschreibbaren Kalender.", "There is no writable calendar.")); return }
        var added = 0, problems: [String] = []
        for u in list {
            guard let data = try? Data(contentsOf: u), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                problems.append("\(u.lastPathComponent): " + L("Datei nicht lesbar", "file not readable")); continue
            }
            let r = MLICal.parse(text, calendarID: cid)
            showIfHidden(cid)
            if !r.events.isEmpty {
                store.mutate(L("Importieren", "Import")) { $0.events.append(contentsOf: r.events) }       // one undo step for the whole file
                added += r.events.count
            }
            problems += r.problems.map { "\(u.lastPathComponent): \($0)" }
            if let f = r.events.first { date = cal.startOfDay(for: f.start) }
        }
        refresh()
        let a = mlAlert()
        a.messageText = L("\(added) Termine importiert", "\(added) events imported")
        if !problems.isEmpty {
            a.informativeText = L("\(problems.count) Einträge konnten nicht übernommen werden:\n", "\(problems.count) entries could not be imported:\n") + problems.prefix(8).joined(separator: "\n") + (problems.count > 8 ? "\n…" : "")
            a.alertStyle = .warning
        }
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    /// Export a local calendar (all its events, series stay series).
    func exportICS(calendar c: MLCal?) {
        let target = c ?? store.calendars.first { $0.id == defaultCalID } ?? store.calendars.first
        guard let cal = target, store.calendar(cal.id) != nil, store.state.calendars.contains(where: { $0.id == cal.id }) else {
            alert(L("Nur lokale Kalender lassen sich exportieren. Wähle einen Kalender unter „Auf meinem Mac“.", "Only local calendars can be exported. Choose one under “On My Mac”.")); return
        }
        let evs = store.state.events.filter { $0.calID == cal.id }
        let p = NSSavePanel()
        p.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        p.nameFieldStringValue = cal.name + ".ics"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try MLICal.export(evs, calendarName: cal.name).write(to: url, atomically: true, encoding: .utf8) }
        catch { alert(L("Der Export ist fehlgeschlagen: ", "Export failed: ") + error.localizedDescription) }
    }

    /// Export a single event (context menu).
    func exportICS(event e: MLEvent) {
        let p = NSSavePanel()
        p.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        p.nameFieldStringValue = (e.title.isEmpty ? L("Termin", "Event") : e.title) + ".ics"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try MLICal.export([e], calendarName: "").write(to: url, atomically: true, encoding: .utf8) }
        catch { alert(L("Der Export ist fehlgeschlagen: ", "Export failed: ") + error.localizedDescription) }
    }
}
