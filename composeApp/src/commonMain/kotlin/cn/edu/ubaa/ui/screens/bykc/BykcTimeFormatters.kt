@file:OptIn(kotlin.time.ExperimentalTime::class)

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

data class BykcAttendanceActionState(
    val canSignIn: Boolean,
    val canSignOut: Boolean,
    val disabledReason: String? = null,
)

fun formatDateTimeDisplay(dateTime: LocalDateTime): String =
    "${formatBykcDate(dateTime)} ${formatBykcTime(dateTime)}"

fun formatDateRange(startDate: LocalDateTime, endDate: LocalDateTime): String =
    if (startDate.date == endDate.date) {
      "${formatBykcDate(startDate)} ${formatBykcTime(startDate)} - ${formatBykcTime(endDate)}"
    } else {
      "${formatDateTimeDisplay(startDate)} - ${formatDateTimeDisplay(endDate)}"
    }

fun formatDateRangeOrStart(startDate: LocalDateTime, endDate: LocalDateTime?): String =
    endDate?.let { formatDateRange(startDate, it) } ?: formatDateTimeDisplay(startDate)

fun resolveSelectTimeDisplay(
    startDate: LocalDateTime?,
    endDate: LocalDateTime?,
    now: LocalDateTime = currentBykcLocalDateTime(),
): BykcSelectTimeDisplay? {
  return when {
    startDate != null && now < startDate ->
        BykcSelectTimeDisplay("开始选课", formatDateTimeDisplay(startDate))
    endDate != null -> BykcSelectTimeDisplay("截止选课", formatDateTimeDisplay(endDate))
    startDate != null -> BykcSelectTimeDisplay("开始选课", formatDateTimeDisplay(startDate))
    else -> null
  }
}

fun isBykcCourseFull(
    courseCurrentCount: Int?,
    courseMaxCount: Int,
    status: BykcCourseStatus?,
): Boolean {
  val fullByCount =
      courseCurrentCount != null && courseMaxCount > 0 && courseCurrentCount >= courseMaxCount
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

  val selectStart = course.courseSelectStartDate
  if (selectStart != null && now < selectStart) {
    return BykcSelectButtonState(false, "该课程尚未开始选课。")
  }

  val selectEnd = course.courseSelectEndDate
  if (selectEnd != null && now > selectEnd) {
    return BykcSelectButtonState(false, "该课程已截止选课，当前不可选择。")
  }

  return when (course.status) {
    BykcCourseStatus.AVAILABLE -> BykcSelectButtonState(true)
    BykcCourseStatus.ENDED -> BykcSelectButtonState(false, "该课程选课已结束，当前不可选择。")
    BykcCourseStatus.EXPIRED -> BykcSelectButtonState(false, "该课程已过期，当前不可选择。")
    else -> BykcSelectButtonState(false, "该课程当前状态不可选择。")
  }
}

fun resolveBykcDisplayStatus(
    course: BykcCourseDetailDto,
    listSnapshot: BykcCourseDto? = null,
    now: LocalDateTime = currentBykcLocalDateTime(),
): BykcCourseStatus {
  val isFull =
      isBykcCourseFull(course.courseCurrentCount, course.courseMaxCount, course.status) ||
          listSnapshot?.let {
            isBykcCourseFull(it.courseCurrentCount, it.courseMaxCount, it.status)
          } == true
  if (isFull) return BykcCourseStatus.FULL

  val selectStart = course.courseSelectStartDate
  if (selectStart != null && now < selectStart) return BykcCourseStatus.PREVIEW

  val selectEnd = course.courseSelectEndDate
  if (selectEnd != null && now > selectEnd) return BykcCourseStatus.ENDED

  return course.status
}

fun resolveBykcAttendanceActionState(
    course: BykcCourseDetailDto,
    now: LocalDateTime = currentBykcLocalDateTime(),
): BykcAttendanceActionState {
  val canSignIn = course.canSign || canBykcSignIn(course, now)
  val canSignOut = course.canSignOut || canBykcSignOut(course, now)

  val disabledReason =
      when {
        course.pass == 1 || course.signConfig == null || canSignIn || canSignOut -> null
        isBykcCheckinStateBlockingAttendanceActions(course.checkin) -> "当前考勤状态不可签到/签退。"
        isBykcCheckinStateWaitingForSignOut(course.checkin) -> "当前不在签退时间窗口内。"
        else -> "当前不在签到时间窗口内。"
      }

  return BykcAttendanceActionState(
      canSignIn = canSignIn,
      canSignOut = canSignOut,
      disabledReason = disabledReason,
  )
}

fun parseBykcDateTime(dateTime: String?): LocalDateTime? {
  if (dateTime.isNullOrBlank()) return null
  return try {
    LocalDateTime.parse(dateTime.replace(" ", "T"))
  } catch (_: Exception) {
    null
  }
}

private fun canBykcSignIn(course: BykcCourseDetailDto, now: LocalDateTime): Boolean =
    course.pass != 1 &&
        isBykcCheckinStateUnsigned(course.checkin) &&
        isBykcWithinWindow(
            course.signConfig?.signStartDate,
            course.signConfig?.signEndDate,
            now,
        )

private fun canBykcSignOut(course: BykcCourseDetailDto, now: LocalDateTime): Boolean =
    course.pass != 1 &&
        isBykcCheckinStateSignOutEligible(course.checkin) &&
        isBykcWithinWindow(
            course.signConfig?.signOutStartDate,
            course.signConfig?.signOutEndDate,
            now,
        )

private fun isBykcWithinWindow(
    startDate: LocalDateTime?,
    endDate: LocalDateTime?,
    now: LocalDateTime,
): Boolean {
  val start = startDate ?: return false
  val end = endDate ?: return false
  return now >= start && now <= end
}

private fun isBykcCheckinStateUnsigned(checkin: Int?): Boolean = checkin == null || checkin == 0

private fun isBykcCheckinStateSignOutEligible(checkin: Int?): Boolean =
    isBykcCheckinStateUnsigned(checkin) || isBykcCheckinStateWaitingForSignOut(checkin)

private fun isBykcCheckinStateWaitingForSignOut(checkin: Int?): Boolean =
    checkin == 5 || checkin == 6

private fun isBykcCheckinStateBlockingAttendanceActions(checkin: Int?): Boolean =
    checkin != null && checkin != 0 && !isBykcCheckinStateWaitingForSignOut(checkin)

private fun currentBykcLocalDateTime(): LocalDateTime =
    Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())

private fun formatBykcDate(dateTime: LocalDateTime): String = buildString {
  append(dateTime.year)
  append('-')
  append((dateTime.month.ordinal + 1).toString().padStart(2, '0'))
  append('-')
  append(dateTime.day.toString().padStart(2, '0'))
}

private fun formatBykcTime(dateTime: LocalDateTime): String =
    "${dateTime.hour.toString().padStart(2, '0')}:${dateTime.minute.toString().padStart(2, '0')}"
