import SwiftUI
import WidgetKit
import XCTest

@available(iOS 17.0, *)
final class WidgetRenderTests: XCTestCase {
    private struct Surface {
        let widget: ScheduleWidgetSurface
        let family: WidgetFamily
        let familyName: String
        let size: CGSize
    }

    @MainActor
    func testTodoEmptyStatesUseMessageLayoutInBothFamilies() throws {
        let now = Date(timeIntervalSince1970: 1_794_758_400)
        let provider = ScheduleTimelineProvider()
        let snapshot = try ScheduleWidgetParser.parseSnapshot(["version": 1, "owner": "合成甲", "semesters": []])
        let states: [(WidgetSnapshot?, String)] = [
            (nil, "打开 UBAA 载入待办"), (snapshot, "打开 UBAA 更新"),
        ]
        for medium in [false, true] {
            func render(_ entry: ScheduleEntry) throws -> Data {
                let content = TodoCardView(entry: entry, medium: medium)
                    .frame(width: medium ? 340 : 146, height: 146)
                return try XCTUnwrap(ImageRenderer(content: content).uiImage?.pngData())
            }
            for (snapshot, message) in states {
                let empty = provider.entry(now: now, theme: .ocean, snapshot: snapshot)
                let todo = WidgetTodoSegment(from: now, state: .noData, message: message,
                    smallRow: nil, smallFooter: nil, mediumRows: [], mediumFooter: nil, staleText: nil, cardLink: nil)
                let messageEntry = ScheduleEntry(date: now, theme: .ocean, publication: .published,
                    upNext: nil, today: nil, todo: todo, selected: nil)
                XCTAssertTrue(try render(empty) == render(messageEntry), "\(medium ? "中卡" : "小卡")：\(message)")
            }
        }
    }

    @MainActor
    func testRenderWidgetFamilies() throws {
        guard let path = ProcessInfo.processInfo.environment["UBAA_WIDGET_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("未设置组件渲染目录")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        let surfaces = [
            Surface(widget: .upNext, family: .systemSmall, familyName: "systemSmall", size: CGSize(width: 170, height: 170)),
            Surface(widget: .upNext, family: .accessoryInline, familyName: "accessoryInline", size: CGSize(width: 257, height: 26)),
            Surface(widget: .upNext, family: .accessoryRectangular, familyName: "accessoryRectangular", size: CGSize(width: 172, height: 76)),
            Surface(widget: .upNext, family: .accessoryCircular, familyName: "accessoryCircular", size: CGSize(width: 72, height: 72)),
            Surface(widget: .today, family: .systemMedium, familyName: "systemMedium", size: CGSize(width: 364, height: 170)),
            Surface(widget: .todo, family: .systemSmall, familyName: "systemSmall", size: CGSize(width: 170, height: 170)),
            Surface(widget: .todo, family: .systemMedium, familyName: "systemMedium", size: CGSize(width: 364, height: 170)),
            Surface(widget: .week, family: .systemLarge, familyName: "systemLarge", size: CGSize(width: 364, height: 382)),
        ]

        let fixture = try WidgetV2Tests.fixture()
        for (state, entry) in try entries(fixture) {
            let liveTimer = try timerEntry(entry, fixture: fixture)
            for surface in surfaces {
                for scheme in [ColorScheme.light, .dark] {
                    let palette = SchedulePalette.resolve(theme: .ocean, scheme: scheme, accented: scheduleAccessory(surface.family))
                    let displayed = surface.widget == .upNext ? liveTimer : entry
                    let content = ScheduleWidgetCard(surface: surface.widget, entry: displayed, family: surface.family)
                        .frame(width: surface.size.width, height: surface.size.height)
                        .background(palette.canvas)
                        .environment(\.colorScheme, scheme)
                        .environment(\.schedulePalette, palette)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    let appearance = scheme == .dark ? "dark" : "light"
                    let name = "\(surface.widget.name)_\(surface.familyName)_\(state)_\(appearance).png"
                    let image = try XCTUnwrap(renderer.uiImage, name)
                    XCTAssertEqual(image.size, surface.size, name)
                    let png = try XCTUnwrap(image.pngData(), name)
                    try png.write(to: directory.appendingPathComponent(name))
                }
            }
        }
    }

