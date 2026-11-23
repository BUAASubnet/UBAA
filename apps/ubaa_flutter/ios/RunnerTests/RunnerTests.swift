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
    func test发布代次与撤销语义() throws {
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
        let scope = try ScheduleWidgetStore.begin(owner: owner)
        XCTAssertFalse(scope.isEmpty)
        XCTAssertTrue(try ScheduleWidgetStore.publish(scope: scope, snapshotJSON: snapshot))
        let read = ScheduleWidgetStore.readState()
        XCTAssertEqual(read.owner, owner)
        XCTAssertEqual(read.snapshot?.semesters.single?.termCode, "t1")

        // 换账号后代次撤销：旧代次不能再发布。
        _ = try ScheduleWidgetStore.begin(owner: "\(owner)-other")
        XCTAssertFalse(try ScheduleWidgetStore.publish(scope: scope, snapshotJSON: snapshot))

        // 空账号清空组件副本。
        _ = try ScheduleWidgetStore.begin(owner: nil)
        XCTAssertNil(ScheduleWidgetStore.readState().owner)
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
