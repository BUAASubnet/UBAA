package cn.edu.ubaa.ui.common.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.UserData

@Composable
fun Sidebar(
  userData: UserData,
  onLogoutClick: () -> Unit,
  onMyClick: () -> Unit,
  onAboutClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Card(
    modifier = modifier.fillMaxHeight().width(280.dp),
    shape = RoundedCornerShape(topEnd = 16.dp, bottomEnd = 16.dp),
    elevation = CardDefaults.cardElevation(defaultElevation = 8.dp),
  ) {
    Column(
      modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).padding(16.dp)
    ) {
      // User Info Section
      Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
      ) {
        Column(
          modifier = Modifier.fillMaxWidth().padding(16.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
        ) {
          // User Avatar
          Box(
            modifier =
              Modifier.size(64.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary)
          ) {
            Icon(
              imageVector = Icons.Default.AccountCircle,
              contentDescription = "用户头像",
              modifier = Modifier.fillMaxSize().padding(8.dp),
              tint = MaterialTheme.colorScheme.onPrimary,
            )
          }

          Spacer(modifier = Modifier.height(12.dp))

          // User Name
          Text(
            text = userData.name,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
          )

          // School ID
          Text(
            text = userData.schoolid,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      Spacer(modifier = Modifier.height(24.dp))

      // Menu Items
      SidebarMenuItem(icon = Icons.Default.Person, title = "我的", onClick = onMyClick)

      Spacer(modifier = Modifier.height(8.dp))

      SidebarMenuItem(icon = Icons.Default.Info, title = "关于", onClick = onAboutClick)

      Spacer(modifier = Modifier.weight(1f))

      // Logout Button
      OutlinedButton(
        onClick = onLogoutClick,
        modifier = Modifier.fillMaxWidth(),
        colors =
          ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
      ) {
        Icon(
          imageVector = Icons.AutoMirrored.Filled.ExitToApp,
          contentDescription = null,
          modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text("退出登录")
      }
    }
  }
}

@Composable
private fun SidebarMenuItem(
  icon: ImageVector,
  title: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Card(
    modifier = modifier.fillMaxWidth().clickable { onClick() },
    colors = CardDefaults.cardColors(containerColor = Color.Transparent),
    border = ButtonDefaults.outlinedButtonBorder(enabled = true),
  ) {
    Row(
      modifier = Modifier.fillMaxWidth().padding(16.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurface,
      )
      Spacer(modifier = Modifier.width(12.dp))
      Text(text = title, style = MaterialTheme.typography.bodyLarge)
    }
  }
}
