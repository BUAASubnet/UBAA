package cn.edu.ubaa.ui.screens.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
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
fun ConnectionModeSelectionScreen(
    availableModes: List<ConnectionMode>,
    onConfirm: (ConnectionMode) -> Unit,
    modifier: Modifier = Modifier,
) {
  var selectedMode by
      remember(availableModes) {
        mutableStateOf(availableModes.firstOrNull() ?: ConnectionMode.SERVER_RELAY)
      }

  Column(
      modifier = modifier.fillMaxSize().padding(24.dp),
      verticalArrangement = Arrangement.Center,
  ) {
    Text(
        text = "选择连接模式",
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold,
    )
    Spacer(modifier = Modifier.height(12.dp))
    Text(
        text = "首次启动需要先确定连接方式，后续可在设置中切换。",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(24.dp))

    availableModes.forEach { mode ->
      Card(
          modifier =
              Modifier.fillMaxWidth().clickable { selectedMode = mode }.padding(vertical = 6.dp),
          colors =
              CardDefaults.cardColors(
                  containerColor =
                      if (selectedMode == mode) {
                        MaterialTheme.colorScheme.secondaryContainer
                      } else {
                        MaterialTheme.colorScheme.surface
                      }
              ),
      ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          RadioButton(selected = selectedMode == mode, onClick = { selectedMode = mode })
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

    Spacer(modifier = Modifier.height(24.dp))
    Button(
        onClick = { onConfirm(selectedMode) },
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(vertical = 14.dp),
    ) {
      Text("继续")
    }
  }
}
