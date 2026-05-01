package cn.edu.ubaa.grade

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class GradeServiceTest {
  @Test
  fun `get grades uses buaa score api query parameters`() = runBlocking {
    val originalVpnEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = false
    val requests = mutableListOf<Pair<HttpMethod, String>>()
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage ->
              HttpClient(MockEngine) {
                engine {
                  addHandler { request ->
                    requests += request.method to request.url.toString()
                    when {
                      request.url.toString() ==
                          "https://app.buaa.edu.cn/buaascore/wap/default/index" &&
                          request.method == HttpMethod.Get ->
                          respond(
                              content = ByteReadChannel("<html>score home</html>"),
                              status = HttpStatusCode.OK,
                              headers =
                                  headersOf(
                                      HttpHeaders.ContentType,
                                      ContentType.Text.Html.toString(),
                                  ),
                          )
                      request.url.toString() ==
                          "https://app.buaa.edu.cn/buaascore/wap/default/index" &&
                          request.method == HttpMethod.Post -> {
                        val bodyText = request.bodyText()
                        assertTrue(
                            "year=2025-2026" in bodyText,
                            "Expected grade request year, got: $bodyText",
                        )
                        assertTrue(
                            "xq=1" in bodyText,
                            "Expected grade request semester, got: $bodyText",
                        )
                        respond(
                            content =
                                ByteReadChannel(
                                    """
                                    {"e":0,"m":"","d":{"1":{"kcmc":"高等数学","xf":"4.0","kccj":"95","fslx":"百分制","kclx":"必修"}}}
                                    """
                                        .trimIndent()
                                ),
                            status = HttpStatusCode.OK,
                            headers =
                                headersOf(
                                    HttpHeaders.ContentType,
                                    ContentType.Application.Json.toString(),
                                ),
                        )
                      }
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

      val result =
          GradeService(sessionManager = sessionManager).getGrades("24182104", "2025-2026-1")

      assertEquals(
          listOf(
              HttpMethod.Get to "https://app.buaa.edu.cn/buaascore/wap/default/index",
              HttpMethod.Post to "https://app.buaa.edu.cn/buaascore/wap/default/index",
          ),
          requests,
      )
      assertEquals("高等数学", result.grades.singleOrNull()?.courseName)
      assertEquals("95", result.grades.singleOrNull()?.score)
      assertEquals(null, result.grades.singleOrNull()?.gradePoint)
    } finally {
      sessionManager.close()
      VpnCipher.isEnabled = originalVpnEnabled
    }
  }

  private fun io.ktor.client.request.HttpRequestData.bodyText(): String =
      when (val content = body) {
        is OutgoingContent.ByteArrayContent -> content.bytes().decodeToString()
        else -> error("Unsupported request body: ${content::class.simpleName}")
      }
}
