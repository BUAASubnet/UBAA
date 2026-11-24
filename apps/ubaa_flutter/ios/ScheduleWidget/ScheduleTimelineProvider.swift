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
    /// 配色主题（iOS 17+ 可由用户配置）。
    var theme: ScheduleTheme
    var date: Date

    var isEmpty: Bool { owner == nil }
}

struct ScheduleTimelineProvider: TimelineProvider {
    typealias Entry = ScheduleEntry

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            owner: "placeholder", updatedAt: nil,
            todayAgenda: [], upcomingAgenda: [], selected: nil,
            nextCourse: nil, inClass: false, theme: .ocean, date: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(currentEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        completion(timeline(now: Date()))
    }

    func timeline(now: Date, theme: ScheduleTheme = .ocean) -> Timeline<ScheduleEntry> {
        let snapshot = ScheduleWidgetStore.shared.readState().snapshot
        let initial = entry(now: now, theme: theme, snapshot: snapshot)
        let entries = ScheduleTimeline.dates(now: now, agenda: initial.todayAgenda).dropFirst()
            .map { entry(now: $0, theme: theme, snapshot: snapshot) }
        return Timeline(entries: [initial] + entries, policy: .atEnd)
    }

    func currentEntry(now: Date, theme: ScheduleTheme = .ocean) -> ScheduleEntry {
        entry(now: now, theme: theme, snapshot: ScheduleWidgetStore.shared.readState().snapshot)
    }

    private func entry(now: Date, theme: ScheduleTheme, snapshot: WidgetSnapshot?) -> ScheduleEntry {
        let today = LocalDate.today(now: now)
        let time = ScheduleTimeline.clock(now: now)
        var todayAgenda: [SavedAgendaItem] = []
        var upcomingAgenda: [SavedAgendaItem] = []
        var selected: SelectedWeek?
        var nextCourse: SavedAgendaItem?
        var inClass = false
        var updatedAt: String?
        if let snapshot {
            todayAgenda = ScheduleWidgetParser.savedAgenda(
                semesters: snapshot.semesters, today: today, days: 1)
            upcomingAgenda = ScheduleWidgetParser.savedAgenda(
                semesters: snapshot.semesters, today: today, days: 3)
            if let base = ScheduleWidgetParser.selectWeek(semesters: snapshot.semesters, today: today) {
                updatedAt = base.semester.updatedAt
                selected = WeekOffsetStore.shared.selectedWeek(from: base, today: today)
            }
            (nextCourse, inClass) = ScheduleTimeline.nextCourse(agenda: todayAgenda, now: time)
        }
        return ScheduleEntry(
            owner: snapshot?.owner, updatedAt: updatedAt,
            todayAgenda: todayAgenda, upcomingAgenda: upcomingAgenda,
            selected: selected, nextCourse: nextCourse, inClass: inClass,
            theme: theme, date: now
        )
    }

}
