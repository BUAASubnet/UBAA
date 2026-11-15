import SwiftUI
import WidgetKit

// 绘制结构对齐 Android `WidgetRenderer.kt` 的信息布局，卡片化呈现课程、
// 任课教师与上课地点；近日列表在 iOS 26+ 支持上下滑动（系统自动启用）。

private let ink = Color(red: 40 / 255, green: 58 / 255, blue: 80 / 255)
private let gridLine = Color(red: 220 / 255, green: 229 / 255, blue: 241 / 255)

extension View {
    /// iOS 17+ 使用系统组件背景，低版本退回纯色填充；
    /// 锁屏组件由系统提供背景，本修饰对其无效。
    @ViewBuilder
    func scheduleWidgetChrome() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.padding(10).background(Color(white: 0.96))
        }
    }
}

// MARK: - 共用部件

struct ScheduleWidgetEmpty: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UBAA 课表")
                .font(.headline)
                .foregroundColor(ink)
            Text("请先打开 UBAA，登录并保存整个学期")
                .font(.caption2)
                .foregroundColor(ink.opacity(0.75))
            Spacer(minLength: 0)
            Text("本地课表 · 点击打开应用")
                .font(.caption2)
                .foregroundColor(ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ScheduleFooter: View {
    var updatedAt: String?
    var body: some View {
        Text("本地课表 · 更新于 \(updatedAt.map(Self.trim) ?? "--")")
            .font(.caption2)
            .foregroundColor(ink.opacity(0.55))
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

/// 横向空间不足时整体等比缩字显示完整内容。
/// widget 渲染管线不支持水平滚动（系统会标注禁止滚动），故以缩放适配。
struct MarqueeRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .fixedSize(horizontal: true, vertical: false)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// 教师 / 地点 / 时间标签行，图标 + 文字，醒目易扫。
struct CourseMetaLine: View {
    var course: WidgetCourse
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            if let teacher = ScheduleDisplay.teacher(from: course.weeksAndTeachers) {
                Label(teacher, systemImage: "person.fill")
                    .labelStyle(MetaLabelStyle())
            }
            if let place = course.placeName, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
                    .labelStyle(MetaLabelStyle())
            }
            if !compact, let begin = course.beginTime, let end = course.endTime {
                Label("\(begin)–\(end)", systemImage: "clock")
                    .labelStyle(MetaLabelStyle())
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8))
            configuration.title.font(.system(size: 9.5, weight: .medium))
        }
        .foregroundColor(ink.opacity(0.8))
    }
}

/// 课程卡片：主题色条 + 课程名 + 教师/地点。
struct CourseCard: View {
    var course: WidgetCourse
    var theme: ScheduleTheme
    var showTime = true

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.accent)
                .frame(width: 3.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.courseName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                CourseMetaLine(course: course, compact: !showTime)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(theme.cardFill)
        )
    }
}

// MARK: - 今日课程（小卡片与锁屏）

struct TodayScheduleWidgetView: View {
    var entry: ScheduleEntry

