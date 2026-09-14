package cn.edu.ubaa.repository

import cn.edu.ubaa.model.dto.*
import kotlin.test.*

class ScheduleTimelineTest {
  @Test
  fun explicitTimesAndOldCacheBoundariesNeverInventBreaks() {
    val course =
        CourseClass("a", "a", null, null, "08:00", "09:35", 1, 2, null, null, null, null, 1)
    val old = WeeklySchedule(listOf(course), "2026-2027-1", "term")
    val oldTimes = scheduleSectionTimes(listOf(old))
    assertEquals("08:00", oldTimes[0].start)
    assertNull(oldTimes[0].end)
    assertNull(oldTimes[1].start)
    assertEquals("09:35", oldTimes[1].end)
    val current =
        old.copy(
            sectionTimes =
                listOf(
                    SectionTime(1, "08:00", "08:45"),
                    SectionTime(2, "08:50", "09:35"),
                    SectionTime(14, "21:30", "22:15"),
                )
        )
    assertEquals(14, scheduleSectionTimes(listOf(current)).size)
    assertEquals("08:45", scheduleSectionTimes(listOf(current))[0].end)
    val conflicting = current.copy(sectionTimes = listOf(SectionTime(1, "09:00", "09:45")))
    assertNull(scheduleSectionTimes(listOf(current, conflicting))[0].start)
    val graduate = old.copy(code = "20261")
    val complete = scheduleSectionTimes(listOf(graduate))
    assertEquals(14, complete.size)
    assertTrue(complete.all { it.start != null && it.end != null })
    assertEquals("14:00", complete[5].start)
    assertEquals("22:15", complete.last().end)
    assertEquals(complete, scheduleSectionTimes(listOf(graduate.copy(arrangedList = emptyList()))))
    // 其他作息方案不套用 01，显式上游数据始终优先。
    assertNull(
        scheduleSectionTimes(
                listOf(graduate.copy(arrangedList = listOf(course.copy(beginTime = "08:30"))))
            )[0]
            .end
    )
    assertEquals(
        "09:00",
        scheduleSectionTimes(listOf(graduate.copy(sectionTimes = conflicting.sectionTimes)))[0]
            .start,
    )
  }
}
