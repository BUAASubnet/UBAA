package cn.edu.ubaa.ui.screens.grade

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
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.Grade

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun GradeScreen(viewModel: GradeViewModel) {
  val uiState by viewModel.uiState.collectAsState()
  val pullRefreshState =
      rememberPullRefreshState(
          refreshing = uiState.isRefreshing,
          onRefresh = { viewModel.ensureLoaded(forceRefresh = true) },
      )

  Box(modifier = Modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    when {
      uiState.isLoading -> {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          CircularProgressIndicator()
        }
      }
      uiState.error != null -> {
        Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
          Text(text = "加载失败: ${uiState.error}", color = MaterialTheme.colorScheme.error)
        }
      }
      uiState.gradeData != null ->
          GradeList(
              grades = uiState.gradeData!!.grades,
              allGrades = uiState.termGrades.values.flatMap { it.grades },
              isSummaryLoading = uiState.isSummaryLoading,
          )
    }
    PullRefreshIndicator(
        refreshing = uiState.isRefreshing,
        state = pullRefreshState,
        modifier = Modifier.align(Alignment.TopCenter),
    )
  }
}

@Composable
private fun GradeList(
    grades: List<Grade>,
    allGrades: List<Grade>,
    isSummaryLoading: Boolean,
) {
  LazyColumn(
      contentPadding = PaddingValues(16.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    item {
      GradeSummaryCard(
          title = "全部成绩",
          statistics = calculateGradeStatistics(allGrades),
          showCourseAndCredits = false,
          isLoading = isSummaryLoading,
      )
    }
    item {
      GradeSummaryCard(
          title = "本学期",
          statistics = calculateGradeStatistics(grades),
          showCourseAndCredits = true,
      )
    }

    if (grades.isEmpty()) {
      item {
        Box(
            modifier = Modifier.fillMaxWidth().padding(32.dp),
            contentAlignment = Alignment.Center,
        ) {
          Text("暂无成绩", style = MaterialTheme.typography.bodyLarge)
        }
      }
    } else {
      items(grades) { grade -> GradeCard(grade = grade) }
    }
  }
}

@Composable
private fun GradeSummaryCard(
    title: String,
    statistics: GradeStatistics,
    showCourseAndCredits: Boolean,
    isLoading: Boolean = false,
) {
  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
  ) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
      if (showCourseAndCredits) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
          SummaryValue(
              label = "课程数",
              value = statistics.courseCount.toString(),
              modifier = Modifier.weight(1f),
          )
          SummaryValue(
              label = "总学分",
              value =
                  if (statistics.totalCredits > 0.0) formatNumber(statistics.totalCredits)
                  else "--",
              modifier = Modifier.weight(1f),
          )
        }
      }
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(16.dp),
      ) {
        SummaryValue(
            label = "GPA",
            value = if (isLoading) "统计中" else statistics.gpa?.let(::formatNumber) ?: "--",
            modifier = Modifier.weight(1f),
        )
        SummaryValue(
            label = "加权平均分",
            value =
                if (isLoading) "统计中" else statistics.weightedAverage?.let(::formatNumber) ?: "--",
            modifier = Modifier.weight(1f),
        )
      }
    }
  }
}

@Composable
private fun SummaryValue(label: String, value: String, modifier: Modifier = Modifier) {
  Column(modifier = modifier) {
    Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text(
        label,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
  }
}

@Composable
private fun GradeCard(grade: Grade) {
  OutlinedCard(modifier = Modifier.fillMaxWidth()) {
    Column(modifier = Modifier.padding(16.dp)) {
      Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(
            Icons.Default.Book,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = grade.courseName ?: "未命名课程",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f),
        )
        GradeBadge(score = grade.score)
      }

      Spacer(modifier = Modifier.height(10.dp))
      gradeDetailRows(grade).forEach { row ->
        GradeInfoRow(
            label = row.label,
            value = row.value,
            icon = if (row.label == "成绩类型") Icons.Default.Person else null,
        )
      }
    }
  }
}

internal data class GradeDetailRow(val label: String, val value: String)

