import SwiftUI
import WidgetKit

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
            .disabled(entry.selected?.canGoBack != true)
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
            .disabled(entry.selected?.canGoForward != true)
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
            let left: CGFloat = 46
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

    /// 节次和开始时间排在同一行：大组件里每节只有十几点高，上下两行会压到相邻节次。
    private func timeGutter(left: CGFloat, top: CGFloat, row: CGFloat) -> some View {
        ForEach(Array(week.times.enumerated()), id: \.offset) { index, slot in
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(slot.section)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink.opacity(0.8))
                Text(slot.start ?? "")
                    .font(.system(size: 8.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }
            // 字号固定、不随动态字体缩放；按理想宽度排，各行时间字号一致。
            .fixedSize()
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
        let lanes = ScheduleWeekLanes.layout(week.arrangedList)
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

}
