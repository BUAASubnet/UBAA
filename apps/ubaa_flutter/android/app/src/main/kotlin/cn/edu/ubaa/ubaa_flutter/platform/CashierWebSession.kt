package cn.edu.ubaa.ubaa_flutter.platform

import android.content.Context
import android.util.Log
import android.view.ViewGroup
import android.webkit.WebView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.util.UUID

internal class CashierWebSession private constructor(
    val view: WebView,
    private val store: ProfileStore,
    private val name: String
) {
    fun close() {
        try {
            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
        } finally {
            if (deleteProfile(store, name)) {
                profilesInProcess--
            } else {
                // 已加载的配置可能到下次进程启动才能删除；现在清理它自己的会话数据。
                try {
                    store.getProfile(name)?.let { profile ->
                        profile.cookieManager.removeAllCookies(null)
                        profile.webStorage.deleteAllData()
                    }
                } catch (_: RuntimeException) {
                    Log.w("CashierWebSession", "无法清除已关闭的收银台会话数据")
                }
            }
        }
    }

    companion object {
        private const val PROFILE_PREFIX = "ubaa-cashier-"
        // 某些提供程序会一直保留已加载的配置；到上限后须重启应用才能新开会话。
        private const val MAX_PROFILES_PER_PROCESS = 16
        private var profilesInProcess = 0
        private var swept = false

        fun isSupported(context: Context): Boolean = try {
            WebViewCompat.getCurrentWebViewPackage(context) != null && availableStore() != null
        } catch (_: RuntimeException) {
            false
        }

        private fun availableStore(): ProfileStore? {
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return null
            val store = ProfileStore.getInstance()
            if (!swept) {
                // 进程被杀时不会执行 onDestroy；只回收上次留下的收银台数据。
                for (name in store.allProfileNames) {
                    if (name.startsWith(PROFILE_PREFIX) && !deleteProfile(store, name)) {
                        profilesInProcess++
                    }
                }
                swept = true
            }
            return if (profilesInProcess < MAX_PROFILES_PER_PROCESS) store else null
        }

        fun create(context: Context): CashierWebSession? {
            val store = availableStore() ?: return null
            val name = "$PROFILE_PREFIX${UUID.randomUUID()}"
            val view = WebView(context)
            val session = CashierWebSession(view, store, name)
            profilesInProcess++
            try {
                // 创建后第一步设置专用配置，不使用默认配置导航，也不导入 Core Cookie。
                WebViewCompat.setProfile(view, name)
                return session
            } catch (error: RuntimeException) {
                session.close()
                throw error
            }
        }

        private fun deleteProfile(store: ProfileStore, name: String): Boolean = try {
            store.deleteProfile(name)
            true
        } catch (_: IllegalStateException) {
            // 仍被提供程序持有时，下次进程启动回收；新会话从不复用它。
            false
        }
    }
}
