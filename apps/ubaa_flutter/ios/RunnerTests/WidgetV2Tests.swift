import XCTest
import WidgetKit
@testable import Runner

final class WidgetV2Tests: XCTestCase {
    static func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "snapshot_v2", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testV2FixtureHasAllThreeTables() throws {
        let raw = try Self.fixture()
        let snapshot = try ScheduleWidgetParser.parseSnapshot(raw)
        let upNext = try XCTUnwrap(snapshot.upNext)
        XCTAssertEqual(upNext.count, (raw["upNext"] as? [Any])?.count)
        XCTAssertTrue(upNext.contains { $0.primary?.countdown?.label == .remaining })
        XCTAssertTrue(upNext.contains { $0.secondary?.kind == .exam })
        let today = try XCTUnwrap(snapshot.today)
        XCTAssertEqual(today.count, (raw["today"] as? [Any])?.count)
        XCTAssertTrue(today.contains { $0.dayLabel == "明天" })
        let todo = try XCTUnwrap(snapshot.todo)
        XCTAssertEqual(todo.count, (raw["todo"] as? [Any])?.count)
        XCTAssertTrue(todo.contains { $0.state == .empty && $0.staleText != nil })
    }

    func testInvalidTableDoesNotDiscardOtherTablesOrWeek() throws {
        var raw = try Self.fixture()
        var next = try XCTUnwrap(raw["upNext"] as? [[String: Any]])
        var primary = try XCTUnwrap(next[0]["primary"] as? [String: Any])
        primary["ongoing"] = 1
        next[0]["primary"] = primary
        raw["upNext"] = next
        var today = try XCTUnwrap(raw["today"] as? [[String: Any]])
        today[0]["from"] = true
        raw["today"] = today
        let parsed = try ScheduleWidgetParser.parseSnapshot(raw)
        XCTAssertNil(parsed.upNext)
        XCTAssertNil(parsed.today)
        XCTAssertNotNil(parsed.todo)
        XCTAssertFalse(parsed.semesters.isEmpty)
    }

    func testEmptyUnorderedAndUnknownStateTablesAreInvalid() throws {
        var raw = try Self.fixture()
        raw["upNext"] = []
        var today = try XCTUnwrap(raw["today"] as? [[String: Any]])
        today.swapAt(0, 1)
        raw["today"] = today
        var todo = try XCTUnwrap(raw["todo"] as? [[String: Any]])
        todo[0]["state"] = "future"
        raw["todo"] = todo
        let parsed = try ScheduleWidgetParser.parseSnapshot(raw)
        XCTAssertNil(parsed.upNext)
        XCTAssertNil(parsed.today)
        XCTAssertNil(parsed.todo)
    }

    func testUnavailableHorizonAndV1KeepOnlyWeek() throws {
        let raw = try Self.fixture()
        var missing = raw
        missing.removeValue(forKey: "horizonEnd")
        for value in [missing, raw.merging(["horizonEnd": "1795968000"]) { _, new in new },
                      raw.merging(["version": 1]) { _, new in new }] {
            let parsed = try ScheduleWidgetParser.parseSnapshot(value)
            XCTAssertNil(parsed.horizonEnd)
            XCTAssertNil(parsed.upNext)
            XCTAssertNil(parsed.today)
            XCTAssertNil(parsed.todo)
            XCTAssertFalse(parsed.semesters.isEmpty)
        }
    }

    func testSelectionBeforeFirstAtBoundaryAndAtHorizon() throws {
        let snapshot = try ScheduleWidgetParser.parseSnapshot(Self.fixture())
        let segments = try XCTUnwrap(snapshot.upNext)
        let horizon = try XCTUnwrap(snapshot.horizonEnd)
        let provider = ScheduleTimelineProvider()
        let before = provider.entry(now: segments[0].from.addingTimeInterval(-1), theme: .ocean, snapshot: snapshot)
        XCTAssertEqual(before.upNext?.from, segments[0].from)
        XCTAssertEqual(before.today?.from, snapshot.today?.first?.from)
        XCTAssertEqual(before.todo?.from, snapshot.todo?.first?.from)
        let boundary = provider.entry(now: segments[1].from, theme: .ocean, snapshot: snapshot)
        XCTAssertEqual(boundary.upNext?.from, segments[1].from)
        for now in [horizon, horizon.addingTimeInterval(1)] {
            let expired = provider.entry(now: now, theme: .ocean, snapshot: snapshot)
            XCTAssertFalse(expired.isEmpty)
            XCTAssertNil(expired.upNext)
            XCTAssertNil(expired.today)
            XCTAssertNil(expired.todo)
            XCTAssertNotNil(expired.selected)
        }
    }

