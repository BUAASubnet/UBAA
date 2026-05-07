package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentTurnedIn
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.School
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.TodayClass
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalTime::class, ExperimentalMaterialApi::class)
@Composable
internal fun HomeScreen(
    todayClasses: List<TodayClass>,
    isLoading: Boolean,
    isRefreshing: Boolean,
    error: String?,
    todoItems: List<HomeTodoItem>,
    todoLoading: Boolean,
    todoLoadingSources: List<HomeTodoSource>,
    todoFailedSources: List<HomeTodoSource>,
    signingTodoId: String?,
    onRetrySchedule: () -> Unit,
    onRefresh: () -> Unit,
    onTodoClick: (HomeTodoItem) -> Unit,
    onSigninTodoClick: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
  val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
  val pullRefreshState = rememberPullRefreshState(refreshing = isRefreshing, onRefresh = onRefresh)
  val todoLoadingSummary = todoLoadingSources.joinToString("、") { it.label }
  val sortedClasses =
      todayClasses.sortedBy { course ->
        course.time?.split("-")?.firstOrNull()?.replace(":", "")?.toIntOrNull() ?: Int.MAX_VALUE
      }

  Box(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      item {
        Column(modifier = Modifier.padding(top = 16.dp)) {
          Row(
              horizontalArrangement = Arrangement.spacedBy(8.dp),
              verticalAlignment = Alignment.CenterVertically,
          ) {
            Text(
                text = "今日课表",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            if (isLoading && sortedClasses.isEmpty()) {
              HomeSectionLoadingChip(text = "加载中")
            }
          }
          Spacer(modifier = Modifier.height(4.dp))
          Text(
              text = "${today.month.ordinal + 1}月${today.day}日",
              style = MaterialTheme.typography.bodyMedium,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      when {
        error != null && sortedClasses.isEmpty() ->
            item { HomeErrorCard(message = error, onRetry = onRetrySchedule) }
        isLoading && sortedClasses.isEmpty() ->
            item {
              HomeLoadingCard(
                  title = "今日课表正在后台加载",
                  subtitle = "课程安排会在这里补齐，不影响先浏览首页其他内容。",
              )
            }
        sortedClasses.isEmpty() && !isLoading ->
            item { HomeEmptyCard(title = "今天没有课程安排", subtitle = "今天可以安心处理其他事项。") }
        else -> items(sortedClasses) { todayClass -> TodayClassCard(todayClass = todayClass) }
      }

      item {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Column {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
              Text(
                  text = "待办区",
                  style = MaterialTheme.typography.titleLarge,
                  fontWeight = FontWeight.Bold,
              )
              if (todoLoading) {
                HomeSectionLoadingChip(text = "后台加载中")
              }
            }
            Text(
                text =
                    if (todoLoadingSummary.isNotBlank()) {
                      "正在加载 $todoLoadingSummary"
                    } else {
                      "聚合近期需要处理的课程和任务"
                    },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
      }

      if (todoFailedSources.isNotEmpty()) {
        item {
          HomeInfoBanner(
              message = "部分内容加载失败：${todoFailedSources.joinToString("、") { it.label }}，已显示其余待办。",
          )
        }
      }

      if (todoItems.isEmpty() && !todoLoading) {
        item { HomeEmptyCard(title = "当前没有待办", subtitle = "近期事项都处理得很干净。") }
      } else if (todoItems.isEmpty()) {
        item {
          HomeLoadingCard(
              title = "待办正在后台加载",
              subtitle =
                  if (todoLoadingSummary.isNotBlank()) {
                    "正在同步 $todoLoadingSummary 的数据。"
                  } else {
                    "待办数据会在这里逐步补齐。"
                  },
          )
        }
      } else {
        items(todoItems) { todoItem ->
          HomeTodoCard(
              item = todoItem,
              isSigning = signingTodoId == todoItem.id,
              onClick = { onTodoClick(todoItem) },
              onSigninClick = { courseId -> onSigninTodoClick(courseId) },
          )
        }
      }

      item { Spacer(modifier = Modifier.height(16.dp)) }
    }

    PullRefreshIndicator(
        refreshing = isRefreshing,
        state = pullRefreshState,
        modifier = Modifier.align(Alignment.TopCenter),
    )
  }
}

@Composable
private fun HomeSectionLoadingChip(text: String) {
  Surface(
      color = MaterialTheme.colorScheme.primaryContainer,
      contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
      shape = MaterialTheme.shapes.small,
  ) {
    Row(
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 2.dp)
      Text(text = text, style = MaterialTheme.typography.labelSmall)
    }
  }
}

@Composable
private fun HomeLoadingCard(title: String, subtitle: String) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.5.dp)
      Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

@Composable
private fun TodayClassCard(todayClass: TodayClass, modifier: Modifier = Modifier) {
  Card(
      modifier = modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
      Text(
          text = todayClass.bizName,
          style = MaterialTheme.typography.titleMedium,
          fontWeight = FontWeight.Bold,
      )

      Spacer(modifier = Modifier.height(8.dp))

      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(modifier = Modifier.weight(1f)) {
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
          Surface(
              color = MaterialTheme.colorScheme.primaryContainer,
              contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
              shape = MaterialTheme.shapes.small,
          ) {
            Text(
                text = shortName,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            )
          }
        }
      }
    }
  }
}

