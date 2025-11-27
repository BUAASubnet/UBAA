package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.edu.ubaa.model.dto.*

// region 主屏幕 Composable
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
        terms: List<Term>,
        weeks: List<Week>,
        weeklySchedule: WeeklySchedule?,
        selectedTerm: Term?,
        selectedWeek: Week?,
        isLoading: Boolean,
        error: String?,
        onTermSelected: (Term) -> Unit, // 保留学期选择逻辑
        onWeekSelected: (Week) -> Unit,
        onCourseClick: (CourseClass) -> Unit,
        onBack: () -> Unit,
        modifier: Modifier = Modifier
) {
    var showWeekSelector by remember { mutableStateOf(false) }
    val currentWeekIndex = weeks.indexOf(selectedWeek)

    Scaffold(
            topBar = {
                ScheduleTopAppBar(
                        title = selectedWeek?.name ?: "选择周次",
                        onPreviousClick = {
                            if (currentWeekIndex > 0) {
                                onWeekSelected(weeks[currentWeekIndex - 1])
                            }
                        },
                        isPreviousEnabled = currentWeekIndex > 0,
                        onNextClick = {
                            if (currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1) {
                                onWeekSelected(weeks[currentWeekIndex + 1])
                            }
                        },
                        isNextEnabled = currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1,
                        onTitleClick = { showWeekSelector = true },
                        onBack = onBack
                )
            },
            modifier = modifier
    ) { paddingValues ->
        Box(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
            when {
                isLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("加载课程表...")
                        }
                    }
                }
                error != null -> {
                    Box(
                            modifier = Modifier.fillMaxSize().padding(16.dp),
                            contentAlignment = Alignment.Center
                    ) {
                        Text(
                                text = "加载失败: $error",
                                color = MaterialTheme.colorScheme.error,
                                textAlign = TextAlign.Center
                        )
                    }
                }
                weeklySchedule != null && selectedWeek != null -> {
                    WeeklyScheduleView(schedule = weeklySchedule, onCourseClick = onCourseClick)
                }
                else -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                                text = "请选择学期和周次",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }

    if (showWeekSelector) {
        WeekSelectionSheet(
                weeks = weeks,
                selectedWeek = selectedWeek,
                onWeekSelected = {
                    onWeekSelected(it)
                    showWeekSelector = false
                },
                onDismiss = { showWeekSelector = false }
        )
    }
}
// endregion

// region 顶部导航栏
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScheduleTopAppBar(
        title: String,
        onPreviousClick: () -> Unit,
        isPreviousEnabled: Boolean,
        onNextClick: () -> Unit,
        isNextEnabled: Boolean,
        onTitleClick: () -> Unit,
        onBack: () -> Unit
) {
    CenterAlignedTopAppBar(
            title = {
                Row(
                        modifier = Modifier.clickable(onClick = onTitleClick),
                        verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                            text = title,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                    )
                }
            },
            navigationIcon = {
                IconButton(onClick = onPreviousClick, enabled = isPreviousEnabled) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "上一周")
                }
            },
            actions = {
                IconButton(onClick = onNextClick, enabled = isNextEnabled) {
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "下一周")
                }
            }
    )
}
// endregion

