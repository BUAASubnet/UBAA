import Flutter
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {}

/// 对齐 Android `WidgetScheduleTest.kt` 的选择逻辑合同。
final class ScheduleWidgetSelectionTests: XCTestCase {
    private func week(_ n: Int, start: String) -> WidgetWeek {
        let begin = try! LocalDate.parse(start)
        return WidgetWeek(
            serialNumber: n,
            name: "第\(n)周",
            startDate: begin,
            endDate: begin.adding(days: 6),
            arrangedList: [
                WidgetCourse(
                    courseName: "合成\(n)", dayOfWeek: 1, beginSection: 1, endSection: 2,
                    beginTime: "08:00", endTime: "09:35", placeName: "合成教室",
                    weeksAndTeachers: nil)
            ],
            times: [WidgetTimeSlot(section: 1, start: "08:00", end: nil)]
        )
    }

    private var semesters: [WidgetSemester] {
        [
            WidgetSemester(
                termCode: "term", updatedAt: "",
                weeks: [week(1, start: "2026-09-28"), week(2, start: "2026-10-05")],
                name: "term")
        ]
    }

    func test日期覆盖和明确周次遵循旧版() throws {
        let oct3 = try XCTUnwrap(LocalDate.parse("2026-10-03"))
        XCTAssertEqual(
            ScheduleWidgetParser.selectWeek(semesters: semesters, today: oct3)?.week.serialNumber,
            1)
        XCTAssertEqual(
            ScheduleWidgetParser.selectWeek(
                semesters: semesters, today: oct3, term: "term", number: 2
            )?.week.serialNumber,
            2)
        XCTAssertEqual(
            ScheduleWidgetParser.selectWeek(
                semesters: semesters, today: try XCTUnwrap(LocalDate.parse("2026-09-01"))
            )?.week.serialNumber,
            1)
        XCTAssertEqual(
            ScheduleWidgetParser.selectWeek(
                semesters: semesters, today: try XCTUnwrap(LocalDate.parse("2026-12-01"))
            )?.week.serialNumber,
            2)
    }

    func test未来三天跨周只返回对应日期课程() throws {
        let values = ScheduleWidgetParser.savedAgenda(
            semesters: semesters,
            today: try XCTUnwrap(LocalDate.parse("2026-10-03")), days: 3)
        XCTAssertEqual(values.map { $0.date.formatted() }, ["2026-10-05"])
        XCTAssertEqual(values.single?.course.courseName, "合成2")
        XCTAssertTrue(
            ScheduleWidgetParser.savedAgenda(
                semesters: semesters,
                today: try XCTUnwrap(LocalDate.parse("2026-12-01")), days: 3
            ).isEmpty)
    }
}

final class ScheduleWidgetParserTests: XCTestCase {
    private func snapshotJSON(day: Int = 1) -> [String: Any] {
        [
            "version": 1,
            "owner": "owner-1",
            "semesters": [
                [
                    "term": "2026-2027-1",
                    "name": "第一学期",
                    "updatedAt": "2026-11-15T12:00:00.000Z",
                    "weeks": [
                        [
                            "number": 1,
                            "name": "第1周",
                            "start": "2026-09-28",
                            "end": "2026-10-04",
                            "courses": [
                                [
                                    "name": "合成1",
                                    "day": day,
                                    "begin": 1,
                                    "end": 2,
                                    "startTime": "08:00",
                                    "endTime": "09:35",
                                    "place": "合成教室",
                                    "weeksAndTeachers": NSNull(),
                                ]
                            ],
                            "times": [
                                ["section": 1, "start": "08:00", "end": NSNull()]
                            ],
                        ]
                    ],
                ]
            ],
        ]
    }

    func test合法快照通过解析() throws {
        let parsed = try ScheduleWidgetParser.parseSnapshot(snapshotJSON())
        XCTAssertEqual(parsed.owner, "owner-1")
        XCTAssertEqual(parsed.semesters.single?.weeks.single?.arrangedList.single?.courseName, "合成1")
    }

    func test解析校验拒绝非法快照() {
        var badVersion = snapshotJSON()
        badVersion["version"] = 2
        XCTAssertThrowsError(try ScheduleWidgetParser.parseSnapshot(badVersion))
        let badDay = snapshotJSON(day: 8)
        XCTAssertThrowsError(try ScheduleWidgetParser.parseSnapshot(badDay))
        var emptyOwner = snapshotJSON()
        emptyOwner["owner"] = ""
        XCTAssertThrowsError(try ScheduleWidgetParser.parseSnapshot(emptyOwner))
    }
}

