package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.TodayClass
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.datetime.*

// 首页屏幕
@OptIn(ExperimentalTime::class)
@Composable
fun HomeScreen(
        todayClasses: List<TodayClass>,
        isLoading: Boolean,
        error: String?,
        onRefresh: () -> Unit,
        modifier: Modifier = Modifier,
) {
  Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
    // 顶部标题栏
    Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
              text = "今日课表",
              style = MaterialTheme.typography.headlineMedium,
              fontWeight = FontWeight.Bold,
      )

      // 获取当前日期
      val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
      val dateStr = "${today.monthNumber}月${today.dayOfMonth}日"
    }

    Spacer(modifier = Modifier.height(16.dp))

    when {
      isLoading -> {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(modifier = Modifier.height(8.dp))
            Text("加载中...")
          }
        }
      }
      error != null -> {
        Card(
                modifier = Modifier.fillMaxWidth(),
                colors =
                        CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer
                        ),
        ) {
          Column(
                  modifier = Modifier.padding(16.dp),
                  horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Text(
                    text = "加载失败",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                    text = error,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
            )
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = onRefresh) { Text("重试") }
          }
        }
      }
      todayClasses.isEmpty() -> {
        Card(
                modifier = Modifier.fillMaxWidth(),
                colors =
                        CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                        ),
        ) {
          Column(
                  modifier = Modifier.fillMaxWidth().padding(32.dp),
                  horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                    text = "今天没有课程安排",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = onRefresh) { Text("刷新") }
          }
        }
      }
      else -> {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          // 按开始时间排序课程
          val sortedClasses =
                  todayClasses.sortedBy { course ->
                    // 从 "14:00-15:35" 格式提取开始时间
                    val startTimeStr = course.time?.split("-")?.firstOrNull()
                    startTimeStr?.replace(":", "")?.toIntOrNull() ?: Int.MAX_VALUE // 无时间课程排在最后
                  }

          items(sortedClasses) { todayClass -> TodayClassCard(todayClass = todayClass) }

          // 底部刷新按钮
          item {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(onClick = onRefresh, modifier = Modifier.fillMaxWidth()) { Text("刷新") }
          }
        }
      }
    }
  }
}

@Composable
private fun TodayClassCard(todayClass: TodayClass, modifier: Modifier = Modifier) {
  Card(
          modifier = modifier.fillMaxWidth(),
          colors =
                  CardDefaults.cardColors(
                          containerColor = MaterialTheme.colorScheme.surfaceVariant
                  ),
  ) {
    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
      Text(
              text = todayClass.bizName,
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.Bold,
      )

      Spacer(modifier = Modifier.height(8.dp))

      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column {
          todayClass.time?.let { time ->
            Text(
                    text = "时间：$time",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }

          todayClass.place?.let { place ->
            Text(
                    text = "地点：$place",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }

        todayClass.shortName?.let { shortName ->
          Card(
                  colors =
                          CardDefaults.cardColors(
                                  containerColor = MaterialTheme.colorScheme.primaryContainer
                          )
          ) {
            Text(
                    text = shortName,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            )
          }
        }
      }
    }
  }
}
