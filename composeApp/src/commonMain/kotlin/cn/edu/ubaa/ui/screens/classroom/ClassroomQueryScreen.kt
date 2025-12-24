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

        LaunchedEffect(Unit) {
                if (uiState is ClassroomUiState.Idle) {
                        viewModel.query()
                }
        }

        if (showDatePicker) {
                val datePickerState = rememberDatePickerState()
                DatePickerDialog(
                        onDismissRequest = { showDatePicker = false },
                        confirmButton = {
                                TextButton(
                                        onClick = {
                                                datePickerState.selectedDateMillis?.let { millis ->
                                                        val instant =
                                                                Instant.fromEpochMilliseconds(
                                                                        millis
                                                                )
                                                        val localDate =
                                                                instant.toLocalDateTime(
                                                                                TimeZone.UTC
                                                                        )
                                                                        .date
                                                        viewModel.setDate(localDate.toString())
                                                }
                                                showDatePicker = false
                                        }
                                ) { Text("确定") }
                        },
                        dismissButton = {
                                TextButton(onClick = { showDatePicker = false }) { Text("取消") }
                        }
                ) { DatePicker(state = datePickerState) }
        }

        Column(modifier = modifier.fillMaxSize()) {
                // Campus Selection
                Surface(tonalElevation = 2.dp, shadowElevation = 1.dp) {
                        Row(
                                modifier = Modifier.fillMaxWidth().padding(8.dp),
                                horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                                CampusButton("学院路", 1, xqid == 1) { viewModel.setXqid(1) }
                                CampusButton("沙河", 2, xqid == 2) { viewModel.setXqid(2) }
                                CampusButton("杭州", 3, xqid == 3) { viewModel.setXqid(3) }
                        }
                }

                // Date Selection & Search
                Row(
                        modifier =
                                Modifier.fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                ) {
                        OutlinedCard(
                                onClick = { showDatePicker = true },
                                modifier = Modifier.weight(1f),
                                shape = RoundedCornerShape(12.dp)
                        ) {
                                Row(
                                        modifier =
                                                Modifier.padding(
                                                        horizontal = 12.dp,
                                                        vertical = 12.dp
                                                ),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                        Text(
                                                text = date,
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurface
                                        )
                                        Icon(
                                                imageVector = Icons.Default.DateRange,
                                                contentDescription = null,
                                                modifier = Modifier.size(20.dp),
                                                tint = MaterialTheme.colorScheme.primary
                                        )
                                }
                        }

                        OutlinedTextField(
                                value = searchQuery,
                                onValueChange = { viewModel.setSearchQuery(it) },
                                placeholder = { Text("搜索教室/楼栋") },
                                modifier = Modifier.weight(1.5f),
                                shape = RoundedCornerShape(12.dp),
                                singleLine = true,
                                leadingIcon = {
                                        Icon(Icons.Default.Search, contentDescription = null)
                                },
                                colors =
                                        OutlinedTextFieldDefaults.colors(
                                                unfocusedContainerColor = Color.Transparent,
                                                focusedContainerColor = Color.Transparent
                                        )
                        )
                }

                when (val state = uiState) {
                        is ClassroomUiState.Idle, is ClassroomUiState.Loading -> {
                                Box(
                                        modifier = Modifier.fillMaxSize(),
                                        contentAlignment = Alignment.Center
                                ) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                                CircularProgressIndicator()
                                                Spacer(modifier = Modifier.height(8.dp))
                                                Text(
                                                        "正在查询空教室...",
                                                        style = MaterialTheme.typography.bodyMedium
                                                )
                                        }
                                }
                        }
                        is ClassroomUiState.Success -> {
                                if (filteredData.isEmpty()) {
                                        Box(
                                                modifier = Modifier.fillMaxSize(),
                                                contentAlignment = Alignment.Center
                                        ) {
                                                Text(
                                                        "未找到匹配的教室",
                                                        style = MaterialTheme.typography.bodyMedium,
                                                        color =
                                                                MaterialTheme.colorScheme
                                                                        .onSurfaceVariant
                                                )
                                        }
                                } else {
                                        ClassroomTable(filteredData)
                                }
                        }
                        is ClassroomUiState.Error -> {
                                Box(
                                        modifier = Modifier.fillMaxSize().padding(16.dp),
                                        contentAlignment = Alignment.Center
                                ) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                                Text(
                                                        text = "查询失败: ${state.message}",
                                                        color = MaterialTheme.colorScheme.error,
                                                        textAlign = TextAlign.Center
                                                )
                                                Spacer(modifier = Modifier.height(16.dp))
                                                Button(onClick = { viewModel.query() }) {
                                                        Text("重试")
                                                }
                                        }
                                }
                        }
                }
        }
}

@Composable
fun CampusButton(name: String, id: Int, selected: Boolean, onClick: () -> Unit) {
        FilterChip(
                selected = selected,
                onClick = onClick,
                label = { Text(name) },
                colors =
                        FilterChipDefaults.filterChipColors(
                                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
                        )
        )
}

