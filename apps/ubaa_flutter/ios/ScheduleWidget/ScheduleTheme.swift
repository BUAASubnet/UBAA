import AppIntents
import SwiftUI
import WidgetKit

/// 组件配色主题；卡片填充、色条与强调色均由此派生。
enum ScheduleTheme: String, CaseIterable, Sendable {
    case ocean
    case forest
    case sunset
    case violet
    case graphite

    /// 卡片底色。
    var cardFill: Color {
        switch self {
        case .ocean: Color(red: 222 / 255, green: 234 / 255, blue: 253 / 255)
        case .forest: Color(red: 219 / 255, green: 240 / 255, blue: 224 / 255)
        case .sunset: Color(red: 253 / 255, green: 233 / 255, blue: 210 / 255)
        case .violet: Color(red: 235 / 255, green: 226 / 255, blue: 250 / 255)
        case .graphite: Color(red: 228 / 255, green: 231 / 255, blue: 235 / 255)
        }
    }

    /// 卡片色条与强调色。
    var accent: Color {
        switch self {
        case .ocean: Color(red: 47 / 255, green: 124 / 255, blue: 246 / 255)
        case .forest: Color(red: 40 / 255, green: 140 / 255, blue: 88 / 255)
        case .sunset: Color(red: 224 / 255, green: 108 / 255, blue: 43 / 255)
        case .violet: Color(red: 128 / 255, green: 88 / 255, blue: 214 / 255)
        case .graphite: Color(red: 88 / 255, green: 101 / 255, blue: 117 / 255)
        }
    }
}

@available(iOS 17.0, *)
enum ScheduleThemeEnum: String, AppEnum {
    case ocean
    case forest
    case sunset
    case violet
    case graphite

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "配色主题"
    static var caseDisplayRepresentations: [ScheduleThemeEnum: DisplayRepresentation] = [
        .ocean: "海盐蓝",
        .forest: "森林绿",
        .sunset: "落日橙",
        .violet: "紫罗兰",
        .graphite: "石墨灰",
    ]

    var theme: ScheduleTheme {
        ScheduleTheme(rawValue: rawValue) ?? .ocean
    }
}

/// iOS 17+ 组件编辑面板：长按桌面组件即可切换配色。
@available(iOS 17.0, *)
struct ScheduleWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "课表组件设置"
    static var description = IntentDescription("调整课表组件的配色主题。")

    @Parameter(title: "配色主题", default: .ocean)
    var theme: ScheduleThemeEnum?
}

/// 读取配置的课表时间线提供者（iOS 17+）；未配置时沿用默认主题。
@available(iOS 17.0, *)
struct ScheduleConfiguredProvider: AppIntentTimelineProvider {
    typealias Entry = ScheduleEntry
    typealias Intent = ScheduleWidgetConfig

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleTimelineProvider().placeholder(in: context)
    }

    func snapshot(
        for configuration: ScheduleWidgetConfig, in context: Context
    ) async -> ScheduleEntry {
        entry(now: Date(), theme: configuration.theme?.theme ?? .ocean)
    }

    func timeline(
        for configuration: ScheduleWidgetConfig, in context: Context
    ) async -> Timeline<ScheduleEntry> {
        let now = Date()
        let single = entry(now: now, theme: configuration.theme?.theme ?? .ocean)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        return Timeline(entries: [single], policy: .after(next))
    }

    private func entry(now: Date, theme: ScheduleTheme) -> ScheduleEntry {
        ScheduleTimelineProvider().currentEntry(now: now, theme: theme)
    }
}
