@file:OptIn(ExperimentalFoundationApi::class)

package cn.edu.ubaa.ui.screens.ygdk

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.YgdkItemDto
import cn.edu.ubaa.ui.common.util.PlatformImagePicker
import cn.edu.ubaa.ui.common.util.formatImageSize
import kotlin.math.abs
import kotlin.time.Clock
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@Composable
fun YgdkClockinFormScreen(
    uiState: YgdkUiState,
    imagePicker: PlatformImagePicker,
    onItemSelected: (Int?) -> Unit,
    onStartTimeChange: (String) -> Unit,
    onEndTimeChange: (String) -> Unit,
    onPlaceChange: (String) -> Unit,
    onShareChange: (Boolean) -> Unit,
    onClearPhoto: () -> Unit,
    onSubmit: () -> Unit,
) {
  var showItemDialog by remember { mutableStateOf(false) }
  var activeTimeField by remember { mutableStateOf<YgdkTimeField?>(null) }

  if (showItemDialog) {
    YgdkItemSelectorDialog(
        items = uiState.overview?.items.orEmpty(),
        selectedItemId = uiState.form.itemId,
        onDismiss = { showItemDialog = false },
        onSelect = {
          onItemSelected(it)
          showItemDialog = false
        },
    )
  }

  activeTimeField?.let { timeField ->
    YgdkTimePickerDialog(
        title = if (timeField == YgdkTimeField.START) "选择开始时间" else "选择结束时间",
        initialTime = uiState.form.timeValueOf(timeField),
        onDismiss = { activeTimeField = null },
        onConfirm = { hour, minute ->
          val selectedValue = buildTodayDateTimeText(hour, minute)
          if (timeField == YgdkTimeField.START) {
            onStartTimeChange(selectedValue)
          } else {
            onEndTimeChange(selectedValue)
          }
          activeTimeField = null
        },
    )
  }

  Scaffold(
      contentWindowInsets =
          WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
      bottomBar = {
        Button(
            onClick = onSubmit,
            enabled = !uiState.isSubmitting,
            modifier = Modifier.fillMaxWidth().padding(16.dp).height(52.dp),
            contentPadding = PaddingValues(horizontal = 16.dp),
        ) {
          Text(if (uiState.isSubmitting) "提交中..." else "提交打卡")
        }
      },
  ) { padding ->
    Column(
        modifier =
            Modifier.fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Card(
          colors =
              CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
          modifier = Modifier.fillMaxWidth(),
      ) {
        Text(
            text = YGDK_FORM_HINT,
            modifier = Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
      }

      uiState.submitMessage?.let {
        Card(
            colors =
                CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            modifier = Modifier.fillMaxWidth(),
        ) {
          Text(
              text = it,
              modifier = Modifier.padding(16.dp),
              color = MaterialTheme.colorScheme.onErrorContainer,
          )
        }
      }

      Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Text(
              text = "运动项目",
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
          )
          OutlinedButton(onClick = { showItemDialog = true }, modifier = Modifier.fillMaxWidth()) {
            Text(uiState.selectedItemLabel())
          }
          Text(
              text = "留空则默认使用 ${uiState.overview?.defaultItemName ?: "跑步"}",
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Text(
              text = "时间",
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
          )
          YgdkTimeSelectorButton(
              label = "开始时间",
              value = uiState.form.displayTimeOf(YgdkTimeField.START),
              placeholder = "选择时间",
              onClick = { activeTimeField = YgdkTimeField.START },
          )
          YgdkTimeSelectorButton(
              label = "结束时间",
              value = uiState.form.displayTimeOf(YgdkTimeField.END),
              placeholder = "选择时间",
              onClick = { activeTimeField = YgdkTimeField.END },
          )
          Text(
              text = "开始时间和结束时间需要同时填写；时间选择后默认使用当天日期。留空则自动生成最近三天内 08:00 到当日上限时间之间的一小时记录。",
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Text(
              text = "地点",
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
          )
          OutlinedTextField(
              value = uiState.form.place,
              onValueChange = onPlaceChange,
              label = { Text("运动地点") },
              placeholder = { Text("操场") },
              modifier = Modifier.fillMaxWidth(),
              leadingIcon = { Icon(Icons.Default.Place, null) },
              singleLine = true,
          )
        }
      }

      Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Text(
              text = "照片",
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
          )
          Row(
              horizontalArrangement = Arrangement.spacedBy(12.dp),
              modifier = Modifier.fillMaxWidth(),
          ) {
            OutlinedButton(onClick = imagePicker::pickImage, modifier = Modifier.weight(1f)) {
              Icon(Icons.Default.Image, contentDescription = null)
              Spacer(modifier = Modifier.padding(4.dp))
              Text("选择图片")
            }
            if (imagePicker.canCapturePhoto) {
              OutlinedButton(onClick = imagePicker::capturePhoto, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.PhotoCamera, contentDescription = null)
                Spacer(modifier = Modifier.padding(4.dp))
                Text("拍摄照片")
              }
            }
          }
          uiState.form.photo?.let { photo ->
            Card(
                colors =
                    CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
                modifier = Modifier.fillMaxWidth(),
            ) {
              Row(
                  modifier = Modifier.fillMaxWidth().padding(12.dp),
                  verticalAlignment = Alignment.CenterVertically,
              ) {
                Column(modifier = Modifier.weight(1f)) {
                  Text(text = photo.fileName, fontWeight = FontWeight.Bold)
                  Text(
                      text = "${photo.mimeType} · ${formatImageSize(photo.sizeInBytes)}",
                      style = MaterialTheme.typography.bodySmall,
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
                IconButton(onClick = onClearPhoto) {
                  Icon(Icons.Default.Delete, contentDescription = "清除图片")
                }
              }
            }
          }
              ?: Text(
                  text = "未选择图片时会自动生成全透明图片。",
                  style = MaterialTheme.typography.bodySmall,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
        }
      }

      Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier =
                Modifier.fillMaxWidth().padding(16.dp).clickable {
                  onShareChange(!uiState.form.shareToSquare)
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Icon(Icons.Default.Share, contentDescription = null)
          Spacer(modifier = Modifier.padding(6.dp))
          Column(modifier = Modifier.weight(1f)) {
            Text(text = "分享到广场", fontWeight = FontWeight.Bold)
            Text(
                text = "默认不分享，开启后会把本次打卡同步到广场。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
          Checkbox(checked = uiState.form.shareToSquare, onCheckedChange = onShareChange)
        }
      }
    }
  }
}

@Composable
private fun YgdkItemSelectorDialog(
    items: List<YgdkItemDto>,
    selectedItemId: Int?,
    onDismiss: () -> Unit,
    onSelect: (Int?) -> Unit,
) {
  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text("选择运动项目") },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          TextButton(onClick = { onSelect(null) }, modifier = Modifier.fillMaxWidth()) {
            Text("不设置，交给系统自动选择")
          }
          items.forEach { item ->
            Row(
                modifier =
                    Modifier.fillMaxWidth()
                        .clickable { onSelect(item.itemId) }
                        .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
              Checkbox(
                  checked = item.itemId == selectedItemId,
                  onCheckedChange = { onSelect(item.itemId) },
              )
              Text(item.name)
            }
          }
        }
      },
      confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
  )
}

