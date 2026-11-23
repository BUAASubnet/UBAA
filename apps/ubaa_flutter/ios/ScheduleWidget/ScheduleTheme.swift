import AppIntents
import SwiftUI
import WidgetKit

/// 组件配色主题。主题色只负责底色、今天和状态；
/// 周课表里的课程块另按课名取色，见 `CourseTint`。
enum ScheduleTheme: String, CaseIterable, Sendable {
    case ocean
    case forest
    case sunset
    case violet
    case graphite

    /// 浅色强调色。深色用提亮后的同色相，保证状态胶囊上的字能看清。
    func accent(scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.ocean, .dark): Color(red: 142 / 255, green: 190 / 255, blue: 255 / 255)
        case (.forest, .dark): Color(red: 125 / 255, green: 219 / 255, blue: 168 / 255)
        case (.sunset, .dark): Color(red: 255 / 255, green: 176 / 255, blue: 122 / 255)
        case (.violet, .dark): Color(red: 205 / 255, green: 182 / 255, blue: 255 / 255)
        case (.graphite, .dark): Color(red: 206 / 255, green: 214 / 255, blue: 224 / 255)
        case (.ocean, _): Color(red: 37 / 255, green: 110 / 255, blue: 220 / 255)
        case (.forest, _): Color(red: 32 / 255, green: 128 / 255, blue: 78 / 255)
        case (.sunset, _): Color(red: 204 / 255, green: 92 / 255, blue: 32 / 255)
        case (.violet, _): Color(red: 116 / 255, green: 74 / 255, blue: 204 / 255)
        case (.graphite, _): Color(red: 82 / 255, green: 94 / 255, blue: 110 / 255)
        }
    }

    /// 组件底板。比系统灰多一点主题色相，深色不落到纯黑。
    func canvas(scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.ocean, .dark): Color(red: 14 / 255, green: 24 / 255, blue: 38 / 255)
        case (.forest, .dark): Color(red: 14 / 255, green: 28 / 255, blue: 22 / 255)
        case (.sunset, .dark): Color(red: 36 / 255, green: 22 / 255, blue: 16 / 255)
        case (.violet, .dark): Color(red: 26 / 255, green: 18 / 255, blue: 38 / 255)
        case (.graphite, .dark): Color(red: 26 / 255, green: 27 / 255, blue: 30 / 255)
        case (.ocean, _): Color(red: 236 / 255, green: 243 / 255, blue: 251 / 255)
        case (.forest, _): Color(red: 236 / 255, green: 245 / 255, blue: 239 / 255)
        case (.sunset, _): Color(red: 252 / 255, green: 243 / 255, blue: 236 / 255)
        case (.violet, _): Color(red: 244 / 255, green: 240 / 255, blue: 250 / 255)
        case (.graphite, _): Color(red: 241 / 255, green: 242 / 255, blue: 245 / 255)
        }
    }
}

/// 一次渲染要用的颜色。`accented` 为真时交给系统着色（锁屏、iOS 18 着色模式）。
struct SchedulePalette {
    var theme: ScheduleTheme
    var scheme: ColorScheme
    var accented: Bool
    var ink: Color
    var secondary: Color
    var tertiary: Color
    var hairline: Color
    var accent: Color
    var onAccent: Color
    var canvas: Color
    var todayWash: Color

    static func resolve(theme: ScheduleTheme, scheme: ColorScheme, accented: Bool) -> SchedulePalette {
        if accented {
            return SchedulePalette(
                theme: theme, scheme: scheme, accented: true,
                ink: .primary, secondary: .secondary, tertiary: .secondary,
                hairline: Color.primary.opacity(0.16),
                accent: .primary, onAccent: .primary,
                canvas: .clear,
                todayWash: Color.primary.opacity(0.12)
            )
        }
        let dark = scheme == .dark
        let accent = theme.accent(scheme: scheme)
        return SchedulePalette(
            theme: theme, scheme: scheme, accented: false,
            ink: dark
                ? Color(red: 0.94, green: 0.96, blue: 0.98)
                : Color(red: 0.11, green: 0.16, blue: 0.23),
            secondary: dark
                ? Color.white.opacity(0.68)
                : Color(red: 0.32, green: 0.41, blue: 0.50),
            tertiary: dark
                ? Color.white.opacity(0.46)
                : Color(red: 0.32, green: 0.41, blue: 0.50).opacity(0.72),
            hairline: dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07),
            accent: accent,
            onAccent: dark ? Color(red: 0.08, green: 0.10, blue: 0.13) : .white,
            canvas: theme.canvas(scheme: scheme),
            todayWash: accent.opacity(dark ? 0.20 : 0.12)
        )
    }
}

extension Color {
    /// HSL，色相 0...360。课程色与应用内课表同一套观感。
    init(hsl h: Double, s: Double, l: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h / 60).truncatingRemainder(dividingBy: 6)
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let rgb: (Double, Double, Double)
        switch hp {
        case 0..<1: rgb = (c, x, 0)
        case 1..<2: rgb = (x, c, 0)
        case 2..<3: rgb = (0, c, x)
        case 3..<4: rgb = (0, x, c)
        case 4..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        self.init(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m)
    }
}

/// 周课表课程色。色相表与 `ScheduleCourseColors` 相同，按课名稳定散列。
enum CourseTint {
    private static let hues: [Double] = [
        210, 25, 155, 285, 55, 335, 185, 95, 255, 5,
        130, 310, 235, 75, 175, 45, 270, 355, 115, 195,
    ]

    private static func bucket(_ name: String) -> Int {
        var seed = 0
        let key = name.trimmingCharacters(in: .whitespaces)
        for scalar in key.unicodeScalars {
            seed = (seed &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return seed % hues.count
    }

    static func fill(name: String, palette: SchedulePalette) -> Color {
        if palette.accented { return Color.primary.opacity(0.16) }
        if palette.theme == .graphite {
            let light: [Double] = [0.93, 0.84, 0.75, 0.88, 0.80]
            let dark: [Double] = [0.22, 0.34, 0.44, 0.28, 0.38]
            let steps = palette.scheme == .dark ? dark : light
            return Color(white: steps[bucket(name) % steps.count])
        }
        let hue = hues[bucket(name)]
        return palette.scheme == .dark
            ? Color(hsl: hue, s: 0.42, l: 0.30)
            : Color(hsl: hue, s: 0.62, l: 0.82)
    }

    static func ink(palette: SchedulePalette) -> Color {
        if palette.accented { return .primary }
        return palette.scheme == .dark
            ? Color(red: 0.96, green: 0.97, blue: 0.98)
            : Color(red: 0.12, green: 0.16, blue: 0.22)
    }

    /// 近日列表的课程色条。石墨主题保持中性，其余用课程色相。
    static func bar(name: String, palette: SchedulePalette) -> Color {
        if palette.accented || palette.theme == .graphite { return palette.accent }
        let hue = hues[bucket(name)]
        return palette.scheme == .dark
            ? Color(hsl: hue, s: 0.50, l: 0.70)
            : Color(hsl: hue, s: 0.58, l: 0.42)
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
        ScheduleTimelineProvider().timeline(now: Date(), theme: configuration.theme?.theme ?? .ocean)
    }

    private func entry(now: Date, theme: ScheduleTheme) -> ScheduleEntry {
        ScheduleTimelineProvider().currentEntry(now: now, theme: theme)
    }
}
