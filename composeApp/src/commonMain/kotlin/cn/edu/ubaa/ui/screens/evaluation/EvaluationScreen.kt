package cn.edu.ubaa.ui.screens.evaluation

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.evaluation.EvaluationCourse

/**
 * 自动评教功能的主屏幕组件。 展示待评教课程列表，允许用户选择部分课程并一键执行自动评教。 在评教过程中展示进度条，完成后展示结果汇总。
 *
 * @param viewModel 负责评教业务逻辑的 ViewModel。
 */
@Composable
fun EvaluationScreen(viewModel: EvaluationViewModel) {
  val uiState by viewModel.uiState.collectAsState()

  Scaffold(
      contentWindowInsets =
          WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
      floatingActionButton = {
        // 仅当有选中的未评教课程且未在加载/提交时显示执行按钮
        val hasSelectedPending = uiState.courses.any { it.second && !it.first.isEvaluated }
        if (hasSelectedPending && !uiState.isLoading && !uiState.isSubmitting) {
          ExtendedFloatingActionButton(
              onClick = { viewModel.submitEvaluations() },
              icon = { Icon(Icons.Default.PlayArrow, null) },
              text = { Text("一键评教") },
              containerColor = MaterialTheme.colorScheme.primaryContainer,
              contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
          )
        }
      },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
      Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        // Text(
        //         text = "自动评教",
        //         style = MaterialTheme.typography.headlineSmall,
        //         fontWeight = FontWeight.Bold,
        //         modifier = Modifier.padding(bottom = 8.dp)
        // )
        Text(
            text = "勾选需要自动评教的课程,默认全选。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 16.dp),
        )

        // 评教进度卡片
        if (!uiState.isLoading && uiState.progress.totalCourses > 0) {
          EvaluationProgressCard(
              progress = uiState.progress,
              modifier = Modifier.padding(bottom = 16.dp),
          )
        }

        if (uiState.isLoading) {
          Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
          }
        } else if (uiState.error != null && uiState.courses.isEmpty()) {
          // 错误提示与重试
          Column(
              modifier = Modifier.fillMaxSize(),
              verticalArrangement = Arrangement.Center,
              horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Text(uiState.error!!, style = MaterialTheme.typography.bodyLarge)
            Button(
                onClick = { viewModel.loadPendingCourses() },
                modifier = Modifier.padding(top = 16.dp),
            ) {
              Icon(Icons.Default.Refresh, null)
              Spacer(Modifier.width(8.dp))
              Text("重试")
            }
          }
        } else {
          // 课程列表
          LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(uiState.courses) { (course, isSelected) ->
              EvaluationCourseItem(
                  course = course,
                  isSelected = isSelected,
                  onToggle = { viewModel.toggleCourseSelection(course) },
              )
            }
          }
        }
      }

      // 提交中遮罩与进度条
      if (uiState.isSubmitting) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black.copy(alpha = 0.5f), // 加深背景遮罩以便更清晰地显示进度
        ) {
          Column(
              horizontalAlignment = Alignment.CenterHorizontally,
              verticalArrangement = Arrangement.Center,
              modifier = Modifier.padding(32.dp),
          ) {
            val progress =
                if (uiState.progressTotal > 0)
                    uiState.progressCurrent.toFloat() / uiState.progressTotal.toFloat()
                else 0f

            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(8.dp),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            Text(
                "正在评教: ${uiState.progressCurrent}/${uiState.progressTotal}",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleMedium,
            )
            Spacer(Modifier.height(8.dp))
            Text("请勿关闭应用，稍候...", color = Color.White.copy(alpha = 0.8f))
          }
        }
      }

      // 结果对话框
      if (uiState.submissionResults.isNotEmpty() && !uiState.isSubmitting) {
        AlertDialog(
            onDismissRequest = { viewModel.clearResults() },
            title = { Text("评教完成") },
            text = {
              LazyColumn(modifier = Modifier.heightIn(max = 400.dp)) {
                items(uiState.submissionResults) { result ->
                  Row(
                      modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                      verticalAlignment = Alignment.CenterVertically,
                  ) {
                    Icon(
                        imageVector =
                            if (result.success) Icons.Default.Check else Icons.Default.Error,
                        contentDescription = null,
                        tint =
                            if (result.success) Color(0xFF4CAF50)
                            else MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Column {
                      Text(
                          result.courseName,
                          style = MaterialTheme.typography.bodyMedium,
                          fontWeight = FontWeight.Bold,
                      )
                      Text(result.message, style = MaterialTheme.typography.bodySmall)
                    }
                  }
                }
              }
            },
            confirmButton = {
              TextButton(
                  onClick = {
                    viewModel.clearResults()
                    viewModel.loadPendingCourses()
                  }
              ) {
                Text("确定")
              }
            },
        )
      }
    }
  }
}