private val timeSlots =
        listOf(
                "1-3" to listOf(1, 2, 3),
                "4-5" to listOf(4, 5),
                "6-7" to listOf(6, 7),
                "8-10" to listOf(8, 9, 10),
                "11-13" to listOf(11, 12, 13),
                "14" to listOf(14)
        )

@Composable
fun ClassroomTable(list: Map<String, List<ClassroomInfo>>) {
        val horizontalScrollState = rememberScrollState()

        LazyColumn(modifier = Modifier.fillMaxSize()) {
                list.forEach { (building, classrooms) ->
                        item { BuildingHeader(building) }

                        item {
                                // Table Header
                                Row(
                                        modifier =
                                                Modifier.fillMaxWidth()
                                                        .horizontalScroll(horizontalScrollState)
                                                        .background(
                                                                MaterialTheme.colorScheme
                                                                        .surfaceVariant.copy(
                                                                        alpha = 0.3f
                                                                )
                                                        )
                                                        .border(
                                                                0.5.dp,
                                                                MaterialTheme.colorScheme
                                                                        .outlineVariant
                                                        )
                                ) {
                                        TableCell(text = "教室\n节数", weight = 1.5f, isHeader = true)
                                        timeSlots.forEach { (label, periods) ->
                                                Box(
                                                        modifier =
                                                                Modifier.weight(
                                                                                periods.size
                                                                                        .toFloat()
                                                                        )
                                                                        .widthIn(
                                                                                min =
                                                                                        40.dp *
                                                                                                periods.size
                                                                        )
                                                                        .height(48.dp)
                                                                        .border(
                                                                                0.6.dp,
                                                                                MaterialTheme
                                                                                        .colorScheme
                                                                                        .outlineVariant
                                                                        ),
                                                        contentAlignment = Alignment.Center
                                                ) {
                                                        Text(
                                                                text = label,
                                                                style =
                                                                        MaterialTheme.typography
                                                                                .labelSmall,
                                                                fontWeight = FontWeight.Bold,
                                                                color =
                                                                        MaterialTheme.colorScheme
                                                                                .onSurfaceVariant,
                                                                textAlign = TextAlign.Center
                                                        )
                                                }
                                        }
                                }
                        }

                        items(classrooms) { classroom ->
                                ClassroomRow(classroom, horizontalScrollState)
                        }

                        item { Spacer(modifier = Modifier.height(16.dp)) }
                }
        }
}

@Composable
fun BuildingHeader(name: String) {
        Box(
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                contentAlignment = Alignment.Center
        ) {
                Surface(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = RoundedCornerShape(4.dp)
                ) {
                        Text(
                                text = name,
                                modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                                fontWeight = FontWeight.Bold
                        )
                }
        }
}

@Composable
fun ClassroomRow(classroom: ClassroomInfo, scrollState: ScrollState) {
        val freePeriods = classroom.kxsds.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
        val freeColor = Color(0xFF98FB98) // Pale Green

        Row(
                modifier =
                        Modifier.fillMaxWidth()
                                .horizontalScroll(scrollState)
                                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
        ) {
                // Classroom Name
                TableCell(
                        text = classroom.name,
                        weight = 1.5f,
                        textColor = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Medium
                )

                // Time Slots - Grouped by blocks with thicker borders
                timeSlots.forEach { (_, periods) ->
                        Row(
                                modifier =
                                        Modifier.weight(periods.size.toFloat())
                                                .widthIn(min = 40.dp * periods.size)
                                                .height(48.dp)
                                                .border(
                                                        0.6.dp,
                                                        MaterialTheme.colorScheme.outlineVariant
                                                )
                        ) {
                                periods.forEach { period ->
                                        val isFree = period in freePeriods
                                        Box(
                                                modifier =
                                                        Modifier.weight(1f)
                                                                .fillMaxHeight()
                                                                .background(
                                                                        if (isFree) freeColor
                                                                        else Color.Transparent
                                                                )
                                                                .border(
                                                                        0.3.dp,
                                                                        MaterialTheme.colorScheme
                                                                                .outlineVariant
                                                                                .copy(alpha = 0.3f)
                                                                )
                                        )
                                }
                        }
                }
        }
}

@Composable
fun RowScope.TableCell(
        text: String,
        weight: Float,
        isHeader: Boolean = false,
        textColor: Color = Color.Unspecified,
        fontWeight: FontWeight? = null
) {
        Box(
                modifier =
                        Modifier.weight(weight)
                                .widthIn(min = 60.dp)
                                .height(48.dp)
                                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
                contentAlignment = Alignment.Center
        ) {
                Text(
                        text = text,
                        style =
                                if (isHeader) MaterialTheme.typography.labelSmall
                                else MaterialTheme.typography.bodySmall,
                        fontWeight = fontWeight
                                        ?: if (isHeader) FontWeight.Bold else FontWeight.Normal,
                        color =
                                if (isHeader) MaterialTheme.colorScheme.onSurfaceVariant
                                else textColor,
                        textAlign = TextAlign.Center,
                        lineHeight = 14.sp
                )
        }
}
