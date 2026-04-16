package cn.edu.ubaa.ui.screens.menu

import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import kotlin.time.Duration.Companion.minutes
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.LocalTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant

internal enum class HomeTodoSource(val label: String) {
  BYKC("博雅"),
  SPOC("SPOC"),
  CGYY("研讨室"),
  SIGNIN("签到"),
}

internal sealed interface HomeTodoAction {
  data class OpenBykcCourse(val courseId: Long) : HomeTodoAction

  data class OpenSpocAssignment(val assignmentId: String) : HomeTodoAction

  data object OpenCgyyOrders : HomeTodoAction

  data class SigninCourse(val courseId: String) : HomeTodoAction
}

internal data class HomeTodoItem(
    val id: String,
    val source: HomeTodoSource,
    val title: String,
    val subtitle: String,
    val statusLabel: String,
    val timeLabel: String,
    val sortTime: LocalDateTime?,
    val action: HomeTodoAction,
) {
  val actionLabel: String?
    get() =
        when (action) {
          is HomeTodoAction.SigninCourse -> "签到"
          else -> null
        }
}

internal fun buildHomeTodoItems(
    bykcCourses: List<BykcChosenCourseDto>,
    spocAssignments: List<SpocAssignmentSummaryDto>,
    cgyyOrders: List<CgyyOrderDto>,
    signinClasses: List<SigninClassDto>,
    now: LocalDateTime,
    timeZone: TimeZone = TimeZone.currentSystemDefault(),
): List<HomeTodoItem> {
  val today = now.date
  return buildList {
        addAll(buildBykcTodoItems(bykcCourses, now))
        addAll(buildSpocTodoItems(spocAssignments, now))
        addAll(buildCgyyTodoItems(cgyyOrders, now))
        addAll(buildSigninTodoItems(signinClasses, now, today, timeZone))
      }
      .sortedWith(compareBy<HomeTodoItem> { it.sortTime == null }.thenBy { it.sortTime })
}

internal fun parseHomeDateTime(value: String?, today: LocalDate? = null): LocalDateTime? {
  val normalized = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
  if ('-' in normalized && (' ' in normalized || 'T' in normalized)) {
    return runCatching { LocalDateTime.parse(normalized.replace(" ", "T")) }.getOrNull()
  }

  val time = parseClockTime(normalized) ?: return null
  val targetDate = today ?: return null
  return LocalDateTime(
      year = targetDate.year,
      month = targetDate.month,
      day = targetDate.day,
      hour = time.hour,
      minute = time.minute,
      second = time.second,
      nanosecond = time.nanosecond,
  )
}

internal fun formatHomeDateTime(value: LocalDateTime?): String =
    value?.let {
      "${it.month.ordinal + 1}月${it.day}日 ${it.hour.toPaddedString()}:${it.minute.toPaddedString()}"
    } ?: "时间待定"

private fun buildBykcTodoItems(
    courses: List<BykcChosenCourseDto>,
    now: LocalDateTime,
): List<HomeTodoItem> =
    courses.mapNotNull { course ->
      val start = course.courseStartDate
      val end = course.courseEndDate
      val hasEnded = end?.let { it < now } == true
      if (hasEnded || (start == null && end == null)) {
        return@mapNotNull null
      }

      val isOngoing = start?.let { it <= now } == true && (end == null || now <= end)
      val subtitle =
          listOfNotNull(course.courseTeacher?.takeIf { it.isNotBlank() }, course.coursePosition)
              .joinToString(" · ")
              .ifBlank { "我的课程" }

      HomeTodoItem(
          id = "bykc:${course.courseId}",
          source = HomeTodoSource.BYKC,
          title = course.courseName,
          subtitle = subtitle,
          statusLabel = if (isOngoing) "进行中" else "即将开始",
          timeLabel =
              if (start != null && end != null) {
                "${formatHomeDateTime(start)} - ${end.hour.toPaddedString()}:${end.minute.toPaddedString()}"
              } else {
                "开始 ${formatHomeDateTime(start)}"
              },
          sortTime = start ?: end,
          action = HomeTodoAction.OpenBykcCourse(course.courseId),
      )
    }

