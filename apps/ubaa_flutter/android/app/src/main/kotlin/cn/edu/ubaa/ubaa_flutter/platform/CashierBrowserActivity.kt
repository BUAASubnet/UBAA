package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.view.MenuItem
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import org.json.JSONObject
import org.json.JSONTokener

/** 应用管理导航的收银台，TLS 和安全浏览仍由 Android WebView 负责。 */
class CashierBrowserActivity : Activity() {
    private var browser: CashierWebSession? = null
    private var alipayPrompt: AlertDialog? = null
    private var launchId = 0L
    private var loginRequest = 0L
    private var pageGeneration = 0L
    private var merchantLoginStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getLongExtra(LAUNCH_ID, 0)
        // 系统重建时不自动重开旧订单或恢复页面会话。
        if (!CashierBrowserChannel.isOpening(id)) {
            finish()
            return
        }
        val order = intent.getStringExtra(ORDER_URL)
        if (order == null || !CashierBrowserPolicy.isOrderUrl(order)) {
            CashierBrowserChannel.reportOpen(id, false)
            finish()
            return
        }
        launchId = id
        loginRequest = intent.getLongExtra(LOGIN_REQUEST, 0)
        actionBar?.setDisplayHomeAsUpEnabled(true)
        val opened = try {
            val session = CashierWebSession.create(this)
            if (session == null) {
                false
            } else {
                browser = session
                configureBrowser(session.view, order)
                setContentView(session.view)
                session.view.loadUrl(order)
                active = this
                true
            }
        } catch (_: RuntimeException) {
            false
        }
        if (!opened) finish()
        CashierBrowserChannel.reportOpen(id, opened)
    }

    private fun configureBrowser(view: WebView, order: String) {
        // 航财通前端需要 JS 与站点存储；不向页面注入接口或本地数据。
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }

        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                pageGeneration++
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (browser?.view !== view || isFinishing) return true
                val target = request.url
                if (target.scheme.equals("https", ignoreCase = true)) return false
                val paymentPackage = CashierBrowserPolicy.paymentPackage(
                    view.url, target.toString(), request.isForMainFrame
                )
                if (paymentPackage != null) confirmAlipay(target, paymentPackage)
                // 未知协议不会被交给任意外部应用，也不会落入 WebView 的错误页。
                return true
            }

            override fun onPageCommitVisible(view: WebView, url: String) {
                // 只展示域名，不展示包含订单号的 URL。
                actionBar?.subtitle = Uri.parse(url).host.orEmpty()
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (browser?.view !== view || isFinishing || view.url != url) return
                if (loginRequest != 0L) {
                    if (CashierBrowserPolicy.isMerchantSsoPage(url)) {
                        trySsoLogin(view, url)
                    } else if (!merchantLoginStarted) {
                        val login = CashierBrowserPolicy.merchantLoginUrl(url, order)
                        if (login != null) {
                            merchantLoginStarted = true
                            view.loadUrl(login)
                            return
                        }
                    }
                }
                if (CashierBrowserPolicy.shouldHideWechatMethod(url)) {
                    view.evaluateJavascript(HIDE_WECHAT_METHOD_SCRIPT, null)
                }
            }
        }
    }

    private fun trySsoLogin(view: WebView, page: String) {
        val request = loginRequest
        val generation = pageGeneration
        fun currentPage() = browser?.view === view && !isFinishing &&
            generation == pageGeneration && view.url == page

        // 只读取本页挑战；账号密码不交给网页脚本、URL 或 Activity 参数。
        view.evaluateJavascript("$SSO_EXECUTION_SCRIPT(${JSONObject.quote(page)})") { result ->
            if (!currentPage() || request != loginRequest) return@evaluateJavascript
            val execution = runCatching { JSONTokener(result).nextValue() as? String }.getOrNull()
            loginRequest = 0
            if (execution.isNullOrBlank()) {
                CashierBrowserChannel.cancelLogin(launchId, request)
                return@evaluateJavascript
            }
            CashierBrowserChannel.requestLogin(launchId, request) { username, password ->
                if (currentPage()) {
                    view.postUrl(
                        CashierBrowserPolicy.merchantSsoLogin,
                        CashierBrowserPolicy.ssoForm(username, password, execution)
                    )
                }
            }
        }
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

    private fun closeSession() {
        CashierBrowserChannel.cancelLogin(launchId, loginRequest)
        loginRequest = 0
        alipayPrompt?.dismiss()
        val session = browser
        browser = null
        if (active === this) active = null
        session?.close()
    }

    override fun onDestroy() {
        closeSession()
        super.onDestroy()
    }

    companion object {
        internal const val ORDER_URL = "orderUrl"
        internal const val LAUNCH_ID = "launchId"
        internal const val LOGIN_REQUEST = "loginRequest"
        private var active: CashierBrowserActivity? = null

        internal fun closeActive() {
            active?.let { activity ->
                activity.closeSession()
                activity.finish()
            }
        }

        private val SSO_EXECUTION_SCRIPT = """
            (function(expectedPage) {
                if (window !== window.top || location.href !== expectedPage) return null;
                if (typeof config !== 'undefined' && config &&
                    ['captcha', 'mfa', 'otp', 'verification', 'verify', 'challenge']
                        .some(function(key) { return key in config; })) return null;
                var error = document.querySelector('#errorDiv');
                if (error && error.textContent.trim()) return null;
                var form = document.querySelector('form#loginForm, form#fm1');
                if (!form || form.method !== 'post' || document.querySelector('#continueForm')) return null;
                var action = new URL(form.action);
                if (action.origin !== location.origin || action.pathname !== '/login' ||
                    (action.search && action.search !== location.search) || action.hash) return null;
                var names = ['username', 'password', 'submit', 'type', 'execution', '_eventId'];
                var fields = Object.create(null);
                for (var field of form.elements) {
                    if (field.tagName !== 'INPUT' || !names.includes(field.name) ||
                        fields[field.name] || field.disabled) return null;
                    fields[field.name] = field;
                }
                if (!names.every(function(name) { return fields[name]; }) ||
                    fields.username.type !== 'text' || fields.username.value ||
                    fields.password.type !== 'password' || fields.password.value ||
                    fields.submit.value !== '登录' || fields.type.value !== 'username_password' ||
                    fields._eventId.value !== 'submit') return null;
                return fields.execution.value;
            })
        """.trimIndent()
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
