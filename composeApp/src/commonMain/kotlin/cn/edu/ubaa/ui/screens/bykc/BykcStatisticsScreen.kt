package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcCategoryStatisticsDto

@Composable
fun BykcStatisticsScreen(viewModel: BykcViewModel) {
  val uiState by viewModel.statisticsState.collectAsState()

  if (uiState.isLoading) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      CircularProgressIndicator()
    }
    return
  }

  if (uiState.error != null) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      Text("加载失败: ${uiState.error}", color = MaterialTheme.colorScheme.error)
    }
    return
  }

  val stats = uiState.statistics ?: return

  LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
    // 累计有效计数卡片
    item {
      Card(
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
        colors =
          CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
      ) {
        Column(
          modifier = Modifier.padding(16.dp).fillMaxWidth(),
          horizontalAlignment = Alignment.CenterHorizontally,
        ) {
          Text(
            text = "总体净有效次数",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
          )
          Text(
            text = "${stats.totalValidCount}",
            style = MaterialTheme.typography.displayLarge,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontWeight = FontWeight.Bold,
          )
        }
      }
    }

    // 统计报表
    item {
      Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
      ) {
        Column {
          // 表头
          Row(
            modifier =
              Modifier.fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
          ) {
            Text(
              text = "课程小类",
              modifier = Modifier.weight(1.5f),
              fontWeight = FontWeight.Bold,
              style = MaterialTheme.typography.bodyMedium,
            )
            Text(
              text = "通过/指标",
              modifier = Modifier.weight(1f),
              fontWeight = FontWeight.Bold,
              textAlign = TextAlign.Center,
              style = MaterialTheme.typography.bodyMedium,
            )
            Text(
              text = "达标情况",
              modifier = Modifier.weight(1f),
              fontWeight = FontWeight.Bold,
              textAlign = TextAlign.End,
              style = MaterialTheme.typography.bodyMedium,
            )
          }

          HorizontalDivider()

          Column {
            stats.categories.forEach { category ->
              BykcStatRow(category)
              HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
            }
          }
        }
      }
    }
  }
}

@Composable
fun BykcStatRow(category: BykcCategoryStatisticsDto) {
  Row(
    modifier = Modifier.fillMaxWidth().padding(12.dp),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(modifier = Modifier.weight(1.5f)) {
      Text(
        text = category.subCategoryName,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
      )
      Text(
        text = category.categoryName,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }

    Text(
      text = "${category.passedCount} / ${category.requiredCount}",
      modifier = Modifier.weight(1f),
      textAlign = TextAlign.Center,
      style = MaterialTheme.typography.bodyMedium,
    )

    Row(
      modifier = Modifier.weight(1f),
      horizontalArrangement = Arrangement.End,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      if (category.isQualified) {
        Icon(
          imageVector = Icons.Default.CheckCircle,
          contentDescription = "达标",
          tint = MaterialTheme.colorScheme.primary,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
          text = "达标",
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.primary,
        )
      } else {
        Icon(
          imageVector = Icons.Default.Warning,
          contentDescription = "未达标",
          tint = MaterialTheme.colorScheme.error,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
          text = "未达标",
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.error,
        )
      }
    }
  }
}
