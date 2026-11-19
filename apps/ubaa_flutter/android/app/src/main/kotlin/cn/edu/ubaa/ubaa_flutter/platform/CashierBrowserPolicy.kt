package cn.edu.ubaa.ubaa_flutter.platform

import java.net.URI
import java.net.URISyntaxException

internal object CashierBrowserPolicy {
    private const val CASHIER = "cashier.cc-pay.cn"
    private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
    private val orderQuery = Regex("id=[A-Za-z0-9]{1,64}")

    fun isOrderUrl(url: String): Boolean {
        val uri = httpsUrl(url) ?: return false
        return uri.host.equals(CASHIER, ignoreCase = true) &&
            uri.rawPath == "/cashier" && uri.rawFragment == null &&
            uri.rawQuery?.startsWith("id=") == true &&
            uri.query?.matches(orderQuery) == true
    }

    fun shouldHideWechatMethod(url: String): Boolean {
        val uri = httpsUrl(url) ?: return false
        return uri.host.equals(CASHIER, ignoreCase = true) && uri.rawPath == "/cashier"
    }

    fun paymentPackage(page: String?, target: String): String? {
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
