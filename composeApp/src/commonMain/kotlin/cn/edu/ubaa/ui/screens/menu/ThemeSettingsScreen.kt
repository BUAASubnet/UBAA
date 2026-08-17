package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

enum class ThemeMode {
  SYSTEM,
  LIGHT,
  DARK;

  val storageKey: String
    get() = name.lowercase()

  companion object {
    fun fromStorageKey(value: String?): ThemeMode =
        entries.firstOrNull { it.storageKey == value?.trim()?.lowercase() } ?: SYSTEM
  }
}

private val colorThemeTypes =
    listOf(
        0xFF6750A4L to "默认",
        0xFF009688L to "青色",
        0xFF2196F3L to "蓝色",
        0xFF3F51B5L to "靛蓝色",
        0xFF7E57C2L to "紫罗兰色",
        0xFFE91E63L to "粉红色",
        0xFFFFEB3BL to "黄色",
        0xFFFF9800L to "橙色",
        0xFFFF5722L to "深橙色",
    )

@Composable
fun ThemeSettingsScreen(
    themeMode: ThemeMode,
    selectedColorValue: Long,
    onColorSelected: (Long) -> Unit,
    useDynamicColor: Boolean,
    onToggleDynamicColor: (Boolean) -> Unit,
    oledEnhance: Boolean,
    onThemeModeSelected: (ThemeMode) -> Unit,
    onToggleOledEnhance: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
  Column(modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
    Text(
        text = "外观设置",
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
    )

    Spacer(modifier = Modifier.height(24.dp))

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
      Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
        Text(text = "深色模式", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(12.dp))
        ThemeMode.entries.forEach { mode ->
          val title =
              when (mode) {
                ThemeMode.SYSTEM -> "跟随系统"
                ThemeMode.LIGHT -> "浅色"
                ThemeMode.DARK -> "深色"
              }
          Row(
              modifier =
                  Modifier.fillMaxWidth()
                      .clickable { onThemeModeSelected(mode) }
                      .padding(vertical = 10.dp),
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.SpaceBetween,
          ) {
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            RadioButton(
                selected = themeMode == mode,
                onClick = { onThemeModeSelected(mode) },
            )
          }
          if (mode != ThemeMode.DARK) {
            HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
          }
        }
      }
    }

    Spacer(modifier = Modifier.height(16.dp))

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
      Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
        Text(text = "配色方案", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(12.dp))
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          colorThemeTypes.forEach { (colorValue, label) ->
            val color = Color(colorValue)
            val selected = colorValue == selectedColorValue
            Box(
                modifier =
                    Modifier.alpha(if (useDynamicColor) 0.5f else 1f)
                        .clickable(enabled = !useDynamicColor) { onColorSelected(colorValue) }
                        .padding(vertical = 4.dp),
            ) {
              Column(horizontalAlignment = Alignment.CenterHorizontally) {
                ThemeSchemePreview(seedColor = color, selected = selected)
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
              }
            }
          }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = if (useDynamicColor) "自动配色启用时，应用将使用默认色调并随深浅色模式调整。" else "选择你希望的应用整体色调。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }

    Spacer(modifier = Modifier.height(16.dp))

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
      Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
          Column {
            Text(text = "自动配色", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "开启后使用应用默认色调。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
          Switch(
              checked = useDynamicColor,
              onCheckedChange = onToggleDynamicColor,
          )
        }
      }
    }

    Spacer(modifier = Modifier.height(16.dp))

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
      Row(
          modifier = Modifier.fillMaxWidth().padding(16.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        Column {
          Text(text = "OLED 优化", style = MaterialTheme.typography.titleMedium)
          Spacer(modifier = Modifier.height(4.dp))
          Text(
              text = "深色模式下使用纯黑背景，适合 OLED 屏幕。",
              style = MaterialTheme.typography.bodyMedium,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Switch(
            checked = oledEnhance,
            onCheckedChange = onToggleOledEnhance,
        )
      }
    }
  }
}

@Composable
private fun ThemeSchemePreview(seedColor: Color, selected: Boolean) {
  val cardShape = RoundedCornerShape(12.dp)
  Box(
      modifier =
          Modifier.size(88.dp)
              .clip(cardShape)
              .background(Color(0xFFF1F1F1))
              .border(
                  width = 1.dp,
                  color = if (selected) blend(seedColor, Color.Black, 0.10f) else Color.Transparent,
                  shape = cardShape,
              )
              .padding(10.dp),
  ) {
    Box(
        modifier = Modifier.align(Alignment.Center).size(62.dp).clip(CircleShape),
    ) {
      Column(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier =
                Modifier.fillMaxWidth().weight(1f).background(blend(seedColor, Color.White, 0.70f)),
        )
        Row(modifier = Modifier.fillMaxWidth().weight(1f)) {
          Box(
              modifier =
                  Modifier.weight(1f)
                      .fillMaxSize()
                      .background(blend(seedColor, Color.Black, 0.36f)),
          )
          Box(
              modifier =
                  Modifier.weight(1f)
                      .fillMaxSize()
                      .background(blend(seedColor, Color.White, 0.36f)),
          )
        }
      }
    }
    if (selected) {
      Box(
          modifier =
              Modifier.align(Alignment.TopEnd)
                  .size(28.dp)
                  .background(MaterialTheme.colorScheme.primary, CircleShape),
          contentAlignment = Alignment.Center,
      ) {
        Icon(
            imageVector = Icons.Default.Check,
            contentDescription = "已选择",
            tint = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.size(18.dp),
        )
      }
    }
  }
}

private fun blend(start: Color, end: Color, amount: Float): Color {
  val clampedAmount = amount.coerceIn(0f, 1f)
  val inverseAmount = 1f - clampedAmount
  return Color(
      red = start.red * inverseAmount + end.red * clampedAmount,
      green = start.green * inverseAmount + end.green * clampedAmount,
      blue = start.blue * inverseAmount + end.blue * clampedAmount,
      alpha = start.alpha * inverseAmount + end.alpha * clampedAmount,
  )
}
