package cn.edu.ubaa.ui.screens.judge

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus

/** 希冀作业列表页。 */
@OptIn(ExperimentalMaterialApi::class)
@Composable
fun JudgeAssignmentsScreen(
    viewModel: JudgeViewModel,
    onAssignmentClick: (JudgeAssignmentSummaryDto) -> Unit,
) {
  val uiState by viewModel.uiState.collectAsState()
  val groupedAssignments = uiState.visibleAssignments.groupBy { it.courseName }
  val pullRefreshState =
      rememberPullRefreshState(
          refreshing = uiState.isRefreshing,
          onRefresh = { viewModel.loadAssignments(refresh = true) },
      )
  var showSearchDialog by remember { mutableStateOf(false) }

  if (showSearchDialog) {
    SearchJudgeAssignmentsDialog(
        initialQuery = uiState.searchQuery,
        onDismiss = { showSearchDialog = false },
        onApply = { query ->
          viewModel.setSearchQuery(query)
          showSearchDialog = false
        },
        onClear = {
          viewModel.setSearchQuery("")
          showSearchDialog = false
        },
    )
  }

  Scaffold(
      contentWindowInsets =
          WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
      floatingActionButton = {
        FloatingActionButton(onClick = { showSearchDialog = true }) {
          Icon(Icons.Default.Search, contentDescription = "搜索")
        }
      },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding).pullRefresh(pullRefreshState)) {
      when {
        uiState.isLoading && uiState.assignmentsResponse == null ->
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
              CircularProgressIndicator()
            }
        uiState.error != null && uiState.assignmentsResponse == null ->
            Box(
                modifier = Modifier.fillMaxSize().padding(16.dp),
                contentAlignment = Alignment.Center,
            ) {
              Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = uiState.error!!, color = MaterialTheme.colorScheme.error)
                Spacer(modifier = Modifier.height(12.dp))
                Button(onClick = { viewModel.loadAssignments() }) { Text("重试") }
              }
            }
        groupedAssignments.isEmpty() && uiState.isEnrichingAssignments ->
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
              Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(12.dp))
                Text("正在加载希冀作业详情")
              }
            }
        groupedAssignments.isEmpty() ->
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
              Text("暂无符合条件的希冀作业")
            }
        else ->
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
              groupedAssignments.forEach { (courseName, assignments) ->
                item {
                  Text(
                      text = courseName,
                      style = MaterialTheme.typography.titleMedium,
                      fontWeight = FontWeight.SemiBold,
                  )
                }

                items(assignments) { assignment ->
                  JudgeAssignmentCard(
                      assignment = assignment,
                      onClick = { onAssignmentClick(assignment) },
                  )
                }
              }
            }
      }

      PullRefreshIndicator(
          refreshing = uiState.isRefreshing,
          state = pullRefreshState,
          modifier = Modifier.align(Alignment.TopCenter),
          backgroundColor = MaterialTheme.colorScheme.surface,
          contentColor = MaterialTheme.colorScheme.primary,
          scale = true,
      )
    }
  }
}

@Composable
private fun SearchJudgeAssignmentsDialog(
    initialQuery: String,
    onDismiss: () -> Unit,
    onApply: (String) -> Unit,
    onClear: () -> Unit,
) {
  var query by remember(initialQuery) { mutableStateOf(initialQuery) }

  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text("搜索作业") },
      text = {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text("课程名称或作业标题") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
      },
      confirmButton = { TextButton(onClick = { onApply(query) }) { Text("搜索") } },
      dismissButton = {
        TextButton(
            onClick = {
              if (initialQuery.isNotBlank()) {
                onClear()
              } else {
                onDismiss()
              }
            }
        ) {
          Text(if (initialQuery.isNotBlank()) "清空" else "取消")
        }
      },
  )
}

@Composable
private fun JudgeAssignmentCard(
    assignment: JudgeAssignmentSummaryDto,
    onClick: () -> Unit,
) {
  Card(
      onClick = onClick,
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
            text = assignment.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f),
        )
        if (assignment.shouldShowJudgeSummaryStatus()) {
          ElevatedAssistChip(
              onClick = onClick,
              label = { Text(assignment.submissionStatusText) },
          )
        }
      }

      val infoLines = assignment.judgeSummaryInfoLines()
      if (infoLines.isNotEmpty()) {
        Spacer(modifier = Modifier.height(8.dp))

        infoLines.forEach { line ->
          Text(
              text = line,
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }
    }
  }
}

internal fun JudgeAssignmentSummaryDto.shouldShowJudgeSummaryStatus(): Boolean =
    submissionStatus != JudgeSubmissionStatus.UNKNOWN && submissionStatusText.isNotBlank()

internal fun JudgeAssignmentSummaryDto.judgeSummaryInfoLines(): List<String> = buildList {
  startTime?.takeIf { it.isNotBlank() }?.let { add("开始：$it") }
  dueTime?.takeIf { it.isNotBlank() }?.let { add("截止：$it") }
  if (totalProblems > 0) {
    add("进度：$submittedCount/$totalProblems")
  }
  maxScore
      ?.takeIf { it.isNotBlank() }
      ?.let { maxScore ->
        val scoreText = myScore?.takeIf { it.isNotBlank() } ?: "无"
        add("分数：$scoreText / $maxScore")
      }
}