    private func timerEntry(_ entry: ScheduleEntry, fixture: [String: Any]) throws -> ScheduleEntry {
        guard let segment = entry.upNext, segment.primary?.countdown != nil else { return entry }
        let now = Int(Date().timeIntervalSince1970)
        let offset = now - Int(entry.date.timeIntervalSince1970)
        let start = Int(segment.from.timeIntervalSince1970)
        let rows = try XCTUnwrap(fixture["upNext"] as? [[String: Any]])
        var row = try XCTUnwrap(rows.first { $0["from"] as? Int == start })
        var primary = try XCTUnwrap(row["primary"] as? [String: Any])
        var countdown = try XCTUnwrap(primary["countdown"] as? [String: Any])
        countdown["target"] = try XCTUnwrap(countdown["target"] as? Int) + offset
        for key in ["startAt", "endAt"] {
            if let value = primary[key] as? Int { primary[key] = value + offset }
        }
        primary["countdown"] = countdown
        row["primary"] = primary
        row["from"] = start + offset
        let snapshot = try ScheduleWidgetParser.parseSnapshot([
            "version": 2, "owner": try XCTUnwrap(fixture["owner"]), "semesters": [],
            "horizonEnd": try XCTUnwrap(fixture["horizonEnd"] as? Int) + offset,
            "upNext": [row],
        ])
        return ScheduleTimelineProvider().entry(now: Date(timeIntervalSince1970: TimeInterval(now)),
                                                theme: .ocean, snapshot: snapshot)
    }

    private func entries(_ fixture: [String: Any]) throws -> [(String, ScheduleEntry)] {
        let snapshot = try ScheduleWidgetParser.parseSnapshot(fixture)
        let upNext = try XCTUnwrap(snapshot.upNext)
        let today = try XCTUnwrap(snapshot.today)
        let todo = try XCTUnwrap(snapshot.todo)
        let start = try XCTUnwrap(upNext.first?.from)
        let horizon = try XCTUnwrap(snapshot.horizonEnd)
        let provider = ScheduleTimelineProvider()
        func at(_ date: Date, snapshot: WidgetSnapshot? = snapshot) -> ScheduleEntry {
            provider.entry(now: date, theme: .ocean, snapshot: snapshot)
        }

        let ongoing = try XCTUnwrap(upNext.first { $0.primary?.ongoing == true })
        let breakTime = try XCTUnwrap(upNext.first { $0.from > ongoing.from && $0.primary?.countdown?.label == .until })
        let tomorrow = try XCTUnwrap(today.first { $0.dayLabel == "明天" })
        let examSecondary = try XCTUnwrap(upNext.first { $0.state == .item && $0.secondary?.kind == .exam })
        let termEnd = try XCTUnwrap(today.first { $0.state == .termEnd })
        let examTodo = try XCTUnwrap(todo.first { $0.smallRow?.kind == .exam })
        let emptyTodo = try XCTUnwrap(todo.first { $0.state == .empty })
        let staleTodo = try XCTUnwrap(todo.first { $0.state == .items && $0.staleText != nil })

        var partial = fixture
        for name in ["upNext", "today"] {
            var row = try XCTUnwrap((fixture[name] as? [[String: Any]])?.last { $0["state"] as? String == "termEnd" })
            row["state"] = "partial"
            row["message"] = "部分课表未载入"
            partial[name] = [row]
        }
        let partialSnapshot = try ScheduleWidgetParser.parseSnapshot(partial)
        return [
            ("上课中", at(ongoing.from)),
            ("课间", at(breakTime.from)),
            ("晚上换明天", at(tomorrow.from)),
            ("考试日副行", at(examSecondary.from)),
            ("partial", at(start, snapshot: partialSnapshot)),
            ("termEnd", at(termEnd.from)),
            ("空态A", at(start, snapshot: nil)),
            ("空态B", at(horizon)),
            ("待办有考试", at(examTodo.from)),
            ("待办空", at(emptyTodo.from)),
            ("staleText", at(staleTodo.from)),
        ]
    }
}
