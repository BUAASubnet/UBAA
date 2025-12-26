package cn.edu.ubaa.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember

/**
 * 自定义的简单导航控制器。
 * 负责维护基于 [AppScreen] 的导航栈，处理页面跳转与回退逻辑。
 */
class NavigationController {
    /** 当前的导航路径。 */
    val navStack = mutableStateListOf(AppScreen.HOME)
    
    /** 获取栈顶屏幕。 */
    val currentScreen: AppScreen
        get() = navStack.lastOrNull() ?: AppScreen.HOME

    /** 跳转至新屏幕。 */
    fun navigateTo(screen: AppScreen) {
        if (navStack.lastOrNull() != screen) {
            navStack.add(screen)
        }
    }

    /** 回退至上一屏幕。 @return 是否回退成功。 */
    fun navigateBack(): Boolean {
        if (navStack.size > 1) {
            navStack.removeAt(navStack.size - 1)
            return true
        }
        return false
    }

    /** 清空导航栈并将指定屏幕设为根页面。 */
    fun setRoot(screen: AppScreen) {
        if (navStack.size == 1 && navStack[0] == screen) return
        navStack.clear()
        navStack.add(screen)
    }
}

/** 在 Composable 函数中记住并获取导航控制器实例。 */
@Composable
fun rememberNavigationController(): NavigationController {
    return remember { NavigationController() }
}