private fun buildSpocTodoItems(
    assignments: List<SpocAssignmentSummaryDto>,
    now: LocalDateTime,
): List<HomeTodoItem> =
    assignments.mapNotNull { assignment ->
      val dueTime = parseHomeDateTime(assignment.dueTime)
      if (
          assignment.submissionStatus != SpocSubmissionStatus.UNSUBMITTED ||
              dueTime == null ||
              dueTime <= now
      ) {
        return@mapNotNull null
      }

      val subtitle =
          listOfNotNull(
                  assignment.courseName.takeIf { it.isNotBlank() },
                  assignment.teacherName?.takeIf { it.isNotBlank() },
              )
              .joinToString(" · ")
              .ifBlank { "SPOC 作业" }

      HomeTodoItem(
          id = "spoc:${assignment.assignmentId}",
          source = HomeTodoSource.SPOC,
          title = assignment.title,
          subtitle = subtitle,
          statusLabel = "待提交",
          timeLabel = "截止 ${formatHomeDateTime(dueTime)}",
          sortTime = dueTime,
          action = HomeTodoAction.OpenSpocAssignment(assignment.assignmentId),
      )
    }

private fun buildCgyyTodoItems(
    orders: List<CgyyOrderDto>,
    now: LocalDateTime,
): List<HomeTodoItem> =
    orders.mapNotNull { order ->
      val start = parseHomeDateTime(order.reservationStartDate)
      val end = parseHomeDateTime(order.reservationEndDate)
      val isRejected = (order.checkStatus ?: 0) < 0
      val isCanceled = order.orderStatus == 2
      val hasEnded = end?.let { it <= now } == true
      if (isRejected || isCanceled || hasEnded || (start == null && end == null)) {
        return@mapNotNull null
      }

      val title =
          listOfNotNull(
                  order.venueName?.takeIf { it.isNotBlank() },
                  (order.venueSpaceName ?: order.siteName)?.takeIf { it.isNotBlank() },
              )
              .joinToString(" / ")
              .ifBlank { "研讨室预约" }
      val subtitle =
          listOfNotNull(
                  order.theme?.takeIf { it.isNotBlank() },
                  order.purposeTypeName?.takeIf { it.isNotBlank() },
              )
              .joinToString(" · ")
              .ifBlank { "我的预约" }
      val isOngoing = start?.let { it <= now } == true && (end == null || now < end)

      HomeTodoItem(
          id = "cgyy:${order.id}",
          source = HomeTodoSource.CGYY,
          title = title,
          subtitle = subtitle,
          statusLabel = if (isOngoing) "使用中" else "待使用",
          timeLabel =
              if (start != null && end != null) {
                "${formatHomeDateTime(start)} - ${end.hour.toPaddedString()}:${end.minute.toPaddedString()}"
              } else {
                "开始 ${formatHomeDateTime(start)}"
              },
          sortTime = start ?: end,
          action = HomeTodoAction.OpenCgyyOrders,
      )
    }

private fun buildSigninTodoItems(
    classes: List<SigninClassDto>,
    now: LocalDateTime,
    today: LocalDate,
    timeZone: TimeZone,
): List<HomeTodoItem> {
  val nowInstant = now.toInstant(timeZone)
  return classes.mapNotNull { signinClass ->
    val start = parseHomeDateTime(signinClass.classBeginTime, today)
    val end = parseHomeDateTime(signinClass.classEndTime, today)
    if (signinClass.signStatus != 0 || start == null || end == null || now >= end) {
      return@mapNotNull null
    }

    val startInstant = start.toInstant(timeZone)
    val isUpcoming = now < start
    val withinUpcomingWindow = nowInstant >= startInstant - 10.minutes
    if (isUpcoming && !withinUpcomingWindow) {
      return@mapNotNull null
    }

    HomeTodoItem(
        id = "signin:${signinClass.courseId}",
        source = HomeTodoSource.SIGNIN,
        title = signinClass.courseName,
        subtitle = "课程签到",
        statusLabel = if (isUpcoming) "即将签到" else "签到中",
        timeLabel =
            "${start.hour.toPaddedString()}:${start.minute.toPaddedString()} - ${end.hour.toPaddedString()}:${end.minute.toPaddedString()}",
        sortTime = start,
        action = HomeTodoAction.SigninCourse(signinClass.courseId),
    )
  }
}

private fun parseClockTime(value: String): LocalTime? {
  val parts = value.split(":")
  if (parts.size !in 2..3) return null
  val hour = parts.getOrNull(0)?.toIntOrNull() ?: return null
  val minute = parts.getOrNull(1)?.toIntOrNull() ?: return null
  val second = parts.getOrNull(2)?.toIntOrNull() ?: 0
  return runCatching { LocalTime(hour, minute, second) }.getOrNull()
}

private fun Int.toPaddedString(): String = toString().padStart(2, '0')
