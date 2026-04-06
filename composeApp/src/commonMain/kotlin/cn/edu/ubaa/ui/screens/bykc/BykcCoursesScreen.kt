package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.delay
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class, ExperimentalTime::class)
@Composable
fun BykcCoursesScreen(
    courses: List<BykcCourseDto>,
    isLoading: Boolean,
    isLoadingMore: Boolean,
    hasMorePages: Boolean,
    hideFullCourses: Boolean,
    error: String?,
    onCourseClick: (BykcCourseDto) -> Unit,
    onHideFullCoursesChange: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val pullRefreshState = rememberPullRefreshState(refreshing = isLoading, onRefresh = onRefresh)
  val now by
      produceState(
          initialValue = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
      ) {
        while (true) {
          delay(60_000)
          value = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        }
      }
  val visibleCourses =
      remember(courses, hideFullCourses) {
        if (hideFullCourses) courses.filterNot { it.isFullCourse() } else courses
      }

  Box(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    Column(modifier = Modifier.fillMaxSize()) {
      Row(
          modifier =
              Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).clickable {
                onHideFullCoursesChange(!hideFullCourses)
              },
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Checkbox(checked = hideFullCourses, onCheckedChange = onHideFullCoursesChange)
        Text("隐藏满人课程", style = MaterialTheme.typography.bodyMedium)
      }

      when {
        isLoading && courses.isEmpty() -> {
          Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("加载中...") }
          }
        }
        error != null -> {
          Box(
              modifier = Modifier.fillMaxSize().padding(16.dp),
              contentAlignment = Alignment.Center,
          ) {
            Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error)
          }
        }
        else -> {
          LazyColumn(
              modifier = Modifier.fillMaxSize(),
              contentPadding = PaddingValues(16.dp),
              verticalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            if (visibleCourses.isEmpty()) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  Text(
                      text =
                          if (hideFullCourses && courses.isNotEmpty()) "当前筛选条件下暂无有空位课程"
                          else "暂无可选课程",
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
              }
            } else {
              items(visibleCourses) { course ->
                BykcCourseCard(course = course, now = now, onClick = { onCourseClick(course) })
              }
            }

            // 加载更多指示器
            if (hasMorePages) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  if (isLoadingMore) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                      CircularProgressIndicator(modifier = Modifier.size(24.dp))
                      Spacer(modifier = Modifier.height(8.dp))
                      Text("加载更多课程...", style = MaterialTheme.typography.bodySmall)
                    }
                  } else {
                    // 触发加载更多的区域
                    LaunchedEffect(Unit) { onLoadMore() }
                    Spacer(modifier = Modifier.height(16.dp))
                  }
                }
              }
            } else if (visibleCourses.isNotEmpty()) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  Text(
                      "没有更多课程了",
                      style = MaterialTheme.typography.bodySmall,
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
              }
            }
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

private fun BykcCourseDto.isFullCourse(): Boolean =
    status == BykcCourseStatus.FULL || (courseMaxCount > 0 && courseCurrentCount >= courseMaxCount)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BykcCourseCard(
    course: BykcCourseDto,
    now: kotlinx.datetime.LocalDateTime,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  Card(
      modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
      shape = RoundedCornerShape(12.dp),
      elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      // 课程名称与状态
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
            text = course.courseName,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        Spacer(modifier = Modifier.width(8.dp))

        CourseStatusChip(status = course.status, selected = course.selected)
      }

      Spacer(modifier = Modifier.height(8.dp))

      // 课程信息
      course.courseTeacher?.let { teacher -> InfoRow(label = "教师", value = teacher) }

      course.coursePosition?.let { position -> InfoRow(label = "地点", value = position) }

      course.courseStartDate?.let { startDate ->
        val endDate = course.courseEndDate ?: ""
        InfoRow(label = "时间", value = formatDateRange(startDate, endDate))
      }
      val selectTimeDisplay =
          resolveSelectTimeDisplay(
              startDate = course.courseSelectStartDate,
              endDate = course.courseSelectEndDate,
              now = now,
          )
      selectTimeDisplay?.let { selectTime ->
        InfoRow(label = selectTime.label, value = selectTime.value)
      }

      // 分类与签到标签
      if (course.subCategory != null || course.hasSignPoints) {
        Spacer(modifier = Modifier.height(4.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
          course.subCategory?.let { subCategory ->
            SuggestionChip(
                onClick = {},
                label = { Text(subCategory, style = MaterialTheme.typography.labelSmall) },
            )
          }
          if (course.hasSignPoints) {
            SuggestionChip(
                onClick = {},
                label = { Text("自主签到", style = MaterialTheme.typography.labelSmall) },
            )
          }
        }
      }

      // 选课情况
      Spacer(modifier = Modifier.height(8.dp))
      val progress =
          remember(course.courseCurrentCount, course.courseMaxCount) {
            if (course.courseMaxCount > 0) {
              (course.courseCurrentCount.toFloat() / course.courseMaxCount.toFloat()).coerceIn(
                  0f,
                  1f,
              )
            } else 0f
          }
      LinearProgressIndicator(
          progress = { progress },
          modifier = Modifier.fillMaxWidth().height(6.dp),
      )
      Spacer(modifier = Modifier.height(4.dp))
      Text(
          text = "已报名 ${course.courseCurrentCount} / ${course.courseMaxCount}",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
fun CourseStatusChip(status: String, selected: Boolean) {
  val (containerColor, labelColor) =
      when {
        selected ->
            Pair(
                MaterialTheme.colorScheme.primaryContainer,
                MaterialTheme.colorScheme.onPrimaryContainer,
            )
        status == BykcCourseStatus.AVAILABLE ->
            Pair(
                MaterialTheme.colorScheme.tertiaryContainer,
                MaterialTheme.colorScheme.onTertiaryContainer,
            )
        status == BykcCourseStatus.FULL ||
            status == BykcCourseStatus.ENDED ||
            status == BykcCourseStatus.EXPIRED ->
            Pair(
                MaterialTheme.colorScheme.errorContainer,
                MaterialTheme.colorScheme.onErrorContainer,
            )
        else ->
            Pair(
                MaterialTheme.colorScheme.secondaryContainer,
                MaterialTheme.colorScheme.onSecondaryContainer,
            )
      }

  AssistChip(
      onClick = {},
      label = {
        Text(
            text = if (selected) "已选" else status,
            style = MaterialTheme.typography.labelMedium,
            color = labelColor,
        )
      },
      leadingIcon =
          if (selected) {
            { Icon(Icons.Default.Check, contentDescription = null, tint = labelColor) }
          } else null,
      colors =
          AssistChipDefaults.assistChipColors(
              containerColor = containerColor,
              labelColor = labelColor,
          ),
  )
}

@Composable
fun InfoRow(label: String, value: String) {
  Row(modifier = Modifier.padding(vertical = 2.dp)) {
    Text(
        text = "$label: ",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(
        text = value,
        style = MaterialTheme.typography.bodyMedium,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
  }
}
