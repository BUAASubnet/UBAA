package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class LocalAuthServiceBackendTest {
  @BeforeTest
  fun setup() {
    runTest { localConnectionTestMutex.lock() }
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    ConnectionRuntime.resolveSelectedMode()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    LocalUpstreamClientProvider.reset()
  }

  @AfterTest
  fun tearDown() {
    LocalUpstreamClientProvider.reset()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    ConnectionRuntime.clearSelectedMode()
    localConnectionTestMutex.unlock()
  }

  @Test
  fun `preloadLoginState restores direct session from upstream cookies`() = runTest {
    val engine =
        MockEngine { request ->
          when (request.url.toString()) {
            "https://sso.buaa.edu.cn/login" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.Found,
                    headers =
                        headersOf(
                            HttpHeaders.Location to listOf("/cas/success"),
                            HttpHeaders.SetCookie to
                                listOf("CASTGC=sso-ticket; Domain=sso.buaa.edu.cn; Path=/; Secure"),
                        ),
                )
            "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.OK,
                    headers =
                        headersOf(HttpHeaders.SetCookie, "JSESSIONID=uc-session; Domain=uc.buaa.edu.cn; Path=/; Secure"),
                )
            "https://uc.buaa.edu.cn/api/uc/status" -> {
              assertTrue(request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=uc-session"))
              respond(
                  content =
                      ByteReadChannel(
                          """{"code":0,"data":{"name":"Test User","schoolid":"22373333","username":"22373333"}}"""
                      ),
                  status = HttpStatusCode.OK,
                  headers = headersOf(HttpHeaders.ContentType, "application/json"),
              )
            }
            else -> error("Unexpected url: ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result = LocalAuthServiceBackend().preloadLoginState()

    assertTrue(result.isSuccess)
    assertEquals("22373333", result.getOrNull()?.userData?.schoolid)
    assertNull(result.getOrNull()?.accessToken)
    assertEquals("22373333", LocalAuthSessionStore.get()?.username)
    assertNotNull(LocalCookieStore.load(ConnectionMode.DIRECT))
  }

  @Test
  fun `preloadLoginState uses webvpn wrapped upstream urls when current mode is webvpn`() =
      runTest {
        ConnectionModeStore.save(ConnectionMode.WEBVPN)
        ConnectionRuntime.resolveSelectedMode()
        val requestedUrls = mutableListOf<String>()
        val engine =
            MockEngine { request ->
              requestedUrls += request.url.toString()
              when {
                request.url.host == "d.buaa.edu.cn" &&
                    request.url.encodedPath.endsWith("/api/login") ->
                    respond(
                        content = ByteReadChannel.Empty,
                        status = HttpStatusCode.OK,
                        headers =
                            headersOf(HttpHeaders.SetCookie, "JSESSIONID=uc-session; Domain=d.buaa.edu.cn; Path=/; Secure"),
                    )
                request.url.host == "d.buaa.edu.cn" && request.url.encodedPath.endsWith("/login") ->
                    respond(
                        content = ByteReadChannel.Empty,
                        status = HttpStatusCode.Found,
                        headers =
                            headersOf(
                                HttpHeaders.Location to listOf("/cas/success"),
                                HttpHeaders.SetCookie to
                                    listOf("CASTGC=sso-ticket; Domain=d.buaa.edu.cn; Path=/; Secure"),
                            ),
                    )
                request.url.host == "d.buaa.edu.cn" &&
                    request.url.encodedPath.endsWith("/api/uc/status") -> {
                  assertTrue(request.url.encodedPath.startsWith("/https/"))
                  assertTrue(request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=uc-session"))
                  respond(
                      content =
                          ByteReadChannel(
                              """{"code":0,"data":{"name":"WebVPN User","schoolid":"22374444","username":"22374444"}}"""
                          ),
                      status = HttpStatusCode.OK,
                      headers = headersOf(HttpHeaders.ContentType, "application/json"),
                  )
                }
                else -> error("Unexpected url: ${request.url}")
              }
            }
        useMockUpstream(engine)

        val result = LocalAuthServiceBackend().preloadLoginState()

        assertTrue(result.isSuccess)
        assertEquals("22374444", result.getOrNull()?.userData?.schoolid)
        assertTrue(requestedUrls.all { it.startsWith("https://d.buaa.edu.cn/") })
        assertNotNull(LocalCookieStore.load(ConnectionMode.WEBVPN))
      }

  @Test
  fun `login returns captcha requirement when direct mode upstream asks for captcha`() = runTest {
    val loginHtml =
        """
        <html>
          <body>
            <form id="fm1">
              <input type="hidden" name="execution" value="e1s1" />
            </form>
            <script>
              config.captcha = { type: 'image', id: 'captcha-1' }
            </script>
          </body>
        </html>
        """.trimIndent()
    val engine =
        MockEngine { request ->
          when (request.url.toString()) {
            "https://sso.buaa.edu.cn/login" ->
                respond(
                    content = ByteReadChannel(loginHtml),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "text/html"),
                )
            "https://sso.buaa.edu.cn/captcha?captchaId=captcha-1" ->
                respond(
                    content = ByteReadChannel(byteArrayOf(1, 2, 3, 4)),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "image/jpeg"),
                )
            else -> error("Unexpected url: ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result = LocalAuthServiceBackend().login("22373333", "secret", captcha = null, execution = null)

    assertTrue(result.isFailure)
    val exception = result.exceptionOrNull()
    assertIs<CaptchaRequiredClientException>(exception)
    assertEquals("captcha-1", exception.captcha.id)
    assertTrue(exception.captcha.base64Image.orEmpty().startsWith("data:image/jpeg;base64,"))
  }

  @Test
  fun `getAuthStatus clears persisted local session when uc session is invalid`() = runTest {
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    val engine =
        MockEngine { request ->
          when (request.url.toString()) {
            "https://uc.buaa.edu.cn/api/uc/status" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.Unauthorized,
                )
            else -> error("Unexpected url: ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result = LocalAuthServiceBackend().getAuthStatus()

    assertTrue(result.isFailure)
    assertNull(LocalAuthSessionStore.get())
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(HttpCookies) {
          storage = LocalCookieStore.storage(ConnectionRuntime.currentMode() ?: ConnectionMode.DIRECT)
        }
      }
    }
  }
}
