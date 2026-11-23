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

/// 当日钟点已过课程结束时间。时间字符串与 `HH:mm` 同形，可直接比较。
private func courseEnded(_ item: SavedAgendaItem, today: LocalDate, clock: String) -> Bool {
    if item.date < today { return true }
    guard item.date == today, let end = item.course.endTime, !end.isEmpty else { return false }
    return end < clock
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
        let clock = ScheduleTimelineProvider.clock(now: entry.date)
        let all = entry.upcomingAgenda
        let upcoming = all.filter { !courseEnded($0, today: today, clock: clock) }
        let finished = all.filter { courseEnded($0, today: today, clock: clock) }
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
        let clock = ScheduleTimelineProvider.clock(now: entry.date)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let focused = isFocus(item)
                AgendaRow(
                    item: item,
                    today: today,
                    showsDay: index == 0 || items[index - 1].date != item.date,
                    focused: focused
                )
                .opacity(courseEnded(item, today: today, clock: clock) && !focused ? 0.42 : 1)
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

private struct AgendaRow: View {
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

// MARK: - 周课表（大组件，七天网格）

struct WeekScheduleWidgetView: View {
    var entry: ScheduleEntry

    var body: some View {
        Group {
            if let week = entry.selected?.week {
                if #available(iOS 26.0, *) {
                    // StandBy 或远距离展示时系统给出 .simplified，切换为紧凑文字课表。
                    WeekDetailSwitch(
                        full: WeekFullContent(entry: entry, week: week),
                        compact: WeekCompactContent(entry: entry, week: week)
                    )
                } else {
                    WeekFullContent(entry: entry, week: week)
                }
            } else {
                ScheduleWidgetEmpty()
            }
        }
    }
}

/// iOS 26+ 依据系统的细节级别切换周课表排版。
@available(iOS 26.0, *)
struct WeekDetailSwitch: View {
    @Environment(\.levelOfDetail) private var levelOfDetail
    let full: WeekFullContent
    let compact: WeekCompactContent

    var body: some View {
        if levelOfDetail == .simplified {
            compact
        } else {
            full
        }
    }
}

struct WeekFullContent: View {
    var entry: ScheduleEntry
    var week: WidgetWeek
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(week.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(week.startDate.monthDay)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
            WeekGrid(week: week, now: entry.date)
            if #available(iOS 17.0, *) {
                HStack {
                    weekSwitcher
                    Spacer(minLength: 0)
                }
            }
            ScheduleFooter(updatedAt: entry.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(.xSmall ... .large)
    }

    @available(iOS 17.0, *)
    private var weekSwitcher: some View {
        HStack(spacing: 0) {
            Button(intent: WeekBumpIntent(delta: -1)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 22)
            }
            Button(intent: WeekBumpIntent(delta: 0)) {
                Text("本周")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(minWidth: 36, minHeight: 22)
            }
            Button(intent: WeekBumpIntent(delta: 1)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 22)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .background {
            Capsule().fill(palette.accent.opacity(palette.accented ? 0.16 : 0.12))
        }
    }
}

/// 每日一行的紧凑周课表，与 Android `renderCompactWeek` 同一信息结构。
struct WeekCompactContent: View {
    var entry: ScheduleEntry
    var week: WidgetWeek
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        let today = LocalDate.today(now: entry.date)
        VStack(alignment: .leading, spacing: 3) {
            Text("\(week.name) · \(week.startDate.monthDay)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
            ForEach(0..<7, id: \.self) { day in
                let classes = week.arrangedList
                    .filter { $0.dayOfWeek == day + 1 }
                    .sorted { ($0.beginTime ?? "") < ($1.beginTime ?? "") }
                let date = week.startDate.adding(days: day)
                let names = classes
                    .map { "\($0.beginTime ?? "") \($0.courseName)" }
                    .joined(separator: " / ")
                let isToday = date == today
                Text(
                    "周\(WeekGrid.weekdayLabels[day]) \(date.monthDay) · \(classes.count)门\n\(names.isEmpty ? "无课" : names)"
                )
                .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? palette.accent : palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            ScheduleFooter(updatedAt: entry.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 七天 × 节次网格。课程块按课名分色，今天一列浅底，当前时刻一条横线。
struct WeekGrid: View {
    var week: WidgetWeek
    var now: Date
    @Environment(\.schedulePalette) private var palette
    static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        GeometryReader { geo in
            let left: CGFloat = 36
            let top: CGFloat = 34
            let periods = max(week.times.count, 1)
            let column = (geo.size.width - left) / 7
            let row = (geo.size.height - top) / CGFloat(periods)
            ZStack(alignment: .topLeading) {
                todayWash(left: left, top: top, column: column, geo: geo)
                gridLines(left: left, top: top, column: column, row: row, periods: periods, geo: geo)
                headers(left: left, top: top, column: column)
                timeGutter(left: left, top: top, row: row)
                // 时刻线画在课程块下面，避免横线切过课名；圆点留在最上层。
                nowLine(left: left, top: top, row: row, geo: geo, showsDot: false)
                courseBlocks(left: left, top: top, column: column, row: row, periods: periods)
                if week.arrangedList.isEmpty {
                    Text("本周没有课")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .position(
                            x: left + (geo.size.width - left) / 2,
                            y: top + (geo.size.height - top) / 2
                        )
                }
                nowLine(left: left, top: top, row: row, geo: geo, showsDot: true)
            }
        }
    }

    private func todayIndex() -> Int? {
        let today = LocalDate.today(now: now)
        guard today >= week.startDate, today <= week.endDate else { return nil }
        let index = today.isoWeekday - 1
        return (0..<7).contains(index) ? index : nil
    }

    private func todayWash(
        left: CGFloat, top: CGFloat, column: CGFloat, geo: GeometryProxy
    ) -> some View {
        Group {
            if let index = todayIndex() {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.todayWash)
                    .frame(
                        width: max(column - 2, 1),
                        height: max(geo.size.height - top, 1)
                    )
                    .position(
                        x: left + column * (CGFloat(index) + 0.5),
                        y: top + max(geo.size.height - top, 1) / 2
                    )
            }
        }
    }

    @ViewBuilder
    private func headers(left: CGFloat, top: CGFloat, column: CGFloat) -> some View {
        let today = todayIndex()
        ForEach(0..<7, id: \.self) { day in
            let isToday = today == day
            VStack(spacing: 1) {
                Text("周\(Self.weekdayLabels[day])")
                    .font(.system(size: 12, weight: isToday ? .bold : .semibold))
                Text(week.startDate.adding(days: day).monthDay)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background {
                        if isToday {
                            Capsule().fill(palette.accent.opacity(palette.accented ? 0.2 : 0.16))
                        }
                    }
            }
            .foregroundStyle(headerColor(day: day, isToday: isToday))
            .scheduleAccentable(isToday)
            .frame(width: column)
            .position(x: left + column * (CGFloat(day) + 0.5), y: top / 2)
        }
    }

    private func headerColor(day: Int, isToday: Bool) -> Color {
        if isToday { return palette.accent }
        return day >= 5 ? palette.tertiary : palette.secondary
    }

    private func timeGutter(left: CGFloat, top: CGFloat, row: CGFloat) -> some View {
        ForEach(Array(week.times.enumerated()), id: \.offset) { index, slot in
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(slot.section)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink.opacity(0.8))
                Text(slot.start ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }
            .frame(width: left - 4, alignment: .trailing)
            .position(x: (left - 4) / 2, y: top + row * (CGFloat(index) + 0.5))
        }
    }

    private func gridLines(
        left: CGFloat, top: CGFloat, column: CGFloat, row: CGFloat,
        periods: Int, geo: GeometryProxy
    ) -> some View {
        Path { path in
            for i in 0...periods {
                let y = top + CGFloat(i) * row
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            for i in 0...7 {
                let x = left + CGFloat(i) * column
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }
        }
        .stroke(palette.hairline, lineWidth: 0.5)
    }

    private func nowLine(
        left: CGFloat, top: CGFloat, row: CGFloat, geo: GeometryProxy, showsDot: Bool
    ) -> some View {
        Group {
            if todayIndex() != nil, let fraction = Self.nowFraction(times: week.times, now: now) {
                let y = top + row * fraction
                if showsDot {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)
                        .position(x: left, y: y)
                        .scheduleAccentable()
                } else {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(geo.size.width - left, 0), height: 1.5)
                        .position(x: left + (geo.size.width - left) / 2, y: y)
                        .scheduleAccentable()
                }
            }
        }
    }

    /// 把当前钟点映射到节次坐标：0 是第一节顶边，整数是节与节的分界。
    private static func nowFraction(times: [WidgetTimeSlot], now: Date) -> CGFloat? {
        guard let first = minutes(times.first?.start) else { return nil }
        let parts = LocalDate.calendar.dateComponents([.hour, .minute], from: now)
        let current = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard current >= first else { return nil }
        if let last = minutes(times.last?.end), current > last { return nil }
        for (index, slot) in times.enumerated() {
            guard let slotStart = minutes(slot.start) else { continue }
            let slotEnd = minutes(slot.end) ?? slotStart
            if current < slotStart { return CGFloat(index) }
            if current <= slotEnd {
                let span = max(slotEnd - slotStart, 1)
                return CGFloat(index) + CGFloat(current - slotStart) / CGFloat(span)
            }
        }
        return nil
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1].prefix(2)),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    private func courseBlocks(
        left: CGFloat, top: CGFloat, column: CGFloat, row: CGFloat, periods: Int
    ) -> some View {
        let lanes = Self.laneLayout(week.arrangedList)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { _, placed in
            let course = placed.0
            let lane = placed.1
            let lanesInColumn = placed.2
            let begin = min(max(course.beginSection ?? 1, 1), periods)
            let end = min(max(course.endSection ?? begin, begin), periods)
            let laneWidth = column / CGFloat(max(lanesInColumn, 1))
            let blockWidth = max(laneWidth - 3, 4)
            let blockHeight = max(CGFloat(end - begin + 1) * row - 3, 8)
            let narrow = blockWidth < 28
            let showPlace = !narrow && blockHeight >= 34 && blockWidth >= 30
            let ink = CourseTint.ink(palette: palette)
            VStack(spacing: 1) {
                Spacer(minLength: 0)
                Text(course.courseName)
                    .font(.system(size: narrow ? 9 : (blockHeight >= 40 ? 12 : 10), weight: .semibold))
                    .lineLimit(narrow ? 4 : 2)
                    .minimumScaleFactor(narrow ? 0.65 : 0.75)
                    .multilineTextAlignment(.center)
                if showPlace, let place = course.placeName, !place.isEmpty {
                    Text(place)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(blockHeight >= 52 ? 2 : 1)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .opacity(0.78)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 2)
            .frame(width: blockWidth, height: blockHeight)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CourseTint.fill(name: course.courseName, palette: palette))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .position(
                x: left + CGFloat((course.dayOfWeek ?? 1) - 1) * column
                    + laneWidth * (CGFloat(lane) + 0.5),
                y: top + row * (CGFloat(begin - 1) + CGFloat(end - begin + 1) / 2)
            )
        }
    }

    /// 同时段课程分道并排，返回（课程, 道号, 同列道数）。
    private static func laneLayout(_ courses: [WidgetCourse]) -> [(WidgetCourse, Int, Int)] {
        var output: [(WidgetCourse, Int, Int)] = []
        for day in 1...7 {
            let items = courses
                .filter { $0.dayOfWeek == day }
                .sorted {
                    (($0.beginSection ?? 1), ($0.endSection ?? 1))
                        < (($1.beginSection ?? 1), ($1.endSection ?? 1))
                }
            var lanes: [Int] = []
            let placed: [(WidgetCourse, Int)] = items.map { course in
                let begin = course.beginSection ?? 1
                var lane = lanes.firstIndex { $0 < begin } ?? -1
                if lane < 0 {
                    lane = lanes.count
                    lanes.append(0)
                }
                lanes[lane] = course.endSection ?? begin
                return (course, lane)
            }
            for (course, lane) in placed {
                // 只和真正重叠的课分道。上午两门并排时，下午独自的课仍占满整列。
                let concurrent = items.filter { Self.overlaps($0, course) }.count
                output.append((course, lane, max(concurrent, lane + 1)))
            }
        }
        return output
    }

    private static func overlaps(_ a: WidgetCourse, _ b: WidgetCourse) -> Bool {
        let a0 = a.beginSection ?? 1
        let a1 = max(a.endSection ?? a0, a0)
        let b0 = b.beginSection ?? 1
        let b1 = max(b.endSection ?? b0, b0)
        return a0 <= b1 && b0 <= a1
    }
}

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
                .widgetURL(URL(string: "ubaa://schedule"))
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
                .widgetURL(URL(string: "ubaa://schedule"))
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
                .widgetURL(URL(string: "ubaa://schedule"))
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("UBAA 周课表")
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
                .widgetURL(URL(string: "ubaa://schedule"))
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
                .widgetURL(URL(string: "ubaa://schedule"))
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
                .widgetURL(URL(string: "ubaa://schedule"))
                .scheduleWidgetChrome(theme: entry.theme)
        }
        .configurationDisplayName("UBAA 周课表")
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

#Preview("UBAA 周课表（大）", as: .systemLarge) {
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
