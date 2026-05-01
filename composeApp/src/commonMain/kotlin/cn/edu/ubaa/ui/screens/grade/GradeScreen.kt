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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.Person
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

@Composable
fun GradeScreen(viewModel: GradeViewModel) {
  val uiState by viewModel.uiState.collectAsState()

  Box(modifier = Modifier.fillMaxSize()) {
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
      uiState.gradeData != null -> GradeList(grades = uiState.gradeData!!.grades)
    }
  }
}

@Composable
private fun GradeList(grades: List<Grade>) {
  LazyColumn(
      contentPadding = PaddingValues(16.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    item { GradeSummaryCard(grades = grades) }

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
private fun GradeSummaryCard(grades: List<Grade>) {
  val totalCredits = grades.mapNotNull { it.credit }.sum()
  val averageScore =
      grades.mapNotNull { it.score?.toDoubleOrNull() }.takeIf { it.isNotEmpty() }?.average()

  Card(
      modifier = Modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
  ) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text("成绩概览", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
      Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        SummaryValue(label = "课程数", value = grades.size.toString())
        SummaryValue(
            label = "总学分",
            value = if (totalCredits > 0.0) formatNumber(totalCredits) else "--",
        )
        SummaryValue(label = "均分", value = averageScore?.let(::formatNumber) ?: "--")
      }
    }
  }
}

@Composable
private fun SummaryValue(label: String, value: String) {
  Column {
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
      GradeInfoRow(label = "课程号", value = grade.courseCode)
      GradeInfoRow(label = "学分", value = grade.credit?.let(::formatNumber))
      GradeInfoRow(label = "绩点", value = grade.gradePoint)
      GradeInfoRow(label = "课程属性", value = grade.courseAttribute)
      GradeInfoRow(label = "课程类别", value = grade.courseCategory ?: grade.courseGroup)
      GradeInfoRow(label = "考试性质", value = grade.examType)
      GradeInfoRow(label = "考试类型", value = grade.examAttempt)
      GradeInfoRow(label = "成绩认定", value = grade.recognitionType, icon = Icons.Default.Person)
    }
  }
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
