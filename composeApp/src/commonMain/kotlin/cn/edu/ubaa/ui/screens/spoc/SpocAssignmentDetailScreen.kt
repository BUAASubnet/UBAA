package cn.edu.ubaa.ui.screens.spoc

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** SPOC 作业详情页。 */
@Composable
fun SpocAssignmentDetailScreen(
    viewModel: SpocViewModel,
    onRetry: () -> Unit,
) {
  val uiState by viewModel.uiState.collectAsState()
  val detail = uiState.assignmentDetail

  Scaffold(
      contentWindowInsets =
          WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
      floatingActionButton = {
        FloatingActionButton(onClick = onRetry) {
          Icon(Icons.Default.Refresh, contentDescription = "刷新")
        }
      },
  ) { padding ->
    when {
      uiState.isDetailLoading ->
          Box(
              modifier = Modifier.fillMaxSize().padding(padding),
              contentAlignment = Alignment.Center,
          ) {
            CircularProgressIndicator()
          }
      uiState.detailError != null ->
          Box(
              modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
              contentAlignment = Alignment.Center,
          ) {
            Text(text = uiState.detailError!!, color = MaterialTheme.colorScheme.error)
          }
      detail == null ->
          Box(
              modifier = Modifier.fillMaxSize().padding(padding),
              contentAlignment = Alignment.Center,
          ) {
            Text("暂无作业详情")
          }
      else ->
          Column(
              modifier =
                  Modifier.fillMaxSize()
                      .padding(padding)
                      .verticalScroll(rememberScrollState())
                      .padding(16.dp),
              verticalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors =
                    CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
            ) {
              Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                Text(
                    text = detail.title,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = detail.courseName,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (!detail.teacherName.isNullOrBlank()) {
                  Text(
                      text = "教师：${detail.teacherName}",
                      style = MaterialTheme.typography.bodyMedium,
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
              }
            }

            DetailInfoCard(
                title = "提交信息",
                lines =
                    buildList {
                      add("状态：${detail.submissionStatusText}")
                      add("开始时间：${detail.startTime ?: "未知"}")
                      add("截止时间：${detail.dueTime ?: "未知"}")
                      detail.score?.takeIf { it.isNotBlank() }?.let { add("分值：$it") }
                      detail.submittedAt?.takeIf { it.isNotBlank() }?.let { add("提交时间：$it") }
                    },
            )

            DetailInfoCard(
                title = "作业内容",
                lines = listOf(detail.contentPlainText ?: "暂无作业说明"),
            )
          }
    }
  }
}

@Composable
private fun DetailInfoCard(title: String, lines: List<String>) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      Text(
          text = title,
          style = MaterialTheme.typography.titleMedium,
          fontWeight = FontWeight.SemiBold,
      )
      lines.forEach {
        Text(
            text = it,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}
