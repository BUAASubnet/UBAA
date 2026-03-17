package cn.edu.ubaa.ui.screens.classroom

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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

private const val LABEL_CONFIRM = "\u786e\u5b9a"
private const val LABEL_CANCEL = "\u53d6\u6d88"
private const val LABEL_CAMPUS_XYL = "\u5b66\u9662\u8def"
private const val LABEL_CAMPUS_SH = "\u6c99\u6cb3"
private const val LABEL_CAMPUS_HZ = "\u676d\u5dde"
private const val LABEL_PICK_DATE = "\u9009\u62e9\u65e5\u671f"
private const val LABEL_SEARCH_PLACEHOLDER = "\u641c\u7d22\u6559\u5ba4"
private const val LABEL_FREE = " \u7a7a\u95f2"
private const val LABEL_LOADING = "\u6b63\u5728\u67e5\u8be2..."
private const val LABEL_EMPTY = "\u672a\u627e\u5230\u5339\u914d\u7684\u6559\u5ba4"
private const val LABEL_RETRY = "\u91cd\u8bd5"
private const val LABEL_SELECT_BUILDING = "\u9009\u62e9\u697c\u680b"
private const val LABEL_TABLE_CLASSROOM = "\u6559\u5ba4"
private const val LABEL_ERROR_PREFIX = "\u67e5\u8be2\u5931\u8d25: "

@OptIn(ExperimentalMaterial3Api::class)
@Composable
@Suppress("UNUSED_PARAMETER")
fun ClassroomQueryScreen(
  viewModel: ClassroomViewModel,
  onBackClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val uiState by viewModel.uiState.collectAsState()
  val xqid by viewModel.xqid.collectAsState()
  val date by viewModel.date.collectAsState()
  val searchQuery by viewModel.searchQuery.collectAsState()
  val selectedBuilding by viewModel.selectedBuilding.collectAsState()
  val availableBuildings by viewModel.availableBuildings.collectAsState()
  val filteredData by viewModel.filteredData.collectAsState()
  var showDatePicker by remember { mutableStateOf(false) }

  LaunchedEffect(Unit) {
    if (uiState is ClassroomUiState.Idle) viewModel.query()
  }

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
          Text(LABEL_CONFIRM)
        }
      },
      dismissButton = {
        TextButton(onClick = { showDatePicker = false }) { Text(LABEL_CANCEL) }
      },
    ) {
      DatePicker(state = datePickerState)
    }
  }

  Column(modifier = modifier.fillMaxSize()) {
    Surface(tonalElevation = 2.dp, shadowElevation = 1.dp) {
      Row(
        modifier = Modifier.fillMaxWidth().padding(8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
      ) {
        CampusButton(LABEL_CAMPUS_XYL, xqid == 1) { viewModel.setXqid(1) }
        CampusButton(LABEL_CAMPUS_SH, xqid == 2) { viewModel.setXqid(2) }
        CampusButton(LABEL_CAMPUS_HZ, xqid == 3) { viewModel.setXqid(3) }
      }
    }

    Row(
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      OutlinedCard(
        onClick = { showDatePicker = true },
        modifier = Modifier.weight(1f),
        shape = RoundedCornerShape(12.dp),
      ) {
        Row(
          modifier = Modifier.fillMaxWidth().padding(12.dp),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(text = date, style = MaterialTheme.typography.bodyMedium)
          Icon(
            imageVector = Icons.Default.DateRange,
            contentDescription = LABEL_PICK_DATE,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary,
          )
        }
      }

      BuildingDropdown(
        buildings = availableBuildings,
        selectedBuilding = selectedBuilding,
        onSelect = viewModel::setSelectedBuilding,
        modifier = Modifier.weight(1f),
      )
    }

    OutlinedTextField(
      value = searchQuery,
      onValueChange = { viewModel.setSearchQuery(it) },
      placeholder = { Text(LABEL_SEARCH_PLACEHOLDER) },
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
      shape = RoundedCornerShape(12.dp),
      singleLine = true,
      leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
    )

    Row(
      modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp),
      horizontalArrangement = Arrangement.Center,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Box(
        modifier =
          Modifier.size(12.dp)
            .background(Color(0xFF98FB98), RoundedCornerShape(2.dp))
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
      )
      Text(
        text = LABEL_FREE,
        modifier = Modifier.padding(start = 4.dp),
        style = MaterialTheme.typography.labelSmall,
      )
    }

    when (val state = uiState) {
      is ClassroomUiState.Loading ->
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(Modifier.height(8.dp))
            Text(LABEL_LOADING)
          }
        }
      is ClassroomUiState.Success ->
        if (filteredData.isEmpty()) {
          Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(LABEL_EMPTY)
          }
        } else {
          ClassroomTable(filteredData)
        }
      is ClassroomUiState.Error ->
        Box(
          modifier = Modifier.fillMaxSize().padding(16.dp),
          contentAlignment = Alignment.Center,
        ) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
              text = LABEL_ERROR_PREFIX + state.message,
              color = MaterialTheme.colorScheme.error,
            )
            Spacer(Modifier.height(16.dp))
            Button(onClick = { viewModel.query() }) { Text(LABEL_RETRY) }
          }
        }
      ClassroomUiState.Idle -> Unit
    }
  }
}

