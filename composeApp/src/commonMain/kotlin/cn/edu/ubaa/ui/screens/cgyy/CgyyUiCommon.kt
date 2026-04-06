package cn.edu.ubaa.ui.screens.cgyy

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.CgyyOrderDisplayColor
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.canCancelAt
import cn.edu.ubaa.model.dto.displayReservationDateText
import cn.edu.ubaa.model.dto.displayStatus
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

internal fun shouldShowCancelAction(order: CgyyOrderDto): Boolean = order.canCancelAt()

@Composable
internal fun CgyyOrderDisplayColor.toComposeColor(): Color =
    when (this) {
      CgyyOrderDisplayColor.SUCCESS -> Color(0xFF95C700)
      CgyyOrderDisplayColor.ERROR -> Color(0xFFFA4D4D)
      CgyyOrderDisplayColor.INFO -> Color(0xFF62B0EE)
      CgyyOrderDisplayColor.NEUTRAL -> MaterialTheme.colorScheme.onSurfaceVariant
    }

@Composable
internal fun CgyyMessageBanner(message: String, modifier: Modifier = Modifier) {
  Surface(
      modifier = modifier.fillMaxWidth(),
      color = MaterialTheme.colorScheme.primaryContainer,
      contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
  ) {
    Text(
        text = message,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        style = MaterialTheme.typography.bodyMedium,
        textAlign = TextAlign.Center,
    )
  }
}

@Composable
internal fun CgyySectionCard(
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
  Card(
      modifier = modifier.fillMaxWidth(),
      colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
      elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
      if (!subtitle.isNullOrBlank()) {
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      content()
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CgyyChipFlowRow(content: @Composable () -> Unit) {
  FlowRow(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp),
      content = { content() },
  )
}

@Composable
internal fun CgyyLoadingState(message: String, modifier: Modifier = Modifier) {
  Column(
      modifier = modifier.fillMaxSize().padding(24.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.Center,
  ) {
    CircularProgressIndicator()
    Spacer(modifier = Modifier.height(12.dp))
    Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
  }
}

@Composable
internal fun CgyyErrorState(message: String?, onRetry: () -> Unit, modifier: Modifier = Modifier) {
  Column(
      modifier = modifier.fillMaxSize().padding(24.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.Center,
  ) {
    Icon(
        imageVector = Icons.Default.Info,
        contentDescription = null,
        modifier = Modifier.size(36.dp),
        tint = MaterialTheme.colorScheme.error,
    )
    Spacer(modifier = Modifier.height(12.dp))
    Text(
        text = message ?: "发生错误",
        color = MaterialTheme.colorScheme.error,
        textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(16.dp))
    Button(onClick = onRetry) { Text("重试") }
  }
}

@Composable
internal fun CgyyToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
  Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(label, modifier = Modifier.weight(1f))
    Switch(checked = checked, onCheckedChange = onCheckedChange)
  }
}

@Composable
internal fun CgyyPurposeTypeDialog(
    options: List<CgyyPurposeTypeDto>,
    selected: Int?,
    onDismiss: () -> Unit,
    onSelect: (Int) -> Unit,
) {
  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text("选择活动类型") },
      text = {
        Column(
            modifier = Modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          options.forEach { option ->
            FilterChip(
                selected = selected == option.key,
                onClick = { onSelect(option.key) },
                label = { Text(option.name) },
            )
          }
        }
      },
      confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
  )
}

@Composable
internal fun CgyyOrderDetailDialog(
    order: CgyyOrderDto,
    onDismiss: () -> Unit,
    onCancel: () -> Unit,
) {
  val status = order.displayStatus()
  val detailText = status.detailText
  val rejectionReason = order.checkContent
  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text(order.venueSpaceName ?: order.venueName.orEmpty()) },
      text = {
        Column(
            modifier = Modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          CgyyDetailRow("订单号", order.tradeNo ?: order.id.toString())
          CgyyDetailRow("状态", status.primaryText, status.color.toComposeColor())
          if (!detailText.isNullOrBlank() && detailText != status.primaryText) {
            CgyyDetailRow("审批阶段", detailText)
          }
          if (!rejectionReason.isNullOrBlank() && (order.checkStatus ?: 0) < 0) {
            CgyyDetailRow("驳回原因", rejectionReason, MaterialTheme.colorScheme.error)
          }
          CgyyDetailRow("日期", order.displayReservationDateText())
          CgyyDetailRow(
              "场地",
              listOf(order.venueName, order.siteName).filterNotNull().joinToString(" "),
          )
          CgyyDetailRow("房间", order.venueSpaceName.orEmpty())
          CgyyDetailRow("主题", order.theme.orEmpty())
          CgyyDetailRow("活动类型", order.purposeTypeName ?: order.purposeType?.toString().orEmpty())
          CgyyDetailRow("参与人数", order.joinerNum?.toString() ?: "-")
          CgyyDetailRow("活动内容", order.activityContent.orEmpty())
          CgyyDetailRow("参与人", order.joiners.orEmpty())
        }
      },
      confirmButton = {
        if (shouldShowCancelAction(order)) {
          TextButton(onClick = onCancel) { Text("取消预约") }
        }
      },
      dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
  )
}

@Composable
private fun CgyyDetailRow(
    label: String,
    value: String,
    color: Color = MaterialTheme.colorScheme.onSurface,
) {
  Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
    Text(
        label,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(value, style = MaterialTheme.typography.bodyMedium, color = color)
  }
}

internal fun JsonElement?.toRawDisplayText(): String =
    when (this) {
      null -> "null"
      is JsonPrimitive -> this.contentOrNull ?: this.toString()
      else -> this.toString()
    }

@Composable
internal fun CgyyEmptyState(title: String, subtitle: String, modifier: Modifier = Modifier) {
  Column(
      modifier = modifier.fillMaxSize().padding(24.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.Center,
  ) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Spacer(modifier = Modifier.height(6.dp))
    Text(
        text = subtitle,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
  }
}

@Composable
internal fun CgyyStatusChip(text: String, color: Color) {
  AssistChip(
      onClick = {},
      label = { Text(text, color = color, fontWeight = FontWeight.Bold) },
      modifier = Modifier.background(Color.Transparent),
  )
}
