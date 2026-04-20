package cn.edu.ubaa.ui

import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import cn.edu.ubaa.ui.screens.menu.HomeTodoAction
import cn.edu.ubaa.ui.screens.menu.buildHomeTodoItems
import cn.edu.ubaa.ui.screens.menu.parseHomeDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
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
        listOf("bykc:101", "signin:signin-1", "spoc:spoc-1", "cgyy:201"),
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
  }
}
