package cn.edu.ubaa.ui.screens.bykc

import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import cn.edu.ubaa.model.dto.BykcSignConfigDto
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.datetime.LocalDateTime

class BykcTimeFormattersTest {

  @Test
  fun `formatDateTimeDisplay trims seconds`() {
    assertEquals(
        "2025-03-15 14:00",
        formatDateTimeDisplay(LocalDateTime.parse("2025-03-15T14:00:00")),
    )
  }

  @Test
  fun `formatDateRange keeps same-day end time compact`() {
    assertEquals(
        "2025-03-15 14:00 - 16:30",
        formatDateRange(
            LocalDateTime.parse("2025-03-15T14:00:00"),
            LocalDateTime.parse("2025-03-15T16:30:00"),
        ),
    )
  }

  @Test
  fun `formatDateRange shows full cross-day timestamps`() {
    assertEquals(
        "2025-03-15 23:30 - 2025-03-16 08:15",
        formatDateRange(
            LocalDateTime.parse("2025-03-15T23:30:00"),
            LocalDateTime.parse("2025-03-16T08:15:00"),
        ),
    )
  }

  @Test
  fun `formatDateRangeOrStart falls back to start time when end is missing`() {
    assertEquals(
        "2025-03-15 14:00",
        formatDateRangeOrStart(LocalDateTime.parse("2025-03-15T14:00:00"), null),
    )
  }

  @Test
  fun `resolveSelectTimeDisplay shows start before selection begins`() {
    val display =
        resolveSelectTimeDisplay(
            startDate = LocalDateTime.parse("2025-03-16T08:00:00"),
            endDate = LocalDateTime.parse("2025-03-16T18:00:00"),
            now = LocalDateTime.parse("2025-03-16T07:30:00"),
        )

    assertEquals("开始选课", display?.label)
    assertEquals("2025-03-16 08:00", display?.value)
  }

  @Test
  fun `resolveSelectTimeDisplay shows end after selection begins`() {
    val display =
        resolveSelectTimeDisplay(
            startDate = LocalDateTime.parse("2025-03-16T08:00:00"),
            endDate = LocalDateTime.parse("2025-03-16T18:00:00"),
            now = LocalDateTime.parse("2025-03-16T08:30:00"),
        )

    assertEquals("截止选课", display?.label)
    assertEquals("2025-03-16 18:00", display?.value)
  }

  @Test
  fun `resolveSelectTimeDisplay falls back to existing boundary`() {
    val display =
        resolveSelectTimeDisplay(
            startDate = null,
            endDate = LocalDateTime.parse("2025-03-16T18:00:00"),
            now = LocalDateTime.parse("2025-03-16T08:30:00"),
        )

    assertEquals("截止选课", display?.label)
    assertEquals("2025-03-16 18:00", display?.value)
  }

  @Test
  fun `isBykcCourseFull returns true for full count and full status`() {
    assertTrue(
        isBykcCourseFull(
            courseCurrentCount = 10,
            courseMaxCount = 10,
            status = BykcCourseStatus.AVAILABLE,
        )
    )
    assertTrue(
        isBykcCourseFull(
            courseCurrentCount = 5,
            courseMaxCount = 10,
            status = BykcCourseStatus.FULL,
        )
    )
  }

  @Test
  fun `resolveBykcSelectButtonState disables course when list snapshot is full`() {
    val state =
        resolveBykcSelectButtonState(
            course =
                BykcCourseDetailDto(
                    id = 1L,
                    courseName = "测试课程",
                    courseMaxCount = 10,
                    courseCurrentCount = 5,
                    courseSelectStartDate = LocalDateTime.parse("2025-03-16T08:00:00"),
                    courseSelectEndDate = LocalDateTime.parse("2025-03-16T18:00:00"),
                    status = BykcCourseStatus.AVAILABLE,
                ),
            listSnapshot =
                BykcCourseDto(
                    id = 1L,
                    courseName = "测试课程",
                    courseMaxCount = 10,
                    courseCurrentCount = 10,
                    status = BykcCourseStatus.FULL,
                ),
            operationInProgress = false,
            now = LocalDateTime.parse("2025-03-16T09:00:00"),
        )

    assertFalse(state.enabled)
    assertEquals("该课程人数已满，当前不可选择。", state.disabledReason)
  }

