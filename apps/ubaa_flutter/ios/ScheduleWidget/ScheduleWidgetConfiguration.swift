import SwiftUI
import WidgetKit

/// 按 family 选择锁屏或主屏渲染。
struct TodayWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    var entry: ScheduleEntry

    var body: some View {
        if #available(iOS 16.0, *), family == .accessoryRectangular {
            AccessoryTodayView(entry: entry)
        } else if #available(iOS 16.0, *), family == .accessoryInline {
            Text(entry.nextCourse.map {
                "\($0.course.beginTime ?? "") \($0.course.courseName)"
            } ?? (entry.todayAgenda.isEmpty ? "今天没有课" : "今日课程已结束"))
            .font(.footnote)
        } else if #available(iOS 16.0, *), family == .accessoryCircular {
            VStack(spacing: 0) {
                Text("\(entry.todayAgenda.count)")
                    .font(.title3.bold())
                    .scheduleAccentable()
                Text("今天").font(.caption2)
            }
        } else {
            TodayScheduleWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget 定义（iOS 15+ 静态版）

struct TodayScheduleWidget: Widget {
    /// 锁屏组件 family 为 iOS 16 引入，iOS 15 仅提供主屏小组件。
    static var families: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [.systemSmall, .accessoryRectangular, .accessoryInline]
        }
        return [.systemSmall]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "cn.edu.ubaa.today-schedule",
            provider: ScheduleTimelineProvider()
        ) { entry in
            TodayWidgetContent(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("今日课程")
        .description("当前或下一节课，随时了解今天要上什么课。")
        .supportedFamilies(Self.families)
    }
}