    var body: some View {
        Group {
            if entry.isEmpty {
                ScheduleWidgetEmpty()
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(entry.theme.accent)
                            .frame(width: 3, height: 11)
                        Text("今日课程 · \(LocalDate.today(now: entry.date).monthDay)")
                            .font(.caption2.bold())
                            .foregroundColor(ink)
                    }
                    if let item = entry.nextCourse {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(entry.inClass ? Color.red : entry.theme.accent)
                                .frame(width: 5, height: 5)
                            Text(entry.inClass ? "正在上课" : "下一节")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(entry.inClass ? .red : entry.theme.accent)
                        }
                        // 时间优先、大字；每行一个元素，放不下整体横滚。
                        if let begin = item.course.beginTime, let end = item.course.endTime {
                            MarqueeRow {
                                Text("\(begin)–\(end)")
                                    .font(.system(size: 15.5, weight: .bold))
                                    .foregroundColor(ink.opacity(0.85))
                                    .foregroundColor(ink)
                            }
                            .frame(height: 21)
                        }
                        MarqueeRow {
                            Text(item.course.courseName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(ink)
                        }
                        .frame(height: 19)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let place = item.course.placeName, !place.isEmpty {
                                Text(place)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(entry.theme.accent)
                                    .lineLimit(1)
                            }
                            if let teacher = ScheduleDisplay.teacher(from: item.course.weeksAndTeachers) {
                                Text(teacher)
                                    .font(.system(size: 10))
                                    .foregroundColor(ink.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Spacer(minLength: 2)
                        Text(entry.todayAgenda.isEmpty ? "今天没有课" : "今天的课都上完了")
                            .font(.callout)
                            .foregroundColor(ink.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    Text("今天 \(entry.todayAgenda.count) 门")
                        .font(.caption2)
                        .foregroundColor(ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// 锁屏：矩形显示下一节课。
struct AccessoryTodayView: View {
    var entry: ScheduleEntry

    var body: some View {
        if let item = entry.nextCourse {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.inClass ? "正在上课" : "下一节")
                    .font(.caption2)
                Text(item.course.courseName)
                    .font(.footnote.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let begin = item.course.beginTime {
                        Text("\(begin)–\(item.course.endTime ?? "")")
                    }
                    if let teacher = ScheduleDisplay.teacher(from: item.course.weeksAndTeachers) {
                        Text(teacher)
                    }
                    if let place = item.course.placeName, !place.isEmpty {
                        Text(place).lineLimit(1)
                    }
                }
                .font(.caption2)
            }
        } else {
            Text(entry.todayAgenda.isEmpty ? "今天没有课" : "今日课程已结束")
                .font(.footnote)
        }
    }
}

// MARK: - 近日课程（中组件，今天起三天，iOS 26+ 可滚动）

struct UpcomingScheduleWidgetView: View {
    var entry: ScheduleEntry

    var body: some View {
        Group {
            if entry.isEmpty {
                ScheduleWidgetEmpty()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(entry.theme.accent)
                            .frame(width: 3, height: 11)
                        Text("近日课程 · 今天起三天")
                            .font(.caption2.bold())
                            .foregroundColor(ink)
                        Spacer()
                    }
                    if entry.upcomingAgenda.isEmpty {
                        Text("没有已安排课程")
                            .font(.footnote)
                            .foregroundColor(ink.opacity(0.75))
                        Spacer()
                    } else {
                        // 静态三行；iOS 26+ 的滚动容器在模拟器会绘制裁剪诊断带，
                        // 纯静态布局最干净，更多课程进 App 查看。
                        agendaRows(Array(entry.upcomingAgenda.prefix(3)))
                        if entry.upcomingAgenda.count > 3 {
                            Text("另 \(entry.upcomingAgenda.count - 3) 门 · 打开应用查看")
                                .font(.system(size: 9))
                                .foregroundColor(ink.opacity(0.55))
                        }
                    }
                    ScheduleFooter(updatedAt: entry.updatedAt)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

extension UpcomingScheduleWidgetView {
    func agendaRows(_ items: [SavedAgendaItem]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                AgendaCard(item: item, theme: entry.theme)
            }
        }
    }
}

/// 近日列表的一行：上行日期时间+课程名，下行教室+教师（教室优先）。
struct AgendaCard: View {
    var item: SavedAgendaItem
    var theme: ScheduleTheme

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.accent)
                .frame(width: 3.5)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeRow {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(item.date.monthDay) \(item.course.beginTime ?? "")–\(item.course.endTime ?? "")")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(theme.accent)
                        Text(item.course.courseName)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(ink)
                    }
                }
                .frame(height: 14)
                MarqueeRow {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let place = item.course.placeName, !place.isEmpty {
                            Text(place)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(ink)
                        }
                        if let teacher = ScheduleDisplay.teacher(from: item.course.weeksAndTeachers) {
                            Text(teacher)
                                .font(.system(size: 9))
                                .foregroundColor(ink.opacity(0.6))
                        }
                    }
                }
                .frame(height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.cardFill))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(entry.theme.accent)
                    .frame(width: 3, height: 11)
                Text("\(week.name) · \(week.startDate.monthDay)")
                    .font(.caption2.bold())
                    .foregroundColor(ink)
            }
            WeekGrid(week: week, theme: entry.theme)
            if #available(iOS 17.0, *) {
                weekSwitcher
            }
            ScheduleFooter(updatedAt: entry.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @available(iOS 17.0, *)
    private var weekSwitcher: some View {
        HStack(spacing: 12) {
            Button(intent: WeekBumpIntent(delta: -1)) {
                Image(systemName: "chevron.left").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(entry.theme.accent)
            Button(intent: WeekBumpIntent(delta: 0)) {
                Text("本周").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(entry.theme.accent)
            Button(intent: WeekBumpIntent(delta: 1)) {
                Image(systemName: "chevron.right").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(entry.theme.accent)
            Spacer()
        }
    }
}

/// 每日一行的紧凑周课表，与 Android `renderCompactWeek` 同一信息结构。
struct WeekCompactContent: View {
    var entry: ScheduleEntry
    var week: WidgetWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(week.name) · \(week.startDate.monthDay)")
                .font(.caption2.bold())
                .foregroundColor(ink.opacity(0.7))
            ForEach(0..<7, id: \.self) { day in
                let classes = week.arrangedList
                    .filter { $0.dayOfWeek == day + 1 }
                    .sorted { ($0.beginTime ?? "") < ($1.beginTime ?? "") }
                let date = week.startDate.adding(days: day)
                let names = classes
                    .map { "\($0.beginTime ?? "") \($0.courseName)" }
                    .joined(separator: " / ")
                Text(
                    "周\(WeekGrid.weekdayLabels[day]) \(date.monthDay) · \(classes.count)门\n\(names.isEmpty ? "无课" : names)"
                )
                .font(.system(size: 9))
                .foregroundColor(ink)
                .lineLimit(2)
            }
            Spacer(minLength: 0)
            ScheduleFooter(updatedAt: entry.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 七天 × 节次网格；同时段课程并排摆放，课程块卡片化并显示教师/地点。
struct WeekGrid: View {
    var week: WidgetWeek
    var theme: ScheduleTheme
    static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        GeometryReader { geo in
            let left: CGFloat = 26
            let top: CGFloat = 24
            let periods = max(week.times.count, 1)
            let column = (geo.size.width - left) / 7
            let row = (geo.size.height - top) / CGFloat(periods)
            ZStack(alignment: .topLeading) {
                gridLines(left: left, top: top, column: column, row: row, geo: geo)
                ForEach(0..<7, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text("周\(Self.weekdayLabels[day])")
                            .font(.system(size: 8))
                        Text(week.startDate.adding(days: day).monthDay)
                            .font(.system(size: 7))
                    }
                    .foregroundColor(ink)
                    .frame(width: column)
                    .position(
                        x: left + column * (CGFloat(day) + 0.5),
                        y: top / 2
                    )
                }
                ForEach(Array(week.times.enumerated()), id: \.offset) { index, slot in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(slot.section)")
                            .font(.system(size: 9, weight: .semibold))
                        Text(slot.start ?? "--:--")
                            .font(.system(size: 7))
                        Text(slot.end ?? "--:--")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(ink)
                    .frame(width: left - 2, alignment: .trailing)
                    .position(x: (left - 2) / 2, y: top + row * (CGFloat(index) + 0.55))
                }
                courseBlocks(left: left, top: top, column: column, row: row, periods: periods)
            }
        }
    }

    private func gridLines(
        left: CGFloat, top: CGFloat, column: CGFloat, row: CGFloat, geo: GeometryProxy
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
        .stroke(gridLine, lineWidth: 0.5)
    }

    private var periods: Int { max(week.times.count, 1) }

    private func courseBlocks(
        left: CGFloat, top: CGFloat, column: CGFloat, row: CGFloat, periods: Int
    ) -> some View {
        let lanes = Self.laneLayout(week.arrangedList, periods: periods)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { _, placed in
            let course = placed.0
            let lane = placed.1
            let lanesInColumn = placed.2
            let begin = min(max(course.beginSection ?? 1, 1), periods)
            let end = min(max(course.endSection ?? begin, begin), periods)
            let laneWidth = column / CGFloat(max(lanesInColumn, 1))
            VStack(spacing: 1) {
                Text(course.courseName)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let place = course.placeName, !place.isEmpty {
                    Text(place)
                        .font(.system(size: 7, weight: .medium))
                        .lineLimit(1)
                }
                if let teacher = ScheduleDisplay.teacher(from: course.weeksAndTeachers) {
                    Text(teacher)
                        .font(.system(size: 6.5))
                        .opacity(0.75)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(theme.accent)
            .padding(2)
            .frame(
                width: max(laneWidth - 2, 4),
                height: CGFloat(end - begin + 1) * row - 2,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.accent.opacity(0.55), lineWidth: 0.8)
                    )
            )
            .position(
                x: left + CGFloat((course.dayOfWeek ?? 1) - 1) * column
                    + laneWidth * (CGFloat(lane) + 0.5),
                y: top + row * (CGFloat(begin - 1) + CGFloat(end - begin + 1) / 2)
            )
        }
    }

    /// 同时段课程分道并排，返回（课程, 道号, 同列道数）。
    private static func laneLayout(
        _ courses: [WidgetCourse], periods: Int
    ) -> [(WidgetCourse, Int, Int)] {
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
                output.append((course, lane, max(lanes.count, 1)))
            }
        }
        return output
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
                Text("\(entry.todayAgenda.count)").font(.title3.bold())
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
                .scheduleWidgetChrome()
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
                .scheduleWidgetChrome()
        }
        .configurationDisplayName("近日课程")
        .description("今天起三天的课程安排，可上下滑动查看。")
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
                .scheduleWidgetChrome()
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
                .scheduleWidgetChrome()
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
                .scheduleWidgetChrome()
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
                .scheduleWidgetChrome()
        }
        .configurationDisplayName("UBAA 周课表")
        .description("整周课表一览，长按可切换配色。")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Xcode Canvas 预览（合成数据，不进入发布行为）

#if DEBUG
extension ScheduleEntry {
    /// 预览用合成课表，与真实投影同构。
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
        let monday = week.arrangedList
        let agenda = [
            SavedAgendaItem(date: week.startDate, course: monday[0]),
            SavedAgendaItem(date: week.startDate, course: monday[1]),
            SavedAgendaItem(date: week.startDate.adding(days: 1), course: monday[2]),
            SavedAgendaItem(date: week.startDate.adding(days: 2), course: monday[4]),
        ]
        return ScheduleEntry(
            owner: "preview", updatedAt: "2026-11-15T12:34:00.000Z",
            todayAgenda: Array(agenda.prefix(2)),
            upcomingAgenda: agenda,
            selected: SelectedWeek(semester: semester, week: week),
            nextCourse: agenda.first, inClass: true,
            theme: .ocean, date: Date()
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
    .frame(width: 336, height: 172)
}

#Preview("课程卡片 · 落日橙主题") {
    CourseCard(
        course: ScheduleEntry.preview.todayAgenda[0].course,
        theme: .sunset
    )
    .frame(width: 300)
}
#endif
