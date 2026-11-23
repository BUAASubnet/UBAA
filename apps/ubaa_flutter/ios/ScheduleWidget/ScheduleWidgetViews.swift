import SwiftUI
import WidgetKit

// 主屏：主题色只管底板、今天和状态；课程按课名分色，色相与应用内课表一致。
// 渲染管线不能横向滚动，竖向 ScrollView 会画出裁剪诊断带，近日列表因此固定三行。

private struct SchedulePaletteKey: EnvironmentKey {
    static let defaultValue = SchedulePalette.resolve(
        theme: .ocean, scheme: .light, accented: false)
}

extension EnvironmentValues {
    var schedulePalette: SchedulePalette {
        get { self[SchedulePaletteKey.self] }
        set { self[SchedulePaletteKey.self] = newValue }
    }
}

extension View {
    /// 着色 / 锁屏模式下把这一笔交给系统强调色；全彩模式无效果。
    @ViewBuilder
    func scheduleAccentable(_ on: Bool = true) -> some View {
        if #available(iOS 16.0, *), on {
            self.widgetAccentable(true)
        } else {
            self
        }
    }

    @ViewBuilder
    func scheduleWidgetChrome(theme: ScheduleTheme) -> some View {
        modifier(ScheduleWidgetChromeModifier(theme: theme))
    }
}

@available(iOS 16.0, *)
private func scheduleAccessory(_ family: WidgetFamily) -> Bool {
    switch family {
    case .accessoryInline, .accessoryCircular, .accessoryRectangular:
        return true
    default:
        return false
    }
}

private struct ScheduleWidgetChromeModifier: ViewModifier {
    var theme: ScheduleTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        ScheduleWidgetChromeHost(
            theme: theme, scheme: scheme, family: family, content: content)
    }
}

private struct ScheduleWidgetChromeHost<Content: View>: View {
    var theme: ScheduleTheme
    var scheme: ColorScheme
    var family: WidgetFamily
    var content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            ScheduleWidgetModeChrome(
                theme: theme, scheme: scheme, family: family, content: content)
        } else {
            let palette = SchedulePalette.resolve(
                theme: theme, scheme: scheme, accented: false)
            content
                .environment(\.schedulePalette, palette)
                .padding(10)
                .background(palette.canvas)
        }
    }
}

@available(iOS 16.0, *)
private struct ScheduleWidgetModeChrome<Content: View>: View {
    var theme: ScheduleTheme
    var scheme: ColorScheme
    var family: WidgetFamily
    var content: Content
    @Environment(\.widgetRenderingMode) private var rendering

    var body: some View {
        let accented = rendering != .fullColor
        let palette = SchedulePalette.resolve(
            theme: theme, scheme: scheme, accented: accented)
        let styled = content.environment(\.schedulePalette, palette)
        if #available(iOS 17.0, *) {
            // 锁屏和系统着色模式用系统材质，避免自定义底板盖住模糊或染色。
            if scheduleAccessory(family) || accented {
                styled.containerBackground(.fill.tertiary, for: .widget)
            } else {
                styled.containerBackground(palette.canvas, for: .widget)
            }
        } else if scheduleAccessory(family) {
            styled
        } else {
            styled.padding(10).background(palette.canvas)
        }
    }
}

private let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

private func weekdayTitle(_ date: LocalDate) -> String {
    let index = min(max(date.isoWeekday - 1, 0), 6)
    return "\(weekdayNames[index]) \(date.monthDay)"
}

private func relativeDay(_ date: LocalDate, today: LocalDate) -> String {
    if date == today { return "今天" }
    if date == today.adding(days: 1) { return "明天" }
    if date == today.adding(days: 2) { return "后天" }
    return date.monthDay
}

// MARK: - 共用部件

struct ScheduleWidgetEmpty: View {
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
                .scheduleAccentable()
            Text("还没有课表")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text("打开 UBAA，登录并保存整个学期")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ScheduleFooter: View {
    var updatedAt: String?
    var extra: Int = 0
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        let stamp = "更新于 \(updatedAt.map(Self.trim) ?? "--")"
        Text(extra > 0 ? "还有 \(extra) 门，\(stamp)" : stamp)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `2026-11-15T12:34:56.000Z` → `11-15 20:34`（北京时间）。
    private static func trim(_ raw: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let date = f.date(from: raw) ?? plain.date(from: raw)
        guard let date else {
            return String(raw.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        let out = DateFormatter()
        out.calendar = LocalDate.calendar
        out.timeZone = TimeZone(identifier: "Asia/Shanghai")
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: date)
    }
}

private struct StatusCapsule: View {
    var inClass: Bool
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        // 着色模式下不用实心胶囊：字和底会变成同一种强调色，挤在一起看不清。
        Text(inClass ? "进行中" : "下一节")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if !palette.accented {
                    Capsule().fill(inClass ? palette.accent : palette.accent.opacity(0.14))
                }
            }
    }

    private var labelColor: Color {
        if palette.accented { return inClass ? Color.primary : Color.secondary }
        return inClass ? palette.onAccent : palette.accent
    }
}

// MARK: - 今日课程（小卡片与锁屏）

