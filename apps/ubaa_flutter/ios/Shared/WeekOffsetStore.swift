import Foundation

/// 多个周课表组件实例共享 App Group 中的同一翻周偏移；跨周、换账号或退出时回到本周。
struct WeekOffsetStore {
    static let shared = WeekOffsetStore(directory: FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: ScheduleWidgetStore.appGroupID))

    private let fileURL: URL?

    init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("week-offset.json")
    }

    private func current(today: LocalDate) -> Int {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anchor = object["anchor"] as? String,
              let offset = object["offset"] as? Int
        else { return 0 }
        let monday = today.adding(days: -(today.isoWeekday - 1))
        return anchor == monday.formatted() ? offset : 0
    }

    /// 翻页偏移；`delta == 0` 表示回到本周（对齐 Android 的 step=0 语义）。
    func bump(delta: Int, from base: SelectedWeek, today: LocalDate) {
        guard (-1...1).contains(delta), let fileURL, let baseIndex = base.index else { return }
        let weeks = base.semester.weeks
        let index = displayedIndex(baseIndex: baseIndex, count: weeks.count, today: today)
        let next = delta == 0 ? baseIndex : index + delta
        guard weeks.indices.contains(next) else { return }
        let monday = today.adding(days: -(today.isoWeekday - 1))
        let object: [String: Any] = [
            "anchor": monday.formatted(),
            "offset": next - baseIndex,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    func selectedWeek(from base: SelectedWeek, today: LocalDate) -> SelectedWeek {
        guard let baseIndex = base.index else { return base }
        let weeks = base.semester.weeks
        let index = displayedIndex(baseIndex: baseIndex, count: weeks.count, today: today)
        return SelectedWeek(semester: base.semester, week: weeks[index])
    }

    private func displayedIndex(baseIndex: Int, count: Int, today: LocalDate) -> Int {
        baseIndex + max(-baseIndex, min(count - 1 - baseIndex, current(today: today)))
    }
}
