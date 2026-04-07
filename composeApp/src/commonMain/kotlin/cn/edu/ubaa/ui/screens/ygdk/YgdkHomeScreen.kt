package cn.edu.ubaa.ui.screens.ygdk

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkRecordDto

@Composable
fun YgdkHomeScreen(
    uiState: YgdkUiState,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    onAddClick: () -> Unit,
    onMessageConsumed: () -> Unit,
) {
  val snackbarHostState = remember { SnackbarHostState() }

  LaunchedEffect(uiState.submitMessage) {
    val message = uiState.submitMessage ?: return@LaunchedEffect
    snackbarHostState.showSnackbar(message)
    onMessageConsumed()
  }

  Scaffold(
      snackbarHost = { SnackbarHost(snackbarHostState) },
      floatingActionButton = {
        FloatingActionButton(onClick = onAddClick) {
          Icon(Icons.Default.Add, contentDescription = "新增打卡")
        }
      },
  ) { padding ->
    when {
      uiState.isLoading && uiState.overview == null ->
          Box(
              modifier = Modifier.fillMaxSize().padding(padding),
              contentAlignment = Alignment.Center,
          ) {
            CircularProgressIndicator()
          }
      uiState.loadError != null && uiState.records.isEmpty() ->
          YgdkFullPageMessage(
              message = uiState.loadError,
              actionLabel = "重试",
              onAction = onRefresh,
              modifier = Modifier.fillMaxSize().padding(padding),
          )
      else ->
          LazyColumn(
              modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
              contentPadding = PaddingValues(top = 16.dp, bottom = 96.dp),
              verticalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            item {
              YgdkSummaryCard(
                  summaryText = uiState.overview.summaryText(),
                  secondaryText = uiState.overview.weeklySummaryText(),
              )
            }
            item {
              Row(
                  modifier = Modifier.fillMaxWidth(),
                  horizontalArrangement = Arrangement.SpaceBetween,
                  verticalAlignment = Alignment.CenterVertically,
              ) {
                Text(
                    text = "打卡记录",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Button(onClick = onRefresh) { Text("刷新") }
              }
            }
            if (uiState.records.isEmpty()) {
              item { YgdkInlineMessage("暂时还没有打卡记录") }
            } else {
              items(uiState.records, key = { it.recordId }) { record ->
                YgdkRecordCard(record = record)
              }
            }
            if (uiState.hasMore) {
              item {
                Button(
                    onClick = onLoadMore,
                    enabled = !uiState.isLoadingMore,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                  Text(if (uiState.isLoadingMore) "加载中..." else "加载更多")
                }
              }
            }
          }
    }
  }
}

@Composable
private fun YgdkSummaryCard(
    summaryText: String,
    secondaryText: String?,
) {
  Card(
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
      modifier = Modifier.fillMaxWidth(),
  ) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text(
          text = summaryText,
          style = MaterialTheme.typography.headlineSmall,
          fontWeight = FontWeight.Bold,
      )
      secondaryText?.let {
        Text(
            text = it,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

@Composable
private fun YgdkRecordCard(record: YgdkRecordDto) {
  Card(modifier = Modifier.fillMaxWidth()) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.DirectionsRun, contentDescription = null)
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = record.itemName ?: "运动打卡",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
      }
      record.place?.let {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Icon(Icons.Default.Place, contentDescription = null)
          Spacer(modifier = Modifier.width(8.dp))
          Text(text = it, style = MaterialTheme.typography.bodyMedium)
        }
      }
      Text(
          text = record.displayTimeText(),
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Text(
          text =
              buildString {
                append(record.createdAtLabel ?: "提交时间未知")
                if (record.images.isNotEmpty()) append(" · ${record.images.size} 张图片")
                append(if (record.isOpen) " · 已分享" else " · 未分享")
              },
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
private fun YgdkFullPageMessage(
    message: String?,
    actionLabel: String,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
  Box(modifier = modifier, contentAlignment = Alignment.Center) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
      Text(text = message ?: "加载失败", color = MaterialTheme.colorScheme.error)
      Spacer(modifier = Modifier.height(12.dp))
      Button(onClick = onAction) { Text(actionLabel) }
    }
  }
}

@Composable
private fun YgdkInlineMessage(message: String) {
  Text(
      text = message,
      modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
      color = MaterialTheme.colorScheme.onSurfaceVariant,
  )
}

private fun YgdkOverviewResponse?.summaryText(): String {
  val summary = this?.summary
  val count = summary?.termCount ?: 0
  val target = summary?.termTarget
  return if (target != null && target > 0) "本学期认定次数 $count / $target" else "本学期认定次数 $count 次"
}

private fun YgdkOverviewResponse?.weeklySummaryText(): String? {
  val summary = this?.summary ?: return null
  val weekCount = summary.weekCount ?: return null
  return if (summary.weekTarget != null) "本周打卡 $weekCount / ${summary.weekTarget}"
  else "本周打卡 $weekCount 次"
}

private fun YgdkRecordDto.displayTimeText(): String {
  val start = startTime
  val end = endTime
  return when {
    !start.isNullOrBlank() && !end.isNullOrBlank() -> "$start - ${end.substringAfter(' ', end)}"
    !start.isNullOrBlank() -> start
    else -> "时间待定"
  }
}