  @Test
  fun `resolveBykcDisplayStatus prefers full when list snapshot is full`() {
    val status =
        resolveBykcDisplayStatus(
            course =
                BykcCourseDetailDto(
                    id = 1L,
                    courseName = "测试课程",
                    courseMaxCount = 10,
                    courseCurrentCount = 5,
                    courseSelectStartDate = LocalDateTime.parse("2025-03-16T08:00:00"),
                    courseSelectEndDate = LocalDateTime.parse("2025-03-16T18:00:00"),
                    status = BykcCourseStatus.AVAILABLE,
                ),
            listSnapshot =
                BykcCourseDto(
                    id = 1L,
                    courseName = "测试课程",
                    courseMaxCount = 10,
                    courseCurrentCount = 10,
                    status = BykcCourseStatus.FULL,
                ),
            now = LocalDateTime.parse("2025-03-16T09:00:00"),
        )

    assertEquals(BykcCourseStatus.FULL, status)
  }

  @Test
  fun `resolveBykcAttendanceActionState uses server sign availability flags`() {
    val state =
        resolveBykcAttendanceActionState(
            BykcCourseDetailDto(
                id = 1L,
                courseName = "测试课程",
                status = BykcCourseStatus.SELECTED,
                selected = true,
                signConfig = BykcSignConfigDto(),
                checkin = 0,
                canSign = true,
                canSignOut = false,
            )
        )

    assertTrue(state.canSignIn)
    assertFalse(state.canSignOut)
    assertEquals(null, state.disabledReason)
  }

  @Test
  fun `resolveBykcAttendanceActionState shows time window reason for pending checkin`() {
    val state =
        resolveBykcAttendanceActionState(
            BykcCourseDetailDto(
                id = 1L,
                courseName = "测试课程",
                status = BykcCourseStatus.SELECTED,
                selected = true,
                signConfig = BykcSignConfigDto(),
                checkin = 0,
                canSign = false,
                canSignOut = false,
            )
        )

    assertEquals("当前不在签到时间窗口内。", state.disabledReason)
  }

  @Test
  fun `resolveBykcAttendanceActionState shows status reason for blocked checkin`() {
    val state =
        resolveBykcAttendanceActionState(
            BykcCourseDetailDto(
                id = 1L,
                courseName = "测试课程",
                status = BykcCourseStatus.SELECTED,
                selected = true,
                signConfig = BykcSignConfigDto(),
                checkin = 1,
                canSign = false,
                canSignOut = false,
            )
        )

    assertEquals("当前考勤状态不可签到/签退。", state.disabledReason)
  }

  @Test
  fun `resolveBykcAttendanceActionState enables sign out when local time enters sign out window`() {
    val state =
        resolveBykcAttendanceActionState(
            course =
                BykcCourseDetailDto(
                    id = 1L,
                    courseName = "测试课程",
                    status = BykcCourseStatus.SELECTED,
                    selected = true,
                    signConfig =
                        BykcSignConfigDto(
                            signStartDate = "2025-03-16 16:20:00",
                            signEndDate = "2025-03-16 16:40:00",
                            signOutStartDate = "2025-03-16 17:50:00",
                            signOutEndDate = "2025-03-16 18:15:00",
                        ),
                    checkin = 5,
                    canSign = false,
                    canSignOut = false,
                ),
            now = LocalDateTime.parse("2025-03-16T17:53:00"),
        )

    assertFalse(state.canSignIn)
    assertTrue(state.canSignOut)
    assertEquals(null, state.disabledReason)
  }

  @Test
  fun `resolveBykcAttendanceActionState enables sign out for unsigned course in sign out window`() {
    val state =
        resolveBykcAttendanceActionState(
            course =
                BykcCourseDetailDto(
                    id = 1L,
                    courseName = "测试课程",
                    status = BykcCourseStatus.SELECTED,
                    selected = true,
                    signConfig =
                        BykcSignConfigDto(
                            signStartDate = "2025-03-16 16:20:00",
                            signEndDate = "2025-03-16 16:40:00",
                            signOutStartDate = "2025-03-16 17:50:00",
                            signOutEndDate = "2025-03-16 18:15:00",
                        ),
                    checkin = 0,
                    canSign = false,
                    canSignOut = false,
                ),
            now = LocalDateTime.parse("2025-03-16T17:53:00"),
        )

    assertFalse(state.canSignIn)
    assertTrue(state.canSignOut)
    assertEquals(null, state.disabledReason)
  }
}
