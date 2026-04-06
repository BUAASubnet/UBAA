package cn.edu.ubaa.ui.screens.cgyy

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CgyyLockCodeScreen(viewModel: CgyyViewModel) {
  val uiState by viewModel.uiState.collectAsState()
  val parsedLockCode = uiState.lockCode?.rawData.toLockCodeDisplayModel()

  val pullRefreshState =
      rememberPullRefreshState(
          refreshing = uiState.isLockCodeLoading,
          onRefresh = viewModel::loadLockCode,
      )

  LaunchedEffect(Unit) {
    while (true) {
      delay(30_000)
      viewModel.loadLockCode()
    }
  }

  Box(modifier = Modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      uiState.lockCodeError?.let { CgyyMessageBanner(it) }

      CgyySectionCard(title = "密码状态") {
        when {
          parsedLockCode?.hasLockCode == true -> {
            CgyyStatusChip(
                text = "当前时段可开门",
                color = MaterialTheme.colorScheme.primary,
            )
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors =
                    CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ),
            ) {
              Column(
                  modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                  horizontalAlignment = Alignment.CenterHorizontally,
                  verticalArrangement = Arrangement.spacedBy(6.dp),
              ) {
                Text(
                    text = parsedLockCode.qrCode.orEmpty(),
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                parsedLockCode.dueDate?.let {
                  Text(
                      text = "有效期至 $it",
                      style = MaterialTheme.typography.bodySmall,
                      color = MaterialTheme.colorScheme.onPrimaryContainer,
                  )
                }
              }
            }
          }
          parsedLockCode?.hasUpcomingReservation == true -> {
            CgyyStatusChip(
                text = "未到开门时段",
                color = MaterialTheme.colorScheme.error,
            )
            Text(
                text =
                    if (uiState.isLockCodeLoading) {
                      "正在获取密码，请稍候..."
                    } else {
                      "你当前没有正在进行中的预约，门锁密码会在可开门时段内返回。"
                    },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
          else -> {
            CgyyStatusChip(
                text = "当前无可用预约",
                color = MaterialTheme.colorScheme.error,
            )
            Text(
                text =
                    if (uiState.isLockCodeLoading) {
                      "正在获取密码，请稍候..."
                    } else {
                      "当前没有可用于获取门锁密码的预约记录。"
                    },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
      }

      if (parsedLockCode != null) {
        CgyySectionCard(title = "预约信息") {
          CgyyInfoLine("预约单号", parsedLockCode.tradeNo)
          CgyyInfoLine("场地", parsedLockCode.venueText)
          CgyyInfoLine("教室", parsedLockCode.spaceName)
          CgyyInfoLine("预约人", parsedLockCode.orderName)
          CgyyInfoLine("预约日期", parsedLockCode.reservationDate)
          CgyyInfoLine("时段", parsedLockCode.timeRangeText)
          CgyyInfoLine("开始时间", parsedLockCode.reservationStartDate)
          CgyyInfoLine("结束时间", parsedLockCode.reservationEndDate)
        }
      }

      Text(
          text = "页面会每 30 秒自动刷新一次密码，你也可以手动下拉刷新。",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.primary,
      )
    }
    PullRefreshIndicator(
        refreshing = uiState.isLockCodeLoading,
        state = pullRefreshState,
        modifier = Modifier.align(Alignment.TopCenter),
    )
  }
}

@Composable
private fun CgyyInfoLine(label: String, value: String?) {
  if (value.isNullOrBlank()) return
  Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
    Text(
        text = label,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(
        text = value,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurface,
    )
    Spacer(modifier = Modifier.height(4.dp))
  }
}

internal data class CgyyLockCodeDisplayModel(
    val qrCode: String?,
    val dueDate: String?,
    val tradeNo: String?,
    val venueName: String?,
    val siteName: String?,
    val spaceName: String?,
    val orderName: String?,
    val reservationDate: String?,
    val reservationDateDetail: String?,
    val reservationStartDate: String?,
    val reservationEndDate: String?,
) {
  val hasLockCode: Boolean
    get() = !qrCode.isNullOrBlank() && qrCode != "null"

  val hasUpcomingReservation: Boolean
    get() =
        !tradeNo.isNullOrBlank() ||
            !reservationDate.isNullOrBlank() ||
            !reservationStartDate.isNullOrBlank()

  val venueText: String?
    get() =
        listOf(venueName.orNullIfBlank(), siteName.orNullIfBlank()).joinToString(" ").ifBlank {
          null
        }

  val timeRangeText: String?
    get() = reservationDateDetail.orNullIfBlank()?.withoutLeadingSpaceLabel(spaceName, siteName)
}

internal fun JsonElement?.toLockCodeDisplayModel(): CgyyLockCodeDisplayModel? {
  val root = this as? JsonObject ?: return null
  val orderView = root["orderView"] as? JsonObject
  return CgyyLockCodeDisplayModel(
      qrCode = root.stringValue("qrCode"),
      dueDate = root.stringValue("dueDate"),
      tradeNo = orderView.stringValue("tradeNo"),
      venueName = orderView.stringValue("venueName"),
      siteName = orderView.stringValue("siteName"),
      spaceName = orderView.stringValue("venueSpaceName"),
      orderName = orderView.stringValue("orderName"),
      reservationDate = orderView.stringValue("reservationDate"),
      reservationDateDetail = orderView.stringValue("reservationDateDetail"),
      reservationStartDate = orderView.stringValue("reservationStartDate"),
      reservationEndDate = orderView.stringValue("reservationEndDate"),
  )
}

private fun JsonObject?.stringValue(key: String): String? {
  val primitive = this?.get(key) as? JsonPrimitive ?: return null
  return primitive.contentOrNull.orNullIfBlank()
}

private fun String?.orNullIfBlank(): String? {
  if (this == null) return null
  val trimmed = this.trim()
  if (trimmed.isEmpty() || trimmed == "null") return null
  return trimmed
}

private fun String.withoutLeadingSpaceLabel(vararg labels: String?): String {
  val normalized = trim()
  val matchedLabel =
      labels.mapNotNull { it.orNullIfBlank() }.firstOrNull { normalized.startsWith(it) }
          ?: return normalized
  return normalized.removePrefix(matchedLabel).trimStart(' ', '/', '-', '>')
}