/**
 * 单个课程列表项组件。
 *
 * @param course 课程信息。
 * @param isSelected 课程是否被勾选。
 * @param onToggle 切换勾选状态的回调。
 */
@Composable
fun EvaluationCourseItem(course: EvaluationCourse, isSelected: Boolean, onToggle: () -> Unit) {
  val isEvaluated = course.isEvaluated

  Card(
      modifier =
          Modifier.fillMaxWidth()
              .padding(vertical = 4.dp)
              .alpha(if (isEvaluated) 0.6f else 1f)
              .then(if (!isEvaluated) Modifier.clickable { onToggle() } else Modifier),
      colors =
          CardDefaults.cardColors(
              containerColor =
                  when {
                    isEvaluated -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                    isSelected -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                    else -> MaterialTheme.colorScheme.surfaceVariant
                  }
          ),
  ) {
    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
      if (isEvaluated) {
        // 已评教：显示完成图标
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = "已完成",
            tint = Color(0xFF4CAF50),
            modifier = Modifier.size(24.dp),
        )
      } else {
        // 未评教：显示可选复选框
        Checkbox(checked = isSelected, onCheckedChange = { onToggle() })
      }
      Spacer(Modifier.width(12.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
            course.kcmc,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color =
                if (isEvaluated) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                else MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "教师: ${course.bpmc}",
            style = MaterialTheme.typography.bodySmall,
            color =
                if (isEvaluated) MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                else MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      if (isEvaluated) {
        Text("已评教", style = MaterialTheme.typography.labelSmall, color = Color(0xFF4CAF50))
      }
    }
  }
}

/** 评教进度卡片组件。 显示评教完成进度。 */
@Composable
fun EvaluationProgressCard(
    progress: cn.edu.ubaa.model.evaluation.EvaluationProgress,
    modifier: Modifier = Modifier,
) {
  Card(
      modifier = modifier.fillMaxWidth(),
      colors =
          CardDefaults.cardColors(
              containerColor =
                  if (progress.isCompleted) Color(0xFF4CAF50).copy(alpha = 0.15f)
                  else MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
          ),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
            text = if (progress.isCompleted) "🎉 评教已完成" else "📊 评教进度",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = "${progress.evaluatedCourses}/${progress.totalCourses}",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color =
                if (progress.isCompleted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary,
        )
      }
      Spacer(Modifier.height(8.dp))
      LinearProgressIndicator(
          progress = { progress.progressPercent / 100f },
          modifier = Modifier.fillMaxWidth().height(8.dp),
          color =
              if (progress.isCompleted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary,
          trackColor = MaterialTheme.colorScheme.surfaceVariant,
      )
      Spacer(Modifier.height(8.dp))
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            text = "已完成 ${progress.evaluatedCourses} 门",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF4CAF50),
        )
        Text(
            text = "待评教 ${progress.pendingCourses} 门",
            style = MaterialTheme.typography.bodySmall,
            color =
                if (progress.pendingCourses > 0) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}
