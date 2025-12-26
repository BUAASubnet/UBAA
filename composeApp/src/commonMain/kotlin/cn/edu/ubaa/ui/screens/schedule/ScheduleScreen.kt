package cn.edu.ubaa.ui.screens.schedule

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.edu.ubaa.model.dto.*

/**
 * 课表展示主屏幕。
 * 以网格形式展示选定周次的课程安排，并提供周次切换功能。
 *
 * @param terms 所有可选学期列表。
 * @param weeks 当前学期的所有周次列表。
 * @param weeklySchedule 当前选定周次的排课数据。
 * @param selectedTerm 当前选中的学期。
 * @param selectedWeek 当前选中的周次。
 * @param isLoading 是否正在加载数据。
 * @param error 错误信息。
 * @param onTermSelected 学期选择回调。
 * @param onWeekSelected 周次选择回调。
 * @param onCourseClick 点击课程单元格的回调。
 */
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
        onTermSelected: (Term) -> Unit,
        onWeekSelected: (Week) -> Unit,
        onCourseClick: (CourseClass) -> Unit,
        modifier: Modifier = Modifier
) {
    var showWeekSelector by remember { mutableStateOf(false) }
    val currentWeekIndex = weeks.indexOf(selectedWeek)

    Scaffold(
            topBar = {
                ScheduleTopAppBar(
                        title = selectedWeek?.name ?: "选择周次",
                        onPreviousClick = { if (currentWeekIndex > 0) onWeekSelected(weeks[currentWeekIndex - 1]) },
                        isPreviousEnabled = currentWeekIndex > 0,
                        onNextClick = { if (currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1) onWeekSelected(weeks[currentWeekIndex + 1]) },
                        isNextEnabled = currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1,
                        onTitleClick = { showWeekSelector = true }
                )
            },
            modifier = modifier
    ) { paddingValues ->
        Box(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
            when {
                isLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(); Spacer(modifier = Modifier.height(8.dp)); Text("加载课程表...")
                        }
                    }
                }
                error != null -> {
                    Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
                        Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                    }
                }
                weeklySchedule != null && selectedWeek != null -> {
                    WeeklyScheduleView(schedule = weeklySchedule, onCourseClick = onCourseClick)
                }
                else -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(text = "请选择学期和周次", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }

    if (showWeekSelector) {
        WeekSelectionSheet(weeks = weeks, selectedWeek = selectedWeek, onWeekSelected = { onWeekSelected(it); showWeekSelector = false }, onDismiss = { showWeekSelector = false })
    }
}

/** 课表页面专用顶部栏。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScheduleTopAppBar(title: String, onPreviousClick: () -> Unit, isPreviousEnabled: Boolean, onNextClick: () -> Unit, isNextEnabled: Boolean, onTitleClick: () -> Unit) {
    CenterAlignedTopAppBar(
            title = {
                Row(modifier = Modifier.clickable(onClick = onTitleClick), verticalAlignment = Alignment.CenterVertically) {
                    Text(text = title, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            },
            actions = {
                IconButton(onClick = onPreviousClick, enabled = isPreviousEnabled) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "上一周") }
                IconButton(onClick = onNextClick, enabled = isNextEnabled) { Icon(Icons.AutoMirrored.Filled.ArrowForward, "下一周") }
            }
    )
}

/** 周次选择底部弹窗。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WeekSelectionSheet(weeks: List<Week>, selectedWeek: Week?, onWeekSelected: (Week) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item { Text(text = "选择周次", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(16.dp)) }
            items(weeks) { week ->
                ListItem(
                        headlineContent = { Text(week.name) },
                        modifier = Modifier.clickable { onWeekSelected(week) },
                        leadingContent = {
                            if (week.curWeek) Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(4.dp)) {
                                Text(text = "本周", style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                            }
                        },
                        trailingContent = { if (week == selectedWeek) Icon(Icons.Default.Check, "已选择", tint = MaterialTheme.colorScheme.primary) }
                )
            }
        }
    }
}

/** 核心周课表视图组件。包含星期标题行、时间轴列和课程网格。 */
@Composable
private fun WeeklyScheduleView(schedule: WeeklySchedule, onCourseClick: (CourseClass) -> Unit, modifier: Modifier = Modifier) {
    val totalPeriods = maxOf(12, schedule.arrangedList.maxOfOrNull { it.endSection ?: 0 } ?: 0)
    val timeLabels = (1..totalPeriods).map { it.toString() }
    val dayLabels = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    val rowHeight: Dp = 64.dp
    val scrollState = rememberScrollState()

    Column(modifier = modifier.padding(horizontal = 8.dp)) {
        HeaderRow(dayLabels)
        Spacer(modifier = Modifier.height(4.dp))
        Row(modifier = Modifier.fillMaxWidth().verticalScroll(scrollState).background(MaterialTheme.colorScheme.surfaceVariant.copy(0.3f), RoundedCornerShape(8.dp))) {
            TimeColumn(timeLabels, rowHeight, Modifier.width(36.dp))
            WeeklyScheduleGrid(schedule, onCourseClick, timeLabels.size, rowHeight, Modifier.weight(1f))
        }
    }
}