// region 周次选择底部弹窗
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WeekSelectionSheet(
        weeks: List<Week>,
        selectedWeek: Week?,
        onWeekSelected: (Week) -> Unit,
        onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item {
                Text(
                        text = "选择周次",
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            items(weeks) { week ->
                ListItem(
                        headlineContent = { Text(week.name) },
                        modifier = Modifier.clickable { onWeekSelected(week) },
                        leadingContent = {
                            if (week.curWeek) {
                                Surface(
                                        color = MaterialTheme.colorScheme.secondaryContainer,
                                        shape = RoundedCornerShape(4.dp)
                                ) {
                                    Text(
                                            text = "本周",
                                            style = MaterialTheme.typography.labelSmall,
                                            modifier =
                                                    Modifier.padding(
                                                            horizontal = 6.dp,
                                                            vertical = 2.dp
                                                    )
                                    )
                                }
                            }
                        },
                        trailingContent = {
                            if (week == selectedWeek) {
                                Icon(
                                        imageVector = Icons.Default.Check,
                                        contentDescription = "已选择",
                                        tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                )
            }
        }
    }
}
// endregion

// region 课程表视图
@Composable
private fun WeeklyScheduleView(
        schedule: WeeklySchedule,
        onCourseClick: (CourseClass) -> Unit,
        modifier: Modifier = Modifier
) {
    val timeLabels = (1..12).map { it.toString() }
    // **FIX 1**: 使用静态的星期标签，不再依赖 schedule.dayList
    val dayLabels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

    Column(modifier = modifier.padding(horizontal = 8.dp)) {
        HeaderRow(dayLabels = dayLabels)
        Spacer(modifier = Modifier.height(4.dp))
        Row(
                modifier =
                        Modifier.fillMaxSize()
                                .background(
                                        color =
                                                MaterialTheme.colorScheme.surfaceVariant.copy(
                                                        alpha = 0.3f
                                                ),
                                        shape = RoundedCornerShape(8.dp)
                                )
        ) {
            TimeColumn(timeLabels = timeLabels, modifier = Modifier.width(36.dp))
            WeeklyScheduleGrid(
                    schedule = schedule,
                    onCourseClick = onCourseClick,
                    totalPeriods = timeLabels.size,
                    modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun HeaderRow(dayLabels: List<String>) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Spacer(modifier = Modifier.width(36.dp))
        dayLabels.forEach { dayLabel ->
            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(
                        text = dayLabel,
                        textAlign = TextAlign.Center,
                        fontSize = 12.sp,
                        lineHeight = 14.sp,
                        fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
private fun TimeColumn(timeLabels: List<String>, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxHeight()) {
        timeLabels.forEach { time ->
            Box(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    contentAlignment = Alignment.Center
            ) {
                Text(
                        text = time,
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
// endregion

// region 全新高效的课程表网格
@Composable
private fun WeeklyScheduleGrid(
        schedule: WeeklySchedule,
        onCourseClick: (CourseClass) -> Unit,
        totalPeriods: Int,
        modifier: Modifier = Modifier
) {
    val totalDays = 7
    val pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
    val gridColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f)

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val cellHeight = maxHeight / totalPeriods
        val cellWidth = maxWidth / totalDays

        Canvas(modifier = Modifier.fillMaxSize()) {
            // ... (Canvas code remains the same)
            for (i in 1 until totalPeriods) {
                val y = i * cellHeight.toPx()
                drawLine(
                        color = gridColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        pathEffect = pathEffect
                )
            }
            for (i in 1 until totalDays) {
                val x = i * cellWidth.toPx()
                drawLine(color = gridColor, start = Offset(x, 0f), end = Offset(x, size.height))
            }
        }

        schedule.arrangedList.forEach { course ->
            val dayIndex = (course.dayOfWeek ?: 1) - 1
            val startPeriodIndex = (course.beginSection ?: 1) - 1
            val periodSpan =
                    (course.endSection ?: course.beginSection ?: 1) - (course.beginSection ?: 1) + 1

            if (dayIndex in 0 until totalDays && startPeriodIndex in 0 until totalPeriods) {
                // **FIX 2**: 修正 Dp 和 Int 的乘法顺序
                val xOffset = cellWidth * dayIndex
                val yOffset = cellHeight * startPeriodIndex
                val courseHeight = (cellHeight * periodSpan)

                CourseCell(
                        course = course,
                        onClick = { onCourseClick(course) },
                        modifier =
                                Modifier.offset(x = xOffset, y = yOffset)
                                        .size(width = cellWidth, height = courseHeight)
                                        .padding(1.dp)
                )
            }
        }
    }
}
// endregion

// region 课程单元格
@Composable
private fun CourseCell(course: CourseClass, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Card(
            modifier = modifier.fillMaxSize().clickable { onClick() },
            shape = RoundedCornerShape(6.dp),
            colors =
                    CardDefaults.cardColors(
                            containerColor = parseColor(course.color)
                                            ?: MaterialTheme.colorScheme.primaryContainer
                    )
    ) {
        Column(
                modifier = Modifier.fillMaxSize().padding(vertical = 4.dp, horizontal = 3.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                    text = course.courseName,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    lineHeight = 14.sp,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
            )
            course.placeName?.let {
                Text(
                        text = "@$it",
                        fontSize = 11.sp,
                        textAlign = TextAlign.Center,
                        lineHeight = 13.sp,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
// endregion

// region 辅助函数
// **FIX 3**: 使用平台无关的颜色解析函数
private fun parseColor(colorString: String?): Color? {
    return try {
        colorString?.let {
            if (it.startsWith("#") && it.length == 7) {
                val hex = it.substring(1)
                val r = hex.substring(0, 2).toInt(16)
                val g = hex.substring(2, 4).toInt(16)
                val b = hex.substring(4, 6).toInt(16)
                Color(r, g, b)
            } else {
                null
            }
        }
    } catch (e: Exception) {
        null
    }
}
// endregion