private fun YgdkUiState.selectedItemLabel(): String {
  val itemId = form.itemId ?: return "不设置，使用默认运动"
  return overview?.items?.firstOrNull { it.itemId == itemId }?.name ?: "不设置，使用默认运动"
}

private enum class YgdkTimeField {
  START,
  END,
}

@Composable
private fun YgdkTimeSelectorButton(
    label: String,
    value: String?,
    placeholder: String,
    onClick: () -> Unit,
) {
  OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
    Icon(Icons.Default.AccessTime, contentDescription = null)
    Spacer(modifier = Modifier.width(8.dp))
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.Start,
    ) {
      Text(text = label, style = MaterialTheme.typography.labelMedium)
      Text(
          text = value ?: placeholder,
          style = MaterialTheme.typography.bodyLarge,
          color =
              if (value == null) MaterialTheme.colorScheme.onSurfaceVariant
              else MaterialTheme.colorScheme.onSurface,
      )
    }
  }
}

@Composable
private fun YgdkTimePickerDialog(
    title: String,
    initialTime: Pair<Int, Int>?,
    onDismiss: () -> Unit,
    onConfirm: (hour: Int, minute: Int) -> Unit,
) {
  var selectedHour by remember { mutableStateOf(initialTime?.first ?: 8) }
  var selectedMinute by remember { mutableStateOf(initialTime?.second?.roundToFiveMinutes() ?: 0) }

  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text(title) },
      text = {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
          YgdkWheelPicker(
              label = "H",
              values = (0..23).toList(),
              initialValue = selectedHour,
              modifier = Modifier.weight(1f),
              onValueSelected = { selectedHour = it },
          )
          Spacer(modifier = Modifier.width(16.dp))
          YgdkWheelPicker(
              label = "M",
              values = (0..55 step 5).toList(),
              initialValue = selectedMinute,
              modifier = Modifier.weight(1f),
              onValueSelected = { selectedMinute = it },
          )
        }
      },
      confirmButton = {
        TextButton(onClick = { onConfirm(selectedHour, selectedMinute) }) { Text("完成") }
      },
      dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
  )
}

