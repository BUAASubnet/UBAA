import WidgetKit

/// 一次渲染所需的全部课表状态，在时间线生成时计算完毕。
struct ScheduleEntry: TimelineEntry {
    /// 无本地课表投影时为空，视图显示引导文案。
    var owner: String?
    var updatedAt: String?
    /// 今天（1 天）与近日（3 天）的课程，按时间排序。
    var todayAgenda: [SavedAgendaItem]
    var upcomingAgenda: [SavedAgendaItem]
    /// 周课表显示的周（含翻周偏移）。
    var selected: SelectedWeek?
    /// 当前或下一节课，锁屏与小卡片使用。
    var nextCourse: SavedAgendaItem?
    /// 相对“现在”是否正在上课。
    var inClass: Bool
    var date: Date

    var isEmpty: Bool { owner == nil }
}

struct ScheduleTimelineProvider: TimelineProvider {
    typealias Entry = ScheduleEntry

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            owner: "placeholder", updatedAt: nil,
            todayAgenda: [], upcomingAgenda: [], selected: nil,
            nextCourse: nil, inClass: false, date: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(currentEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        let entry = currentEntry(now: now)
        // 课表投影由应用发布后主动刷新；此处只推进“当前/下一节”状态，
        // 与 Android 组件的 30 分钟刷新节奏对齐。
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry(now: Date) -> ScheduleEntry {
        let (owner, snapshot) = ScheduleWidgetStore.readState()
        let today = LocalDate.today(now: now)
        let time = Self.clock(now: now)
        var todayAgenda: [SavedAgendaItem] = []
        var upcomingAgenda: [SavedAgendaItem] = []
        var selected: SelectedWeek?
        var nextCourse: SavedAgendaItem?
        var inClass = false
        var updatedAt: String?
        if let snapshot {
            updatedAt = snapshot.semesters
                .first { $0.termCode == ScheduleWidgetParser.selectWeek(
                    semesters: snapshot.semesters, today: today)?.semester.termCode
                }?.updatedAt
            todayAgenda = ScheduleWidgetParser.savedAgenda(
                semesters: snapshot.semesters, today: today, days: 1)
            upcomingAgenda = ScheduleWidgetParser.savedAgenda(
                semesters: snapshot.semesters, today: today, days: 3)
            let offset = WeekOffsetStore.current(today: today)
            let base = ScheduleWidgetParser.selectWeek(semesters: snapshot.semesters, today: today)
            if let base, offset != 0 {
                let weeks = base.semester.weeks
                let index = weeks.firstIndex { $0.serialNumber == base.week.serialNumber } ?? 0
                let target = weeks.indices.contains(index + offset) ? weeks[index + offset] : base.week
                selected = SelectedWeek(semester: base.semester, week: target)
            } else {
                selected = base
            }
            (nextCourse, inClass) = Self.nextCourse(agenda: todayAgenda, now: time)
        }
        return ScheduleEntry(
            owner: owner, updatedAt: updatedAt,
            todayAgenda: todayAgenda, upcomingAgenda: upcomingAgenda,
            selected: selected, nextCourse: nextCourse, inClass: inClass,
            date: now
        )
    }

    /// `HH:mm` 的当日钟表时间，与课程起止字符串同一格式。
    static func clock(now: Date) -> String {
        let c = LocalDate.calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 当前课或之后的第一节课；今日没有更多课程时为 `nil`。
    static func nextCourse(
        agenda: [SavedAgendaItem], now: String
    ) -> (SavedAgendaItem?, Bool) {
        for item in agenda {
            let begin = item.course.beginTime ?? ""
            let end = item.course.endTime ?? ""
            if begin.isEmpty { continue }
            if now < begin { return (item, false) }
            if end.isEmpty || now <= end { return (item, true) }
        }
        return (nil, false)
    }
}
