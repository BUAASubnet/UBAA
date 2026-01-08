package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.delay
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterialApi::class, ExperimentalTime::class)
@Composable
fun BykcChosenCoursesScreen(
        courses: List<BykcChosenCourseDto>,
        isLoading: Boolean,
        error: String?,
        onCourseClick: (BykcChosenCourseDto) -> Unit,
        onRefresh: () -> Unit,
        modifier: Modifier = Modifier,
) {
  val pullRefreshState = rememberPullRefreshState(refreshing = isLoading, onRefresh = onRefresh)

  Box(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    when {
      isLoading && courses.isEmpty() -> {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(modifier = Modifier.height(8.dp))
            Text("加载已选课程...")
          }
        }
      }
      error != null -> {
        Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error)
            Spacer(modifier = Modifier.height(16.dp))
            Button(onClick = onRefresh) { Text("重试") }
          }
        }
      }
      courses.isEmpty() -> {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                    imageVector = Icons.Default.EventBusy,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                    text = "暂无已选课程",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
      }
      else -> {
        LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          items(courses) { course ->
            BykcChosenCourseCard(course = course, onClick = { onCourseClick(course) })
          }
        }
      }
    }

    PullRefreshIndicator(
            refreshing = isLoading,
            state = pullRefreshState,
            modifier = Modifier.align(Alignment.TopCenter),
            backgroundColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.primary,
            scale = true,
    )
  }
}

@OptIn(ExperimentalTime::class)
@Composable
fun BykcChosenCourseCard(
        course: BykcChosenCourseDto,
        onClick: () -> Unit,
        modifier: Modifier = Modifier,
) {
  Card(
          modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
          shape = RoundedCornerShape(12.dp),
          elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      // 课程名称
      Text(
              text = course.courseName,
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
              maxLines = 2,
              overflow = TextOverflow.Ellipsis,
      )

      Spacer(modifier = Modifier.height(8.dp))

      // 课程信息区
      course.courseTeacher?.let { teacher -> InfoRow(label = "教师", value = teacher) }

      course.coursePosition?.let { position -> InfoRow(label = "地点", value = position) }

      course.courseStartDate?.let { startDate ->
        val endDate = course.courseEndDate ?: ""
        InfoRow(label = "时间", value = formatDateRange(startDate, endDate))
      }

      course.selectDate?.let { selectDate ->
        InfoRow(label = "选课时间", value = selectDate.substringBefore(" 00:00:00"))
      }

      // 分类标签
      if (course.category != null || course.subCategory != null) {
        Spacer(modifier = Modifier.height(8.dp))
        Row {
          course.category?.let { category ->
            SuggestionChip(
                    onClick = {},
                    label = { Text(category, style = MaterialTheme.typography.labelSmall) },
                    modifier = Modifier.padding(end = 4.dp),
            )
          }
          course.subCategory?.let { subCategory ->
            SuggestionChip(
                    onClick = {},
                    label = { Text(subCategory, style = MaterialTheme.typography.labelSmall) },
            )
          }
        }
      }

      // 状态指示（签到与考核）
      Column(horizontalAlignment = Alignment.End) {
        Spacer(modifier = Modifier.height(12.dp))
        HorizontalDivider()
        Spacer(modifier = Modifier.height(12.dp))

        val (checkinText, checkinColor) = getCheckinStatus(course.checkin)
        val (passText, passColor) = getPassStatus(course.pass)

        Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
        ) {
          // 签到状态
          // 签到状态
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                    imageVector = Icons.Default.AssignmentInd,
                    contentDescription = null,
                    tint = checkinColor,
                    modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                    text = checkinText,
                    style = MaterialTheme.typography.bodySmall,
                    color = checkinColor,
            )
          }

          // 考核状态
          // 签到状态
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                    imageVector =
                            if (course.pass == 1) Icons.Default.CheckCircle else Icons.Default.Info,
                    contentDescription = null,
                    tint = passColor,
                    modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(text = passText, style = MaterialTheme.typography.bodySmall, color = passColor)
          }

          // 分数显示（有分数时）
          if (course.score != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Icon(
                      imageVector = Icons.Default.Grade,
                      contentDescription = null,
                      tint = MaterialTheme.colorScheme.secondary,
                      modifier = Modifier.size(20.dp),
              )
              Spacer(modifier = Modifier.width(4.dp))
              Text(
                      text = "${course.score} 分",
                      style = MaterialTheme.typography.bodySmall,
                      fontWeight = FontWeight.Bold,
                      color = MaterialTheme.colorScheme.secondary,
              )
            }
          }
        }

        // 签到/签退操作区
        Row(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.End,
        ) {
          val now = remember { mutableStateOf<kotlin.time.Instant>(Clock.System.now()) }
          LaunchedEffect(Unit) {
            while (true) {
              delay(5000)
              now.value = Clock.System.now()
            }
          }

          val isInSignInWindow =
                  remember(
                          course.signConfig?.signStartDate,
                          course.signConfig?.signEndDate,
                          now.value
                  ) {
                    isWithinWindow(course.signConfig?.signStartDate, course.signConfig?.signEndDate)
                  }
          val isInSignOutWindow =
                  remember(
                          course.signConfig?.signOutStartDate,
                          course.signConfig?.signOutEndDate,
                          now.value,
                  ) {
                    isWithinWindow(
                            course.signConfig?.signOutStartDate,
                            course.signConfig?.signOutEndDate
                    )
                  }

          // 逻辑说明：
          // 可签到：未签到(0)且在时间窗口
          val canSignIn = (course.checkin == 0) && isInSignInWindow

          // 可签退：已签到未签退(5或6)且在时间窗口
          val canSignOut = (course.checkin == 5 || course.checkin == 6) && isInSignOutWindow

          // 考核通过(1)时隐藏按钮
          val showButtons = course.pass != 1 && course.signConfig != null

          if (showButtons) {
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
              AssistChip(
                      onClick = { if (canSignIn) onClick() },
                      enabled = canSignIn,
                      label = { Text("签到", style = MaterialTheme.typography.labelSmall) },
                      leadingIcon = {
                        Icon(
                                Icons.AutoMirrored.Filled.Login,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                        )
                      },
                      colors =
                              AssistChipDefaults.assistChipColors(
                                      containerColor = MaterialTheme.colorScheme.primaryContainer,
                                      labelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                                      disabledContainerColor =
                                              MaterialTheme.colorScheme.surfaceVariant.copy(
                                                      alpha = 0.5f
                                              ),
                                      disabledLabelColor =
                                              MaterialTheme.colorScheme.onSurfaceVariant.copy(
                                                      alpha = 0.5f
                                              ),
                              ),
              )
              AssistChip(
                      onClick = { if (canSignOut) onClick() },
                      enabled = canSignOut,
                      label = { Text("签退", style = MaterialTheme.typography.labelSmall) },
                      leadingIcon = {
                        Icon(
                                Icons.AutoMirrored.Filled.Logout,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                        )
                      },
                      colors =
                              AssistChipDefaults.assistChipColors(
                                      containerColor = MaterialTheme.colorScheme.secondaryContainer,
                                      labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                                      disabledContainerColor =
                                              MaterialTheme.colorScheme.surfaceVariant.copy(
                                                      alpha = 0.5f
                                              ),
                                      disabledLabelColor =
                                              MaterialTheme.colorScheme.onSurfaceVariant.copy(
                                                      alpha = 0.5f
                                              ),
                              ),
              )
            }
          }
        }
      }
    }
  }
}