struct TodayScheduleWidgetView: View {
    var entry: ScheduleEntry
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        Group {
            if entry.isEmpty {
                ScheduleWidgetEmpty()
            } else {
                let today = LocalDate.today(now: entry.date)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(weekdayTitle(today))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        if entry.nextCourse != nil {
                            StatusCapsule(inClass: entry.inClass)
                        }
                    }
                    Spacer(minLength: 8)
                    if let item = entry.nextCourse {
                        hero(item.course)
                    } else {
                        Text(entry.todayAgenda.isEmpty ? "今天没有课" : "今天的课都上完了")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if entry.todayAgenda.count > 0 {
                        Text("今天 \(entry.todayAgenda.count) 门")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .dynamicTypeSize(.xSmall ... .large)
    }

    private func hero(_ course: WidgetCourse) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.courseName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let begin = course.beginTime, let end = course.endTime,
               !begin.isEmpty, !end.isEmpty {
                Text("\(begin)–\(end)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(entry.inClass ? palette.accent : palette.secondary)
                    .lineLimit(1)
            }
            placeLine(course)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .scheduleAccentable()
        }
    }

    @ViewBuilder
    private func placeLine(_ course: WidgetCourse) -> some View {
        let place = course.placeName.flatMap { $0.isEmpty ? nil : $0 }
        let teacher = ScheduleDisplay.teacher(from: course.weeksAndTeachers)
        if place != nil || teacher != nil {
            HStack(spacing: 6) {
                if let place {
                    Text(place)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let teacher {
                    Text(teacher)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// 锁屏矩形：课名一行，时间地点一行。系统负责单色，这里不铺主题色。
struct AccessoryTodayView: View {
    var entry: ScheduleEntry

    var body: some View {
        if let item = entry.nextCourse {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.course.courseName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(meta(item.course))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.inClass ? "进行中" : "下一节")
                    .font(.system(size: 11, weight: .medium))
                    .scheduleAccentable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.todayAgenda.isEmpty ? "今天没有课" : "今日课程已结束")
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func meta(_ course: WidgetCourse) -> String {
        var parts: [String] = []
        if let begin = course.beginTime, !begin.isEmpty {
            parts.append("\(begin)–\(course.endTime ?? "")")
        }
        if let place = course.placeName, !place.isEmpty {
            parts.append(place)
        }
        return parts.joined(separator: "  ")
    }
}

// MARK: - 近日课程（中组件，今天起三天）

struct UpcomingScheduleWidgetView: View {
    var entry: ScheduleEntry
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        Group {
            if entry.isEmpty {
                ScheduleWidgetEmpty()
            } else {
                let window = visibleAgenda()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("近日课程")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 8)
                        Text("今天起三天")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    if window.items.isEmpty {
                        Spacer(minLength: 8)
                        Text("这三天没有课")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.secondary)
                        Spacer(minLength: 8)
                    } else {
                        Spacer(minLength: 8)
                        rows(window.items)
                        Spacer(minLength: 8)
                    }
                    ScheduleFooter(updatedAt: entry.updatedAt, extra: window.extra)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .dynamicTypeSize(.xSmall ... .large)
        .clipped()
    }

    /// 中组件只放两行，行距才放得开；其余记在底部。
    private func visibleAgenda() -> (items: [SavedAgendaItem], extra: Int) {
        let limit = 2
        let today = LocalDate.today(now: entry.date)
        let clock = ScheduleTimeline.clock(now: entry.date)
        let all = entry.upcomingAgenda
        let ended = { (item: SavedAgendaItem) in
            ScheduleTimeline.hasEnded(item, today: today, clock: clock, agenda: entry.todayAgenda)
        }
        let upcoming = all.filter { !ended($0) }
        let finished = all.filter(ended)
        let items: [SavedAgendaItem]
        if upcoming.count >= limit {
            items = Array(upcoming.prefix(limit))
        } else if upcoming.isEmpty {
            items = Array(finished.suffix(limit))
        } else {
            let need = min(limit - upcoming.count, finished.count)
            items = Array(finished.suffix(need)) + upcoming
        }
        return (items, max(0, upcoming.count - limit))
    }

    private func rows(_ items: [SavedAgendaItem]) -> some View {
        let today = LocalDate.today(now: entry.date)
        let clock = ScheduleTimeline.clock(now: entry.date)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let focused = isFocus(item)
                AgendaRow(
                    item: item,
                    today: today,
                    showsDay: index == 0 || items[index - 1].date != item.date,
                    focused: focused
                )
                .opacity(ScheduleTimeline.hasEnded(item, today: today, clock: clock, agenda: entry.todayAgenda)
                         && !focused ? 0.42 : 1)
            }
        }
    }

    private func isFocus(_ item: SavedAgendaItem) -> Bool {
        guard let next = entry.nextCourse else { return false }
        return item.date == next.date
            && item.course.courseName == next.course.courseName
            && item.course.beginTime == next.course.beginTime
    }
}

struct AgendaRow: View {
    var item: SavedAgendaItem
    var today: LocalDate
    var showsDay: Bool
    var focused: Bool
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(relativeDay(item.date, today: today))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(focused ? palette.accent : palette.secondary)
                    .opacity(showsDay ? 1 : 0)
                Text(timeRange)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 84, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.course.courseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                meta
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(CourseTint.bar(name: item.course.courseName, palette: palette))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 2)
                    .scheduleAccentable()
            }
            Spacer(minLength: 0)
        }
    }

    private var timeRange: String {
        let begin = item.course.beginTime ?? ""
        let end = item.course.endTime ?? ""
        if begin.isEmpty { return "--:--" }
        if end.isEmpty { return begin }
        return "\(begin)–\(end)"
    }

    @ViewBuilder
    private var meta: some View {
        let place = item.course.placeName.flatMap { $0.isEmpty ? nil : $0 }
        let teacher = ScheduleDisplay.teacher(from: item.course.weeksAndTeachers)
        if place != nil || teacher != nil {
            HStack(spacing: 6) {
                if let place {
                    Text(place)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let teacher {
                    Text(teacher)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.ink)
        }
    }
}
