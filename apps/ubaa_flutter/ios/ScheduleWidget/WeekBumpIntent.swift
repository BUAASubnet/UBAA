import AppIntents

@available(iOS 17.0, *)
struct WeekBumpIntent: AppIntent {
    static var title: LocalizedStringResource = "切换周次"
    static var description = IntentDescription("在桌面课表上切换到上一周或下一周。")

    @Parameter(title: "步长")
    var delta: Int

    init(delta: Int) {
        self.delta = delta
    }

    init() {
        self.delta = 1
    }

    func perform() async throws -> some IntentResult {
        WeekOffsetStore.bump(delta: delta, today: .today())
        return .result()
    }
}
