package cn.edu.ubaa.ubaa_flutter.widgets

import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WidgetScheduleTest {
    @Test
    fun 第二版保留原课表并拒绝未知版本() {
        val raw = JSONObject("""{"version":1,"owner":"合成账号","semesters":[{"term":"term","updatedAt":"2026-11-16T00:00:00Z","name":"合成学期","weeks":[{"number":1,"name":"第一周","start":"2026-09-28","end":"2026-10-04","courses":[{"name":"合成课程","day":1}],"times":[{"section":1}]}]}]}""")
        val first = parseWidgetSnapshot(raw)
        assertEquals("合成课程", first.semesters.single().weeks.single().arrangedList.single().courseName)
        assertEquals(first, parseWidgetSnapshot(raw.put("version", 2).put("upNext", JSONObject.NULL)))
        assertThrows(IllegalArgumentException::class.java) { parseWidgetSnapshot(raw.put("version", 3)) }
    }

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