/** 星期标题行。 */
@Composable
private fun HeaderRow(dayLabels: List<String>) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Spacer(modifier = Modifier.width(36.dp))
        dayLabels.forEach { Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) { Text(text = it, fontSize = 12.sp, fontWeight = FontWeight.Medium) } }
    }
}

/** 时间轴列。 */
@Composable
private fun TimeColumn(timeLabels: List<String>, rowHeight: Dp, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        timeLabels.forEach { Box(modifier = Modifier.height(rowHeight).fillMaxWidth(), contentAlignment = Alignment.Center) { Text(text = it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
    }
}

/** 课程表网格。负责绘制背景辅助线和摆放课程单元格。 */
@Composable
private fun WeeklyScheduleGrid(schedule: WeeklySchedule, onCourseClick: (CourseClass) -> Unit, totalPeriods: Int, rowHeight: Dp, modifier: Modifier = Modifier) {
    val totalDays = 7
    val gridColor = MaterialTheme.colorScheme.onSurface.copy(0.1f)
    BoxWithConstraints(modifier = modifier.height(rowHeight * totalPeriods)) {
        val density = LocalDensity.current
        val cellHeightPx = with(density) { rowHeight.toPx() }
        val cellWidth = maxWidth / totalDays

        Canvas(modifier = Modifier.fillMaxSize()) {
            val pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
            for (i in 1 until totalPeriods) {
                val y = i * cellHeightPx
                drawLine(gridColor, Offset(0f, y), Offset(size.width, y), pathEffect = pathEffect)
            }
            for (i in 1 until totalDays) {
                val x = i * cellWidth.toPx()
                drawLine(gridColor, Offset(x, 0f), Offset(x, size.height))
            }
        }

        schedule.arrangedList.forEach { course ->
            val dayIndex = (course.dayOfWeek ?: 1) - 1
            val startIdx = (course.beginSection ?: 1) - 1
            val span = (course.endSection ?: course.beginSection ?: 1) - (course.beginSection ?: 1) + 1
            if (dayIndex in 0 until totalDays && startIdx in 0 until totalPeriods) {
                CourseCell(course, { onCourseClick(course) }, Modifier.offset(cellWidth * dayIndex, rowHeight * startIdx).size(cellWidth, rowHeight * span).padding(1.dp))
            }
        }
    }
}

/** 单个课程卡片组件。 */
@Composable
private fun CourseCell(course: CourseClass, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val isDark = isSystemInDarkTheme()
    val parsedColor = remember(course.color) { parseColor(course.color) }
    val containerColor = remember(parsedColor, isDark) {
        val base = parsedColor ?: Color(0xFF6200EE)
        if (isDark && parsedColor != null) base.copy(alpha = 0.7f) else base
    }
    val contentColor = if (containerColor.luminance() > 0.5f) Color.Black else Color.White

    Card(modifier = modifier.fillMaxSize().clickable { onClick() }, shape = RoundedCornerShape(6.dp), colors = CardDefaults.cardColors(containerColor = containerColor, contentColor = contentColor)) {
        Column(modifier = Modifier.fillMaxSize().padding(4.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = course.courseName, fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, lineHeight = 14.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
            course.placeName?.let { Text(text = "@$it", fontSize = 11.sp, textAlign = TextAlign.Center, lineHeight = 13.sp, color = contentColor.copy(0.8f), maxLines = 2, overflow = TextOverflow.Ellipsis) }
        }
    }
}

/** 解析十六进制颜色字符串。 */
private fun parseColor(colorString: String?): Color? {
    return try {
        if (colorString?.startsWith("#") == true && colorString.length == 7) {
            Color(colorString.substring(1).toInt(16) or (0xFF shl 24))
        } else null
    } catch (_: Exception) { null }
}