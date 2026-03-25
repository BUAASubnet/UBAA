package cn.edu.ubaa.ui.screens.bykc

import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.datetime.LocalDateTime

class BykcTimeFormattersTest {

  @Test
  fun `formatDateTimeDisplay trims seconds`() {
    assertEquals("2025-03-15 14:00", formatDateTimeDisplay("2025-03-15 14:00:00"))
  }

  @Test
  fun `formatDateRange keeps same-day end time compact`() {
    assertEquals(
        "2025-03-15 14:00 - 16:30",
        formatDateRange("2025-03-15 14:00:00", "2025-03-15 16:30:00"),
    )
  }

  @Test
  fun `formatDateRange shows full cross-day timestamps`() {
    assertEquals(
        "2025-03-15 23:30 - 2025-03-16 08:15",
        formatDateRange("2025-03-15 23:30:00", "2025-03-16 08:15:00"),
    )
  }

  @Test
  fun `resolveSelectTimeDisplay shows start before selection begins`() {
    val display =
        resolveSelectTimeDisplay(
            startDate = "2025-03-16 08:00:00",
            endDate = "2025-03-16 18:00:00",
            now = LocalDateTime.parse("2025-03-16T07:30:00"),
        )

    assertEquals("开始选课", display?.label)
    assertEquals("2025-03-16 08:00", display?.value)
  }

  @Test
  fun `resolveSelectTimeDisplay shows end after selection begins`() {
    val display =
        resolveSelectTimeDisplay(
            startDate = "2025-03-16 08:00:00",
            endDate = "2025-03-16 18:00:00",
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
            endDate = "2025-03-16 18:00:00",
            now = LocalDateTime.parse("2025-03-16T08:30:00"),
        )

    assertEquals("截止选课", display?.label)
    assertEquals("2025-03-16 18:00", display?.value)
  }

  @Test
  fun `isBykcCourseFull returns true for full count and full status`() {
    assertTrue(isBykcCourseFull(courseCurrentCount = 10, courseMaxCount = 10, status = "可选"))
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
                    courseSelectStartDate = "2025-03-16 08:00:00",
                    courseSelectEndDate = "2025-03-16 18:00:00",
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
                    courseSelectStartDate = "2025-03-16 08:00:00",
                    courseSelectEndDate = "2025-03-16 18:00:00",
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
}
