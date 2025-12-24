package cn.edu.ubaa.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember

class NavigationController {
    val navStack = mutableStateListOf(AppScreen.HOME)
    val currentScreen: AppScreen
        get() = navStack.lastOrNull() ?: AppScreen.HOME

    // 底部 Tab 和侧边栏状态由 UI 驱动，此处仅管理导航栈
    fun navigateTo(screen: AppScreen) {
        if (navStack.lastOrNull() != screen) {
            navStack.add(screen)
        }
    }

    fun navigateBack(): Boolean {
        if (navStack.size > 1) {
            navStack.removeAt(navStack.size - 1)
            return true
        }
        return false
    }

    fun setRoot(screen: AppScreen) {
        if (navStack.size == 1 && navStack[0] == screen) return
        navStack.clear()
        navStack.add(screen)
    }
}

@Composable
fun rememberNavigationController(): NavigationController {
    return remember { NavigationController() }
}