final class ScheduleWidgetStoreTests: XCTestCase {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    func test退出销毁密钥即使密文无法删除() throws {
        let directory = try fixtureDirectory()
        let key = directory.appendingPathComponent("schedule-widgets.key")
        let encrypted = directory.appendingPathComponent("schedule-widgets.enc")
        let store = ScheduleWidgetStore(directory: directory) { url in
            if url == encrypted { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }
        let reader = ScheduleWidgetStore(directory: directory)
        let scope = try store.begin(owner: "合成甲")
        let snapshot: [String: Any] = ["version": 1, "owner": "合成甲", "semesters": []]
        XCTAssertTrue(try store.publish(scope: scope, snapshotJSON: snapshot))
        XCTAssertEqual(reader.readState().snapshot?.owner, "合成甲")
        let oldKey = try Data(contentsOf: key)
        let oldCiphertext = try Data(contentsOf: encrypted)

        _ = try store.begin(owner: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: key.path))
        XCTAssertEqual(try Data(contentsOf: encrypted), oldCiphertext)
        XCTAssertNil(reader.readState().owner)
        XCTAssertFalse(try store.publish(scope: scope, snapshotJSON: snapshot))

        let newScope = try store.begin(owner: "合成甲")
        XCTAssertFalse(FileManager.default.fileExists(atPath: key.path))
        XCTAssertTrue(try store.publish(scope: newScope, snapshotJSON: snapshot))
        XCTAssertNotEqual(try Data(contentsOf: key), oldKey)
        try oldCiphertext.write(to: encrypted)
        XCTAssertNil(reader.readState().snapshot)
    }

    func test删密钥失败返回存储错误且不请求刷新() throws {
        let directory = try fixtureDirectory()
        let store = ScheduleWidgetStore(directory: directory) { url in
            if url.lastPathComponent == "schedule-widgets.key",
               FileManager.default.fileExists(atPath: url.path) {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: url)
        }
        let scope = try store.begin(owner: "合成甲")
        let snapshot: [String: Any] = ["version": 1, "owner": "合成甲", "semesters": []]
        XCTAssertTrue(try store.publish(scope: scope, snapshotJSON: snapshot))
        let plugin = ScheduleWidgetPlugin(store: store, reload: { XCTFail("失败时不得请求刷新") })
        let reply = expectation(description: "撤销失败")
        plugin.handle(FlutterMethodCall(methodName: "begin", arguments: [:])) { value in
            XCTAssertEqual((value as? FlutterError)?.code, "widget_storage_failure")
            reply.fulfill()
        }
        wait(for: [reply], timeout: 3)
        XCTAssertEqual(store.readState().owner, "合成甲")
        XCTAssertFalse(try store.publish(scope: scope, snapshotJSON: snapshot))
    }

    func test发布代次与撤销语义() throws {
        let directory = try fixtureDirectory()
        let store = ScheduleWidgetStore(directory: directory)
        let reader = ScheduleWidgetStore(directory: directory)
        let key = directory.appendingPathComponent("schedule-widgets.key")
        let owner = "store-test-\(UUID().uuidString.prefix(8))"
        let snapshot: [String: Any] = [
            "version": 1,
            "owner": owner,
            "semesters": [
                [
                    "term": "t1",
                    "name": "学期",
                    "updatedAt": "2026-11-15T12:00:00.000Z",
                    "weeks": [
                        [
                            "number": 1,
                            "name": "第1周",
                            "start": "2026-09-28",
                            "end": "2026-10-04",
                            "courses": [[
                                "name": "合成1", "day": 1, "begin": 1, "end": 2,
                                "startTime": "08:00", "endTime": "09:35",
                                "place": "合成教室", "weeksAndTeachers": NSNull(),
                            ]],
                            "times": [["section": 1, "start": "08:00", "end": NSNull()]],
                        ]
                    ],
                ]
            ],
        ]
        // 新代次发布成功，读回一致。
        let scope = try store.begin(owner: owner)
        XCTAssertFalse(scope.isEmpty)
        XCTAssertTrue(try store.publish(scope: scope, snapshotJSON: snapshot))
        let read = reader.readState()
        XCTAssertEqual(read.owner, owner)
        XCTAssertEqual(read.snapshot?.semesters.single?.termCode, "t1")

        // 换账号后代次撤销：旧代次不能再发布。
        let newOwner = "\(owner)-other"
        let newScope = try store.begin(owner: newOwner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: key.path))
        XCTAssertNil(reader.readState().owner)
        XCTAssertFalse(try store.publish(scope: scope, snapshotJSON: snapshot))
        XCTAssertFalse(try store.publish(scope: newScope, snapshotJSON: snapshot))
        var newSnapshot = snapshot
        newSnapshot["owner"] = newOwner
        XCTAssertTrue(try store.publish(scope: newScope, snapshotJSON: newSnapshot))
        XCTAssertEqual(reader.readState().owner, newOwner)