    func testTimelineIncludesHorizonAndCampusMidnightAndNeverReloadsWithoutSnapshot() throws {
        let snapshot = try ScheduleWidgetParser.parseSnapshot(Self.fixture())
        let horizon = try XCTUnwrap(snapshot.horizonEnd)
        let now = horizon.addingTimeInterval(-25)
        let provider = ScheduleTimelineProvider()
        let absent = provider.timeline(now: now, theme: .ocean, snapshot: nil)
        XCTAssertEqual(absent.entries.map(\.date), [now])
        XCTAssertTrue(absent.entries[0].isEmpty)
        XCTAssertEqual(absent.policy, .never)
        let timeline = provider.timeline(now: now, theme: .ocean, snapshot: snapshot)
        XCTAssertEqual(timeline.entries.map(\.date), [now, horizon])
        XCTAssertEqual(timeline.policy, .after(now.addingTimeInterval(6 * 3600)))
        let before = now.addingTimeInterval(-86400)
        let midnight = LocalDate.calendar.startOfDay(for: now)
        XCTAssertTrue(provider.timeline(now: before, theme: .ocean, snapshot: snapshot)
            .entries.contains { $0.date == midnight })
    }

    func testTimelineCapsEntriesAndReloadsAtFirstOmittedBoundary() throws {
        var raw = try Self.fixture()
        let today = try XCTUnwrap((raw["today"] as? [[String: Any]])?.first)
        let start = try XCTUnwrap(raw["dayStart"] as? Int)
        raw["today"] = (1...101).map { offset in
            today.merging(["from": start + offset]) { _, new in new }
        }
        let snapshot = try ScheduleWidgetParser.parseSnapshot(raw)
        let now = Date(timeIntervalSince1970: TimeInterval(start))
        let timeline = ScheduleTimelineProvider().timeline(now: now, theme: .ocean, snapshot: snapshot)
        XCTAssertEqual(timeline.entries.map(\.date), (0..<100).map { now.addingTimeInterval(TimeInterval($0)) })
        XCTAssertEqual(timeline.policy, .after(now.addingTimeInterval(100)))
    }

    func testSnapshotReadFailureControlsEmptyStateAndRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = ScheduleWidgetStore(directory: directory)
        let provider = ScheduleTimelineProvider()
        let now = Date(timeIntervalSince1970: 1_794_758_400)
        func check(isEmpty: Bool, policy: TimelineReloadPolicy) {
            let timeline = provider.timeline(now: now, store: store)
            XCTAssertEqual(timeline.entries.map(\.date), [now])
            XCTAssertEqual(timeline.entries.first?.isEmpty, isEmpty)
            XCTAssertEqual(provider.currentEntry(now: now, store: store).isEmpty, isEmpty)
            XCTAssertEqual(timeline.policy, policy)
        }
        check(isEmpty: true, policy: .never)

        let snapshot: [String: Any] = ["version": 1, "owner": "合成甲", "semesters": []]
        let scope = try store.begin(owner: "合成甲")
        XCTAssertTrue(try store.publish(scope: scope, snapshotJSON: snapshot))
        XCTAssertEqual(store.readState().snapshot?.owner, "合成甲")

