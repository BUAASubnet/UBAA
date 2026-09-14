package cn.edu.ubaa.repository

import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.Week
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.plus

/** 桌面小组件和点击入口共用已保存的学期、周次，不发起网络请求。 */
data class SavedScheduleWeek(val semester: SemesterSchedule, val week: Week)

fun selectSavedScheduleWeek(
    semesters: List<SemesterSchedule>,
    today: LocalDate,
    termCode: String? = null,
    weekNumber: Int? = null,
): SavedScheduleWeek? {
  val date = today.toString()
  val available = semesters.filter { it.weeks.isNotEmpty() }
  val semester =
      available.firstOrNull { it.termCode == termCode }
          ?: available
              .filter { it.weeks.any { week -> date >= week.startDate && date <= week.endDate } }
              .maxByOrNull { it.weeks.minOf { week -> week.startDate } }
          ?: available.maxByOrNull { it.weeks.minOf { week -> week.startDate } }
          ?: return null
  val weeks = semester.weeks.sortedBy { it.serialNumber }
  val week =
      weeks.firstOrNull { it.serialNumber == weekNumber && semester.termCode == termCode }
          ?: weeks.firstOrNull { date >= it.startDate && date <= it.endDate }
          ?: if (date < weeks.first().startDate) weeks.first() else weeks.last()
  return SavedScheduleWeek(semester, week)
}

data class SavedAgendaItem(val date: LocalDate, val course: CourseClass)

fun savedAgenda(
    semesters: List<SemesterSchedule>,
    today: LocalDate,
    days: Int,
): List<SavedAgendaItem> =
    (0 until days).flatMap { offset ->
      val date = today.plus(offset, DateTimeUnit.DAY)
      val selected = selectSavedScheduleWeek(semesters, date) ?: return@flatMap emptyList()
      if (date.toString() !in selected.week.startDate..selected.week.endDate)
          return@flatMap emptyList()
      selected.semester.schedules[selected.week.serialNumber]
          ?.arrangedList
          .orEmpty()
          .filter { it.dayOfWeek == date.dayOfWeek.ordinal + 1 }
          .sortedBy { it.beginTime }
          .map { SavedAgendaItem(date, it) }
    }
