import SwiftUI
import WidgetKit

@available(iOS 17.0, *)
enum ScheduleWidgetSurface {
    case upNext, today, todo, week

    var kind: String {
        switch self {
        case .upNext: "cn.edu.ubaa.today-schedule"
        case .today: "cn.edu.ubaa.upcoming-schedule"
        case .todo: "cn.edu.ubaa.todo"
        case .week: "cn.edu.ubaa.week-schedule"
        }
    }

    var name: String {
        switch self {
        case .upNext: "接下来"
        case .today: "今天"
        case .todo: "待办"
        case .week: "周课表"
        }
    }

    var description: String {
        switch self {
        case .upNext: "现在或接下来要去的课、博雅、预约和考试。长按可切换配色。"
        case .today: "今天剩下的安排，晚上自动换成明天。长按可切换配色。"
        case .todo: "7 天内要截止的作业和临近的考试。长按可切换配色。"
        case .week: "整周课表一览，长按可切换配色。"
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .upNext: [.systemSmall, .accessoryInline, .accessoryRectangular, .accessoryCircular]
        case .today: [.systemMedium]
        case .todo: [.systemSmall, .systemMedium]
        case .week: [.systemLarge]
        }
    }
}

@available(iOS 17.0, *)
struct ScheduleWidgetCard: View {
    let surface: ScheduleWidgetSurface
    let entry: ScheduleEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch surface {
            case .upNext: UpNextWidgetContent(entry: entry, family: family)
            case .today: TodayCardView(entry: entry)
            case .todo: TodoCardView(entry: entry, medium: family == .systemMedium)
            case .week: WeekScheduleWidgetView(entry: entry)
            }
        }
        .padding(scheduleAccessory(family) ? 0 : 12)
        .dynamicTypeSize(.xSmall ... .large)
    }
}

@available(iOS 17.0, *)
private struct ScheduleWidgetContent: View {
    let surface: ScheduleWidgetSurface
    let entry: ScheduleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ScheduleWidgetCard(surface: surface, entry: entry, family: family)
            .scheduleWidgetChrome(theme: entry.theme)
    }
}

@available(iOS 17.0, *)
@MainActor
private func configuredWidget(_ surface: ScheduleWidgetSurface) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: surface.kind, provider: ScheduleConfiguredProvider()) { entry in
        ScheduleWidgetContent(surface: surface, entry: entry)
    }
    .configurationDisplayName(surface.name)
    .description(surface.description)
    .supportedFamilies(surface.families)
    .contentMarginsDisabled()
}

@available(iOS 17.0, *)
struct UpNextConfiguredWidget: Widget {
    var body: some WidgetConfiguration { configuredWidget(.upNext) }
}

@available(iOS 17.0, *)
struct TodayConfiguredWidget: Widget {
    var body: some WidgetConfiguration { configuredWidget(.today) }
}

@available(iOS 17.0, *)
struct TodoConfiguredWidget: Widget {
    var body: some WidgetConfiguration { configuredWidget(.todo) }
}

@available(iOS 17.0, *)
struct WeekConfiguredWidget: Widget {
    var body: some WidgetConfiguration { configuredWidget(.week) }
}

#if DEBUG
@available(iOS 17.0, *)
struct SchedulePreviewWidget: Widget {
    let surface: ScheduleWidgetSurface

    init() { self.init(surface: .upNext) }

    init(surface: ScheduleWidgetSurface) { self.surface = surface }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: surface.kind, provider: ScheduleTimelineProvider()) { entry in
            ScheduleWidgetContent(surface: surface, entry: entry)
        }
        .configurationDisplayName(surface.name)
        .description(surface.description)
        .supportedFamilies(surface.families)
        .contentMarginsDisabled()
    }
}

@available(iOS 17.0, *)
#Preview("接下来（小）", as: .systemSmall) {
    SchedulePreviewWidget(surface: .upNext)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("接下来（锁屏行内）", as: .accessoryInline) {
    SchedulePreviewWidget(surface: .upNext)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("接下来（锁屏矩形）", as: .accessoryRectangular) {
    SchedulePreviewWidget(surface: .upNext)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("接下来（锁屏圆形）", as: .accessoryCircular) {
    SchedulePreviewWidget(surface: .upNext)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("今天（中）", as: .systemMedium) {
    SchedulePreviewWidget(surface: .today)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("待办（小）", as: .systemSmall) {
    SchedulePreviewWidget(surface: .todo)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("待办（中）", as: .systemMedium) {
    SchedulePreviewWidget(surface: .todo)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("周课表（大）", as: .systemLarge) {
    SchedulePreviewWidget(surface: .week)
} timeline: {
    ScheduleEntry.preview()
}

@available(iOS 17.0, *)
#Preview("周课表 · 紧凑排版") {
    let entry = ScheduleEntry.preview()
    if let week = entry.selected?.week {
        WeekCompactContent(entry: entry, week: week)
            .padding(12)
            .frame(width: 336, height: 172)
            .background(SchedulePalette.resolve(theme: .ocean, scheme: .light, accented: false).canvas)
    }
}
#endif
