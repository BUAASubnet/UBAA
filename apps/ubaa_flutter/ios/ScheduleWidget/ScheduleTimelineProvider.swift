import WidgetKit

struct ScheduleEntry: TimelineEntry {
    enum Publication {
        case missing, unreadable, published
    }

    let date: Date
    let theme: ScheduleTheme
    let publication: Publication
    var isEmpty: Bool { publication == .missing }
    let upNext: WidgetUpNextSegment?
    let today: WidgetTodaySegment?
    let todo: WidgetTodoSegment?
    let selected: SelectedWeek?
}

struct ScheduleTimelineProvider: TimelineProvider {
    typealias Entry = ScheduleEntry

    func placeholder(in context: Context) -> ScheduleEntry {
        .preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(context.isPreview ? .preview() : currentEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        completion(timeline(now: Date()))
    }

    func timeline(now: Date, theme: ScheduleTheme = .ocean, store: ScheduleWidgetStore = .shared) -> Timeline<ScheduleEntry> {
        timeline(now: now, theme: theme, state: store.readState())
    }

    func timeline(now: Date, theme: ScheduleTheme, snapshot: WidgetSnapshot?) -> Timeline<ScheduleEntry> {
        timeline(now: now, theme: theme, state: snapshot.map { .available($0) } ?? .missing)
    }

    private func timeline(now: Date, theme: ScheduleTheme, state: ScheduleWidgetStore.ReadState) -> Timeline<ScheduleEntry> {
        guard let snapshot = state.snapshot else {
            let policy: TimelineReloadPolicy
            if case .unavailable = state {
                policy = .after(now.addingTimeInterval(15 * 60))
            } else {
                policy = .never
            }
            return Timeline(entries: [entry(now: now, theme: theme, state: state)], policy: policy)
        }
        let windowEnd = now.addingTimeInterval(24 * 60 * 60)
        let fallback = now.addingTimeInterval(6 * 60 * 60)
        let starts = (snapshot.upNext ?? []).map(\.from)
            + (snapshot.today ?? []).map(\.from) + (snapshot.todo ?? []).map(\.from)
        let agenda = ScheduleWidgetParser.savedAgenda(semesters: snapshot.semesters, today: LocalDate.today(now: now), days: 1)
        var dates = Set(ScheduleTimeline.dates(now: now, agenda: agenda))
        dates.formUnion(starts.filter { $0 >= now })
        if let horizon = snapshot.horizonEnd, horizon >= now {
            dates.insert(horizon)
        }
        let sortedDates = dates.sorted()
        let entryDates = sortedDates.prefix(100).prefix { $0 <= windowEnd }
        let entries = entryDates.map { entry(now: $0, theme: theme, state: state) }
        let next = sortedDates.dropFirst(entryDates.count).first
        return Timeline(entries: entries, policy: .after(min(next ?? fallback, fallback)))
    }

    func currentEntry(now: Date, theme: ScheduleTheme = .ocean, store: ScheduleWidgetStore = .shared) -> ScheduleEntry {
        entry(now: now, theme: theme, state: store.readState())
    }

    func entry(now: Date, theme: ScheduleTheme, snapshot: WidgetSnapshot?) -> ScheduleEntry {
        entry(now: now, theme: theme, state: snapshot.map { .available($0) } ?? .missing)
    }

    private func entry(now: Date, theme: ScheduleTheme, state: ScheduleWidgetStore.ReadState) -> ScheduleEntry {
        let snapshot = state.snapshot
        let publication: ScheduleEntry.Publication
        switch state {
        case .missing: publication = .missing
        case .unavailable, .corrupt: publication = .unreadable
        case .available: publication = .published
        }
        let today = LocalDate.today(now: now)
        let selected = snapshot.flatMap {
            ScheduleWidgetParser.selectWeek(semesters: $0.semesters, today: today)
        }.map {
            WeekOffsetStore.shared.selectedWeek(from: $0, today: today)
        }
        let withinHorizon = snapshot?.horizonEnd.map { now < $0 } ?? false
        return ScheduleEntry(
            date: now, theme: theme, publication: publication,
            upNext: withinHorizon ? segment(snapshot?.upNext, at: now) : nil,
            today: withinHorizon ? segment(snapshot?.today, at: now) : nil,
            todo: withinHorizon ? segment(snapshot?.todo, at: now) : nil,
            selected: selected
        )
    }

    private func segment<Segment: WidgetCardSegment>(_ table: [Segment]?, at now: Date) -> Segment? {
        table?.last { $0.from <= now } ?? table?.first
    }
}

extension ScheduleEntry {
    static func preview(theme: ScheduleTheme = .ocean) -> ScheduleEntry {
        let date = Date(timeIntervalSince1970: 1_794_793_800)
        let primary = WidgetUpNextSegment.Primary(
            kind: .bykc, tag: "博雅", title: "博雅讲座", place: "主楼 A201", timeText: "10:10",
            dayText: "", startText: "10:10", endText: "11:45", startAt: nil, endAt: nil,
            ongoing: false, countdown: nil, extraCount: 1, private: false, link: nil)
        let exam = WidgetTodoSegment.Row(
            kind: .exam, title: "高等数学", leftText: "还有 3 天", sub: "11-19 14:00 · 主 M101 · 座位 23",
            urgent: false, private: false, link: nil)
        let assignment = WidgetTodoSegment.Row(
            kind: .judge, title: "第三次上机作业", leftText: "今天 23:59", sub: "希冀作业",
            urgent: true, private: false, link: nil)
        let courses = [
            WidgetCourse(courseName: "大学英语", dayOfWeek: 1, beginSection: 3, endSection: 4,
                         beginTime: "10:10", endTime: "11:45", placeName: "教一 B305", weeksAndTeachers: nil),
            WidgetCourse(courseName: "高等数学", dayOfWeek: 2, beginSection: 1, endSection: 2,
                         beginTime: "08:00", endTime: "09:35", placeName: "主楼 A201", weeksAndTeachers: nil),
            WidgetCourse(courseName: "数据结构", dayOfWeek: 4, beginSection: 3, endSection: 4,
                         beginTime: "10:10", endTime: "11:45", placeName: "实验楼 102", weeksAndTeachers: nil),
        ]
        let times = [
            WidgetTimeSlot(section: 1, start: "08:00", end: "08:50"),
            WidgetTimeSlot(section: 2, start: "09:00", end: "09:35"),
            WidgetTimeSlot(section: 3, start: "10:10", end: "11:00"),
            WidgetTimeSlot(section: 4, start: "11:10", end: "11:45"),
            WidgetTimeSlot(section: 5, start: "14:00", end: "14:50"),
            WidgetTimeSlot(section: 6, start: "15:00", end: "15:50"),
            WidgetTimeSlot(section: 7, start: "16:10", end: "17:00"),
            WidgetTimeSlot(section: 8, start: "17:10", end: "18:00"),
        ]
        let day = LocalDate.today(now: date)
        let week = WidgetWeek(serialNumber: 12, name: "第12周", startDate: day, endDate: day.adding(days: 6),
                              arrangedList: courses, times: times)
        let semester = WidgetSemester(termCode: "2026-2027-1", updatedAt: "", weeks: [week], name: "第一学期")
        return ScheduleEntry(
            date: date, theme: theme, publication: .published,
            upNext: WidgetUpNextSegment(from: date, state: .item, message: nil, primary: primary,
                secondary: .init(kind: .exam, text: "14:00 考试 · 主 M101", private: false, link: nil), cardLink: nil),
            today: WidgetTodaySegment(from: date, state: .items, message: nil, dayLabel: "今天", rows: [
                .init(kind: .course, tag: nil, title: "大学英语", place: "教一 B305", timeText: "10:10",
                      endText: "11:45", rangeText: nil, ongoing: false, private: false, link: nil),
                .init(kind: .cgyy, tag: "预约", title: "研讨室预约", place: "研讨室 305", timeText: "14:00",
                      endText: "16:00", rangeText: nil, ongoing: false, private: false, link: nil),
            ], dueLine: "今天 1 项截止", cardLink: nil),
            todo: WidgetTodoSegment(from: date, state: .items, message: nil, smallRow: assignment,
                smallFooter: nil, mediumRows: [exam, assignment], mediumFooter: nil, staleText: nil, cardLink: nil),
            selected: SelectedWeek(semester: semester, week: week)
        )
    }
}