        let key = directory.appendingPathComponent("schedule-widgets.key")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: key.path)
        XCTAssertThrowsError(try Data(contentsOf: key))
        check(isEmpty: false, policy: .after(now.addingTimeInterval(15 * 60)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        XCTAssertEqual(store.readState().snapshot?.owner, "合成甲")

        let encrypted = directory.appendingPathComponent("schedule-widgets.enc")
        var bytes = try Data(contentsOf: encrypted)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: encrypted)
        check(isEmpty: false, policy: .never)
        XCTAssertTrue(try store.publish(scope: scope, snapshotJSON: snapshot))
        XCTAssertEqual(store.readState().snapshot?.owner, "合成甲")
    }

    func testTimelineIncludesCourseEdgesForBothVersionsWithoutNewTables() throws {
        let raw = try Self.fixture()
        let start = try XCTUnwrap(raw["dayStart"] as? Int)
        let now = Date(timeIntervalSince1970: TimeInterval(start + 7 * 3600))
        let provider = ScheduleTimelineProvider()
        for version in [1, 2] {
            var weekOnly = raw
            weekOnly["version"] = version
            for table in ["upNext", "today", "todo"] { weekOnly.removeValue(forKey: table) }
            let snapshot = try ScheduleWidgetParser.parseSnapshot(weekOnly)
            let timeline = provider.timeline(now: now, theme: .ocean, snapshot: snapshot)
            XCTAssertEqual(timeline.entries.map(\.date), [0, 60, 155, 17 * 60].map {
                now.addingTimeInterval(TimeInterval($0 * 60))
            }, "v\(version)")
        }
    }

    func testTimelineReloadsAtFirstOmittedCourseMidnightOrHorizon() throws {
        let raw = try Self.fixture()
        let row = try XCTUnwrap((raw["today"] as? [[String: Any]])?.first)
        let start = try XCTUnwrap(raw["dayStart"] as? Int)
        let cases = [
            (now: start + 8 * 3600 - 600, horizon: start + 36000, omittedAfter: 600),
            (now: start + 86400 - 600, horizon: start + 87000, omittedAfter: 600),
            (now: start, horizon: start + 120, omittedAfter: 120),
        ]
        for scenario in cases {
            let rows = (1...99).map { offset in
                row.merging(["from": scenario.now + offset]) { _, new in new }
            }
            let snapshot = try ScheduleWidgetParser.parseSnapshot([
                "version": 2, "owner": try XCTUnwrap(raw["owner"]),
                "semesters": try XCTUnwrap(raw["semesters"]), "horizonEnd": scenario.horizon,
                "today": rows,
            ])
            let now = Date(timeIntervalSince1970: TimeInterval(scenario.now))
            let timeline = ScheduleTimelineProvider().timeline(now: now, theme: .ocean, snapshot: snapshot)
            XCTAssertEqual(timeline.entries.map(\.date), (0..<100).map { now.addingTimeInterval(TimeInterval($0)) })
            XCTAssertEqual(timeline.policy, .after(now.addingTimeInterval(TimeInterval(scenario.omittedAfter))))
        }
    }

    func testHostRegistersWidgetSchemeWithoutFlutterRouting() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let widget = try XCTUnwrap(types.first { $0["CFBundleURLName"] as? String == "cn.edu.ubaa.widget" })
        XCTAssertEqual(widget["CFBundleURLSchemes"] as? [String], ["ubaa"])
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "FlutterDeepLinkingEnabled") as? Bool, false)
    }

    func testColdLaunchRetainsOnlyLatestUntilDartTakesAndWarmLaunchIsImmediate() throws {
        let first = try XCTUnwrap(URL(string: "ubaa://widget/open?target=home"))
        let latest = try XCTUnwrap(URL(string: "ubaa://widget/open?target=agendaTodo"))
        let invalid = try XCTUnwrap(URL(string: "ubaa://widget/opened?target=home"))
        let inbox = WidgetLaunchInbox()
        var pushed: [String] = []
        inbox.receive(first)
        inbox.connect { pushed.append($0) }
        inbox.receive(latest)
        inbox.receive(invalid)
        XCTAssertTrue(pushed.isEmpty)
        XCTAssertEqual(inbox.take(), latest.absoluteString)
        XCTAssertNil(inbox.take())
        inbox.receive(first)
        inbox.receive(invalid)
        XCTAssertEqual(pushed, [first.absoluteString])
        inbox.connect { pushed.append($0) }
        inbox.receive(latest)
        XCTAssertEqual(pushed, [first.absoluteString])
        XCTAssertEqual(inbox.take(), latest.absoluteString)
    }
}
