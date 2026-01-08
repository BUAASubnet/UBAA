package cn.edu.ubaa.ui.screens.exam

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Chair
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.Exam
import kotlin.collections.get
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.datetime.*

@Composable
fun ExamScreen(viewModel: ExamViewModel) {
    val uiState by viewModel.uiState.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        when {
            uiState.isLoading -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            uiState.error != null -> {
                Box(
                        modifier = Modifier.fillMaxSize().padding(16.dp),
                        contentAlignment = Alignment.Center
                ) { Text(text = "加载失败: ${uiState.error}", color = MaterialTheme.colorScheme.error) }
            }
            uiState.examData != null -> {
                ExamTimelineList(
                        arranged = uiState.examData!!.arranged,
                        notArranged = uiState.examData!!.notArranged
                )
            }
        }
    }
}

@Composable
fun ExamTimelineList(arranged: List<Exam>, notArranged: List<Exam>) {
    var showFinished by remember { mutableStateOf(false) }

    val (finished, upcoming) = arranged.partition { isExamFinished(it) }

    // 按日期分组考试，未定日期排后
    val groupedUpcoming = upcoming.groupBy { it.examDate?.substringBefore(" ") ?: "待定" }
    val upcomingSortedKeys = groupedUpcoming.keys.sorted()

    val groupedFinished = finished.groupBy { it.examDate?.substringBefore(" ") ?: "待定" }
    val finishedSortedKeys = groupedFinished.keys.sortedDescending() // 已结束的按日期倒序排

    LazyColumn(
            contentPadding = PaddingValues(16.dp),
    ) {
        // 已结束考试折叠部分
        if (finished.isNotEmpty()) {
            item {
                Surface(
                        onClick = { showFinished = !showFinished },
                        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        shape = RoundedCornerShape(8.dp)
                ) {
                    Row(
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                                text = "已结束考试 (${finished.size})",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Icon(
                                imageVector =
                                        if (showFinished) Icons.Default.ExpandLess
                                        else Icons.Default.ExpandMore,
                                contentDescription = if (showFinished) "收起" else "展开",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (showFinished) {
                finishedSortedKeys.forEach { date ->
                    val exams = groupedFinished[date]!!
                    items(exams.size) { index ->
                        ExamTimelineItem(
                                exam = exams[index],
                                dateString = if (index == 0) date else null,
                                isLastInGroup = index == exams.size - 1,
                                isLastGlobal =
                                        date == finishedSortedKeys.last() &&
                                                index == exams.size - 1 &&
                                                upcoming.isEmpty() &&
                                                notArranged.isEmpty(),
                                isFinished = true
                        )
                    }
                }

                if (upcoming.isNotEmpty() || notArranged.isNotEmpty()) {
                    item {
                        Spacer(modifier = Modifier.height(16.dp))
                        HorizontalDivider(
                                modifier = Modifier.padding(vertical = 8.dp),
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                    }
                }
            }
        }

        if (upcoming.isNotEmpty()) {
            item {
                Text(
                        text = "即将到来",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(bottom = 16.dp)
                )
            }

            upcomingSortedKeys.forEach { date ->
                val exams = groupedUpcoming[date]!!
                items(exams.size) { index ->
                    ExamTimelineItem(
                            exam = exams[index],
                            dateString = if (index == 0) date else null,
                            isLastInGroup = index == exams.size - 1,
                            isLastGlobal =
                                    date == upcomingSortedKeys.last() &&
                                            index == exams.size - 1 &&
                                            notArranged.isEmpty()
                    )
                }
            }
        } else if (notArranged.isEmpty() && finished.isEmpty()) {
            item {
                Box(
                        modifier = Modifier.fillMaxWidth().padding(32.dp),
                        contentAlignment = Alignment.Center
                ) { Text("暂无考试安排", style = MaterialTheme.typography.bodyLarge) }
            }
        }

        if (notArranged.isNotEmpty()) {
            item {
                Text(
                        text = "未安排/其他",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.padding(top = 24.dp, bottom = 16.dp)
                )
            }
            items(notArranged) { exam ->
                // 未安排考试使用标准卡片
                ExamCard(exam, showSeat = false)
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }
}

@Composable
fun ExamTimelineItem(
        exam: Exam,
        dateString: String?,
        isLastInGroup: Boolean,
        isLastGlobal: Boolean,
        isFinished: Boolean = false
) {
    val timelineColor =
            if (isFinished) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.primary

    Row(modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        // 左侧：日期与时间线
        Column(
                modifier = Modifier.width(60.dp),
                horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (dateString != null && dateString != "待定") {
                // 解析日期为月-日
                val shortDate =
                        try {
                            val parts = dateString.split("-")
                            if (parts.size >= 3) "${parts[1]}-${parts[2]}" else dateString
                        } catch (e: Exception) {
                            dateString
                        }

                Text(
                        text = shortDate,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = timelineColor,
                        textAlign = TextAlign.Center
                )
            }

            Box(
                    modifier = Modifier.weight(1f).width(20.dp),
                    contentAlignment = Alignment.TopCenter
            ) {
                Canvas(modifier = Modifier.fillMaxHeight().width(2.dp)) {
                    val lineEnd = if (isLastGlobal) size.height * 0.2f else size.height
                    drawLine(
                            color = timelineColor.copy(alpha = 0.3f),
                            start = Offset(size.width / 2, 0f),
                            end = Offset(size.width / 2, lineEnd),
                            strokeWidth = 2.dp.toPx()
                    )
                    drawCircle(
                            color = timelineColor,
                            radius = 4.dp.toPx(),
                            center = Offset(size.width / 2, 16.dp.toPx()) // 圆点与卡片顶部对齐
                    )
                }
            }
        }

        // 右侧：考试卡片
        Box(modifier = Modifier.weight(1f).padding(bottom = if (isLastInGroup) 24.dp else 12.dp)) {
            ExamCard(exam, showSeat = true, isFinished = isFinished)
        }
    }
}

@Composable
fun ExamCard(exam: Exam, showSeat: Boolean, isFinished: Boolean = false) {
    val alpha = if (isFinished) 0.6f else 1f

    CompositionLocalProvider(
            LocalContentColor provides LocalContentColor.current.copy(alpha = alpha)
    ) {
        OutlinedCard(
                modifier = Modifier.fillMaxWidth(),
                colors =
                        CardDefaults.outlinedCardColors(
                                containerColor =
                                        if (isFinished)
                                                MaterialTheme.colorScheme.surfaceVariant.copy(
                                                        alpha = 0.3f
                                                )
                                        else MaterialTheme.colorScheme.surface
                        ),
                border =
                        CardDefaults.outlinedCardBorder()
                                .copy(
                                        brush =
                                                SolidColor(
                                                        MaterialTheme.colorScheme.outlineVariant
                                                                .copy(alpha = alpha)
                                                )
                                )
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                            text = exam.courseName,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f)
                    )

                    if (showSeat && !exam.examSeatNo.isNullOrBlank()) {

                        Surface(
                                color =
                                        if (isFinished)
                                                MaterialTheme.colorScheme.outlineVariant.copy(
                                                        alpha = 0.5f
                                                )
                                        else MaterialTheme.colorScheme.secondaryContainer,
                                shape = RoundedCornerShape(8.dp)
                        ) {
                            Row(
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                        imageVector = Icons.Default.Chair,
                                        contentDescription = null,
                                        modifier = Modifier.size(14.dp),
                                        tint =
                                                if (isFinished)
                                                        MaterialTheme.colorScheme.onSurfaceVariant
                                                else MaterialTheme.colorScheme.onSecondaryContainer
                                )

                                Spacer(modifier = Modifier.width(4.dp))

                                Text(
                                        text = "${exam.examSeatNo}号",
                                        style = MaterialTheme.typography.labelMedium,
                                        fontWeight = FontWeight.Bold,
                                        color =
                                                if (isFinished)
                                                        MaterialTheme.colorScheme.onSurfaceVariant
                                                else MaterialTheme.colorScheme.onSecondaryContainer
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                // 时间行

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                            imageVector = Icons.Default.AccessTime,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint =
                                    if (isFinished) MaterialTheme.colorScheme.outline
                                    else MaterialTheme.colorScheme.primary
                    )

                    Spacer(modifier = Modifier.width(8.dp))

                    val timeText =
                            if (exam.startTime != null && exam.endTime != null) {

                                "${exam.startTime} - ${exam.endTime}"
                            } else {

                                exam.examTimeDescription ?: "时间待定"
                            }

                    Text(
                            text = timeText,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // 地点行

                exam.examPlace?.let { place ->
                    Spacer(modifier = Modifier.height(6.dp))

                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                                imageVector = Icons.Default.LocationOn,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint =
                                        if (isFinished) MaterialTheme.colorScheme.outline
                                        else MaterialTheme.colorScheme.primary
                        )

                        Spacer(modifier = Modifier.width(8.dp))

                        Text(
                                text = place,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalTime::class)
private fun isExamFinished(exam: Exam): Boolean {
    val dateStr = exam.examDate?.substringBefore(" ") ?: return false
    val endTimeStr = exam.endTime ?: "23:59"
    return try {
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        val examDate = LocalDate.parse(dateStr)
        val examEndTime =
                try {
                    LocalTime.parse(endTimeStr)
                } catch (e: Exception) {
                    LocalTime(23, 59)
                }

        if (now.date > examDate) true
        else if (now.date < examDate) false else now.time > examEndTime
    } catch (e: Exception) {
        false
    }
}