internal fun gradeDetailRows(grade: Grade): List<GradeDetailRow> =
    listOf(
            "课程号" to grade.courseCode,
            "学分" to grade.credit?.let(::formatNumber),
            "课程属性" to grade.courseAttribute,
            "课程类别" to (grade.courseCategory ?: grade.courseGroup),
            "考试性质" to grade.examType,
            "考试类型" to grade.examAttempt,
            "成绩类型" to grade.recognitionType,
        )
        .mapNotNull { (label, value) ->
          value?.takeIf { it.isNotBlank() }?.let { GradeDetailRow(label, it) }
        }

@Composable
private fun GradeBadge(score: String?) {
  Card(
      colors =
          CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
  ) {
    Row(
        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
          Icons.Default.Grade,
          contentDescription = null,
          modifier = Modifier.width(16.dp),
          tint = MaterialTheme.colorScheme.onSecondaryContainer,
      )
      Spacer(modifier = Modifier.width(4.dp))
      Text(
          score?.takeIf { it.isNotBlank() } ?: "--",
          fontWeight = FontWeight.Bold,
          color = MaterialTheme.colorScheme.onSecondaryContainer,
      )
    }
  }
}

@Composable
private fun GradeInfoRow(
    label: String,
    value: String?,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
) {
  val displayValue = value?.takeIf { it.isNotBlank() } ?: return
  Row(
      modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    icon?.let {
      Icon(
          it,
          contentDescription = null,
          modifier = Modifier.width(16.dp),
          tint = MaterialTheme.colorScheme.outline,
      )
      Spacer(modifier = Modifier.width(6.dp))
    }
    Text(
        "$label：",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(displayValue, style = MaterialTheme.typography.bodyMedium)
  }
}

private fun formatNumber(value: Double): String {
  val rounded = kotlin.math.round(value * 100.0) / 100.0
  return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
}

internal data class GradeStatistics(
    val courseCount: Int,
    val totalCredits: Double,
    val gpa: Double?,
    val weightedAverage: Double?,
)

internal fun calculateGradeStatistics(grades: List<Grade>): GradeStatistics {
  var gpaWeightedTotal = 0.0
  var gpaCreditTotal = 0.0
  var scoreWeightedTotal = 0.0
  var scoreCreditTotal = 0.0

  grades.forEach { grade ->
    val credit = grade.credit?.takeIf { it > 0.0 } ?: return@forEach
    val score = grade.score?.trim()?.takeIf { it.isNotEmpty() } ?: return@forEach
    val points = score.toGradePoint() ?: return@forEach
    val numericScore = score.toWeightedAverageScore() ?: return@forEach

    gpaWeightedTotal += points * credit
    gpaCreditTotal += credit
    scoreWeightedTotal += numericScore * credit
    scoreCreditTotal += credit
  }

  return GradeStatistics(
      courseCount = grades.size,
      totalCredits = grades.mapNotNull { it.credit?.takeIf { credit -> credit > 0.0 } }.sum(),
      gpa = weightedValue(gpaWeightedTotal, gpaCreditTotal),
      weightedAverage = weightedValue(scoreWeightedTotal, scoreCreditTotal),
  )
}

private fun weightedValue(total: Double, credits: Double): Double? =
    if (credits > 0.0) kotlin.math.round((total / credits) * 100.0) / 100.0 else null

private fun String.toGradePoint(): Double? {
  val normalizedScore = normalizedLevelScore()
  return when (normalizedScore) {
    "优" -> 4.0
    "良" -> 3.5
    "中" -> 2.8
    "及格" -> 1.7
    "不及格" -> 0.0
    "通过",
    "不通过" -> null
    else -> {
      val numericScore = normalizedScore.toDoubleOrNull() ?: return null
      if (numericScore < 60.0) 0.0
      else 4.0 - (3.0 * (100.0 - numericScore) * (100.0 - numericScore) / 1600.0)
    }
  }
}

private fun String.toWeightedAverageScore(): Double? {
  return when (normalizedLevelScore()) {
    "优" -> 95.0
    "良" -> 85.0
    "中" -> 75.0
    "及格" -> 60.0
    "不及格" -> 0.0
    "通过",
    "不通过" -> null
    else -> toDoubleOrNull()
  }
}

private fun String.normalizedLevelScore(): String =
    when (this) {
      "优秀" -> "优"
      "良好" -> "良"
      "中等" -> "中"
      else -> this
    }
