import SwiftUI
import WidgetKit

// 绘制结构对齐 Android `WidgetRenderer.kt` 的信息布局：
// 周课表为七天网格，近日为课程行列表，小卡片显示当前/下一节课。

private let ink = Color(red: 40 / 255, green: 58 / 255, blue: 80 / 255)
private let blockFill = Color(red: 222 / 255, green: 234 / 255, blue: 253 / 255)
private let gridLine = Color(red: 220 / 255, green: 229 / 255, blue: 241 / 255)

extension View {
    /// iOS 17+ 使用系统组件背景与系统内容边距；低版本自绘背景与内边距。
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
        guard let date else { return String(raw.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        let out = DateFormatter()
        out.calendar = LocalDate.calendar
        out.timeZone = TimeZone(identifier: "Asia/Shanghai")
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: date)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日课程 · \(LocalDate.today(now: entry.date).monthDay)")
                        .font(.caption2.bold())
                        .foregroundColor(ink.opacity(0.7))
                    if let item = entry.nextCourse {
                        Text(entry.inClass ? "正在上课" : "下一节")
                            .font(.caption2)
                            .foregroundColor(entry.inClass ? .red : ink.opacity(0.6))
                        Text(item.course.courseName)
                            .font(.callout.bold())
                            .foregroundColor(ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if let begin = item.course.beginTime, let end = item.course.endTime {
                            Text("\(begin)–\(end)")
                                .font(.caption2)
                                .foregroundColor(ink.opacity(0.75))
                        }
                        if let place = item.course.placeName, !place.isEmpty {
                            Text(place)
                                .font(.caption2)
                                .foregroundColor(ink.opacity(0.75))
                                .lineLimit(1)
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

// MARK: - 近日课程（中组件，今天起三天）

struct UpcomingScheduleWidgetView: View {
    var entry: ScheduleEntry

    var body: some View {
        Group {
            if entry.isEmpty {
                ScheduleWidgetEmpty()
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("近日课程 · 今天起三天")
                        .font(.caption2.bold())
                        .foregroundColor(ink.opacity(0.7))
                    if entry.upcomingAgenda.isEmpty {
                        Text("没有已安排课程")
                            .font(.footnote)
                            .foregroundColor(ink.opacity(0.75))
                        Spacer()
                    } else {
                        ForEach(
                            Array(entry.upcomingAgenda.prefix(4).enumerated()),
                            id: \.offset
                        ) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(item.date.monthDay) \(item.course.beginTime ?? "")–\(item.course.endTime ?? "")")
                                    .font(.caption2)
                                    .foregroundColor(ink.opacity(0.7))
                                    .fixedSize()
                                Text(item.course.courseName)
                                    .font(.caption2.bold())
                                    .foregroundColor(ink)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if let place = item.course.placeName, !place.isEmpty {
                                    Text(place)
                                        .font(.caption2)
                                        .foregroundColor(ink.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                        if entry.upcomingAgenda.count > 4 {
                            Text("另 \(entry.upcomingAgenda.count - 4) 门 · 点击查看")
                                .font(.caption2)
                                .foregroundColor(ink.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        ScheduleFooter(updatedAt: entry.updatedAt)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(week.name) · \(week.startDate.monthDay)")
                .font(.caption2.bold())
                .foregroundColor(ink.opacity(0.7))
            WeekGrid(week: week)
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
            .foregroundColor(ink)
            Button(intent: WeekBumpIntent(delta: 0)) {
                Text("本周").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(ink)
            Button(intent: WeekBumpIntent(delta: 1)) {
                Image(systemName: "chevron.right").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundColor(ink)
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
                Text("周\(WeekGrid.weekdayLabels[day]) \(date.monthDay) · \(classes.count)门\n\(names.isEmpty ? "无课" : names)")
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

/// 七天 × 节次网格；同时段课程并排摆放，与 Android 网格渲染一致。
struct WeekGrid: View {
    var week: WidgetWeek
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
                            .font(.system(size: 8))
                        Text(slot.start ?? "--:--")
                            .font(.system(size: 6))
                        Text(slot.end ?? "--:--")
                            .font(.system(size: 6))
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
                    .font(.system(size: 7, weight: .semibold))
                    .lineLimit(2)
                if let beginTime = course.beginTime {
                    Text(beginTime).font(.system(size: 6))
                }
                if let place = course.placeName, !place.isEmpty {
                    Text(place).font(.system(size: 6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(ink)
            .padding(2)
            .frame(
                width: max(laneWidth - 2, 4),
                height: CGFloat(end - begin + 1) * row - 2,
                alignment: .topLeading
            )
            .background(blockFill, in: RoundedRectangle(cornerRadius: 4))
            .position(
                x: left + CGFloat(course.dayOfWeek! - 1) * column
                    + laneWidth * (CGFloat(lane) + 0.5),
                y: top + row * (CGFloat(begin - 1) + CGFloat(end - begin + 1) / 2)
            )
        }
    }

    /// 同时段课程分道并排，返回（课程, 道号, 同列道数）。
    private static func laneLayout(
        _ courses: [WidgetCourse], periods: Int
    ) -> [([WidgetCourse].Element, Int, Int)] {
        var output: [([WidgetCourse].Element, Int, Int)] = []
        for day in 1...7 {
            let items = courses
                .filter { $0.dayOfWeek == day }
                .sorted {
                    (($0.beginSection ?? 1), ($0.endSection ?? 1))
                        < (($1.beginSection ?? 1), ($1.endSection ?? 1))
                }
            var lanes: [Int] = []
            let placed: [([WidgetCourse].Element, Int)] = items.map { course in
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

// MARK: - Widget 定义

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
            TodayScheduleWidgetView(entry: entry)
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
                .scheduleWidgetChrome()
        }
        .configurationDisplayName("UBAA 周课表")
        .description("整周课表一览，可切换周次。")
        .supportedFamilies([.systemLarge])
    }
}
