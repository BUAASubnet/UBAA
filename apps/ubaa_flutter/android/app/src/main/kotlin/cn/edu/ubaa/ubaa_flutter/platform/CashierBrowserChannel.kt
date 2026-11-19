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

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isSupported())
                "open" -> result.success(open(call.arguments as? String))
                else -> result.notImplemented()
            }
        }
    }

    private fun isSupported(): Boolean = try {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || WebView.getCurrentWebViewPackage() != null
    } catch (_: RuntimeException) {
        false
    }

    private fun open(url: String?): Boolean {
        if (url == null || !CashierBrowserPolicy.isOrderUrl(url) || activity.isFinishing) return false
        return try {
            val intent = Intent(activity, CashierBrowserActivity::class.java)
                .putExtra(CashierBrowserActivity.ORDER_URL, url)
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
