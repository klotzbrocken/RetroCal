import Foundation

// Quick entry (FUN-10, FUN-11): one sentence → event. German and English.
// Rule: whatever is not understood stays in the title, and anything that had to be guessed is reported in `warnings`
// so the preview can show it before saving. Nothing ambiguous is silently turned into a date.

struct MLQuick {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var hasDate: Bool
    var hasTime: Bool
    var location = ""
    var repeatRule: MLRepeat = .none
    var warnings: [String] = []
}

enum MLQuickParser {
    private static let weekdays: [(String, Int)] = [
        ("sonntag", 1), ("montag", 2), ("dienstag", 3), ("mittwoch", 4), ("donnerstag", 5), ("freitag", 6), ("samstag", 7), ("sonnabend", 7),
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
        ("so", 1), ("mo", 2), ("di", 3), ("mi", 4), ("do", 5), ("fr", 6), ("sa", 7),
    ]
    private static let months: [String: Int] = [
        "januar": 1, "jan": 1, "january": 1, "februar": 2, "feb": 2, "february": 2, "märz": 3, "maerz": 3, "mär": 3, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "mai": 5, "may": 5, "juni": 6, "jun": 6, "june": 6, "juli": 7, "jul": 7, "july": 7,
        "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "oktober": 10, "okt": 10, "october": 10, "oct": 10,
        "november": 11, "nov": 11, "dezember": 12, "dez": 12, "december": 12, "dec": 12,
    ]
    private static let numberWords: [String: Int] = [
        "eins": 1, "ein": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    private static var monthAlt: String { months.keys.sorted { $0.count > $1.count }.joined(separator: "|") }
    private static var weekdayAlt: String { weekdays.map { $0.0 }.sorted { $0.count > $1.count }.joined(separator: "|") }
    private static var numberAlt: String { numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|") }

    static func parse(_ input: String, now: Date = Date(), cal: Calendar = MLPrefs.calendar) -> MLQuick {
        var s = " " + input + " "
        var day: Date?
        var minutes: Int?, endMinutes: Int?
        var duration: Int?
        var rule = MLRepeat.none
        var warnings: [String] = []
        let today = cal.startOfDay(for: now)
        let end = "(?=[\\s,.;!?]|$)"

        func take(_ pattern: String, _ f: ([String]) -> Bool) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return }
            let g = (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: s) else { return "" }; return String(s[r]).lowercased()
            }
            if f(g) { s.replaceSubrange(Range(m.range, in: s)!, with: "\u{1}") }
        }
        func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard let dt = cal.date(from: DateComponents(year: y, month: m, day: d)),
                  cal.component(.day, from: dt) == d, cal.component(.month, from: dt) == m else { return nil }   // rejects 31.02.
            return dt
        }
        func nextWeekday(_ wd: Int, includingToday: Bool) -> Date {
            var d = today
            if !includingToday || cal.component(.weekday, from: d) != wd {
                repeat { d = cal.date(byAdding: .day, value: 1, to: d)! } while cal.component(.weekday, from: d) != wd
            }
            return d
        }
        func wdNumber(_ name: String) -> Int? { weekdays.first { $0.0 == name }?.1 }
        func number(_ w: String) -> Int? { Int(w) ?? numberWords[w] ?? (w == "einer" || w == "a" || w == "an" ? 1 : nil) }

        // 1. repetition
        take("(?<=\\s)(?:jeden|jede|jeder|every)\\s(\(weekdayAlt))\(end)") { g in
            guard let wd = wdNumber(g[1]), g[1].count > 2 else { return false }
            rule = .weekly; day = nextWeekday(wd, includingToday: true); return true
        }
        take("(?<=\\s)(täglich|taeglich|daily|jeden tag|every day)\(end)") { _ in rule = .daily; return true }
        take("(?<=\\s)(wöchentlich|woechentlich|weekly|jede woche|every week)\(end)") { _ in rule = .weekly; return true }
        take("(?<=\\s)(monatlich|monthly|jeden monat|every month)\(end)") { _ in rule = .monthly; return true }
        take("(?<=\\s)(jährlich|jaehrlich|yearly|annually|jedes jahr|every year)\(end)") { _ in rule = .yearly; return true }

        // 2. date
        if day == nil { take("(?<=\\s)(\\d{4})-(\\d{1,2})-(\\d{1,2})\(end)") { g in day = ymd(Int(g[1])!, Int(g[2])!, Int(g[3])!); return day != nil } }
        if day == nil {
            take("(?<=\\s)(\\d{1,2})\\.\\s?(\\d{1,2})\\.(\\d{2,4})?\(end)") { g in
                var y = g[3].isEmpty ? cal.component(.year, from: today) : Int(g[3])!
                if y < 100 { y += 2000 }
                guard var d = ymd(y, Int(g[2])!, Int(g[1])!) else { return false }
                if g[3].isEmpty, d < today { d = ymd(y + 1, Int(g[2])!, Int(g[1])!) ?? d }
                day = d; return true
            }
        }
        if day == nil {   // 5. März [2027] / 5 march / March 5th, 2027
            take("(?<=\\s)(\\d{1,2})(?:st|nd|rd|th)?\\.?\\s?(\(monthAlt))\\.?(?:\\s(\\d{4}))?\(end)") { g in
                guard let m = months[g[2]] else { return false }
                return setMonthDay(&day, m, Int(g[1])!, g[3], today, cal, ymd)
            }
        }
        if day == nil {
            take("(?<=\\s)(\(monthAlt))\\.?\\s(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s(\\d{4}))?\(end)") { g in
                guard let m = months[g[1]] else { return false }
                return setMonthDay(&day, m, Int(g[2])!, g[3], today, cal, ymd)
            }
        }
        if day == nil { take("(?<=\\s)(übermorgen|ubermorgen|day after tomorrow)\(end)") { _ in day = cal.date(byAdding: .day, value: 2, to: today); return true } }
        if day == nil { take("(?<=\\s)(morgen|tomorrow)\(end)") { _ in day = cal.date(byAdding: .day, value: 1, to: today); return true } }
        if day == nil { take("(?<=\\s)(heute|today)\(end)") { _ in day = today; return true } }
        if day == nil {   // in 3 Tagen / in two weeks / in einer Woche
            take("(?<=\\s)(?:in|nach)\\s(\\d+|\(numberAlt)|einer|einem|a|an)\\s(tag|tagen|tage|day|days|woche|wochen|week|weeks|monat|monaten|monate|month|months)\(end)") { g in
                guard let n = number(g[1]), n > 0 else { return false }
                let unit = g[2]
                if unit.hasPrefix("t") || unit.hasPrefix("d") { day = cal.date(byAdding: .day, value: n, to: today) }
                else if unit.hasPrefix("w") { day = cal.date(byAdding: .day, value: 7 * n, to: today) }
                else { day = cal.date(byAdding: .month, value: n, to: today) }
                return day != nil
            }
        }
        if day == nil {   // nächsten Montag / next friday / diesen Freitag / this friday
            take("(?<=\\s)(nächsten|naechsten|nächste|nächster|next|diesen|diese|dieser|this)\\s(\(weekdayAlt))\(end)") { g in
                guard let wd = wdNumber(g[2]), g[2].count > 2 else { return false }
                day = nextWeekday(wd, includingToday: g[1].hasPrefix("dies") || g[1] == "this"); return true
            }
        }
        if day == nil {
            take("(?<=\\s)(?:am|on)?\\s?(\(weekdayAlt))\(end)") { g in
                guard let wd = wdNumber(g[1]), g[1].count > 2 else { return false }
                day = nextWeekday(wd, includingToday: false); return true
            }
        }

        // 3. time
        func apply(_ h: Int, _ mer: String) -> Int? {
            var h = h
            if mer == "pm", h < 12 { h += 12 }; if mer == "am", h == 12 { h = 0 }
            return h < 24 ? h : nil
        }
        take("(?<=\\s)(?:von|from|ab)?\\s?(\\d{1,2})(?::(\\d{2}))?\\s?(uhr|h|am|pm)?\\s?(?:-|–|—|bis|to|until)\\s?(\\d{1,2})(?::(\\d{2}))?\\s?(uhr|h|am|pm)?\(end)") { g in
            guard !(g[2].isEmpty && g[3].isEmpty && g[5].isEmpty && g[6].isEmpty) else { return false }   // "10-12" alone is not a time
            let mer = g[6].isEmpty ? g[3] : g[6]
            let m1 = ["am", "pm"].contains(mer) ? mer : "", m2 = m1
            guard var h1 = apply(Int(g[1])!, g[3].isEmpty ? m1 : g[3]), let h2 = apply(Int(g[4])!, m2) else { return false }
            if h1 > h2, m1 == "pm", g[3].isEmpty { h1 -= 12 }
            let a = h1 * 60 + (Int(g[2]) ?? 0), b = h2 * 60 + (Int(g[5]) ?? 0)
            guard a < b, (Int(g[2]) ?? 0) < 60, (Int(g[5]) ?? 0) < 60 else { return false }
            minutes = a; endMinutes = b; return true
        }
        if minutes == nil {   // halb drei = 2:30
            take("(?<=\\s)halb\\s(\\d{1,2}|\(numberAlt))\(end)") { g in
                guard var h = number(g[1]), (1...12).contains(h) else { return false }
                h -= 1; if h == 0 { h = 12 }
                if h < 12 && h >= 1 && h <= 6 { h += 12; warnings.append(L("„halb \(g[1])“ als \(String(format: "%02d:30", h)) gelesen (nachmittags angenommen)", "“half \(g[1])” read as \(String(format: "%02d:30", h)) (afternoon assumed)")) }
                minutes = h * 60 + 30; return true
            }
        }
        if minutes == nil {
            take("(?<=\\s)(\\d{1,2}):(\\d{2})\\s?(am|pm)?\(end)") { g in
                guard let h = apply(Int(g[1])!, g[3]), Int(g[2])! < 60 else { return false }
                minutes = h * 60 + Int(g[2])!; return true
            }
        }
        if minutes == nil {
            take("(?<=\\s)(\\d{1,2})\\s?(uhr|h|am|pm)\(end)") { g in
                guard let h = apply(Int(g[1])!, g[2]) else { return false }
                minutes = h * 60; return true
            }
        }
        if minutes == nil { take("(?<=\\s)(mittags?|noon)\(end)") { _ in minutes = 12 * 60; return true } }
        if minutes == nil { take("(?<=\\s)(mitternacht|midnight)\(end)") { _ in minutes = 0; return true } }

        // duration: "für 2 Stunden", "for 90 minutes", "30 min", "anderthalb Stunden"
        take("(?<=\\s)(?:für|for)?\\s?(anderthalb|\\d+(?:[.,]\\d+)?)\\s?(stunden|stunde|std|hours|hour|hrs|hr|minuten|minute|min|minutes|mins)\(end)") { g in
            let v = g[1] == "anderthalb" ? 1.5 : Double(g[1].replacingOccurrences(of: ",", with: ".")) ?? 0
            guard v > 0 else { return false }
            duration = Int((g[2].hasPrefix("m") ? v : v * 60).rounded()); return duration! > 0 && duration! < 24 * 60
        }

        // 4. connectors in front of what was recognised, then the markers
        for _ in 0..<3 { s = s.replacingOccurrences(of: "(?i)(?<=\\s)(um|at|am|on|von|from|bis|to|für|for|ab|den|the)\\s*\\x{01}", with: "\u{1}", options: .regularExpression) }

        // 5. place: "@ Café Luise", "in Berlin", "bei Müller", "at Joe's" (only behind a title)
        var location = ""
        // The place is the text behind "in/bei/@/at" up to the next marker, or up to the end of the sentence.
        for pat in ["(?<=\\S)\\s(?:@|in|bei|im|at)\\s+([^\\x{01}]+?)\\s*(?=\\x{01})", "(?<=\\S)\\s(?:@|in|bei|im|at)\\s+([^\\x{01}]+?)\\s*\\z"] {
            guard location.isEmpty, let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: s.trimmingCharacters(in: .whitespaces).isEmpty ? s : s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s),
                  let whole = Range(m.range, in: s) else { continue }
            let loc = s[r].trimmingCharacters(in: .whitespaces)
            if !loc.isEmpty, loc.split(separator: " ").count <= 5 { location = loc; s.replaceSubrange(whole, with: " ") }
        }
        s = s.replacingOccurrences(of: "\u{1}", with: " ")
        let title = s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:-–"))

        let base = day ?? today
        var q: MLQuick
        if let mi = minutes {
            let st = cal.date(byAdding: .minute, value: mi, to: base)!
            let en: Date
            if let e = endMinutes { en = cal.date(byAdding: .minute, value: e, to: base)! }
            else { en = st.addingTimeInterval(TimeInterval((duration ?? 60) * 60)) }
            q = MLQuick(title: title, start: st, end: en, allDay: false, hasDate: day != nil, hasTime: true)
        } else {
            if duration != nil { warnings.append(L("Dauer ohne Uhrzeit ignoriert", "Duration without a time ignored")) }
            q = MLQuick(title: title, start: base, end: base, allDay: true, hasDate: day != nil, hasTime: false)
        }
        q.location = location; q.repeatRule = rule; q.warnings = warnings
        return q
    }

    private static func setMonthDay(_ day: inout Date?, _ m: Int, _ d: Int, _ year: String, _ today: Date, _ cal: Calendar, _ ymd: (Int, Int, Int) -> Date?) -> Bool {
        let y = year.isEmpty ? cal.component(.year, from: today) : Int(year)!
        guard var dt = ymd(y, m, d) else { return false }
        if year.isEmpty, dt < today { dt = ymd(y + 1, m, d) ?? dt }
        day = dt; return true
    }
}
