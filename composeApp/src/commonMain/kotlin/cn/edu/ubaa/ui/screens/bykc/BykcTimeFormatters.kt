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
    !endDate.isNullOrBlank() -> BykcSelectTimeDisplay("截止选课", formatDateTimeDisplay(endDate))
    !startDate.isNullOrBlank() -> BykcSelectTimeDisplay("开始选课", formatDateTimeDisplay(startDate))
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
    startDate: String?,
    endDate: String?,
    now: LocalDateTime,
): Boolean {
  val start = parseBykcDateTime(startDate) ?: return false
  val end = parseBykcDateTime(endDate) ?: return false
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