@Composable
private fun CampusButton(name: String, selected: Boolean, onClick: () -> Unit) {
  FilterChip(selected = selected, onClick = onClick, label = { Text(name) })
}

@Composable
private fun BuildingDropdown(
  buildings: List<String>,
  selectedBuilding: String,
  onSelect: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  var expanded by remember { mutableStateOf(false) }

  Box(modifier = modifier) {
    OutlinedCard(
      onClick = { expanded = true },
      modifier = Modifier.fillMaxWidth(),
      shape = RoundedCornerShape(12.dp),
    ) {
      Row(
        modifier = Modifier.fillMaxWidth().padding(12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = selectedBuilding,
          style = MaterialTheme.typography.bodyMedium,
          maxLines = 1,
        )
        Icon(
          imageVector = Icons.Default.ArrowDropDown,
          contentDescription = LABEL_SELECT_BUILDING,
          tint = MaterialTheme.colorScheme.primary,
        )
      }
    }

    DropdownMenu(
      expanded = expanded,
      onDismissRequest = { expanded = false },
      modifier = Modifier.fillMaxWidth(0.95f),
    ) {
      buildings.forEach { building ->
        DropdownMenuItem(
          text = { Text(building) },
          onClick = {
            expanded = false
            onSelect(building)
          },
        )
      }
    }
  }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
fun ClassroomTable(list: Map<String, List<ClassroomInfo>>) {
  LazyColumn(modifier = Modifier.fillMaxSize()) {
    stickyHeader {
      Row(
        modifier =
          Modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
      ) {
        TableCell(LABEL_TABLE_CLASSROOM, 2.2f, true)
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

@Composable
private fun BuildingHeader(name: String) {
  Box(
    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
    contentAlignment = Alignment.Center,
  ) {
    Surface(
      color = MaterialTheme.colorScheme.secondaryContainer,
      shape = RoundedCornerShape(4.dp),
    ) {
      Text(
        text = name,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
      )
    }
  }
}

@Composable
private fun ClassroomRow(classroom: ClassroomInfo) {
  val freePeriods =
    remember(classroom.kxsds) {
      classroom.kxsds.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
    }

  Row(
    modifier =
      Modifier.fillMaxWidth()
        .height(44.dp)
        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
  ) {
    Box(
      modifier =
        Modifier.weight(2.2f)
          .fillMaxHeight()
          .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
      contentAlignment = Alignment.Center,
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

    for (i in 1..14) {
      val isFree = i in freePeriods
      Box(
        modifier =
          Modifier.weight(1f)
            .fillMaxHeight()
            .background(if (isFree) Color(0xFF98FB98) else Color.Transparent)
            .border(0.3.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
      )
    }
  }
}

@Composable
private fun RowScope.TableCell(text: String, weight: Float, isHeader: Boolean) {
  Box(
    modifier =
      Modifier.weight(weight)
        .height(40.dp)
        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
    contentAlignment = Alignment.Center,
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
