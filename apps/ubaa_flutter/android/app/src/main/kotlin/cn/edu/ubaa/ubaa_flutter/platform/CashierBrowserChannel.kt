package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.webkit.WebView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CashierBrowserChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/cashier-browser")
    private var pendingLogin = 0L

    init {
        current = this
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isSupported())
                "open" -> result.success(open(call.arguments as? Map<*, *>))
                else -> result.notImplemented()
            }
        }
    }

    private fun isSupported(): Boolean = try {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || WebView.getCurrentWebViewPackage() != null
    } catch (_: RuntimeException) {
        false
    }

    private fun open(arguments: Map<*, *>?): Boolean {
        val url = arguments?.get("url") as? String ?: return false
        val request = (arguments["loginRequest"] as? Number)?.toLong() ?: 0L
        if (!CashierBrowserPolicy.isOrderUrl(url) || activity.isFinishing) return false
        return try {
            val intent = Intent(activity, CashierBrowserActivity::class.java)
                .putExtra(CashierBrowserActivity.ORDER_URL, url)
                .putExtra(CashierBrowserActivity.LOGIN_REQUEST, request)
            activity.startActivity(intent)
            pendingLogin = request
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    fun dispose() {
        if (current === this) current = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        private var current: CashierBrowserChannel? = null

        fun requestLogin(request: Long, complete: (String, String) -> Unit) {
            val owner = current ?: return
            if (request == 0L || owner.pendingLogin != request) return
            owner.pendingLogin = 0
            owner.channel.invokeMethod("requestLogin", request, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (current !== owner) return
                    val data = result as? Map<*, *> ?: return
                    val username = data["username"] as? String ?: return
                    val password = data["password"] as? String ?: return
                    if (username.isNotBlank() && password.isNotEmpty()) complete(username, password)
                }
                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            })
        }

        fun cancelLogin(request: Long) {
            val owner = current ?: return
            if (request == 0L || owner.pendingLogin != request) return
            owner.pendingLogin = 0
            owner.channel.invokeMethod("cancelLogin", request)
        }
    }
}