        // 空账号清空组件副本。
        _ = try store.begin(owner: nil)
        XCTAssertNil(reader.readState().owner)
    }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}

final class WeekOffsetStoreTests: XCTestCase {
    func test零步长回到本周而非停留() throws {
        let today = try XCTUnwrap(LocalDate.parse("2026-11-18"))
        WeekOffsetStore.bump(delta: 2, today: today)
        XCTAssertEqual(WeekOffsetStore.current(today: today), 2)
        // 对齐 Android step=0：回到本周。
        WeekOffsetStore.bump(delta: 0, today: today)
        XCTAssertEqual(WeekOffsetStore.current(today: today), 0)
    }

    func test跨周边界自动回到本周() throws {
        let today = try XCTUnwrap(LocalDate.parse("2026-11-18"))
        WeekOffsetStore.bump(delta: 3, today: today)
        let nextWeek = try XCTUnwrap(LocalDate.parse("2026-11-25"))
        XCTAssertEqual(WeekOffsetStore.current(today: nextWeek), 0)
    }
}

final class ScheduleDisplayTests: XCTestCase {
    func test从周次教师串提取教师名() {
        XCTAssertEqual(ScheduleDisplay.teacher(from: "1周,4-6周[理论]/合成教师[主讲]"), "合成教师[主讲]")
        XCTAssertEqual(ScheduleDisplay.teacher(from: "1-16周/合成甲"), "合成甲")
        XCTAssertEqual(ScheduleDisplay.teacher(from: " 1-16周 / 合成甲 \n"), "合成甲")
        XCTAssertEqual(ScheduleDisplay.teacher(from: "合成甲"), "合成甲")
        XCTAssertNil(ScheduleDisplay.teacher(from: "1-16周 合成甲"))
        XCTAssertNil(ScheduleDisplay.teacher(from: "1-3周/甲/乙"))
        XCTAssertNil(ScheduleDisplay.teacher(from: "1-3周/ "))
        XCTAssertNil(ScheduleDisplay.teacher(from: nil))
        XCTAssertNil(ScheduleDisplay.teacher(from: " \n\t "))
        XCTAssertNil(ScheduleDisplay.teacher(from: "1-16周"))
    }
}

final class ScheduleTimelineTests: XCTestCase {
    private func time(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func item(_ name: String, start: String, end: String?) throws -> SavedAgendaItem {
        SavedAgendaItem(
            date: try LocalDate.parse("2026-11-23"),
            course: WidgetCourse(courseName: name, dayOfWeek: 1, beginSection: 1, endSection: 2,
                                 beginTime: start, endTime: end, placeName: nil, weeksAndTeachers: nil))
    }

    func test七点五十五生成开课下课和上海午夜() throws {
        let agenda = [try item("合成甲", start: "08:00", end: "09:35")]
        let now = try time("2026-11-23T07:55:00+08:00")
        let start = try time("2026-11-23T08:00:00+08:00")
        let end = try time("2026-11-23T09:35:00+08:00")
        let midnight = try time("2026-11-24T00:00:00+08:00")
        let dates = ScheduleTimeline.dates(now: now, agenda: agenda)
        XCTAssertEqual(dates, [now, start, end, midnight])
        XCTAssertEqual(LocalDate.today(now: try XCTUnwrap(dates.last)).formatted(), "2026-11-24")
        XCTAssertFalse(ScheduleTimeline.nextCourse(agenda: agenda, now: "07:55").1)
        XCTAssertTrue(ScheduleTimeline.nextCourse(agenda: agenda, now: "08:00").1)
        XCTAssertNil(ScheduleTimeline.nextCourse(agenda: agenda, now: "09:35").0)
    }

    func test缺结束时间最多进行到下一节或午夜() throws {
        let first = try item("合成甲", start: "08:00", end: nil)
        let second = try item("合成乙", start: "10:00", end: nil)
        let agenda = [first, second]
        XCTAssertEqual(ScheduleTimeline.nextCourse(agenda: agenda, now: "09:59").0?.course.courseName, "合成甲")
        XCTAssertEqual(ScheduleTimeline.nextCourse(agenda: agenda, now: "10:00").0?.course.courseName, "合成乙")
        XCTAssertTrue(ScheduleTimeline.nextCourse(agenda: agenda, now: "23:59").1)
        XCTAssertTrue(ScheduleTimeline.hasEnded(first, today: first.date, clock: "10:00", agenda: agenda))
        XCTAssertTrue(ScheduleTimeline.hasEnded(second, today: second.date.adding(days: 1), clock: "00:00", agenda: []))
    }
}
