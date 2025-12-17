package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun BykcChosenCoursesScreen(
        courses: List<BykcChosenCourseDto>,
        isLoading: Boolean,
        error: String?,
        onCourseClick: (BykcChosenCourseDto) -> Unit,
        onRefresh: () -> Unit,
        modifier: Modifier = Modifier
) {
    val pullRefreshState = rememberPullRefreshState(refreshing = isLoading, onRefresh = onRefresh)

    Column(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
        when {
            isLoading -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("加载已选课程...")
                    }
                }
            }
            error != null -> {
                Box(
                        modifier = Modifier.fillMaxSize().padding(16.dp),
                        contentAlignment = Alignment.Center
                ) {
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
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                                text = "暂无已选课程",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            else -> {
                LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
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
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp)
        )
    }
}

@Composable
fun BykcChosenCourseCard(
        course: BykcChosenCourseDto,
        onClick: () -> Unit,
        modifier: Modifier = Modifier
) {
    Card(
            modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
            shape = RoundedCornerShape(12.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Course name
            Text(
                    text = course.courseName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Course info
            course.courseTeacher?.let { teacher -> InfoRow(label = "教师", value = teacher) }

            course.coursePosition?.let { position -> InfoRow(label = "地点", value = position) }

            course.courseStartDate?.let { startDate ->
                val endDate = course.courseEndDate ?: ""
                InfoRow(label = "时间", value = formatDateRange(startDate, endDate))
            }

            course.selectDate?.let { selectDate ->
                InfoRow(label = "选课时间", value = selectDate.substringBefore(" 00:00:00"))
            }

            // Category chips
            if (course.category != null || course.subCategory != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Row {
                    course.category?.let { category ->
                        SuggestionChip(
                                onClick = {},
                                label = {
                                    Text(category, style = MaterialTheme.typography.labelSmall)
                                },
                                modifier = Modifier.padding(end = 4.dp)
                        )
                    }
                    course.subCategory?.let { subCategory ->
                        SuggestionChip(
                                onClick = {},
                                label = {
                                    Text(subCategory, style = MaterialTheme.typography.labelSmall)
                                }
                        )
                    }
                }
            }

            // Status indicator based on start/end times and results
            Spacer(modifier = Modifier.height(12.dp))
            Divider()
            Spacer(modifier = Modifier.height(12.dp))

            val statusType =
                    remember(
                            course.courseStartDate,
                            course.courseEndDate,
                            course.checkin,
                            course.pass
                    ) { computeChosenCourseStatus(course) }

            val statusLabel =
                    when (statusType) {
                        ChosenCourseStatusType.NOT_STARTED -> "未开始"
                        ChosenCourseStatusType.IN_PROGRESS -> "进行中"
                        ChosenCourseStatusType.PASSED -> "已通过"
                        ChosenCourseStatusType.FAILED -> "未通过"
                        ChosenCourseStatusType.CHECKED_IN -> "已签到"
                        ChosenCourseStatusType.NOT_CHECKED_IN -> "未签到"
                    }

            val statusIcon: ImageVector =
                    when (statusType) {
                        ChosenCourseStatusType.NOT_STARTED, ChosenCourseStatusType.NOT_CHECKED_IN ->
                                Icons.Default.HourglassEmpty
                        ChosenCourseStatusType.IN_PROGRESS -> Icons.Default.PlayArrow
                        ChosenCourseStatusType.PASSED, ChosenCourseStatusType.CHECKED_IN ->
                                Icons.Default.CheckCircle
                        ChosenCourseStatusType.FAILED -> Icons.Default.Cancel
                    }

            val statusColor =
                    when (statusType) {
                        ChosenCourseStatusType.NOT_STARTED, ChosenCourseStatusType.NOT_CHECKED_IN ->
                                MaterialTheme.colorScheme.onSurfaceVariant
                        ChosenCourseStatusType.IN_PROGRESS -> MaterialTheme.colorScheme.primary
                        ChosenCourseStatusType.PASSED -> MaterialTheme.colorScheme.tertiary
                        ChosenCourseStatusType.FAILED -> MaterialTheme.colorScheme.error
                        ChosenCourseStatusType.CHECKED_IN -> MaterialTheme.colorScheme.primary
                    }

            Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                            imageVector = statusIcon,
                            contentDescription = null,
                            tint = statusColor,
                            modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                            text = statusLabel,
                            style = MaterialTheme.typography.bodySmall,
                            color = statusColor
                    )
                }

                // Score (only when available)
                course.score?.let { score ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                                imageVector = Icons.Default.Grade,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.secondary,
                                modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                                text = "$score 分",
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.secondary
                        )
                    }
                }
            }

            // Sign-in action indicators
            if (course.canSign || course.canSignOut) {
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (course.canSign) {
                        AssistChip(
                                onClick = {},
                                label = {
                                    Text("可签到", style = MaterialTheme.typography.labelSmall)
                                },
                                leadingIcon = {
                                    Icon(
                                            Icons.Default.Login,
                                            contentDescription = null,
                                            modifier = Modifier.size(16.dp)
                                    )
                                },
                                colors =
                                        AssistChipDefaults.assistChipColors(
                                                containerColor =
                                                        MaterialTheme.colorScheme.primaryContainer,
                                                labelColor =
                                                        MaterialTheme.colorScheme.onPrimaryContainer
                                        )
                        )
                    }
                    if (course.canSignOut) {
                        AssistChip(
                                onClick = {},
                                label = {
                                    Text("可签退", style = MaterialTheme.typography.labelSmall)
                                },
                                leadingIcon = {
                                    Icon(
                                            Icons.Default.Logout,
                                            contentDescription = null,
                                            modifier = Modifier.size(16.dp)
                                    )
                                },
                                colors =
                                        AssistChipDefaults.assistChipColors(
                                                containerColor =
                                                        MaterialTheme.colorScheme
                                                                .secondaryContainer,
                                                labelColor =
                                                        MaterialTheme.colorScheme
                                                                .onSecondaryContainer
                                        )
                        )
                    }
                }
            }
        }
    }
}

private enum class ChosenCourseStatusType {
    NOT_STARTED,
    IN_PROGRESS,
    PASSED,
    FAILED,
    CHECKED_IN,
    NOT_CHECKED_IN
}

private fun computeChosenCourseStatus(course: BykcChosenCourseDto): ChosenCourseStatusType {
    val start =
            course.courseStartDate?.let {
                runCatching { LocalDateTime.parse(it.replace(" ", "T")) }.getOrNull()
            }
    val end =
            course.courseEndDate?.let {
                runCatching { LocalDateTime.parse(it.replace(" ", "T")) }.getOrNull()
            }
    val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())

    if (start != null && end != null) {
        return when {
            now < start -> ChosenCourseStatusType.NOT_STARTED
            now >= start && now <= end -> ChosenCourseStatusType.IN_PROGRESS
            course.checkin == 1 && course.pass == 1 -> ChosenCourseStatusType.PASSED
            else -> ChosenCourseStatusType.FAILED
        }
    }

    // Fallback if dates are missing or parsing failed
    return when {
        course.pass == 1 -> ChosenCourseStatusType.PASSED
        course.checkin == 1 -> ChosenCourseStatusType.CHECKED_IN
        else -> ChosenCourseStatusType.NOT_CHECKED_IN
    }
}
