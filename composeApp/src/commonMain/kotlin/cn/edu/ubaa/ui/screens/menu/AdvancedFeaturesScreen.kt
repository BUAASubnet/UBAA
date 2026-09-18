package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentTurnedIn
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

internal data class AdvancedFeatureItem(
    val id: String,
    val title: String,
    val description: String,
    val icon: ImageVector,
)

internal fun advancedFeatureItems(): List<AdvancedFeatureItem> =
    listOf(
        AdvancedFeatureItem(
            id = "ihome",
            title = "iHome",
            description = "校园诉求、回复与关注",
            icon = Icons.Default.Forum,
        ),
        AdvancedFeatureItem(
            id = "cgyy",
            title = "研讨室预约",
            description = "查询、提交和管理研讨室预约",
            icon = Icons.Default.DateRange,
        ),
        AdvancedFeatureItem(
            id = "ygdk",
            title = "阳光打卡",
            description = "查看记录并提交体育活动打卡",
            icon = Icons.Default.WbSunny,
        ),
        AdvancedFeatureItem(
            id = "evaluation",
            title = "自动评教",
            description = "一键完成学期末评教任务",
            icon = Icons.Default.AssignmentTurnedIn,
        ),
        AdvancedFeatureItem(
            id = "more",
            title = "更多功能",
            description = "更多高级功能正在开发中...",
            icon = Icons.Default.MoreHoriz,
        ),
    )

@Composable
fun AdvancedFeaturesScreen(
    onCgyyClick: () -> Unit,
    onEvaluationClick: () -> Unit,
    onYgdkClick: () -> Unit,
    onIhomeClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val features = advancedFeatureItems()

  Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      items(features) { feature ->
        AdvancedFeatureCard(
            feature = feature,
            onClick = {
              when (feature.id) {
                "ihome" -> onIhomeClick()
                "cgyy" -> onCgyyClick()
                "ygdk" -> onYgdkClick()
                "evaluation" -> onEvaluationClick()
              }
            },
        )
      }
    }
  }
}

@Composable
private fun AdvancedFeatureCard(
    feature: AdvancedFeatureItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  Card(
      modifier = modifier.fillMaxWidth().heightIn(min = 160.dp).clickable { onClick() },
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
      elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
  ) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Icon(
          imageVector = feature.icon,
          contentDescription = null,
          modifier = Modifier.size(48.dp),
          tint = MaterialTheme.colorScheme.primary,
      )
      Spacer(modifier = Modifier.height(12.dp))
      Text(
          text = feature.title,
          style = MaterialTheme.typography.titleMedium,
          fontWeight = FontWeight.Bold,
          textAlign = TextAlign.Center,
      )
      Spacer(modifier = Modifier.height(4.dp))
      Text(
          text = feature.description,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          textAlign = TextAlign.Center,
          lineHeight = MaterialTheme.typography.bodySmall.lineHeight,
      )
    }
  }
}
