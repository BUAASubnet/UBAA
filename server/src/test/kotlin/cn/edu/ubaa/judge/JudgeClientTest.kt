package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class JudgeClientTest {
  @Test
  fun `get courses activates judge cas service before course page`() = runBlocking {
    val originalVpnEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = false
    val requestedUrls = mutableListOf<String>()
    val userAgents = mutableListOf<String>()
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { storage: CookiesStorage ->
              HttpClient(MockEngine) {
                followRedirects = false
                install(HttpCookies) { this.storage = storage }
                engine {
                  addHandler { request ->
                    requestedUrls += request.url.toString()
                    userAgents += request.headers[HttpHeaders.UserAgent].orEmpty()
                    when (request.url.toString()) {
                      "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
                          respond(
                              content = "",
                              status = HttpStatusCode.Found,
                              headers =
                                  headersOf(
                                      HttpHeaders.Location,
                                      "http://judge.buaa.edu.cn/",
                                  ),
                          )
                      "http://judge.buaa.edu.cn/" ->
                          respondHtml("<html><body>judge ready</body></html>")
                      "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" ->
                          respondHtml(
                              """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
                          )
                      else -> error("Unexpected request: ${request.method.value} ${request.url}")
                    }
                  }
                }
              }
            },
        )

    try {
      val candidate = sessionManager.prepareSession("24182104")
      sessionManager.commitSession(candidate, UserData("Test User", "24182104"))

      val client = JudgeClient(username = "24182104", sessionManager = sessionManager)
      val courses = client.getCourses()

      assertEquals(listOf(JudgeCourseRaw("1", "软件工程")), courses)
      assertEquals(
          "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F",
          requestedUrls.first(),
      )
      assertEquals("http://judge.buaa.edu.cn/", requestedUrls[1])
      assertTrue(
          userAgents.all { it.startsWith("Mozilla/5.0") },
          "Judge requests should use browser-like headers: $userAgents",
      )
    } finally {
      sessionManager.close()
      VpnCipher.isEnabled = originalVpnEnabled
    }
  }
}

private fun io.ktor.client.engine.mock.MockRequestHandleScope.respondHtml(body: String) =
    respond(
        content = body,
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString()),
    )
