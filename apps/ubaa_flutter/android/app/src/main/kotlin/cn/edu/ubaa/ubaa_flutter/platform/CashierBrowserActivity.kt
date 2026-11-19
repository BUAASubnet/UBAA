package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.MenuItem
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast

/** 应用管理导航的收银台，TLS 和安全浏览仍由 Android WebView 负责。 */
class CashierBrowserActivity : Activity() {
    private var browser: WebView? = null
    private var alipayPrompt: AlertDialog? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val order = intent.getStringExtra(ORDER_URL)
        if (order == null || !CashierBrowserPolicy.isOrderUrl(order)) {
            finish()
            return
        }
        actionBar?.setDisplayHomeAsUpEnabled(true)
        val view = try {
            WebView(this)
        } catch (_: RuntimeException) {
            Toast.makeText(this, "无法打开航财通收银台", Toast.LENGTH_LONG).show()
            finish()
            return
        }
        browser = view
        // 航财通前端需要 JS 与站点存储；不向页面注入接口或本地数据。
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }

        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val target = request.url
                if (target.scheme.equals("https", ignoreCase = true)) return false
                val paymentPackage = CashierBrowserPolicy.paymentPackage(view.url, target.toString())
                if (paymentPackage != null) confirmAlipay(target, paymentPackage)
                // 未知协议不会被交给任意外部应用，也不会落入 WebView 的错误页。
                return true
            }

            override fun onPageCommitVisible(view: WebView, url: String) {
                // 只展示域名，不展示包含订单号的 URL。
                actionBar?.subtitle = Uri.parse(url).host.orEmpty()
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (CashierBrowserPolicy.shouldHideWechatMethod(url)) {
                    view.evaluateJavascript(HIDE_WECHAT_METHOD_SCRIPT, null)
                }
            }
        }
        setContentView(view)
        view.loadUrl(order)
    }

    private fun confirmAlipay(url: Uri, paymentPackage: String) {
        if (alipayPrompt != null || isFinishing || isDestroyed) return
        alipayPrompt = AlertDialog.Builder(this)
            .setTitle("打开支付宝？")
            .setMessage("收银台请求打开支付宝。请在支付宝内核对订单并确认付款。")
            .setNegativeButton("取消", null)
            .setPositiveButton("打开支付宝") { _, _ -> openAlipay(url, paymentPackage) }
            .create().also { dialog ->
                dialog.setOnDismissListener { alipayPrompt = null }
                dialog.show()
            }
    }

    private fun openAlipay(url: Uri, paymentPackage: String) {
        val payment = Intent(Intent.ACTION_VIEW, url)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage(paymentPackage)
        try {
            startActivity(payment)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, "无法打开支付宝，请确认已经安装支付宝", Toast.LENGTH_LONG).show()
        } catch (_: SecurityException) {
            Toast.makeText(this, "系统未允许打开支付宝", Toast.LENGTH_LONG).show()
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId != android.R.id.home) return super.onOptionsItemSelected(item)
        finish()
        return true
    }

    override fun onDestroy() {
        alipayPrompt?.dismiss()
        browser?.let { view ->
            view.stopLoading()
            (view.parent as? android.view.ViewGroup)?.removeView(view)
            view.destroy()
        }
        browser = null
        super.onDestroy()
    }

    companion object {
        internal const val ORDER_URL = "orderUrl"
        private val HIDE_WECHAT_METHOD_SCRIPT = """
            (function() {
                if (location.protocol !== 'https:' ||
                    location.hostname.toLowerCase() !== 'cashier.cc-pay.cn' ||
                    location.pathname !== '/cashier' ||
                    window.__ubaaHideWechatEntryObserver) return;
                window.__ubaaHideWechatEntryObserver = true;
                function syncPaymentMethods() {
                    var cashier = document.querySelector('app-cashier-mobile');
                    if (!cashier) return;
                    var hideWechat = Boolean(cashier.querySelector('.alipay'));
                    cashier.querySelectorAll('.wxpay').forEach(function(entry) {
                        entry.hidden = hideWechat;
                    });
                }
                syncPaymentMethods();
                new MutationObserver(syncPaymentMethods).observe(document.documentElement, {
                    childList: true,
                    subtree: true
                });
            })();
        """.trimIndent()
    }
}
