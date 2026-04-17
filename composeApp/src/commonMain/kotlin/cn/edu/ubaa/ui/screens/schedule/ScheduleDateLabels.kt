package cn.edu.ubaa.ui.screens.schedule

import cn.edu.ubaa.model.dto.Week
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.plus

internal data class ScheduleHeaderDayLabel(
    val weekdayLabel: String,
    val dateLabel: String? = null,
)

internal fun defaultScheduleHeaderDayLabels(): List<ScheduleHeaderDayLabel> =
    listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日").map {
      ScheduleHeaderDayLabel(weekdayLabel = it)
    }

internal fun Week.headerDayLabels(): List<ScheduleHeaderDayLabel> {
  val parsedStart =
      parseWeekBoundaryDate(startDate)
          ?: parseWeekBoundaryDate(endDate)?.plus(DatePeriod(days = -6))
  val defaults = defaultScheduleHeaderDayLabels()
  if (parsedStart == null) return defaults

  return defaults.mapIndexed { index, default ->
    ScheduleHeaderDayLabel(
        weekdayLabel = default.weekdayLabel,
        dateLabel = parsedStart.plus(DatePeriod(days = index)).toShortMonthDayLabel(),
    )
  }
}

private fun parseWeekBoundaryDate(raw: String?): LocalDate? {
  val normalized = raw?.trim().orEmpty()
  if (normalized.isEmpty()) return null

  runCatching { LocalDate.parse(normalized) }
      .getOrNull()
      ?.let {
        return it
      }

  val match = FLEXIBLE_DATE_PATTERN.find(normalized) ?: return null
  val (yearText, monthText, dayText) = match.destructured
  return runCatching { LocalDate(yearText.toInt(), monthText.toInt(), dayText.toInt()) }.getOrNull()
}

private fun LocalDate.toShortMonthDayLabel(): String = "${month.ordinal + 1}-${day}"

private val FLEXIBLE_DATE_PATTERN = Regex("""(\d{4})\D+(\d{1,2})\D+(\d{1,2})""")
