package cn.edu.ubaa.ubaa_flutter.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CashierBrowserPolicyTest {
    private val order = "https://cashier.cc-pay.cn/cashier?id=Order1"
    private val payment = "alipays://platformapi/startapp?appId=fixture&url=https%3A%2F%2Fexample.invalid"
    private val alipayPage = "https://excashier.alipay.com/standard/auth.htm?payOrderId=fixture"

    @Test
    fun browserAcceptsOriginalOrderButRejectsMismatchedOriginsAndExtraParameters() {
        assertTrue(CashierBrowserPolicy.isOrderUrl(order))
        for (url in listOf(
            "http://cashier.cc-pay.cn/cashier?id=Order1",
            "https://cashier.cc-pay.cn.other.invalid/cashier?id=Order1",
            "https://name@cashier.cc-pay.cn/cashier?id=Order1",
            "https://cashier.cc-pay.cn:8443/cashier?id=Order1",
            "https://cashier.cc-pay.cn/login?id=Order1",
            "$order&payWay=alipay",
            "$order&id=Order2",
            "$order#fragment"
        )) {
            assertFalse(url, CashierBrowserPolicy.isOrderUrl(url))
        }
    }

    @Test
    fun merchantSsoUsesThePassCallbackAndKeepsTheOriginalOrder() {
        val encoded = "https%3A%2F%2Fcashier.cc-pay.cn%2Fcashier%3Fid%3DOrder1"
        val page = "https://pass.cc-pay.cn/signIn?backUrl=$encoded"
        assertEquals(
            "https://pass.cc-pay.cn/login?backUrl=$encoded&channel=BUAASSO",
            CashierBrowserPolicy.merchantLoginUrl(page, order)
        )
        for (url in listOf(
            page.replace("Order1", "Other"),
            page.replace("pass.cc-pay.cn", "pass.cc-pay.cn.other.invalid"),
            page.replace("https:", "http:"),
            "$page&backUrl=$encoded",
            "$page&channel=BUAASSO",
            "$page#fragment"
        )) assertNull(url, CashierBrowserPolicy.merchantLoginUrl(url, order))

        val login = CashierBrowserPolicy.merchantSsoLogin
        assertTrue(CashierBrowserPolicy.isMerchantSsoPage(login))
        for (url in listOf(
            "https://sso.buaa.edu.cn/login?service=$encoded",
            login.replace("sso.buaa.edu.cn", "sso.buaa.edu.cn.other.invalid"),
            login.replace("sso.buaa.edu.cn", "sso.buaa.edu.cn:8443"),
            login.replace("service=", "%73ervice="),
            "$login&service=$encoded",
            "$login#fragment"
        )) assertFalse(url, CashierBrowserPolicy.isMerchantSsoPage(url))
    }

    @Test
    fun casCredentialsAndChallengeAreEncodedOnlyInThePostBody() {
        val body = CashierBrowserPolicy.ssoForm("student+test", "a&b +试", "e=1&2")
        assertEquals(
            "username=student%2Btest&password=a%26b+%2B%E8%AF%95&submit=%E7%99%BB%E5%BD%95" +
                "&type=username_password&execution=e%3D1%262&_eventId=submit",
            body.toString(Charsets.UTF_8)
        )
    }

    @Test
    fun wechatEntryIsHiddenOnlyOnSecureCashierPage() {
        for (url in listOf(
            "https://cashier.cc-pay.cn/cashier?id=Order1",
            "https://CASHIER.CC-PAY.CN/cashier?for=wxpay_wap",
            "https://cashier.cc-pay.cn:443/cashier"
        )) {
            assertTrue(url, CashierBrowserPolicy.shouldHideWechatMethod(url))
        }
        for (url in listOf(
            "http://cashier.cc-pay.cn/cashier?id=Order1",
            "https://cashier.cc-pay.cn.other.invalid/cashier?id=Order1",
            "https://cashier.cc-pay.cn:8443/cashier?id=Order1",
            "https://cashier.cc-pay.cn/transaction?id=Order1",
            "https://cashier.cc-pay.cn.evil.invalid/cashier"
        )) {
            assertFalse(url, CashierBrowserPolicy.shouldHideWechatMethod(url))
        }
    }

    @Test
    fun trustedCheckoutCanOnlyHandoffAlipaysToAlipay() {
        for (source in listOf(order, alipayPage)) {
            assertEquals(
                "com.eg.android.AlipayGphone",
                CashierBrowserPolicy.paymentPackage(source, payment, isMainFrame = true)
            )
        }
        for (target in listOf(
            "intent://platformapi/startapp#Intent;scheme=alipays;end",
            "alipay://platformapi/startapp",
            "file:///android_asset/checkout",
            "alipays://name@platformapi/startapp",
            "alipays:///startapp"
        )) {
            assertNull(target, CashierBrowserPolicy.paymentPackage(order, target, isMainFrame = true))
        }
    }

    @Test
    fun otherSitesCannotRequestPaymentHandoff() {
        for (source in listOf(
            null,
            "http://excashier.alipay.com/standard/auth.htm",
            "https://excashier.alipay.com:8443/standard/auth.htm",
            "https://excashier.alipay.com.other.invalid/",
            "https://fakealipay.com/",
            "https://excashier.alipay.com@other.invalid/",
            "https://sso.buaa.edu.cn/login"
        )) {
            assertNull(source, CashierBrowserPolicy.paymentPackage(source, payment, isMainFrame = true))
        }
    }

    @Test
    fun subframesCannotRequestPaymentHandoffFromTrustedCheckout() {
        for (source in listOf(order, alipayPage)) {
            assertNull(source, CashierBrowserPolicy.paymentPackage(source, payment, isMainFrame = false))
        }
    }
}
