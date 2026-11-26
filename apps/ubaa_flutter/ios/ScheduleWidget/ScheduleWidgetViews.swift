import SwiftUI
import WidgetKit

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
func scheduleAccessory(_ family: WidgetFamily) -> Bool {
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

struct ScheduleWidgetEmpty: View {
    var needsUpdate = false
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
                .scheduleAccentable()
            Text(needsUpdate ? "需要更新" : "还没有课表")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(needsUpdate ? "打开 UBAA 更新" : "打开 UBAA 载入课表")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func widgetLink(_ raw: String?) -> URL? {
    guard let raw, raw.hasPrefix("ubaa://widget/open?") else { return nil }
    return URL(string: raw)
}

private func joinedText(_ fields: String?..., separator: String) -> String {
    fields.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: separator)
}

private extension View {
    @ViewBuilder
    func widgetRowLink(_ raw: String?) -> some View {
        if let url = widgetLink(raw) {
            Link(destination: url) { self }
        } else {
            self
        }
    }

    func agendaBar(_ color: Color, width: CGFloat, inset: CGFloat, accented: Bool) -> some View {
        padding(.leading, inset)
            .overlay(alignment: .leading) {
                Group {
                    if accented {
                        Capsule().strokeBorder(color, lineWidth: 1)
                    } else {
                        Capsule().fill(color)
                    }
                }
                    .frame(width: width)
                    .scheduleAccentable()
            }
    }

    func cardAlignment() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AgendaTag: View {
    let text: String
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                if !palette.accented { Capsule().fill(palette.accent.opacity(0.14)) }
            }
            .scheduleAccentable()
    }
}

private struct AgendaMessage: View {
    let text: String?
    var partial = false
    let size: CGFloat
    let color: Color
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let text {
                Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
            }
            if partial {
                Text("打开 UBAA 更新").font(.system(size: 12)).foregroundStyle(palette.secondary)
            }
        }
    }
}

