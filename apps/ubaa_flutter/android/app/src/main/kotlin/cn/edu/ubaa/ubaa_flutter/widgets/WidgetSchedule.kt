package cn.edu.ubaa.ubaa_flutter.widgets

import java.time.LocalDate
import org.json.JSONObject

internal data class WidgetCourse(
    val courseName: String,
    val dayOfWeek: Int?,
    val beginSection: Int?,
    val endSection: Int?,
    val beginTime: String?,
    val endTime: String?,
    val placeName: String?,
    val weeksAndTeachers: String? = null,
)

internal data class WidgetTime(val section: Int, val start: String?, val end: String?)

internal data class WidgetWeek(
    val serialNumber: Int,
    val name: String,
    val startDate: String,
    val endDate: String,
    val arrangedList: List<WidgetCourse>,
    val times: List<WidgetTime>,
)

internal data class WidgetSemester(
    val termCode: String,
    val updatedAt: String,
    val weeks: List<WidgetWeek>,
    val name: String = termCode,
)

internal data class WidgetSnapshot(val owner: String, val semesters: List<WidgetSemester>)

internal data class SelectedWeek(val semester: WidgetSemester, val week: WidgetWeek)

internal data class SavedAgendaItem(val date: LocalDate, val course: WidgetCourse)

internal fun parseWidgetSnapshot(raw: JSONObject): WidgetSnapshot {
    require(raw.getInt("version") == 1)
    val owner = raw.getString("owner")
    require(owner.isNotBlank() && owner.length <= 128)
    val terms = raw.getJSONArray("semesters")
    require(terms.length() <= 32)
    val semesters =
        (0 until terms.length()).map { i ->
            val term = terms.getJSONObject(i)
            val termCode = term.getString("term")
            require(termCode.isNotBlank() && termCode.length <= 128)
            val weeks = term.getJSONArray("weeks")
            require(weeks.length() in 1..80)
            val rows =
                (0 until weeks.length())
                    .map { j ->
                        val week = weeks.getJSONObject(j)
                        val number = week.getInt("number")
                        val start = LocalDate.parse(week.getString("start"))
                        val end = LocalDate.parse(week.getString("end"))
                        require(
                            number > 0 && start.dayOfWeek.value == 1 && start.plusDays(6) == end
                        )
                        val courses = week.getJSONArray("courses")
                        require(courses.length() <= 512)
                        val classes =
                            (0 until courses.length()).map { k ->
                                val c = courses.getJSONObject(k)
                                val day = c.getInt("day")
                                require(day in 1..7)
                                val begin = c.optionalInt("begin")
                                val finish = c.optionalInt("end")
                                require(begin == null || begin in 1..32)
                                require(finish == null || finish in (begin ?: 1)..32)
                                WidgetCourse(
                                    c.getString("name").also { require(it.length <= 2048) },
                                    day,
                                    begin,
                                    finish,
                                    c.optionalString("startTime"),
                                    c.optionalString("endTime"),
                                    c.optionalString("place"),
                                    c.optionalString("weeksAndTeachers"),
                                )
                            }
                        val times = week.getJSONArray("times")
                        require(times.length() in 1..32)
                        val slots =
                            (0 until times.length()).map { k ->
                                val t = times.getJSONObject(k)
                                WidgetTime(
                                    t.getInt("section").also { require(it in 1..32) },
                                    t.optionalString("start"),
                                    t.optionalString("end"),
                                )
                            }
                        require(slots.map { it.section }.distinct().size == slots.size)
                        WidgetWeek(
                            number,
                            week.getString("name"),
                            start.toString(),
                            end.toString(),
                            classes,
                            slots,
                        )
                    }
                    .sortedBy { it.serialNumber }
            require(rows.map { it.serialNumber }.distinct().size == rows.size)
            WidgetSemester(
                termCode,
                term.getString("updatedAt"),
                rows,
                term.optionalString("name") ?: termCode,
            )
        }
    require(semesters.map { it.termCode }.distinct().size == semesters.size)
    return WidgetSnapshot(owner, semesters)
}

private fun JSONObject.optionalInt(key: String): Int? = if (isNull(key)) null else getInt(key)

private fun JSONObject.optionalString(key: String): String? =
    if (isNull(key)) null else getString(key).also { require(it.length <= 2048) }

/** 与冻结旧版同序：指定学期、本日覆盖的最新学期、起始日期最新学期。 */
internal fun selectSavedScheduleWeek(
    semesters: List<WidgetSemester>,
    today: LocalDate,
    term: String? = null,
    number: Int? = null,
): SelectedWeek? {
    val date = today.toString()
    val available = semesters.filter { it.weeks.isNotEmpty() }
    val semester =
        available.firstOrNull { it.termCode == term }
            ?: available
                .filter { it.weeks.any { w -> date in w.startDate..w.endDate } }
                .maxByOrNull { it.weeks.minOf { w -> w.startDate } }
            ?: available.maxByOrNull { it.weeks.minOf { w -> w.startDate } }
            ?: return null
    val weeks = semester.weeks.sortedBy { it.serialNumber }
    val week =
        weeks.firstOrNull { semester.termCode == term && it.serialNumber == number }
            ?: weeks.firstOrNull { date in it.startDate..it.endDate }
            ?: if (date < weeks.first().startDate) weeks.first() else weeks.last()
    return SelectedWeek(semester, week)
}

internal fun savedAgenda(
    semesters: List<WidgetSemester>,
    today: LocalDate,
    days: Int,
): List<SavedAgendaItem> {
    require(days in 1..3)
    return (0 until days).flatMap { offset ->
        val date = today.plusDays(offset.toLong())
        val selected = selectSavedScheduleWeek(semesters, date)
        if (selected == null || date.toString() !in selected.week.startDate..selected.week.endDate)
            emptyList()
        else
            selected.week.arrangedList
                .filter { it.dayOfWeek == date.dayOfWeek.value }
                .sortedBy { it.beginTime }
                .map { SavedAgendaItem(date, it) }
    }
}
