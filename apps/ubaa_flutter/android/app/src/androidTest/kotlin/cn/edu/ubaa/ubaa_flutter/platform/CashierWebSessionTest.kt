package cn.edu.ubaa.ubaa_flutter.platform

import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class CashierWebSessionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val origin = "https://${UUID.randomUUID()}.invalid/"

    @Test
    fun checkoutStorageIsIsolatedFromTheDefaultProfileAndPreviousCheckout() {
        var supported = false
        instrumentation.runOnMainSync { supported = CashierWebSession.isSupported(context) }
        assumeTrue("WebView lacks isolated profiles", supported)

        val defaults = CookieManager.getInstance()
        defaults.setCookie(origin, "unrelated=preserved; Secure")
        try {
            withSession { first ->
                assertEquals("\"|\"", evaluate(first, STORAGE))
                assertEquals("\"account=first|first\"", evaluate(
                    first,
                    "document.cookie='account=first; Secure'; localStorage.setItem('account', 'first'); $STORAGE"
                ))
            }
            withSession { second ->
                assertEquals("\"|\"", evaluate(second, STORAGE))
            }
            assertEquals("unrelated=preserved", defaults.getCookie(origin))
        } finally {
            defaults.setCookie(origin, "unrelated=; Max-Age=0; Secure")
        }
    }

    private fun withSession(block: (WebView) -> Unit) {
        lateinit var session: CashierWebSession
        val loaded = CountDownLatch(1)
        instrumentation.runOnMainSync {
            session = checkNotNull(CashierWebSession.create(context))
            session.view.settings.apply {
                blockNetworkLoads = true
                javaScriptEnabled = true
                domStorageEnabled = true
            }
            session.view.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) { loaded.countDown() }
            }
            session.view.loadDataWithBaseURL(origin, "<html></html>", "text/html", "UTF-8", null)
        }
        try {
            check(loaded.await(10, TimeUnit.SECONDS)) { "Synthetic WebView page did not load" }
            block(session.view)
        } finally {
            instrumentation.runOnMainSync { session.close() }
        }
    }

    private fun evaluate(view: WebView, script: String): String? {
        val evaluated = CountDownLatch(1)
        var result: String? = null
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) {
                result = it
                evaluated.countDown()
            }
        }
        check(evaluated.await(10, TimeUnit.SECONDS)) { "Synthetic WebView script did not complete" }
        return result
    }

    private companion object {
        const val STORAGE = "document.cookie + '|' + (localStorage.getItem('account') || '')"
    }
}
