package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.random.Random

class CashierBrowserChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/cashier-browser")
    private val handler = Handler(Looper.getMainLooper())
    private val openDeadline = Runnable { finishOpen(false) }
    private var launchId = 0L
    private var pendingOpen: MethodChannel.Result? = null
    private var pendingLogin = 0L

    init {
        CashierBrowserActivity.closeActive()
        current?.finishOpen(false)
        current = this
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(CashierWebSession.isSupported(activity))
                "open" -> open(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun open(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val url = arguments?.get("url") as? String
        if (current !== this || pendingOpen != null || activity.isFinishing || activity.isDestroyed ||
            url == null || !CashierBrowserPolicy.isOrderUrl(url) ||
            !CashierWebSession.isSupported(activity)
        ) {
            result.success(false)
            return
        }
        CashierBrowserActivity.closeActive()
        launchId = ++nextLaunchId
        pendingOpen = result
        pendingLogin = (arguments["loginRequest"] as? Number)?.toLong() ?: 0L
        // 活动若被系统拦截且未创建，不能让 Flutter 一直等待初始化回执。
        handler.postDelayed(openDeadline, 15_000L)
        try {
            val intent = Intent(activity, CashierBrowserActivity::class.java)
                .putExtra(CashierBrowserActivity.ORDER_URL, url)
                .putExtra(CashierBrowserActivity.LAUNCH_ID, launchId)
                .putExtra(CashierBrowserActivity.LOGIN_REQUEST, pendingLogin)
            activity.startActivity(intent)
        } catch (_: RuntimeException) {
            finishOpen(false)
        }
    }

    private fun finishOpen(opened: Boolean) {
        val result = pendingOpen ?: return
        pendingOpen = null
        handler.removeCallbacks(openDeadline)
        if (!opened) pendingLogin = 0
        result.success(opened)
    }

    fun dispose() {
        if (current === this) current = null
        finishOpen(false)
        channel.setMethodCallHandler(null)
    }

    companion object {
        private var current: CashierBrowserChannel? = null
        private var nextLaunchId = Random.nextLong()

        internal fun isOpening(id: Long): Boolean =
            current?.let { it.launchId == id && it.pendingOpen != null } == true

        internal fun reportOpen(id: Long, opened: Boolean) {
            current?.takeIf { it.launchId == id }?.finishOpen(opened)
        }

        internal fun requestLogin(id: Long, request: Long, complete: (String, String) -> Unit) {
            val owner = current ?: return
            if (id != owner.launchId || request == 0L || owner.pendingLogin != request) return
            owner.pendingLogin = 0
            owner.channel.invokeMethod("requestLogin", request, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (current !== owner || id != owner.launchId) return
                    val data = result as? Map<*, *> ?: return
                    val username = data["username"] as? String ?: return
                    val password = data["password"] as? String ?: return
                    if (username.isNotBlank() && password.isNotEmpty()) complete(username, password)
                }
                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            })
        }

        internal fun cancelLogin(id: Long, request: Long) {
            val owner = current ?: return
            if (id != owner.launchId || request == 0L || owner.pendingLogin != request) return
            owner.pendingLogin = 0
            owner.channel.invokeMethod("cancelLogin", request)
        }
    }
}
