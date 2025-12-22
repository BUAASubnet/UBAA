package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun BykcCoursesScreen(
        courses: List<BykcCourseDto>,
        isLoading: Boolean,
        error: String?,
        onCourseClick: (BykcCourseDto) -> Unit,
        onRefresh: () -> Unit,
        includeExpired: Boolean,
        onIncludeExpiredChange: (Boolean) -> Unit,
        modifier: Modifier = Modifier
) {
    val pullRefreshState = rememberPullRefreshState(refreshing = isLoading, onRefresh = onRefresh)

    Box(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
        Column(modifier = Modifier.fillMaxSize()) {
        // 筛选控件
            Card(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    colors =
                            CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                            )
            ) {
                Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = includeExpired, onCheckedChange = onIncludeExpiredChange)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("显示已过期课程")
                    }

                    IconButton(onClick = onRefresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "刷新")
                    }
                }
            }

            when {
                isLoading && courses.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("加载课程列表...")
                        }
                    }
                }
                error != null -> {
                    Box(
                            modifier = Modifier.fillMaxSize().padding(16.dp),
                            contentAlignment = Alignment.Center
                    ) { Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error) }
                }
                courses.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("暂无可选课程")
                    }
                }
                else -> {
                    LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(courses) { course ->
                            BykcCourseCard(course = course, onClick = { onCourseClick(course) })
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
                scale = true
        )
    }
}

@Composable
fun BykcCourseCard(course: BykcCourseDto, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Card(
            modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
            shape = RoundedCornerShape(12.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // 课程名称与状态
            Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                        text = course.courseName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
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

            // Category
            if (course.category != null || course.subCategory != null) {
                Spacer(modifier = Modifier.height(4.dp))
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

                // 选课情况
            Spacer(modifier = Modifier.height(8.dp))
            val progress =
                    remember(course.courseCurrentCount, course.courseMaxCount) {
                        if (course.courseMaxCount > 0) {
                            (course.courseCurrentCount.toFloat() / course.courseMaxCount.toFloat())
                                    .coerceIn(0f, 1f)
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
                    color = MaterialTheme.colorScheme.onSurfaceVariant
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
                                MaterialTheme.colorScheme.onPrimaryContainer
                        )
                status == BykcCourseStatus.AVAILABLE ->
                        Pair(
                                MaterialTheme.colorScheme.tertiaryContainer,
                                MaterialTheme.colorScheme.onTertiaryContainer
                        )
                status == BykcCourseStatus.FULL ||
                        status == BykcCourseStatus.ENDED ||
                        status == BykcCourseStatus.EXPIRED ->
                        Pair(
                                MaterialTheme.colorScheme.errorContainer,
                                MaterialTheme.colorScheme.onErrorContainer
                        )
                else ->
                        Pair(
                                MaterialTheme.colorScheme.secondaryContainer,
                                MaterialTheme.colorScheme.onSecondaryContainer
                        )
            }

    AssistChip(
            onClick = {},
            label = {
                Text(
                        text = if (selected) "已选" else status,
                        style = MaterialTheme.typography.labelMedium,
                        color = labelColor
                )
            },
            leadingIcon =
                    if (selected) {
                        { Icon(Icons.Default.Check, contentDescription = null, tint = labelColor) }
                    } else null,
            colors =
                    AssistChipDefaults.assistChipColors(
                            containerColor = containerColor,
                            labelColor = labelColor
                    )
    )
}

@Composable
fun InfoRow(label: String, value: String) {
    Row(modifier = Modifier.padding(vertical = 2.dp)) {
        Text(
                text = "$label: ",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
        )
    }
}

fun formatDateRange(startDate: String, endDate: String): String {
    // 期望格式: "2025-03-15 14:00:00"
    // 提取日期和时间部分
    val startParts = startDate.split(" ")
    val endParts = endDate.split(" ")

    if (startParts.size == 2 && endParts.size == 2) {
        val startDatePart = startParts[0] // "2025-03-15"
        val startTimePart = startParts[1].substring(0, 5) // "14:00"
        val endDatePart = endParts[0]
        val endTimePart = endParts[1].substring(0, 5)

        return if (startDatePart == endDatePart) {
                    // 同一天
                    "$startDatePart $startTimePart - $endTimePart"
        } else {
        // 跨天
        "$startDatePart $startTimePart - $endDate"
        }
    }

    return "$startDate - $endDate"
}
