package cn.edu.ubaa.ubaa_flutter.platform

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** 把应用内主题交给系统，Android 12+ 冷启动的系统启动画面随之使用同一明暗。 */
class AppearanceChannel(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/appearance")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setThemeMode") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val mode = when (call.arguments as? String) {
                "light" -> UiModeManager.MODE_NIGHT_NO
                "dark" -> UiModeManager.MODE_NIGHT_YES
                // setApplicationNightMode 的 AUTO 清除应用覆盖，恢复系统配置。
                "system" -> UiModeManager.MODE_NIGHT_AUTO
                else -> {
                    result.error("invalid_theme", "未知主题", null)
                    return@setMethodCallHandler
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // 系统按应用持久保存该值；与当前值相同时不会触发配置变化。
                context.getSystemService(UiModeManager::class.java)?.setApplicationNightMode(mode)
            }
            result.success(null)
        }
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