struct UpcomingScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "cn.edu.ubaa.upcoming-schedule",
            provider: ScheduleTimelineProvider()
        ) { entry in
            UpcomingScheduleWidgetView(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("近日课程")
        .description("今天起三天的课程安排。")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "cn.edu.ubaa.week-schedule",
            provider: ScheduleTimelineProvider()
        ) { entry in
            WeekScheduleWidgetView(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("周课表")
        .description("整周课表一览，可切换周次。")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Widget 定义（iOS 17+ 可配置配色版）

@available(iOS 17.0, *)
struct TodayConfiguredWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "cn.edu.ubaa.today-schedule",
            provider: ScheduleConfiguredProvider()
        ) { entry in
            TodayWidgetContent(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("今日课程")
        .description("当前或下一节课，长按可切换配色。")
        .supportedFamilies(TodayScheduleWidget.families)
    }
}

@available(iOS 17.0, *)
struct UpcomingConfiguredWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "cn.edu.ubaa.upcoming-schedule",
            provider: ScheduleConfiguredProvider()
        ) { entry in
            UpcomingScheduleWidgetView(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("近日课程")
        .description("今天起三天的课程安排，长按可切换配色。")
        .supportedFamilies([.systemMedium])
    }
}

@available(iOS 17.0, *)
struct WeekConfiguredWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "cn.edu.ubaa.week-schedule",
            provider: ScheduleConfiguredProvider()
        ) { entry in
            WeekScheduleWidgetView(entry: entry)
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("周课表")
        .description("整周课表一览，长按可切换配色。")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Xcode Canvas 预览（合成数据，不进入发布行为）

#if DEBUG
extension ScheduleEntry {
    /// 预览用合成课表，与真实投影同构。固定在周一上午，方便看“进行中”和今天列。
    static var preview: ScheduleEntry {
        let week = WidgetWeek(
            serialNumber: 12, name: "第12周",
            startDate: LocalDate(year: 2026, month: 11, day: 16),
            endDate: LocalDate(year: 2026, month: 11, day: 22),
            arrangedList: [
                WidgetCourse(
                    courseName: "高等数学", dayOfWeek: 1, beginSection: 1, endSection: 2,
                    beginTime: "08:00", endTime: "09:50", placeName: "主楼 A201",
                    weeksAndTeachers: "1-16周 张明"),
                WidgetCourse(
                    courseName: "大学英语", dayOfWeek: 1, beginSection: 3, endSection: 4,
                    beginTime: "10:10", endTime: "12:00", placeName: "教一楼 B305",
                    weeksAndTeachers: "1-16周 李华"),
                WidgetCourse(
                    courseName: "数据结构", dayOfWeek: 2, beginSection: 5, endSection: 6,
                    beginTime: "14:00", endTime: "15:50", placeName: "实验楼 102",
                    weeksAndTeachers: "3-14周 王强"),
                WidgetCourse(
                    courseName: "概率论", dayOfWeek: 4, beginSection: 3, endSection: 4,
                    beginTime: "10:10", endTime: "12:00", placeName: "主楼 A308",
                    weeksAndTeachers: "1-16周 赵敏"),
                WidgetCourse(
                    courseName: "形势与政策", dayOfWeek: 3, beginSection: 7, endSection: 8,
                    beginTime: "16:10", endTime: "18:00", placeName: "教一楼 C101",
                    weeksAndTeachers: "5-12周 陈亮"),
                WidgetCourse(
                    courseName: "线性代数", dayOfWeek: 1, beginSection: 1, endSection: 2,
                    beginTime: "08:00", endTime: "09:50", placeName: "主楼 B102",
                    weeksAndTeachers: "1-16周 刘洋"),
            ],
            times: [
                WidgetTimeSlot(section: 1, start: "08:00", end: "08:50"),
                WidgetTimeSlot(section: 2, start: "09:00", end: "09:50"),
                WidgetTimeSlot(section: 3, start: "10:10", end: "11:00"),
                WidgetTimeSlot(section: 4, start: "11:10", end: "12:00"),
                WidgetTimeSlot(section: 5, start: "14:00", end: "14:50"),
                WidgetTimeSlot(section: 6, start: "15:00", end: "15:50"),
                WidgetTimeSlot(section: 7, start: "16:10", end: "17:00"),
                WidgetTimeSlot(section: 8, start: "17:10", end: "18:00"),
            ]
        )
        let semester = WidgetSemester(
            termCode: "2026-2027-1",
            updatedAt: "2026-11-15T12:34:00.000Z",
            weeks: [week],
            name: "2026-2027 第一学期"
        )
        let agenda = [
            SavedAgendaItem(date: week.startDate, course: week.arrangedList[0]),
            SavedAgendaItem(date: week.startDate, course: week.arrangedList[1]),
            SavedAgendaItem(date: week.startDate.adding(days: 1), course: week.arrangedList[2]),
            SavedAgendaItem(date: week.startDate.adding(days: 2), course: week.arrangedList[4]),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 16, hour: 8, minute: 30))!
        return ScheduleEntry(
            owner: "preview", updatedAt: "2026-11-15T12:34:00.000Z",
            todayAgenda: Array(agenda.prefix(2)),
            upcomingAgenda: agenda,
            selected: SelectedWeek(semester: semester, week: week),
            nextCourse: agenda.first, inClass: true,
            theme: .ocean, date: morning
        )
    }
}

#Preview("今日课程（小）", as: .systemSmall) {
    TodayScheduleWidget()
} timeline: {
    [ScheduleEntry.preview]
}

#Preview("今日课程（锁屏矩形）", as: .accessoryRectangular) {
    TodayScheduleWidget()
} timeline: {
    [ScheduleEntry.preview]
}

#Preview("今日课程（锁屏文本）", as: .accessoryInline) {
    TodayScheduleWidget()
} timeline: {
    [ScheduleEntry.preview]
}

#Preview("近日课程（中）", as: .systemMedium) {
    UpcomingScheduleWidget()
} timeline: {
    [ScheduleEntry.preview]
}

#Preview("周课表（大）", as: .systemLarge) {
    WeekScheduleWidget()
} timeline: {
    [ScheduleEntry.preview]
}

#Preview("周课表 · 紧凑排版") {
    WeekCompactContent(
        entry: .preview,
        week: ScheduleEntry.preview.selected!.week
    )
    .padding(12)
    .frame(width: 336, height: 172)
    .background(SchedulePalette.resolve(theme: .ocean, scheme: .light, accented: false).canvas)
}

#Preview("近日一行 · 落日") {
    AgendaRow(
        item: ScheduleEntry.preview.upcomingAgenda[0],
        today: LocalDate(year: 2026, month: 11, day: 16),
        showsDay: true,
        focused: true
    )
    .padding()
    .environment(
        \.schedulePalette,
        SchedulePalette.resolve(theme: .sunset, scheme: .light, accented: false)
    )
    .frame(width: 340)
}
#endif
