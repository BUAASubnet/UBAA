package cn.edu.ubaa.ui.screens.classroom

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.edu.ubaa.model.dto.ClassroomInfo
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/**
 * 教室查询功能屏幕。
 * 支持校区切换、日期筛选、关键字搜索，并以复杂的网格图表展示各时段教室的空闲情况。
 *
 * @param viewModel 控制查询逻辑的状态机。
 * @param onBackClick 点击返回按钮的回调。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassroomQueryScreen(
        viewModel: ClassroomViewModel,
        onBackClick: () -> Unit,
        modifier: Modifier = Modifier
) {
        val uiState by viewModel.uiState.collectAsState()
        val xqid by viewModel.xqid.collectAsState()
        val date by viewModel.date.collectAsState()
        val searchQuery by viewModel.searchQuery.collectAsState()
        val filteredData by viewModel.filteredData.collectAsState()
        var showDatePicker by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) { if (uiState is ClassroomUiState.Idle) viewModel.query() }

        if (showDatePicker) {
                val datePickerState = rememberDatePickerState()
                DatePickerDialog(
                        onDismissRequest = { showDatePicker = false },
                        confirmButton = {
                                TextButton(onClick = {
                                        datePickerState.selectedDateMillis?.let { viewModel.setDate(Instant.fromEpochMilliseconds(it).toLocalDateTime(TimeZone.UTC).date.toString()) }
                                        showDatePicker = false
                                })
                                { Text("确定") }
                        },
                        dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("取消") } }
                ) { DatePicker(state = datePickerState) }
        }

        Column(modifier = modifier.fillMaxSize()) {
                Surface(tonalElevation = 2.dp, shadowElevation = 1.dp) {
                        Row(Modifier.fillMaxWidth().padding(8.dp), Arrangement.SpaceEvenly) {
                                CampusButton("学院路", 1, xqid == 1) { viewModel.setXqid(1) }
                                CampusButton("沙河", 2, xqid == 2) { viewModel.setXqid(2) }
                                CampusButton("杭州", 3, xqid == 3) { viewModel.setXqid(3) }
                        }
                }

                Row(Modifier.fillMaxWidth().padding(16.dp, 8.dp), Arrangement.spacedBy(8.dp), Alignment.CenterVertically) {
                        OutlinedCard(onClick = { showDatePicker = true }, Modifier.weight(1f), shape = RoundedCornerShape(12.dp)) {
                                Row(
                                        modifier = Modifier.padding(12.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.SpaceBetween
                                ) { 
                                        Text(text = date, style = MaterialTheme.typography.bodyMedium); Icon(Icons.Default.DateRange, null, Modifier.size(20.dp), MaterialTheme.colorScheme.primary)
                                }
                        }
                        OutlinedTextField(
                                value = searchQuery, onValueChange = { viewModel.setSearchQuery(it) }, placeholder = { Text("搜索教室/楼栋") },
                                modifier = Modifier.weight(1.5f), shape = RoundedCornerShape(12.dp), singleLine = true,
                                leadingIcon = { Icon(Icons.Default.Search, null) }
                        )
                }

                when (val state = uiState) {
                        is ClassroomUiState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { 
                                Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(); Spacer(Modifier.height(8.dp)); Text("正在查询...") }
                        }
                        is ClassroomUiState.Success -> if (filteredData.isEmpty()) Box(Modifier.fillMaxSize(), Alignment.Center) { Text("未找到匹配教室") }
                                else ClassroomTable(filteredData)
                        is ClassroomUiState.Error -> Box(Modifier.fillMaxSize().padding(16.dp), Alignment.Center) { 
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        Text(text = "查询失败: ${state.message}", color = MaterialTheme.colorScheme.error); Spacer(Modifier.height(16.dp)); Button(onClick = { viewModel.query() }) { Text("重试") }
                                }
                        }
                        else -> {}
                }
        }
}

/** 校区切换按钮。 */
@Composable
fun CampusButton(name: String, id: Int, selected: Boolean, onClick: () -> Unit) {
        FilterChip(selected = selected, onClick = onClick, label = { Text(name) })
}

private val timeSlots = listOf("1-3" to listOf(1, 2, 3), "4-5" to listOf(4, 5), "6-7" to listOf(6, 7), "8-10" to listOf(8, 9, 10), "11-13" to listOf(11, 12, 13), "14" to listOf(14))

/** 教室排布表。以楼栋为组进行展示。 */
@Composable
fun ClassroomTable(list: Map<String, List<ClassroomInfo>>) {
        val horizontalScrollState = rememberScrollState()
        LazyColumn(Modifier.fillMaxSize()) {
                list.forEach { (building, classrooms) ->
                        item { BuildingHeader(building) }
                        item {
                                Row(Modifier.fillMaxWidth().horizontalScroll(horizontalScrollState).background(MaterialTheme.colorScheme.surfaceVariant.copy(0.3f)).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)) {
                                        TableCell("教室\n节数", 1.5f, true)
                                        timeSlots.forEach { (label, periods) ->
                                                Box(Modifier.width(40.dp * periods.size).height(48.dp).border(0.6.dp, MaterialTheme.colorScheme.outlineVariant), Alignment.Center) { 
                                                        Text(text = label, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                                                }
                                        }
                                }
                        }
                        items(classrooms) { ClassroomRow(it, horizontalScrollState) }
                        item { Spacer(Modifier.height(16.dp)) }
                }
        }
}

/** 楼栋分组标题。 */
@Composable
fun BuildingHeader(name: String) {
        Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), Alignment.Center) {
                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(4.dp)) {
                        Text(text = name, Modifier.padding(24.dp, 4.dp), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }
        }
}

/** 教室详情行。展示每个节次的空闲背景色。 */
@Composable
fun ClassroomRow(classroom: ClassroomInfo, scrollState: ScrollState) {
        val freePeriods = classroom.kxsds.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
        Row(Modifier.fillMaxWidth().horizontalScroll(scrollState).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)) {
                TableCell(classroom.name, 1.5f, false, MaterialTheme.colorScheme.primary, FontWeight.Medium)
                timeSlots.forEach { (_, periods) ->
                        Row(Modifier.width(40.dp * periods.size).height(48.dp).border(0.6.dp, MaterialTheme.colorScheme.outlineVariant)) {
                                periods.forEach { Box(Modifier.weight(1f).fillMaxHeight().background(if (it in freePeriods) Color(0xFF98FB98) else Color.Transparent).border(0.3.dp, MaterialTheme.colorScheme.outlineVariant.copy(0.3f))) }
                        }
                }
        }
}

/** 通用单元格容器。 */
@Composable
fun RowScope.TableCell(text: String, weight: Float, isHeader: Boolean, textColor: Color = Color.Unspecified, fontWeight: FontWeight? = null) {
        Box(Modifier.weight(weight).widthIn(60.dp).height(48.dp).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant), Alignment.Center) {
                Text(text = text, style = if (isHeader) MaterialTheme.typography.labelSmall else MaterialTheme.typography.bodySmall, fontWeight = fontWeight ?: if (isHeader) FontWeight.Bold else FontWeight.Normal, color = if (isHeader) MaterialTheme.colorScheme.onSurfaceVariant else textColor, textAlign = TextAlign.Center, lineHeight = 14.sp)
        }
}