@OptIn(ExperimentalTime::class)
private fun isWithinWindow(start: String?, end: String?): Boolean {
  if (start.isNullOrBlank() || end.isNullOrBlank()) return false
  return try {
    val startDt = LocalDateTime.parse(start.replace(" ", "T"))
    val endDt = LocalDateTime.parse(end.replace(" ", "T"))
    val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    now >= startDt && now <= endDt
  } catch (_: Exception) {
    false
  }
}

@Composable
fun getCheckinStatus(checkin: Int): Pair<String, Color> {
  val successColor = MaterialTheme.colorScheme.primary
  val warningColor = MaterialTheme.colorScheme.tertiary
  val errorColor = MaterialTheme.colorScheme.error
  val defaultColor = MaterialTheme.colorScheme.onSurfaceVariant

  return when (checkin) {
    1 -> "考勤通过" to successColor
    2 -> "迟到" to errorColor
    3 -> "早退" to errorColor
    4 -> "缺勤" to errorColor
    5 -> "已签到、未签退" to warningColor
    6 -> "已签到(异常)、未签退" to warningColor
    7 -> "未签到、已签退" to warningColor
    8 -> "未签到、已签退(异常)" to warningColor
    9 -> "已签到(异常)、已签退" to warningColor
    10 -> "已签到、已签退(异常)" to warningColor
    11 -> "已签到(异常)、已签退(异常)" to warningColor
    else -> "待考勤" to defaultColor
  }
}

@Composable
fun getPassStatus(pass: Int?): Pair<String, Color> {
  val successColor = MaterialTheme.colorScheme.primary
  val errorColor = MaterialTheme.colorScheme.error
  val defaultColor = MaterialTheme.colorScheme.onSurfaceVariant

  return when (pass) {
    1 -> "考核通过" to successColor
    0 -> "考核未通过" to errorColor
    else -> "待考核" to defaultColor
  }
}
