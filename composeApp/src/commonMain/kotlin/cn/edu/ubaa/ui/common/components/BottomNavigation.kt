package cn.edu.ubaa.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier

enum class BottomNavTab {
    HOME,
    REGULAR,
    ADVANCED
}

@Composable
fun BottomNavigation(
        currentTab: BottomNavTab,
        onTabSelected: (BottomNavTab) -> Unit,
        modifier: Modifier = Modifier
) {
    NavigationBar(
            modifier = modifier.fillMaxWidth(),
            containerColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onSurface
    ) {
        NavigationBarItem(
                icon = { Icon(imageVector = Icons.Default.Home, contentDescription = "主页") },
                label = { Text("主页") },
                selected = currentTab == BottomNavTab.HOME,
                onClick = { onTabSelected(BottomNavTab.HOME) }
        )

        NavigationBarItem(
                icon = {
                    Icon(imageVector = Icons.AutoMirrored.Filled.List, contentDescription = "普通功能")
                },
                label = { Text("普通功能") },
                selected = currentTab == BottomNavTab.REGULAR,
                onClick = { onTabSelected(BottomNavTab.REGULAR) }
        )

        NavigationBarItem(
                icon = { Icon(imageVector = Icons.Default.Settings, contentDescription = "高级功能") },
                label = { Text("高级功能") },
                selected = currentTab == BottomNavTab.ADVANCED,
                onClick = { onTabSelected(BottomNavTab.ADVANCED) }
        )
    }
}