@Composable
private fun HomeTodoCard(
    item: HomeTodoItem,
    isSigning: Boolean,
    onClick: () -> Unit,
    onSigninClick: (String) -> Unit,
) {
  val isSigninItem = item.action is HomeTodoAction.SigninCourse
  Card(
      modifier =
          Modifier.fillMaxWidth()
              .then(if (isSigninItem) Modifier else Modifier.clickable(onClick = onClick)),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
      elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Surface(
          color = sourceContainerColor(item.source),
          contentColor = sourceContentColor(item.source),
          shape = MaterialTheme.shapes.medium,
      ) {
        Box(
            modifier = Modifier.size(44.dp),
            contentAlignment = Alignment.Center,
        ) {
          Icon(
              imageVector = sourceIcon(item.source),
              contentDescription = item.source.label,
              modifier = Modifier.size(22.dp),
          )
        }
      }

      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          TodoChip(
              text = item.source.label,
              color = sourceContainerColor(item.source),
              contentColor = sourceContentColor(item.source),
          )
          TodoChip(
              text = item.statusLabel,
              color = MaterialTheme.colorScheme.secondaryContainer,
              contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
          )
        }

        Text(
            text = item.title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = item.subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = item.timeLabel,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
      }

      if (item.action is HomeTodoAction.SigninCourse) {
        Button(
            onClick = { onSigninClick(item.action.courseId) },
            enabled = !isSigning,
        ) {
          if (isSigning) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp,
            )
          } else {
            Text("签到")
          }
        }
      } else {
        Icon(
            imageVector = Icons.Default.Info,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

@Composable
private fun HomeErrorCard(message: String, onRetry: () -> Unit) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Text(
          text = "课表加载失败",
          style = MaterialTheme.typography.titleMedium,
          color = MaterialTheme.colorScheme.onErrorContainer,
      )
      Spacer(modifier = Modifier.height(6.dp))
      Text(
          text = message,
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onErrorContainer,
      )
      Spacer(modifier = Modifier.height(10.dp))
      TextButton(onClick = onRetry) { Text("重试") }
    }
  }
}

@Composable
private fun HomeEmptyCard(title: String, subtitle: String) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Icon(
          imageVector = Icons.Default.Schedule,
          contentDescription = null,
          modifier = Modifier.size(36.dp),
          tint = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Text(text = title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
      Text(
          text = subtitle,
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
private fun HomeInfoBanner(message: String) {
  Surface(
      modifier = Modifier.fillMaxWidth(),
      color = MaterialTheme.colorScheme.tertiaryContainer,
      contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
      shape = MaterialTheme.shapes.medium,
  ) {
    Text(
        text = message,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
    )
  }
}

@Composable
private fun TodoChip(text: String, color: Color, contentColor: Color) {
  Surface(color = color, contentColor = contentColor, shape = MaterialTheme.shapes.small) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
    )
  }
}

@Composable
private fun sourceContainerColor(source: HomeTodoSource): Color =
    when (source) {
      HomeTodoSource.BYKC -> MaterialTheme.colorScheme.primaryContainer
      HomeTodoSource.SPOC -> MaterialTheme.colorScheme.tertiaryContainer
      HomeTodoSource.JUDGE -> MaterialTheme.colorScheme.primaryContainer
      HomeTodoSource.CGYY -> MaterialTheme.colorScheme.secondaryContainer
      HomeTodoSource.SIGNIN -> MaterialTheme.colorScheme.errorContainer
    }

@Composable
private fun sourceContentColor(source: HomeTodoSource): Color =
    when (source) {
      HomeTodoSource.BYKC -> MaterialTheme.colorScheme.onPrimaryContainer
      HomeTodoSource.SPOC -> MaterialTheme.colorScheme.onTertiaryContainer
      HomeTodoSource.JUDGE -> MaterialTheme.colorScheme.onPrimaryContainer
      HomeTodoSource.CGYY -> MaterialTheme.colorScheme.onSecondaryContainer
      HomeTodoSource.SIGNIN -> MaterialTheme.colorScheme.onErrorContainer
    }

private fun sourceIcon(source: HomeTodoSource): ImageVector =
    when (source) {
      HomeTodoSource.BYKC -> Icons.Default.School
      HomeTodoSource.SPOC -> Icons.Default.AssignmentTurnedIn
      HomeTodoSource.JUDGE -> Icons.Default.Code
      HomeTodoSource.CGYY -> Icons.Default.MeetingRoom
      HomeTodoSource.SIGNIN -> Icons.Default.CheckCircle
    }
