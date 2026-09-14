package cn.edu.ubaa.repository

import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.Week
import cn.edu.ubaa.model.dto.WeeklySchedule
import kotlin.test.*
import kotlinx.datetime.LocalDate

class SavedScheduleWeekTest {
  @Test
  fun upcomingAgendaIncludesNextWeekButNeverRepeatsAfterTermEnds() {
    val weeks =
        listOf(
            Week("2026-09-07", "2026-09-13", "20261", false, 1, "1"),
            Week("2026-09-14", "2026-09-20", "20261", false, 2, "2"),
        )
    fun course(day: Int) =
        CourseClass("a", "a", null, null, "08:00", "08:45", 1, 1, null, null, null, null, day)
    val semester =
        SemesterSchedule(
            emptyList(),
            "20261",
            weeks,
            mapOf(
                1 to WeeklySchedule(listOf(course(7)), "20261", "term"),
                2 to WeeklySchedule(listOf(course(1)), "20261", "term"),
            ),
        )
    assertEquals(
        listOf("2026-09-13", "2026-09-14"),
        savedAgenda(listOf(semester), LocalDate.parse("2026-09-13"), 3).map { it.date.toString() },
    )
    assertTrue(savedAgenda(listOf(semester), LocalDate.parse("2026-09-28"), 1).isEmpty())
  }

  @Test
  fun widgetUsesCurrentWeekOrRequestedCachedWeekWithoutNetwork() {
    val weeks =
        listOf(
            Week("2026-09-07", "2026-09-13", "20261", false, 1, "第1周"),
            Week("2026-09-14", "2026-09-20", "20261", false, 2, "第2周"),
        )
    val semester = SemesterSchedule(emptyList(), "20261", weeks, emptyMap())
    val old =
        semester.copy(
            termCode = "20252",
            weeks =
                listOf(
                    weeks
                        .first()
                        .copy(term = "20252", startDate = "2026-03-01", endDate = "2026-09-20")
                ),
        )
    val data = listOf(old, semester)
    val today = LocalDate.parse("2026-09-15")
    assertEquals("20261", selectSavedScheduleWeek(data, today)?.semester?.termCode)
    assertEquals(2, selectSavedScheduleWeek(data, today)?.week?.serialNumber)
    assertEquals(1, selectSavedScheduleWeek(data, today, "20261", 1)?.week?.serialNumber)
    assertEquals(2, selectSavedScheduleWeek(data, today, "missing", 1)?.week?.serialNumber)
    assertEquals(
        1,
        selectSavedScheduleWeek(listOf(semester), LocalDate.parse("2026-09-01"))
            ?.week
            ?.serialNumber,
    )
    assertEquals(
        2,
        selectSavedScheduleWeek(listOf(semester), LocalDate.parse("2026-10-01"))
            ?.week
            ?.serialNumber,
    )
    assertNull(selectSavedScheduleWeek(emptyList(), today))
    assertNull(selectSavedScheduleWeek(listOf(semester.copy(weeks = emptyList())), today))
  }
}
