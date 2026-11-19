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
                CashierBrowserPolicy.paymentPackage(source, payment)
            )
        }
        for (target in listOf(
            "intent://platformapi/startapp#Intent;scheme=alipays;end",
            "alipay://platformapi/startapp",
            "file:///android_asset/checkout",
            "alipays://name@platformapi/startapp",
            "alipays:///startapp"
        )) {
            assertNull(target, CashierBrowserPolicy.paymentPackage(order, target))
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
            assertNull(source, CashierBrowserPolicy.paymentPackage(source, payment))
        }
    }
}
