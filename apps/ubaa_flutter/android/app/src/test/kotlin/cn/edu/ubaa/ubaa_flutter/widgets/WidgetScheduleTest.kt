package cn.edu.ubaa.ubaa_flutter.widgets

import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Test

class WidgetScheduleTest {
    private fun week(n: Int, start: String) =
        WidgetWeek(
            n,
            "第${n}周",
            start,
            LocalDate.parse(start).plusDays(6).toString(),
            listOf(WidgetCourse("合成$n", 1, 1, 2, "08:00", "09:35", "合成教室")),
            listOf(WidgetTime(1, "08:00", null)),
        )

    private val semesters =
        listOf(WidgetSemester("term", "", listOf(week(1, "2026-09-28"), week(2, "2026-10-05"))))

    @Test
    fun 日期覆盖和明确周次遵循旧版() {
        assertEquals(
            1,
            selectSavedScheduleWeek(semesters, LocalDate.parse("2026-10-03"))!!.week.serialNumber,
        )
        assertEquals(
            2,
            selectSavedScheduleWeek(semesters, LocalDate.parse("2026-10-03"), "term", 2)!!
                .week
                .serialNumber,
        )
        assertEquals(
            1,
            selectSavedScheduleWeek(semesters, LocalDate.parse("2026-09-01"))!!.week.serialNumber,
        )
        assertEquals(
            2,
            selectSavedScheduleWeek(semesters, LocalDate.parse("2026-12-01"))!!.week.serialNumber,
        )
    }

    @Test
    fun 未来三天跨周只返回对应日期课程() {
        val values = savedAgenda(semesters, LocalDate.parse("2026-10-03"), 3)
        assertEquals(listOf("2026-10-05"), values.map { it.date.toString() })
        assertEquals("合成2", values.single().course.courseName)
        assertTrue(savedAgenda(semesters, LocalDate.parse("2026-12-01"), 3).isEmpty())
    }
}
