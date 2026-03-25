package cn.edu.ubaa.ui.screens.bykc

import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlin.time.Clock
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

data class BykcSelectTimeDisplay(val label: String, val value: String)

data class BykcSelectButtonState(val enabled: Boolean, val disabledReason: String? = null)

fun formatDateTimeDisplay(dateTime: String): String {
  val parts = dateTime.split(" ")
  if (parts.size != 2) return dateTime

  val datePart = parts[0]
  val timePart = parts[1]
  if (timePart.length < 5) return dateTime

  return "$datePart ${timePart.take(5)}"
}

fun formatDateRange(startDate: String, endDate: String): String {
  val startParts = startDate.split(" ")
  val endParts = endDate.split(" ")

  if (startParts.size == 2 && endParts.size == 2) {
    val startDatePart = startParts[0]
    val startTimePart = startParts[1].take(5)
    val endDatePart = endParts[0]
    val endTimePart = endParts[1].take(5)

    return if (startDatePart == endDatePart) {
      "$startDatePart $startTimePart - $endTimePart"
    } else {
      "${formatDateTimeDisplay(startDate)} - ${formatDateTimeDisplay(endDate)}"
    }
  }

  return "$startDate - $endDate"
}

fun resolveSelectTimeDisplay(
    startDate: String?,
    endDate: String?,
    now: LocalDateTime = currentBykcLocalDateTime(),
): BykcSelectTimeDisplay? {
  val start = parseBykcDateTime(startDate)

  return when {
    !startDate.isNullOrBlank() && start != null && now < start ->
        BykcSelectTimeDisplay("开始选课", formatDateTimeDisplay(startDate))
    !endDate.isNullOrBlank() ->
        BykcSelectTimeDisplay("截止选课", formatDateTimeDisplay(endDate))
    !startDate.isNullOrBlank() ->
        BykcSelectTimeDisplay("开始选课", formatDateTimeDisplay(startDate))
    else -> null
  }
}

fun isBykcCourseFull(
    courseCurrentCount: Int,
    courseMaxCount: Int,
    status: String?,
): Boolean {
  val fullByCount = courseMaxCount > 0 && courseCurrentCount >= courseMaxCount
  return fullByCount || status == BykcCourseStatus.FULL
}

fun resolveBykcSelectButtonState(
    course: BykcCourseDetailDto,
    operationInProgress: Boolean,
    listSnapshot: BykcCourseDto? = null,
    now: LocalDateTime = currentBykcLocalDateTime(),
): BykcSelectButtonState {
  if (operationInProgress) return BykcSelectButtonState(enabled = false)

  val isFull =
      isBykcCourseFull(course.courseCurrentCount, course.courseMaxCount, course.status) ||
          listSnapshot?.let {
            isBykcCourseFull(it.courseCurrentCount, it.courseMaxCount, it.status)
          } == true

  if (isFull) return BykcSelectButtonState(false, "该课程人数已满，当前不可选择。")
  if (course.selected) return BykcSelectButtonState(false, "该课程已选，无法重复选择。")

  val selectStart = parseBykcDateTime(course.courseSelectStartDate)
  if (selectStart != null && now < selectStart) {
    return BykcSelectButtonState(false, "该课程尚未开始选课。")
  }

  val selectEnd = parseBykcDateTime(course.courseSelectEndDate)
  if (selectEnd != null && now > selectEnd) {
    return BykcSelectButtonState(false, "该课程已截止选课，当前不可选择。")
  }

  return when (course.status) {
    BykcCourseStatus.AVAILABLE -> BykcSelectButtonState(true)
    BykcCourseStatus.ENDED -> BykcSelectButtonState(false, "该课程已结束，当前不可选择。")
    BykcCourseStatus.EXPIRED -> BykcSelectButtonState(false, "该课程已过期，当前不可选择。")
    else -> BykcSelectButtonState(false, "该课程当前状态不可选择。")
  }
}

fun resolveBykcDisplayStatus(
    course: BykcCourseDetailDto,
    listSnapshot: BykcCourseDto? = null,
    now: LocalDateTime = currentBykcLocalDateTime(),
): String {
  val isFull =
      isBykcCourseFull(course.courseCurrentCount, course.courseMaxCount, course.status) ||
          listSnapshot?.let {
            isBykcCourseFull(it.courseCurrentCount, it.courseMaxCount, it.status)
          } == true
  if (isFull) return BykcCourseStatus.FULL

  val selectStart = parseBykcDateTime(course.courseSelectStartDate)
  if (selectStart != null && now < selectStart) return BykcCourseStatus.PREVIEW

  val selectEnd = parseBykcDateTime(course.courseSelectEndDate)
  if (selectEnd != null && now > selectEnd) return BykcCourseStatus.ENDED

  return course.status
}

fun parseBykcDateTime(dateTime: String?): LocalDateTime? {
  if (dateTime.isNullOrBlank()) return null
  return try {
    LocalDateTime.parse(dateTime.replace(" ", "T"))
  } catch (_: Exception) {
    null
  }
}

private fun currentBykcLocalDateTime(): LocalDateTime =
    Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
