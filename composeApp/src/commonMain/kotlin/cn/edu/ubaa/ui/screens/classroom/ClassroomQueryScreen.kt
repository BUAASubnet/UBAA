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
 * 教室查询功能屏幕。 结合了美观的视觉风格（圆角、配色）与紧凑的布局（一页展示14节课）。
 *
 * @param viewModel 控制查询逻辑的状态机。
 * @param onBackClick 点击返回按钮的回调。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ClassroomQueryScreen(
  viewModel: ClassroomViewModel,
  onBackClick: () -> Unit,
  modifier: Modifier = Modifier,
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
        TextButton(
          onClick = {
            datePickerState.selectedDateMillis?.let {
              viewModel.setDate(
                Instant.fromEpochMilliseconds(it).toLocalDateTime(TimeZone.UTC).date.toString()
              )
            }
            showDatePicker = false
          }
        ) {
          Text("确定")
        }
      },
      dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("取消") } },
    ) {
      DatePicker(state = datePickerState)
    }
  }

  Column(modifier = modifier.fillMaxSize()) {
    Surface(tonalElevation = 2.dp, shadowElevation = 1.dp) {
      Row(Modifier.fillMaxWidth().padding(8.dp), Arrangement.SpaceEvenly) {
        CampusButton("学院路", 1, xqid == 1) { viewModel.setXqid(1) }
        CampusButton("沙河", 2, xqid == 2) { viewModel.setXqid(2) }
        CampusButton("杭州", 3, xqid == 3) { viewModel.setXqid(3) }
      }
    }

    Row(
      Modifier.fillMaxWidth().padding(16.dp, 8.dp),
      Arrangement.spacedBy(8.dp),
      Alignment.CenterVertically,
    ) {
      OutlinedCard(
        onClick = { showDatePicker = true },
        Modifier.weight(1f),
        shape = RoundedCornerShape(12.dp),
      ) {
        Row(
          modifier = Modifier.padding(12.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.SpaceBetween,
        ) {
          Text(text = date, style = MaterialTheme.typography.bodyMedium)
          Icon(
            Icons.Default.DateRange,
            null,
            Modifier.size(20.dp),
            MaterialTheme.colorScheme.primary,
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
        leadingIcon = { Icon(Icons.Default.Search, null) },
      )
    }

    // 简单的图例
    Row(
      Modifier.fillMaxWidth().padding(bottom = 8.dp),
      horizontalArrangement = Arrangement.Center,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Box(
        Modifier.size(12.dp)
          .background(Color(0xFF98FB98), RoundedCornerShape(2.dp))
          .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
      )
      Text(" 空闲", Modifier.padding(start = 4.dp), style = MaterialTheme.typography.labelSmall)
    }

    when (val state = uiState) {
      is ClassroomUiState.Loading ->
        Box(Modifier.fillMaxSize(), Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(Modifier.height(8.dp))
            Text("正在查询...")
          }
        }
      is ClassroomUiState.Success ->
        if (filteredData.isEmpty())
          Box(Modifier.fillMaxSize(), Alignment.Center) { Text("未找到匹配教室") }
        else ClassroomTable(filteredData)
      is ClassroomUiState.Error ->
        Box(Modifier.fillMaxSize().padding(16.dp), Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = "查询失败: ${state.message}", color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(16.dp))
            Button(onClick = { viewModel.query() }) { Text("重试") }
          }
        }
      else -> {}
    }
  }
}

@Composable
fun CampusButton(name: String, id: Int, selected: Boolean, onClick: () -> Unit) {
  FilterChip(selected = selected, onClick = onClick, label = { Text(name) })
}

/** 教室排布表。 使用 LazyColumn 实现，包含表头和楼栋分组。 */
@Composable
fun ClassroomTable(list: Map<String, List<ClassroomInfo>>) {
  LazyColumn(Modifier.fillMaxSize()) {
    // 固定表头
    stickyHeader {
      Row(
        Modifier.fillMaxWidth()
          .background(MaterialTheme.colorScheme.surface)
          .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
      ) {
        TableCell("教室", 2.2f, true)
        for (i in 1..14) {
          TableCell(i.toString(), 1f, true)
        }
      }
    }

    list.forEach { (building, classrooms) ->
      item { BuildingHeader(building) }
      items(classrooms) { ClassroomRow(it) }
    }
    item { Spacer(Modifier.height(16.dp)) }
  }
}

/** 楼栋分组标题 (恢复原有的圆角 Surface 风格)。 */
@Composable
fun BuildingHeader(name: String) {
  Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), Alignment.Center) {
    Surface(
      color = MaterialTheme.colorScheme.secondaryContainer,
      shape = RoundedCornerShape(4.dp),
    ) {
      Text(
        text = name,
        Modifier.padding(24.dp, 4.dp),
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
      )
    }
  }
}

/** 教室详情行。 使用 Weight 布局实现一页宽度的 1-14 节课展示，无需水平滚动。 */
@Composable
fun ClassroomRow(classroom: ClassroomInfo) {
  val freePeriods =
    remember(classroom.kxsds) {
      classroom.kxsds.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
    }

  Row(
    Modifier.fillMaxWidth().height(44.dp).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
  ) {
    // 教室名单元格
    Box(
      Modifier.weight(2.2f)
        .fillMaxHeight()
        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
      Alignment.Center,
    ) {
      Text(
        text = classroom.name,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.primary,
        textAlign = TextAlign.Center,
        fontSize = 11.sp,
        lineHeight = 12.sp,
      )
    }

    // 1-14 节课状态单元格
    for (i in 1..14) {
      val isFree = i in freePeriods
      Box(
        Modifier.weight(1f)
          .fillMaxHeight()
          .background(if (isFree) Color(0xFF98FB98) else Color.Transparent)
          .border(0.3.dp, MaterialTheme.colorScheme.outlineVariant.copy(0.3f))
      )
    }
  }
}

/** 通用单元格容器 (表头用)。 */
@Composable
fun RowScope.TableCell(text: String, weight: Float, isHeader: Boolean) {
  Box(
    Modifier.weight(weight)
      .height(40.dp) // 略微增加高度以匹配之前的风格
      .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
    Alignment.Center,
  ) {
    Text(
      text = text,
      style =
        if (isHeader) MaterialTheme.typography.labelSmall else MaterialTheme.typography.bodySmall,
      fontWeight = if (isHeader) FontWeight.Bold else FontWeight.Normal,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
      fontSize = 10.sp,
    )
  }
}