@available(iOS 17.0, *)
struct UpNextWidgetContent: View {
    let entry: ScheduleEntry
    let family: WidgetFamily
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        Group {
            if let segment = entry.upNext {
                switch family {
                case .accessoryInline: inline(segment)
                case .accessoryRectangular: rectangular(segment)
                case .accessoryCircular: circular(segment)
                default: small(segment)
                }
            } else {
                switch family {
                case .accessoryInline: Text("打开 UBAA").foregroundStyle(palette.ink)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UBAA").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.ink).scheduleAccentable()
                        Text("打开以载入课表").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.secondary)
                    }
                case .accessoryCircular:
                    Image(systemName: "calendar").foregroundStyle(palette.accent).scheduleAccentable()
                default: ScheduleWidgetEmpty(needsUpdate: !entry.isEmpty)
                }
            }
        }
        .widgetURL(widgetLink(entry.upNext?.cardLink))
    }

    private func countdown(_ primary: WidgetUpNextSegment.Primary) -> Text? {
        guard let value = primary.countdown, value.target >= entry.date else { return nil }
        return Text("\(value.label.rawValue) \(Text(timerInterval: entry.date...value.target, countsDown: true))")
    }

    @ViewBuilder
    private func small(_ segment: WidgetUpNextSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if segment.state == .item, let primary = segment.primary {
                let timer = countdown(primary)
                HStack(spacing: 4) {
                    (primary.ongoing ? timer ?? Text(primary.timeText) : Text(primary.timeText))
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(primary.ongoing && timer != nil ? palette.accent : palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .scheduleAccentable()
                    Spacer(minLength: 0)
                    if let tag = primary.tag, !tag.isEmpty { AgendaTag(text: tag) }
                    if primary.extraCount > 0 {
                        Text("+\(primary.extraCount)").font(.system(size: 11))
                            .foregroundStyle(palette.tertiary).fixedSize()
                    }
                }
                if primary.ongoing, timer != nil {
                    Text(primary.timeText).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.6)
                } else if !primary.ongoing, let timer {
                    timer.font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.accent)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).scheduleAccentable()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let place = primary.place, !place.isEmpty {
                        Text(place).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(primary.title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.secondary)
                        .lineLimit(segment.secondary == nil ? 2 : 1)
                        .privacySensitive(primary.private)
                }
                .agendaBar(palette.accent, width: 4, inset: 9, accented: palette.accented)
            } else {
                AgendaMessage(text: segment.message, partial: segment.state == .partial, size: 16, color: palette.ink)
            }
            if let secondary = segment.secondary {
                Spacer(minLength: 0)
                secondaryLine(secondary, size: 11).minimumScaleFactor(0.8)
            }
        }
        .cardAlignment()
    }

    private func inline(_ segment: WidgetUpNextSegment) -> some View {
        let text: Text
        if segment.state == .item, let primary = segment.primary {
            if primary.ongoing {
                let place = primary.place.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
                let time = countdown(primary) ?? Text(primary.timeText)
                text = Text("\(time)\(place)")
            } else {
                text = Text(joinedText(primary.timeText, primary.place, primary.private ? nil : primary.title, separator: " "))
            }
        } else {
            text = Text(segment.message ?? "")
        }
        return text.foregroundStyle(palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }

    private func rectangular(_ segment: WidgetUpNextSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if segment.state == .item, let primary = segment.primary {
                let time = primary.ongoing
                    ? countdown(primary) ?? Text(primary.timeText)
                    : Text(joinedText(primary.timeText, primary.place, separator: " "))
                rectangleHeadline(time)
                HStack(spacing: 0) {
                    if primary.ongoing, let place = primary.place, !place.isEmpty {
                        Text(place)
                        if !primary.title.isEmpty { Text(" · ") }
                    }
                    Text(primary.title).privacySensitive(primary.private)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            } else {
                rectangleHeadline(Text(segment.message ?? ""))
            }
            if let secondary = segment.secondary {
                secondaryLine(secondary, size: 12)
            } else if segment.state == .item, let count = segment.primary?.extraCount, count > 0 {
                Text("+\(count)").font(.system(size: 12)).foregroundStyle(palette.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rectangleHeadline(_ text: Text) -> some View {
        text.font(.system(size: 15, weight: .semibold)).monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1).minimumScaleFactor(0.6).scheduleAccentable()
    }

    @ViewBuilder
    private func circular(_ segment: WidgetUpNextSegment) -> some View {
        if segment.state == .item, let primary = segment.primary {
            if primary.ongoing, let start = primary.startAt, let end = primary.endAt, start < end {
                ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    if end >= entry.date {
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .font(.system(size: 11)).foregroundStyle(palette.ink)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .progressViewStyle(.circular)
                .tint(palette.accent)
                .scheduleAccentable()
            } else {
                VStack(spacing: 0) {
                    if !primary.dayText.isEmpty {
                        Text(primary.dayText).font(.system(size: 10)).foregroundStyle(palette.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(primary.startText).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).scheduleAccentable()
                }
            }
        } else {
            Text("—").foregroundStyle(palette.ink).scheduleAccentable()
        }
    }

    private func secondaryLine(_ secondary: WidgetUpNextSegment.Secondary, size: CGFloat) -> some View {
        Text(secondary.text).font(.system(size: size, weight: .medium))
            .foregroundStyle(secondary.kind == .exam ? palette.accent : palette.tertiary)
            .lineLimit(1).privacySensitive(secondary.private).scheduleAccentable(secondary.kind == .exam)
    }
}

@available(iOS 17.0, *)
struct TodayCardView: View {
    let entry: ScheduleEntry
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        Group {
            if let segment = entry.today {
                VStack(alignment: .leading, spacing: 6) {
                    header(segment)
                    if segment.state == .items {
                        ForEach(Array(segment.rows.prefix(3).enumerated()), id: \.offset) { _, row in
                            agendaRow(row).widgetRowLink(row.link)
                        }
                    } else {
                        AgendaMessage(text: segment.message, partial: segment.state == .partial,
                                      size: 16, color: palette.secondary)
                    }
                }
                .cardAlignment()
            } else {
                ScheduleWidgetEmpty(needsUpdate: !entry.isEmpty)
            }
        }
        .widgetURL(widgetLink(entry.today?.cardLink))
    }

    private func header(_ segment: WidgetTodaySegment) -> some View {
        HStack(spacing: 4) {
            Text(segment.dayLabel ?? "今天").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink).lineLimit(1).layoutPriority(1)
            if segment.state == .items {
                Spacer(minLength: 0)
                let count = segment.rows.count - 3
                HStack(spacing: 0) {
                    if count > 0 { Text("还有 \(count) 项") }
                    if let due = segment.dueLine, !due.isEmpty {
                        if count > 0 { Text(" · ") }
                        Text(due).foregroundStyle(palette.accent).scheduleAccentable()
                    }
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.tertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func agendaRow(_ row: WidgetTodaySegment.Row) -> some View {
        let bar = row.kind == .course ? CourseTint.bar(name: row.title, palette: palette) : palette.accent
        return HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.timeText).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                if row.ongoing {
                    Text("进行中").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.accent)
                        .scheduleAccentable()
                } else {
                    Text(row.endText.flatMap { $0.isEmpty ? nil : "至 \($0)" } ?? "")
                        .font(.system(size: 10)).foregroundStyle(palette.tertiary)
                        .monospacedDigit().lineLimit(1, reservesSpace: true).minimumScaleFactor(0.8)
                }
            }
            .frame(width: 46, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let tag = row.tag, !tag.isEmpty { AgendaTag(text: tag) }
                    Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.ink)
                        .lineLimit(1).privacySensitive(row.private)
                }
                Text(row.place ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                    .lineLimit(1, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .agendaBar(bar, width: 3, inset: 8, accented: palette.accented)
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .background {
            if row.ongoing && !palette.accented {
                RoundedRectangle(cornerRadius: 8).fill(palette.todayWash)
            }
        }
    }
}

@available(iOS 17.0, *)
struct TodoCardView: View {
    let entry: ScheduleEntry
    let medium: Bool
    @Environment(\.schedulePalette) private var palette

    var body: some View {
        let segment = entry.todo
        let hasItems = segment?.state == .items
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("待办").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.ink)
                if medium {
                    Spacer(minLength: 0)
                    footer(hasItems ? segment?.mediumFooter : nil, segment?.staleText)
                }
            }
            if let segment, hasItems {
                if medium {
                    ForEach(Array(segment.mediumRows.prefix(3).enumerated()), id: \.offset) { _, row in
                        mediumRow(row).widgetRowLink(row.link)
                    }
                } else if let row = segment.smallRow {
                    smallRow(row)
                }
            } else {
                let message = segment?.message ?? (entry.isEmpty ? "打开 UBAA 载入待办" : "打开 UBAA 更新")
                AgendaMessage(text: message, size: 15, color: palette.secondary)
            }
            if !medium {
                Spacer(minLength: 0)
                footer(hasItems ? segment?.smallFooter : nil, segment?.staleText)
            }
        }
        .cardAlignment()
        .widgetURL(widgetLink(segment?.cardLink))
    }

    @ViewBuilder
    private func footer(_ more: String?, _ stale: String?) -> some View {
        let text = joinedText(more, stale, separator: " · ")
        if !text.isEmpty {
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.tertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func smallRow(_ row: WidgetTodoSegment.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            due(row, size: 17)
            Text(row.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.ink)
                .lineLimit(2).privacySensitive(row.private)
            Text(row.sub).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.secondary).lineLimit(1)
        }
    }

    private func mediumRow(_ row: WidgetTodoSegment.Row) -> some View {
        HStack(spacing: 6) {
            due(row, size: 13).frame(width: 72, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.ink)
                    .lineLimit(1).privacySensitive(row.private)
                Text(row.sub).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .agendaBar(row.kind == .exam ? palette.accent : palette.tertiary, width: 3, inset: 8, accented: palette.accented)
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
    }

    private func due(_ row: WidgetTodoSegment.Row, size: CGFloat) -> some View {
        Text(row.leftText).font(.system(size: size, weight: .semibold)).monospacedDigit()
            .foregroundStyle(row.urgent ? palette.accent : palette.ink).lineLimit(1)
            .minimumScaleFactor(0.8).scheduleAccentable(row.urgent)
    }
}