@Composable
private fun YgdkWheelPicker(
    label: String,
    values: List<Int>,
    initialValue: Int,
    modifier: Modifier = Modifier,
    rowHeight: Dp = 56.dp,
    visibleRows: Int = 5,
    onValueSelected: (Int) -> Unit,
) {
  val initialIndex = values.indexOf(initialValue).coerceAtLeast(0)
  val listState = rememberLazyListState(initialFirstVisibleItemIndex = initialIndex)
  val coroutineScope = rememberCoroutineScope()
  val flingBehavior = rememberSnapFlingBehavior(lazyListState = listState)
  var selectedIndex by remember(values, initialIndex) { mutableStateOf(initialIndex) }
  val pickerHeight = rowHeight * visibleRows
  val contentPadding = rowHeight * (visibleRows / 2)

  LaunchedEffect(listState, values) {
    snapshotFlow {
          val layoutInfo = listState.layoutInfo
          val center = (layoutInfo.viewportStartOffset + layoutInfo.viewportEndOffset) / 2
          layoutInfo.visibleItemsInfo
              .minByOrNull { item -> abs((item.offset + item.size / 2) - center) }
              ?.index
        }
        .filterNotNull()
        .map { it.coerceIn(values.indices) }
        .distinctUntilChanged()
        .collect { index ->
          selectedIndex = index
          onValueSelected(values[index])
        }
  }

  Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
    Text(text = label, style = MaterialTheme.typography.labelLarge)
    Spacer(modifier = Modifier.height(8.dp))
    Box(
        modifier = Modifier.height(pickerHeight).fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
      Card(
          modifier = Modifier.fillMaxWidth().height(rowHeight),
          colors =
              CardDefaults.cardColors(
                  containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
              ),
      ) {}
      LazyColumn(
          state = listState,
          flingBehavior = flingBehavior,
          modifier = Modifier.fillMaxWidth(),
          contentPadding = PaddingValues(vertical = contentPadding),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        items(values.size) { index ->
          val isSelected = index == selectedIndex
          Box(
              modifier =
                  Modifier.fillMaxWidth().height(rowHeight).clickable {
                    coroutineScope.launch { listState.animateScrollToItem(index) }
                  },
              contentAlignment = Alignment.Center,
          ) {
            Text(
                text = values[index].toTwoDigitText(),
                style =
                    if (isSelected) MaterialTheme.typography.headlineMedium
                    else MaterialTheme.typography.headlineSmall,
                color =
                    if (isSelected) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.28f),
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
            )
          }
        }
      }
    }
  }
}

private fun YgdkFormState.timeValueOf(field: YgdkTimeField): Pair<Int, Int>? {
  val source =
      when (field) {
        YgdkTimeField.START -> startTime
        YgdkTimeField.END -> endTime
      }
  return source.parseDateTimeOrNull()?.let { it.hour to it.minute.roundToFiveMinutes() }
}

private fun YgdkFormState.displayTimeOf(field: YgdkTimeField): String? {
  val source =
      when (field) {
        YgdkTimeField.START -> startTime
        YgdkTimeField.END -> endTime
      }
  val parsed = source.parseDateTimeOrNull() ?: return null
  return "${parsed.hour.toTwoDigitText()}:${parsed.minute.toTwoDigitText()}"
}

private fun buildTodayDateTimeText(hour: Int, minute: Int): String {
  val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
  return "${now.date} ${hour.toTwoDigitText()}:${minute.toTwoDigitText()}"
}

private fun Int.roundToFiveMinutes(): Int = ((this + 2) / 5 * 5).coerceAtMost(55)

private fun Int.toTwoDigitText(): String = toString().padStart(2, '0')

private fun String.parseDateTimeOrNull(): LocalDateTime? {
  return runCatching { LocalDateTime.parse(trim().replace(' ', 'T')) }.getOrNull()
}
