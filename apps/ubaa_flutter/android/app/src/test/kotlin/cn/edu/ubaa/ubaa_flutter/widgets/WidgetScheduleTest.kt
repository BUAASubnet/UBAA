package cn.edu.ubaa.ubaa_flutter.widgets

import java.io.File
import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WidgetScheduleTest {
    private fun fixture(): JSONObject {
        val file = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { it.resolve("fixtures/schedule_widget/snapshot_v2.json") }
            .first { it.isFile }
        return JSONObject(file.readText())
    }

    @Test
    fun 共享样例的第二版状态表不能被忽略() {
        val raw = fixture()
        val snapshot = parseWidgetSnapshot(raw)
        val legacy = parseWidgetSnapshot(raw.put("version", 1))
        assertNotEquals(snapshot, legacy)
        assertEquals(legacy.semesters, snapshot.semesters)
        assertEquals(1795968000L, snapshot.horizonEnd)
        assertEquals("高等数学", snapshot.upNext!!.first().primary!!.title)
        assertEquals(listOf("高等数学", "大学英语", "研讨室预约", "博雅讲座"), snapshot.today!!.first().rows.map { it.title })
        assertEquals("明天", snapshot.today.first { it.from == 1794834000L }.dayLabel)
        assertEquals("exam", snapshot.todo!!.first().smallRow!!.kind)
        assertTrue(snapshot.todo.last().staleText!!.isNotEmpty())
    }

    @Test
    fun 取段包含起点但不包含有效期终点() {
        val snapshot = parseWidgetSnapshot(fixture())
        for (table in listOf(snapshot.upNext!!, snapshot.today!!, snapshot.todo!!)) {
            val first = table.first()
            val second = table[1]
            val end = snapshot.horizonEnd!!
            assertEquals(first, snapshot.segment(table, first.from - 1))
            assertEquals(first, snapshot.segment(table, second.from - 1))
            assertEquals(second, snapshot.segment(table, second.from))
            assertEquals(table.last(), snapshot.segment(table, end - 1))
            assertNull(snapshot.segment(table, end))
            assertNull(snapshot.segment(table, end + 1))
        }
    }

    @Test
    fun 坏表不影响其余状态表或周课表() {
        val raw = fixture()
        val original = parseWidgetSnapshot(raw)
        val brokenUpNext = listOf<(JSONObject) -> Unit>(
            { it.put("upNext", JSONObject()) },
            { it.put("upNext", org.json.JSONArray()) },
            { it.getJSONArray("upNext").getJSONObject(1).put("from", original.upNext!!.first().from) },
            { it.getJSONArray("upNext").getJSONObject(0).put("from", "1794758400") },
            { it.getJSONArray("upNext").getJSONObject(16).put("from", original.horizonEnd) },
            { it.getJSONArray("upNext").getJSONObject(0).put("state", "unknown") },
            { it.getJSONArray("upNext").getJSONObject(0).put("primary", JSONObject.NULL) },
            { it.getJSONArray("upNext").getJSONObject(0).getJSONObject("primary").put("ongoing", "false") },
        )
        for (breakTable in brokenUpNext) {
            val broken = parseWidgetSnapshot(JSONObject(raw.toString()).also(breakTable))
            assertEquals(original.copy(upNext = null), broken)
        }
        raw.getJSONArray("today").getJSONObject(0).put("rows", org.json.JSONArray())
        raw.getJSONArray("todo").getJSONObject(0).getJSONObject("smallRow").put("urgent", 1)
        assertEquals(original.copy(today = null, todo = null), parseWidgetSnapshot(raw))
        assertEquals(original.copy(horizonEnd = null, upNext = null, today = null, todo = null),
            parseWidgetSnapshot(raw.put("horizonEnd", "1795968000")))
    }

    @Test
    fun 刷新取三张表的下一起点与有效期终点() {
        val snapshot = parseWidgetSnapshot(fixture())
        assertEquals(1794758400L, snapshot.nextRefresh(1794758399))
        assertEquals(1794783600L, snapshot.nextRefresh(1794758400))
        assertEquals(1794787200L, snapshot.nextRefresh(1794783600))
        assertEquals(1794819600L, snapshot.nextRefresh(1794816000))
        assertEquals(1794832200L, snapshot.nextRefresh(1794826800))
        assertEquals(1795968000L, snapshot.nextRefresh(1795086000))
        assertEquals(1795968000L, snapshot.copy(upNext = null, today = null, todo = null).nextRefresh(1794758400))
        assertNull(snapshot.nextRefresh(1795968000))
        assertNull(WidgetSnapshot(snapshot.owner, snapshot.semesters).nextRefresh(1794758400))
    }

    @Test
    fun 各组件每个槽位的请求码各不相同() {
        val ids = listOf(1, 2, 3, 4, 1024)
        val codes = ids.flatMap { id -> (0..15).map { slot -> widgetRequestCode(id, slot) } }
        assertEquals(ids.size * 16, codes.toSet().size)
        assertEquals(48, widgetRequestCode(3, 0))
        assertEquals(51, widgetRequestCode(3, 3))
    }

    @Test
    fun 通道首次取走前只保留最近链接() {
        val inbox = WidgetLaunchInbox()
        assertNull(inbox.offer("旧链接"))
        assertNull(inbox.offer("新链接"))
        assertEquals("新链接", inbox.take())
        assertNull(inbox.take())
        assertEquals("热启动链接", inbox.offer("热启动链接"))
        inbox.awaitTake()
        assertNull(inbox.offer("新引擎链接"))
        assertEquals("新引擎链接", inbox.take())
    }

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
}
