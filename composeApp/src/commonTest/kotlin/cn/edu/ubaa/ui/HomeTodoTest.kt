package cn.edu.ubaa.ui

import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import cn.edu.ubaa.model.dto.Week
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkTermSummaryDto
import cn.edu.ubaa.ui.screens.menu.HomeTodoAction
import cn.edu.ubaa.ui.screens.menu.HomeTodoSource
import cn.edu.ubaa.ui.screens.menu.buildHomeTodoItems
import cn.edu.ubaa.ui.screens.menu.parseHomeDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone

class HomeTodoTest {
  @Test
  fun `buildHomeTodoItems filters invalid items and sorts by mixed time`() {
    val items =
        buildHomeTodoItems(
            bykcCourses =
                listOf(
                    BykcChosenCourseDto(
                        id = 1,
                        courseId = 101,
                        courseName = "博雅进行中",
                        courseTeacher = "王老师",
                        coursePosition = "学院路校区",
                        courseStartDate = LocalDateTime.parse("2026-03-24T11:00:00"),
                        courseEndDate = LocalDateTime.parse("2026-03-24T13:00:00"),
                    ),
                    BykcChosenCourseDto(
                        id = 2,
                        courseId = 102,
                        courseName = "博雅已结束",
                        courseStartDate = LocalDateTime.parse("2026-03-24T08:00:00"),
                        courseEndDate = LocalDateTime.parse("2026-03-24T09:00:00"),
                    ),
                ),
            spocAssignments =
                listOf(
                    SpocAssignmentSummaryDto(
                        assignmentId = "spoc-1",
                        courseId = "course-1",
                        courseName = "算法设计",
                        title = "第一次作业",
                        dueTime = "2026-03-24 12:30:00",
                        submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                        submissionStatusText = "未提交",
                    ),
                    SpocAssignmentSummaryDto(
                        assignmentId = "spoc-2",
                        courseId = "course-2",
                        courseName = "编译原理",
                        title = "已交作业",
                        dueTime = "2026-03-24 12:10:00",
                        submissionStatus = SpocSubmissionStatus.SUBMITTED,
                        submissionStatusText = "已提交",
                    ),
                ),
            judgeAssignments =
                listOf(
                    JudgeAssignmentSummaryDto(
                        courseId = "judge-course-1",
                        courseName = "希冀课程",
                        assignmentId = "judge-1",
                        title = "希冀未完成作业",
                        dueTime = "2026-03-24 12:20:00",
                        maxScore = "100",
                        totalProblems = 2,
                        submittedCount = 1,
                        submissionStatus = JudgeSubmissionStatus.PARTIAL,
                        submissionStatusText = "进行中(1/2)",
                    ),
                    JudgeAssignmentSummaryDto(
                        courseId = "judge-course-2",
                        courseName = "希冀课程",
                        assignmentId = "judge-2",
                        title = "希冀已完成作业",
                        dueTime = "2026-03-24 12:15:00",
                        maxScore = "10",
                        myScore = "10",
                        totalProblems = 1,
                        submittedCount = 1,
                        submissionStatus = JudgeSubmissionStatus.SUBMITTED,
                        submissionStatusText = "已完成 10/10",
                    ),
                ),
            cgyyOrders =
                listOf(
                    CgyyOrderDto(
                        id = 201,
                        venueName = "老主楼研讨室",
                        venueSpaceName = "A201",
                        theme = "小组讨论",
                        reservationStartDate = "2026-03-24 13:30:00",
                        reservationEndDate = "2026-03-24 15:00:00",
                        orderStatus = 1,
                        checkStatus = 2,
                    ),
                    CgyyOrderDto(
                        id = 202,
                        venueName = "新主楼研讨室",
                        venueSpaceName = "B301",
                        reservationStartDate = "2026-03-24 10:00:00",
                        reservationEndDate = "2026-03-24 11:00:00",
                        orderStatus = 2,
                    ),
                ),
            signinClasses =
                listOf(
                    SigninClassDto(
                        courseId = "signin-1",
                        courseName = "离散数学",
                        classBeginTime = "11:55",
                        classEndTime = "12:45",
                        signStatus = 0,
                    ),
                    SigninClassDto(
                        courseId = "signin-2",
                        courseName = "数字逻辑",
                        classBeginTime = "12:20",
                        classEndTime = "13:10",
                        signStatus = 0,
                    ),
                ),
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    assertEquals(
        listOf(
            "bykc:101",
            "signin:signin-1",
            "judge:judge-course-1:judge-1",
            "spoc:spoc-1",
            "cgyy:201",
        ),
        items.map { it.id },
    )
    assertEquals("进行中", items.first().statusLabel)
    assertEquals("签到中", items[1].statusLabel)
  }

  @Test
  fun `signin todo item uses direct sign action`() {
    val items =
        buildHomeTodoItems(
            bykcCourses = emptyList(),
            spocAssignments = emptyList(),
            judgeAssignments = emptyList(),
            cgyyOrders = emptyList(),
            signinClasses =
                listOf(
                    SigninClassDto(
                        courseId = "signin-1",
                        courseName = "大学物理",
                        classBeginTime = "12:08",
                        classEndTime = "13:00",
                        signStatus = 0,
                    )
                ),
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    val item = items.single()
    val action = assertIs<HomeTodoAction.SigninCourse>(item.action)
    assertEquals("signin-1", action.courseId)
    assertEquals("签到", item.actionLabel)
    assertEquals("即将签到", item.statusLabel)
  }

  @Test
  fun `judge todo item opens assignment detail with course and assignment ids`() {
    val items =
        buildHomeTodoItems(
            bykcCourses = emptyList(),
            spocAssignments = emptyList(),
            judgeAssignments =
                listOf(
                    JudgeAssignmentSummaryDto(
                        courseId = "course-1",
                        courseName = "希冀课程",
                        assignmentId = "assignment-1",
                        title = "待完成希冀作业",
                        dueTime = "2026-03-24 13:00:00",
                        maxScore = "100",
                        totalProblems = 2,
                        submittedCount = 0,
                        submissionStatus = JudgeSubmissionStatus.UNSUBMITTED,
                        submissionStatusText = "未提交",
                    )
                ),
            cgyyOrders = emptyList(),
            signinClasses = emptyList(),
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    val item = items.single()
    val action = assertIs<HomeTodoAction.OpenJudgeAssignment>(item.action)
    assertEquals("course-1", action.courseId)
    assertEquals("assignment-1", action.assignmentId)
    assertEquals("待提交", item.statusLabel)
  }

  @Test
  fun `spoc todo items hide assignments that have not started`() {
    val items =
        buildHomeTodoItems(
            bykcCourses = emptyList(),
            spocAssignments =
                listOf(
                    SpocAssignmentSummaryDto(
                        assignmentId = "spoc-started",
                        courseId = "course-1",
                        courseName = "算法设计",
                        title = "已开始作业",
                        startTime = "2026-03-24 11:00:00",
                        dueTime = "2026-03-24 13:00:00",
                        submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                        submissionStatusText = "未提交",
                    ),
                    SpocAssignmentSummaryDto(
                        assignmentId = "spoc-future",
                        courseId = "course-2",
                        courseName = "编译原理",
                        title = "未开始作业",
                        startTime = "2026-03-24 12:30:00",
                        dueTime = "2026-03-24 14:00:00",
                        submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                        submissionStatusText = "未提交",
                    ),
                ),
            judgeAssignments = emptyList(),
            cgyyOrders = emptyList(),
            signinClasses = emptyList(),
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    assertEquals(listOf("spoc:spoc-started"), items.map { it.id })
  }

  @Test
  fun `ygdk todo item appears during final reminder weeks when counts are below targets`() {
    val items =
        buildHomeTodoItems(
            bykcCourses = emptyList(),
            spocAssignments = emptyList(),
            judgeAssignments = emptyList(),
            cgyyOrders = emptyList(),
            signinClasses = emptyList(),
            ygdkOverview = ygdkOverview(weekCount = 3, termCount = 15),
            currentWeek = week(serialNumber = 11),
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    val item = assertNotNull(items.singleOrNull())
    assertEquals("ygdk:2025-2026-2:11", item.id)
    assertEquals(HomeTodoSource.YGDK, item.source)
    assertEquals("本周阳光打卡未达标", item.title)
    assertEquals("本周已打卡 3 / 4 次", item.subtitle)
    assertEquals("待打卡", item.statusLabel)
    assertEquals("截止 3月29日 23:59", item.timeLabel)
    assertEquals(LocalDateTime.parse("2026-03-29T23:59:59"), item.sortTime)
    assertIs<HomeTodoAction.OpenYgdkHome>(item.action)
  }

  @Test
  fun `ygdk todo item hides outside final reminder weeks`() {
    val items =
        ygdkTodoItems(
            overview = ygdkOverview(weekCount = 3, termCount = 15),
            currentWeek = week(serialNumber = 10),
        )

    assertEquals(emptyList(), items.map { it.id })
  }

  @Test
  fun `ygdk todo item hides after weekly or term target is reached`() {
    assertEquals(
        emptyList(),
        ygdkTodoItems(
                overview = ygdkOverview(weekCount = 4, termCount = 15),
                currentWeek = week(serialNumber = 12),
            )
            .map { it.id },
    )
    assertEquals(
        emptyList(),
        ygdkTodoItems(
                overview = ygdkOverview(weekCount = 3, termCount = 16),
                currentWeek = week(serialNumber = 12),
            )
            .map { it.id },
    )
  }

  @Test
  fun `ygdk todo item hides when reminder is disabled or locally completed`() {
    assertEquals(
        emptyList(),
        ygdkTodoItems(
                overview = ygdkOverview(weekCount = 3, termCount = 15),
                currentWeek = week(serialNumber = 13),
                ygdkReminderEnabled = false,
            )
            .map { it.id },
    )
    assertEquals(
        emptyList(),
        ygdkTodoItems(
                overview = ygdkOverview(weekCount = 3, termCount = 15),
                currentWeek = week(serialNumber = 13),
                ygdkWeekDone = true,
            )
            .map { it.id },
    )
    assertEquals(
        emptyList(),
        ygdkTodoItems(
                overview = ygdkOverview(weekCount = 3, termCount = 15),
                currentWeek = week(serialNumber = 13),
                ygdkTermDone = true,
            )
            .map { it.id },
    )
  }

  @Test
  fun `parseHomeDateTime supports full datetime and time only`() {
    assertEquals(
        LocalDateTime.parse("2026-03-24T14:30:00"),
        parseHomeDateTime("2026-03-24 14:30:00"),
    )
    assertEquals(
        LocalDateTime.parse("2026-03-24T09:15:00"),
        parseHomeDateTime("09:15", LocalDateTime.parse("2026-03-24T12:00:00").date),
    )
    assertNull(parseHomeDateTime("not-a-time"))
  }

  companion object {
    private val NOW = LocalDateTime.parse("2026-03-24T12:00:00")

    private fun ygdkTodoItems(
        overview: YgdkOverviewResponse?,
        currentWeek: Week?,
        ygdkReminderEnabled: Boolean = true,
        ygdkWeekDone: Boolean = false,
        ygdkTermDone: Boolean = false,
    ) =
        buildHomeTodoItems(
            bykcCourses = emptyList(),
            spocAssignments = emptyList(),
            judgeAssignments = emptyList(),
            cgyyOrders = emptyList(),
            signinClasses = emptyList(),
            ygdkOverview = overview,
            currentWeek = currentWeek,
            ygdkReminderEnabled = ygdkReminderEnabled,
            ygdkWeekDone = ygdkWeekDone,
            ygdkTermDone = ygdkTermDone,
            now = NOW,
            timeZone = TimeZone.UTC,
        )

    private fun ygdkOverview(
        weekCount: Int?,
        termCount: Int,
    ) =
        YgdkOverviewResponse(
            summary = YgdkTermSummaryDto(termCount = termCount, weekCount = weekCount),
            classifyId = 3,
            classifyName = "阳光体育",
        )

    private fun week(serialNumber: Int) =
        Week(
            startDate = "2026-06-15",
            endDate = "2026-06-21",
            term = "2025-2026-2",
            curWeek = true,
            serialNumber = serialNumber,
            name = "第${serialNumber}周",
        )
  }
}
