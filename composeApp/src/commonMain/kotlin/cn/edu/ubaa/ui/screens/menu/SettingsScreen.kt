package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.api.ConnectionMode

@Composable
fun SettingsScreen(
    currentMode: ConnectionMode,
    availableModes: List<ConnectionMode>,
    onModeSelected: (ConnectionMode) -> Unit,
    modifier: Modifier = Modifier,
) {
  var pendingMode by remember { mutableStateOf<ConnectionMode?>(null) }

  Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
    Text(
        text = "连接模式",
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
    )
    Spacer(modifier = Modifier.height(8.dp))
    Text(
        text = "当前模式：${currentMode.displayName}",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(16.dp))

    availableModes.forEach { mode ->
      Card(
          modifier =
              Modifier.fillMaxWidth().padding(vertical = 6.dp).clickable {
                if (mode != currentMode) {
                  pendingMode = mode
                }
              },
          colors =
              CardDefaults.cardColors(
                  containerColor =
                      if (mode == currentMode) {
                        MaterialTheme.colorScheme.secondaryContainer
                      } else {
                        MaterialTheme.colorScheme.surface
                      }
              ),
      ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            RadioButton(
                selected = mode == currentMode,
                onClick = null,
            )
            Column(modifier = Modifier.padding(start = 12.dp)) {
              Text(text = mode.displayName, style = MaterialTheme.typography.titleMedium)
              Spacer(modifier = Modifier.height(4.dp))
              Text(
                  text = mode.description,
                  style = MaterialTheme.typography.bodyMedium,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
        }
      }
    }
  }

  pendingMode?.let { mode ->
    AlertDialog(
        onDismissRequest = { pendingMode = null },
        title = { Text("切换连接模式") },
        text = { Text("将退出当前登录并清除本模式会话，需重新登录。") },
        confirmButton = {
          TextButton(
              onClick = {
                pendingMode = null
                onModeSelected(mode)
              }
          ) {
            Text("确认切换")
          }
        },
        dismissButton = {
          TextButton(onClick = { pendingMode = null }) {
            Text("取消")
          }
        },
    )
  }
}
