package cn.edu.ubaa.ubaa_flutter.platform

import java.net.URI
import java.net.URISyntaxException
import java.net.URLEncoder
import java.nio.charset.StandardCharsets.UTF_8

internal object CashierBrowserPolicy {
    private const val CASHIER = "cashier.cc-pay.cn"
    private const val PASS = "https://pass.cc-pay.cn/login"
    private const val SSO = "https://sso.buaa.edu.cn/login"
    val merchantSsoLogin = "$SSO?service=${encode(PASS)}"
    private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
    private val orderQuery = Regex("id=[A-Za-z0-9]{1,64}")

    fun isOrderUrl(url: String): Boolean {
        val uri = httpsUrl(url) ?: return false
        return uri.host.equals(CASHIER, ignoreCase = true) &&
            uri.rawPath == "/cashier" && uri.rawFragment == null &&
            uri.rawQuery?.startsWith("id=") == true &&
            uri.query?.matches(orderQuery) == true
    }

    /** 只为原订单触发已观察到的商户登录，不绕过商户建立 backUrl 的步骤。 */
    fun merchantLoginUrl(page: String, order: String): String? {
        if (!isOrderUrl(order)) return null
        val uri = httpsUrl(page) ?: return null
        if (!uri.host.equals("pass.cc-pay.cn", ignoreCase = true) ||
            (uri.rawPath != "/login" && uri.rawPath != "/signIn") || uri.rawFragment != null) return null
        val query = uri.rawQuery ?: return null
        if (!query.startsWith("backUrl=") || '&' in query || uri.query != "backUrl=$order") return null
        return "$PASS?backUrl=${encode(order)}&channel=BUAASSO"
    }

    fun isMerchantSsoPage(page: String): Boolean {
        val uri = httpsUrl(page) ?: return false
        val raw = uri.rawQuery ?: return false
        return uri.host.equals("sso.buaa.edu.cn", ignoreCase = true) &&
            uri.rawPath == "/login" && uri.rawFragment == null &&
            raw.startsWith("service=") && '&' !in raw && uri.query == "service=$PASS"
    }

    fun ssoForm(username: String, password: String, execution: String): ByteArray =
        ("username=${encode(username)}&password=${encode(password)}&submit=${encode("登录")}" +
            "&type=username_password&execution=${encode(execution)}&_eventId=submit")
            .toByteArray(UTF_8)

    private fun encode(value: String): String = URLEncoder.encode(value, UTF_8.name())

    fun shouldHideWechatMethod(url: String): Boolean {
        val uri = httpsUrl(url) ?: return false
        return uri.host.equals(CASHIER, ignoreCase = true) && uri.rawPath == "/cashier"
    }

    fun paymentPackage(page: String?, target: String, isMainFrame: Boolean): String? {
        if (!isMainFrame) return null
        val sourceHost = httpsUrl(page)?.host?.lowercase() ?: return null
        if (sourceHost != CASHIER && sourceHost != "alipay.com" &&
            !sourceHost.endsWith(".alipay.com")) return null
        val uri = parse(target) ?: return null
        if (uri.scheme != "alipays" || uri.host.isNullOrEmpty() ||
            uri.rawUserInfo != null || uri.port != -1) return null
        return ALIPAY_PACKAGE
    }

    private fun httpsUrl(url: String?): URI? = url?.let(::parse)?.takeIf {
        it.scheme.equals("https", ignoreCase = true) && it.host != null &&
            it.rawUserInfo == null && (it.port == -1 || it.port == 443)
    }

    private fun parse(url: String): URI? = try {
        URI(url)
    } catch (_: URISyntaxException) {
        null
    }
}
