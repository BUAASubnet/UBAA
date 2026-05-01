package cn.edu.ubaa.ui.screens.judge

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material3.ElevatedAssistChip
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
import cn.edu.ubaa.model.dto.JudgeProblemDto

/** 希冀作业详情页。 */
@Composable
fun JudgeAssignmentDetailScreen(
    viewModel: JudgeViewModel,
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
              }
            }

            DetailInfoCard(
                title = "提交信息",
                lines =
                    buildList {
                      add("状态：${detail.submissionStatusText}")
                      add("开始时间：${detail.startTime ?: "未知"}")
                      add("截止时间：${detail.dueTime ?: "未知"}")
                      if (detail.totalProblems > 0) {
                        add("进度：${detail.submittedCount}/${detail.totalProblems}")
                      }
                      detail.maxScore
                          ?.takeIf { it.isNotBlank() }
                          ?.let { maxScore ->
                            val scoreText = detail.myScore?.takeIf { it.isNotBlank() } ?: "无"
                            add("分数：$scoreText / $maxScore")
                          }
                    },
            )

            DetailInfoCard(
                title = "题目明细",
                lines = if (detail.problems.isEmpty()) listOf("暂无题目明细") else emptyList(),
            )

            detail.problems.forEach { problem -> JudgeProblemCard(problem) }
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

@Composable
private fun JudgeProblemCard(problem: JudgeProblemDto) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
            text = problem.name,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
        )
        ElevatedAssistChip(onClick = {}, label = { Text(problem.statusText) })
      }

      problem.maxScore
          ?.takeIf { it.isNotBlank() }
          ?.let { maxScore ->
            val scoreText = problem.score?.takeIf { it.isNotBlank() } ?: "无"
            Text(
                text = "分数：$scoreText / $maxScore",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
    }
  }
}
