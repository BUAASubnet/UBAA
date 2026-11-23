import Foundation

enum ScheduleTimeline {
    static func dates(now: Date, agenda: [SavedAgendaItem]) -> [Date] {
        let calendar = LocalDate.calendar
        let startOfDay = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let edges = agenda.flatMap { [$0.course.beginTime, $0.course.endTime] }
            .compactMap { minutes($0) }
            .compactMap { calendar.date(byAdding: .minute, value: $0, to: startOfDay) }
            .filter { $0 > now && $0 < midnight }
        return [now] + Set(edges).sorted() + [midnight]
    }

    static func clock(now: Date) -> String {
        let parts = LocalDate.calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func nextCourse(agenda: [SavedAgendaItem], now: String) -> (SavedAgendaItem?, Bool) {
        guard let current = minutes(now) else { return (nil, false) }
        for item in agenda {
            guard let start = minutes(item.course.beginTime) else { continue }
            if current < start { return (item, false) }
            if current < end(of: item, in: agenda) { return (item, true) }
        }
        return (nil, false)
    }

    static func hasEnded(_ item: SavedAgendaItem, today: LocalDate, clock: String, agenda: [SavedAgendaItem]) -> Bool {
        if item.date < today { return true }
        guard item.date == today, let current = minutes(clock) else { return false }
        return current >= end(of: item, in: agenda)
    }

    private static func end(of item: SavedAgendaItem, in agenda: [SavedAgendaItem]) -> Int {
        if let explicit = minutes(item.course.endTime) { return explicit }
        guard let start = minutes(item.course.beginTime) else { return 24 * 60 }
        return agenda.lazy.compactMap { minutes($0.course.beginTime) }.first { $0 > start } ?? 24 * 60
    }

    private static func minutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
