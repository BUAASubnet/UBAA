import Foundation

/// 与 Android `WidgetSchedule.kt` 同合同的离线课表投影模型与选择逻辑。
/// 第一版与第二版快照共用周课表字段。
/// 本文件由 Runner 与 ScheduleWidget 扩展共同编译。

enum ScheduleDisplay {
    /// 详情页可显示未拆分的原文；组件空间有限，只显示能可靠提取的教师名。
    /// 「葛宁[主讲],王五[辅讲]」只留姓名写成「葛宁、王五」，角色标记在组件里只占位置。
    static func teacher(from weeksAndTeachers: String?) -> String? {
        guard let raw = weeksAndTeachers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let parts = raw.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let teachers: String
        if parts.count == 2, parts[0].contains("周") {
            teachers = parts[1]
        } else if parts.count == 1, !raw.contains("周") {
            teachers = raw
        } else {
            return nil
        }
        let names = teachers
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map {
                $0.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }
}

enum ScheduleWidgetModelError: Error {
    case invalidFormat
}

/// 无时区的公历日期，语义与 Java `LocalDate` 一致（`yyyy-MM-dd`）。
struct LocalDate: Comparable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ value: String) throws -> LocalDate {
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value
        else { throw ScheduleWidgetModelError.invalidFormat }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 与 `LocalDate.now(ZoneId.of("Asia/Shanghai"))` 对齐。
    static func today(now: Date = Date()) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    func adding(days: Int) -> LocalDate {
        let base = LocalDate.formatter.date(from: "\(year)-\(pad(month))-\(pad(day))")!
        let next = LocalDate.calendar.date(byAdding: .day, value: days, to: base)!
        let c = LocalDate.calendar.dateComponents([.year, .month, .day], from: next)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// ISO-8601 星期：周一 = 1 … 周日 = 7。
    var isoWeekday: Int {
        let base = LocalDate.formatter.date(from: "\(year)-\(pad(month))-\(pad(day))")!
        return LocalDate.calendar.component(.weekday, from: base) == 1
            ? 7
            : LocalDate.calendar.component(.weekday, from: base) - 1
    }

    func formatted() -> String { "\(year)-\(pad(month))-\(pad(day))" }
    /// `MM-DD`，用于标题。
    var monthDay: String { "\(pad(month))-\(pad(day))" }

    private func pad(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct WidgetCourse {
    var courseName: String
    var dayOfWeek: Int?
    var beginSection: Int?
    var endSection: Int?
    var beginTime: String?
    var endTime: String?
    var placeName: String?
    var weeksAndTeachers: String?
}

struct WidgetTimeSlot {
    var section: Int
    var start: String?
    var end: String?
}

struct WidgetWeek {
    var serialNumber: Int
    var name: String
    var startDate: LocalDate
    var endDate: LocalDate
    var arrangedList: [WidgetCourse]
    var times: [WidgetTimeSlot]
}

struct WidgetSemester {
    var termCode: String
    var updatedAt: String
    var weeks: [WidgetWeek]
    var name: String
}

struct WidgetSnapshot {
    var owner: String
    var semesters: [WidgetSemester]
    var horizonEnd: Date?
    var upNext: [WidgetUpNextSegment]?
    var today: [WidgetTodaySegment]?
    var todo: [WidgetTodoSegment]?
}

protocol WidgetCardSegment: Decodable {
    var from: Date { get }
    var hasPayload: Bool { get }
}

enum WidgetItemKind: String, Decodable {
    case course, exam, bykc, cgyy, judge, spoc, ygdk, local
}

struct WidgetCountdown: Decodable {
    enum Label: String, Decodable {
        case remaining = "还剩"
        case until = "还有"
    }

    let label: Label
    let target: Date
}

struct WidgetUpNextSegment: WidgetCardSegment {
    enum State: String, Decodable { case item, none, partial, termEnd }

    struct Primary: Decodable {
        let kind: WidgetItemKind
        let tag: String?
        let title: String
        let place: String?
        let timeText: String
        let dayText: String
        let startText: String
        let endText: String?
        let startAt: Date?
        let endAt: Date?
        let ongoing: Bool
        let countdown: WidgetCountdown?
        let extraCount: Int
        let `private`: Bool
        let link: String?
    }

    struct Secondary: Decodable {
        enum Kind: String, Decodable { case exam, next }
        let kind: Kind
        let text: String
        let `private`: Bool
        let link: String?
    }

    let from: Date
    let state: State
    let message: String?
    let primary: Primary?
    let secondary: Secondary?
    let cardLink: String?

    var hasPayload: Bool { state == .item ? primary != nil : message != nil }
}

struct WidgetTodaySegment: WidgetCardSegment {
    enum State: String, Decodable { case items, none, partial, termEnd }

    struct Row: Decodable {
        let kind: WidgetItemKind
        let tag: String?
        let title: String
        let place: String?
        let timeText: String
        let endText: String?
        let rangeText: String?
        let ongoing: Bool
        let `private`: Bool
        let link: String?
    }

    let from: Date
    let state: State
    let message: String?
    let dayLabel: String?
    let rows: [Row]
    let dueLine: String?
    let cardLink: String?

    var hasPayload: Bool { state == .items ? dayLabel != nil && !rows.isEmpty : message != nil }
}

struct WidgetTodoSegment: WidgetCardSegment {
    enum State: String, Decodable { case items, empty, noData }

    struct Row: Decodable {
        let kind: WidgetItemKind
        let title: String
        let leftText: String
        let sub: String
        let urgent: Bool
        let `private`: Bool
        let link: String?
    }

    let from: Date
    let state: State
    let message: String?
    let smallRow: Row?
    let smallFooter: String?
    let mediumRows: [Row]
    let mediumFooter: String?
    let staleText: String?
    let cardLink: String?

    var hasPayload: Bool { state == .items ? smallRow != nil && !mediumRows.isEmpty : message != nil }
}

struct SelectedWeek {
    var semester: WidgetSemester
    var week: WidgetWeek

    var index: Int? { semester.weeks.firstIndex { $0.serialNumber == week.serialNumber } }
    var canGoBack: Bool { index.map { $0 > 0 } ?? false }
    var canGoForward: Bool { index.map { $0 + 1 < semester.weeks.count } ?? false }
}

struct SavedAgendaItem {
    var date: LocalDate
    var course: WidgetCourse
}

enum ScheduleWeekLanes {
    typealias Placement = (course: WidgetCourse, lane: Int, count: Int)

    static func layout(_ courses: [WidgetCourse]) -> [Placement] {
        var output: [Placement] = []
        for day in 1...7 {
            let items = courses.filter { $0.dayOfWeek == day }.sorted {
                (($0.beginSection ?? 1), ($0.endSection ?? 1))
                    < (($1.beginSection ?? 1), ($1.endSection ?? 1))
            }
            var cluster: [(course: WidgetCourse, lane: Int)] = []
            var laneEnds: [Int] = []
            var clusterEnd = 0
            for course in items {
                let begin = course.beginSection ?? 1
                let end = max(course.endSection ?? begin, begin)
                if begin > clusterEnd {
                    output += cluster.map { ($0.course, $0.lane, laneEnds.count) }
                    cluster.removeAll(keepingCapacity: true)
                    laneEnds.removeAll(keepingCapacity: true)
                }
                let lane = laneEnds.firstIndex { $0 < begin } ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
                cluster.append((course, lane))
                clusterEnd = max(clusterEnd, end)
            }
            output += cluster.map { ($0.course, $0.lane, laneEnds.count) }
        }
        return output
    }
}

enum ScheduleWidgetParser {
    static func parseSnapshot(_ raw: [String: Any]) throws -> WidgetSnapshot {
        guard let version = raw["version"] as? Int, (1...2).contains(version) else {
            throw ScheduleWidgetModelError.invalidFormat
        }
        let owner = try string(raw["owner"], max: 128, allowEmpty: false)
        let terms = (raw["semesters"] as? [[String: Any]]) ?? []
        guard terms.count <= 32 else { throw ScheduleWidgetModelError.invalidFormat }
        var semesters: [WidgetSemester] = []
        for term in terms {
            let termCode = try string(term["term"], max: 128, allowEmpty: false)
            let weeks = (term["weeks"] as? [[String: Any]]) ?? []
            guard (1...80).contains(weeks.count) else { throw ScheduleWidgetModelError.invalidFormat }
            var rows: [WidgetWeek] = []
            for week in weeks {
                guard let number = week["number"] as? Int, number > 0,
                      let startRaw = week["start"] as? String,
                      let endRaw = week["end"] as? String
                else { throw ScheduleWidgetModelError.invalidFormat }
                let start = try LocalDate.parse(startRaw)
                let end = try LocalDate.parse(endRaw)
                guard start.isoWeekday == 1, start.adding(days: 6) == end
                else { throw ScheduleWidgetModelError.invalidFormat }
                let courses = (week["courses"] as? [[String: Any]]) ?? []
                guard courses.count <= 512 else { throw ScheduleWidgetModelError.invalidFormat }
                var classes: [WidgetCourse] = []
                for c in courses {
                    guard let day = c["day"] as? Int, (1...7).contains(day)
                    else { throw ScheduleWidgetModelError.invalidFormat }
                    let begin = c["begin"] as? Int
                    let finish = c["end"] as? Int
                    guard begin == nil || (1...32).contains(begin!),
                          finish == nil || (begin ?? 1)...32 ~= finish!
                    else { throw ScheduleWidgetModelError.invalidFormat }
                    classes.append(
                        WidgetCourse(
                            courseName: try string(c["name"], max: 2048, allowEmpty: true),
                            dayOfWeek: day,
                            beginSection: begin,
                            endSection: finish,
                            beginTime: try optionalString(c["startTime"]),
                            endTime: try optionalString(c["endTime"]),
                            placeName: try optionalString(c["place"]),
                            weeksAndTeachers: try optionalString(c["weeksAndTeachers"])
                        )
                    )
                }
                let times = (week["times"] as? [[String: Any]]) ?? []
                guard (1...32).contains(times.count) else { throw ScheduleWidgetModelError.invalidFormat }
                var slots: [WidgetTimeSlot] = []
                for t in times {
                    guard let section = t["section"] as? Int, (1...32).contains(section)
                    else { throw ScheduleWidgetModelError.invalidFormat }
                    slots.append(
                        WidgetTimeSlot(
                            section: section,
                            start: try optionalString(t["start"]),
                            end: try optionalString(t["end"])
                        )
                    )
                }
                guard Set(slots.map(\.section)).count == slots.count
                else { throw ScheduleWidgetModelError.invalidFormat }
                rows.append(
                    WidgetWeek(
                        serialNumber: number,
                        name: try string(week["name"], max: 2048, allowEmpty: true),
                        startDate: start,
                        endDate: end,
                        arrangedList: classes,
                        times: slots
                    )
                )
            }
            rows.sort { $0.serialNumber < $1.serialNumber }
            guard Set(rows.map(\.serialNumber)).count == rows.count
            else { throw ScheduleWidgetModelError.invalidFormat }
            semesters.append(
                WidgetSemester(
                    termCode: termCode,
                    updatedAt: (term["updatedAt"] as? String) ?? "",
                    weeks: rows,
                    name: try optionalString(term["name"]) ?? termCode
                )
            )
        }
        guard Set(semesters.map(\.termCode)).count == semesters.count
        else { throw ScheduleWidgetModelError.invalidFormat }
        var snapshot = WidgetSnapshot(owner: owner, semesters: semesters)
        if version == 2 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { value in
                let seconds = try value.singleValueContainer().decode(Int64.self)
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }
            if let horizon = decode(Date.self, raw["horizonEnd"], with: decoder) {
                snapshot.horizonEnd = horizon
                snapshot.upNext = decodeTable(raw["upNext"], before: horizon, with: decoder)
                snapshot.today = decodeTable(raw["today"], before: horizon, with: decoder)
                snapshot.todo = decodeTable(raw["todo"], before: horizon, with: decoder)
            }
        }
        return snapshot
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, _ raw: Any?, with decoder: JSONDecoder
    ) -> Value? {
        guard let raw, JSONSerialization.isValidJSONObject([raw]),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed])
        else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func decodeTable<Segment: WidgetCardSegment>(
        _ raw: Any?, before horizon: Date, with decoder: JSONDecoder
    ) -> [Segment]? {
        guard let table = decode([Segment].self, raw, with: decoder), !table.isEmpty else { return nil }
        var previous: Date?
        for segment in table {
            guard segment.hasPayload, segment.from < horizon,
                  previous.map({ $0 < segment.from }) ?? true else { return nil }
            previous = segment.from
        }
        return table
    }

    /// 与冻结旧版同序：指定学期、本日覆盖的最新学期、起始日期最新学期。
    static func selectWeek(
        semesters: [WidgetSemester],
        today: LocalDate,
        term: String? = nil,
        number: Int? = nil
    ) -> SelectedWeek? {
        let date = today.formatted()
        let available = semesters.filter { !$0.weeks.isEmpty }
        let semester: WidgetSemester? =
            available.first(where: { $0.termCode == term })
            ?? available
                .filter { $0.weeks.contains { date >= $0.startDate.formatted() && date <= $0.endDate.formatted() } }
                .max { $0.weeks.map(\.startDate).min()! < $1.weeks.map(\.startDate).min()! }
            ?? available.max { $0.weeks.map(\.startDate).min()! < $1.weeks.map(\.startDate).min()! }
        guard let semester else { return nil }
        let weeks = semester.weeks.sorted { $0.serialNumber < $1.serialNumber }
        let week: WidgetWeek? =
            weeks.first(where: { semester.termCode == term && $0.serialNumber == number })
            ?? weeks.first(where: { date >= $0.startDate.formatted() && date <= $0.endDate.formatted() })
            ?? (date < weeks.first!.startDate.formatted() ? weeks.first! : weeks.last!)
        guard let week else { return nil }
        return SelectedWeek(semester: semester, week: week)
    }

    /// 今天起 `days`（1...3）天的课程。
    static func savedAgenda(
        semesters: [WidgetSemester],
        today: LocalDate,
        days: Int
    ) -> [SavedAgendaItem] {
        guard (1...3).contains(days) else { return [] }
        return (0..<days).flatMap { offset -> [SavedAgendaItem] in
            let date = today.adding(days: offset)
            guard let selected = selectWeek(semesters: semesters, today: date),
                  date >= selected.week.startDate, date <= selected.week.endDate
            else { return [] }
            return selected.week.arrangedList
                .filter { $0.dayOfWeek == date.isoWeekday }
                .sorted { ($0.beginTime ?? "") < ($1.beginTime ?? "") }
                .map { SavedAgendaItem(date: date, course: $0) }
        }
    }

    private static func string(
        _ value: Any?, max: Int, allowEmpty: Bool
    ) throws -> String {
        guard let s = value as? String, s.count <= max,
              allowEmpty || !s.isEmpty
        else { throw ScheduleWidgetModelError.invalidFormat }
        return s
    }

    private static func optionalString(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let s = value as? String, s.count <= 2048
        else { throw ScheduleWidgetModelError.invalidFormat }
        return s
    }
}
