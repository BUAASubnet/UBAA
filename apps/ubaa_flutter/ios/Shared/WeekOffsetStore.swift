import Foundation

/// 周课表翻周偏移，存放在 App Group 容器；以当周周一为锚点，跨周自动回到本周。
/// iOS 17+ 的组件按钮通过 `WeekBumpIntent` 增减偏移；iOS 15/16 无组件内交互，始终显示本周。
enum WeekOffsetStore {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ScheduleWidgetStore.appGroupID)?
            .appendingPathComponent("week-offset.json")
    }

    static func current(today: LocalDate) -> Int {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anchor = object["anchor"] as? String,
              let offset = object["offset"] as? Int
        else { return 0 }
        let monday = today.adding(days: -(today.isoWeekday - 1))
        return anchor == monday.formatted() ? max(-20, min(20, offset)) : 0
    }

    /// 翻页偏移；`delta == 0` 表示回到本周（对齐 Android 的 step=0 语义）。
    static func bump(delta: Int, today: LocalDate) {
        guard let fileURL else { return }
        let monday = today.adding(days: -(today.isoWeekday - 1))
        let next = delta == 0 ? 0 : max(-20, min(20, current(today: today) + delta))
        let object: [String: Any] = [
            "anchor": monday.formatted(),
            "offset": next,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
