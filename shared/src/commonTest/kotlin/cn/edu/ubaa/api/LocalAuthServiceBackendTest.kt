package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.CaptchaRequiredClientException
import cn.edu.ubaa.api.auth.LoginStatsReporter
import cn.edu.ubaa.api.local.LocalAuthServiceBackend
import cn.edu.ubaa.api.local.LocalAuthSession
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.model.dto.LoginStatsConnectionMode
import cn.edu.ubaa.model.dto.LoginStatsReportRequest
import cn.edu.ubaa.model.dto.LoginStatsSuccessMode
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.content.TextContent
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
  private val reportedLogins = mutableListOf<LoginStatsReportRequest>()

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
    reportedLogins.clear()
    LoginStatsReporter.reporter = { request -> reportedLogins += request }
  }

  @AfterTest
  fun tearDown() {
    LoginStatsReporter.reset()
    LocalUpstreamClientProvider.reset()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    ConnectionRuntime.clearSelectedMode()
    reportedLogins.clear()
    localConnectionTestMutex.unlock()
  }

  @Test
  fun `直连预登录完成 UC 票据交换`() = runTest {
    verifyUcTicketExchange(ConnectionMode.DIRECT, preload = true)
  }

  @Test
  fun `直连密码登录完成 UC 票据交换`() = runTest {
    verifyUcTicketExchange(ConnectionMode.DIRECT, preload = false)
  }

  @Test
  fun `WebVPN 预登录升级网关包装的 HTTP SSO 地址`() = runTest {
    verifyUcTicketExchange(ConnectionMode.WEBVPN, preload = true)
  }

  @Test
  fun `WebVPN 密码登录升级原始 HTTP SSO 地址并保持网关路由`() = runTest {
    verifyUcTicketExchange(ConnectionMode.WEBVPN, preload = false)
  }

  private suspend fun verifyUcTicketExchange(mode: ConnectionMode, preload: Boolean) {
    ConnectionModeStore.save(mode)
    ConnectionRuntime.resolveSelectedMode()
    var ticketExchanged = false
    var passwordPosts = 0
    val activateUrl =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
    val serviceQuery = "service=https%3A%2F%2Fuc.buaa.edu.cn%2Fapi%2Flogin%3Ftarget%3Dtest"
    val engine = MockEngine { request ->
      assertEquals("https", request.url.protocol.name, "认证请求不得降级到 HTTP")
      if (mode == ConnectionMode.WEBVPN) {
        assertEquals("d.buaa.edu.cn", request.url.host)
        assertTrue(request.url.encodedPath.startsWith("/https/"))
      }
      val original = cn.edu.ubaa.api.local.LocalWebVpnSupport.fromWebVpnUrl(request.url.toString())
      when (original) {
        "https://sso.buaa.edu.cn/login" -> {
          if (request.method.value == "POST") {
            passwordPosts++
            val params = io.ktor.http.parseQueryString(request.bodyText())
            assertEquals("test-user", params["username"])
            assertEquals("test-password", params["password"])
            assertEquals("username_password", params["type"])
            assertEquals("e1s1", params["execution"])
            assertEquals("submit", params["_eventId"])
            respond(
                "",
                HttpStatusCode.Found,
                headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/"),
            )
          } else if (preload) {
            respond(
                "",
                HttpStatusCode.Found,
                headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/"),
            )
          } else {
            respond(
                """<form id="loginForm"><input name="execution" value="e1s1"/><input name="type" value="username_password"/><input name="_eventId" value="submit"/></form>""",
                HttpStatusCode.OK,
            )
          }
        }
        activateUrl ->
            if (ticketExchanged) {
              respond(
                  "",
                  HttpStatusCode.Found,
                  headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/"),
              )
            } else {
              val location = "http://sso.buaa.edu.cn/login?$serviceQuery"
              val wrapped =
                  if (mode == ConnectionMode.WEBVPN && preload)
                      cn.edu.ubaa.api.local.LocalWebVpnSupport.toWebVpnUrl(location)
                  else location
              respond("", HttpStatusCode.Found, headersOf(HttpHeaders.Location, wrapped))
            }
        "https://sso.buaa.edu.cn/login?$serviceQuery" ->
            respond(
                "",
                HttpStatusCode.Found,
                headersOf(HttpHeaders.Location, "$activateUrl&ticket=synthetic-ticket"),
            )
        "$activateUrl&ticket=synthetic-ticket" -> {
          ticketExchanged = true
          respond(
              "",
              HttpStatusCode.Found,
              headersOf(
                  HttpHeaders.Location to listOf(activateUrl),
                  HttpHeaders.SetCookie to listOf("JSESSIONID=synthetic-uc; Path=/; Secure"),
              ),
          )
        }
        "https://uc.buaa.edu.cn/" -> respond("", HttpStatusCode.OK)
        "https://uc.buaa.edu.cn/api/uc/status" -> {
          val authenticated =
              ticketExchanged &&
                  request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=synthetic-uc")
          respond(
              if (authenticated) """{"code":0,"data":{"name":"测试用户","schoolid":"2333"}}"""
              else """{"code":10600,"data":null}""",
              HttpStatusCode.OK,
              headersOf(HttpHeaders.ContentType, "application/json"),
          )
        }
        else -> error("出现非预期请求")
      }
    }
    useMockUpstream(engine)
    // WebVPN 主登录成功后的辅助直连也使用模拟客户端，不能向真实上游发出测试请求。
    LocalUpstreamClientProvider.isolatedClientFactory = { _, _ ->
      HttpClient(MockEngine { respond("", HttpStatusCode.ServiceUnavailable) })
    }

    val schoolid =
        if (preload) {
          val result = LocalAuthServiceBackend().preloadLoginState()
          assertTrue(result.isSuccess)
          result.getOrNull()?.userData?.schoolid
        } else {
          val result = LocalAuthServiceBackend().login("test-user", "test-password", null, null)
          assertTrue(result.isSuccess)
          result.getOrNull()?.user?.schoolid
        }
    assertEquals("2333", schoolid)
    assertEquals(if (preload) 0 else 1, passwordPosts)
    assertTrue(ticketExchanged)
  }

  @Test
  fun `UC 重定向循环应终止且不能创建登录态`() = runTest {
    var activationRequests = 0
    useMockUpstream(
        MockEngine { request ->
          if (request.url.host == "uc.buaa.edu.cn") activationRequests++
          respond("", HttpStatusCode.Found, headersOf(HttpHeaders.Location, request.url.toString()))
        }
    )
    val result = LocalAuthServiceBackend().preloadLoginState()
    assertTrue(result.isFailure)
    assertEquals(11, activationRequests)
    assertNull(LocalAuthSessionStore.get())
    assertTrue(reportedLogins.isEmpty())
  }

  @Test
  fun `preloadLoginState restores direct session from upstream cookies`() = runTest {
    val engine = MockEngine { request ->
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
                    headersOf(
                        HttpHeaders.SetCookie,
                        "JSESSIONID=uc-session; Domain=uc.buaa.edu.cn; Path=/; Secure",
                    ),
            )
        "https://uc.buaa.edu.cn/api/uc/status" -> {
          assertTrue(
              request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=uc-session")
          )
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
    assertEquals(
        listOf(
            LoginStatsReportRequest(
                username = "22373333",
                successMode = LoginStatsSuccessMode.PRELOAD_AUTO,
                connectionMode = LoginStatsConnectionMode.DIRECT,
            )
        ),
        reportedLogins,
    )
  }

  @Test
  fun `preloadLoginState uses webvpn wrapped upstream urls when current mode is webvpn`() =
      runTest {
        ConnectionModeStore.save(ConnectionMode.WEBVPN)
        ConnectionRuntime.resolveSelectedMode()
        val requestedUrls = mutableListOf<String>()
        val engine = MockEngine { request ->
          requestedUrls += request.url.toString()
          when {
            request.url.host == "d.buaa.edu.cn" && request.url.encodedPath.endsWith("/api/login") ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.OK,
                    headers =
                        headersOf(
                            HttpHeaders.SetCookie,
                            "JSESSIONID=uc-session; Domain=d.buaa.edu.cn; Path=/; Secure",
                        ),
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
              assertTrue(
                  request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=uc-session")
              )
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
        assertEquals(
            listOf(
                LoginStatsReportRequest(
                    username = "22374444",
                    successMode = LoginStatsSuccessMode.PRELOAD_AUTO,
                    connectionMode = LoginStatsConnectionMode.WEBVPN,
                )
            ),
            reportedLogins,
        )
      }

  @Test
  fun `login reports direct login stats after successful authentication`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login" ->
            when (request.method.value) {
              "GET" ->
                  respond(
                      content =
                          ByteReadChannel(
                              """
                              <html>
                                <body>
                                  <form id="fm1">
                                    <input type="hidden" name="execution" value="e1s1" />
                                  </form>
                                </body>
                              </html>
                              """
                                  .trimIndent()
                          ),
                      status = HttpStatusCode.OK,
                      headers = headersOf(HttpHeaders.ContentType, "text/html"),
                  )
              "POST" ->
                  respond(
                      content = ByteReadChannel.Empty,
                      status = HttpStatusCode.Found,
                      headers = headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/landing"),
                  )
              else -> error("Unexpected method: ${request.method}")
            }
        "https://uc.buaa.edu.cn/landing" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://uc.buaa.edu.cn/api/uc/status" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"code":0,"data":{"name":"Direct User","schoolid":"22375555","username":"22375555"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result =
        LocalAuthServiceBackend().login("22375555", "secret", captcha = null, execution = null)

    assertTrue(result.isSuccess)
    assertEquals("22375555", result.getOrNull()?.user?.schoolid)
    assertEquals(
        listOf(
            LoginStatsReportRequest(
                username = "22375555",
                successMode = LoginStatsSuccessMode.MANUAL,
                connectionMode = LoginStatsConnectionMode.DIRECT,
            )
        ),
        reportedLogins,
    )
  }

  @Test
  fun `login ignores sso password expiry warning and records direct login stats`() = runTest {
    var loginPostCount = 0
    var ignoreBody = ""
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login" ->
            when (request.method.value) {
              "GET" ->
                  respond(
                      content =
                          ByteReadChannel(
                              """
                              <html>
                                <body>
                                  <form id="fm1">
                                    <input type="hidden" name="execution" value="e1s1" />
                                  </form>
                                </body>
                              </html>
                              """
                                  .trimIndent()
                          ),
                      status = HttpStatusCode.OK,
                      headers = headersOf(HttpHeaders.ContentType, "text/html"),
                  )
              "POST" -> {
                loginPostCount += 1
                if (loginPostCount == 1) {
                  respond(
                      content = ByteReadChannel(passwordExpiryWarningHtml()),
                      status = HttpStatusCode.OK,
                      headers = headersOf(HttpHeaders.ContentType, "text/html"),
                  )
                } else {
                  ignoreBody = request.bodyText()
                  respond(
                      content = ByteReadChannel.Empty,
                      status = HttpStatusCode.Found,
                      headers = headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/landing"),
                  )
                }
              }
              else -> error("Unexpected method: ${request.method}")
            }
        "https://uc.buaa.edu.cn/landing" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://uc.buaa.edu.cn/api/uc/status" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"code":0,"data":{"name":"Direct User","schoolid":"22375555","username":"22375555"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result =
        LocalAuthServiceBackend().login("22375555", "secret", captcha = null, execution = null)

    assertTrue(result.isSuccess)
    assertEquals(2, loginPostCount)
    assertTrue(ignoreBody.contains("execution=e2s2"), "Unexpected ignore body: $ignoreBody")
    assertTrue(
        ignoreBody.contains("_eventId=ignoreAndContinue"),
        "Unexpected ignore body: $ignoreBody",
    )
    assertEquals("22375555", result.getOrNull()?.user?.schoolid)
    assertEquals(
        listOf(
            LoginStatsReportRequest(
                username = "22375555",
                successMode = LoginStatsSuccessMode.MANUAL,
                connectionMode = LoginStatsConnectionMode.DIRECT,
            )
        ),
        reportedLogins,
    )
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
        """
            .trimIndent()
    val engine = MockEngine { request ->
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

    val result =
        LocalAuthServiceBackend().login("22373333", "secret", captcha = null, execution = null)

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
    val engine = MockEngine { request ->
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
          storage =
              LocalCookieStore.storage(ConnectionRuntime.currentMode() ?: ConnectionMode.DIRECT)
        }
      }
    }
  }

  private fun passwordExpiryWarningHtml(): String =
      """
      <html>
        <body>
          <form id="continueForm" action="/login" method="post">
            <div>账号存在安全风险，请修改密码</div>
            <input type="hidden" name="execution" value="e2s2" />
            <button type="submit" name="_eventId" value="ignoreAndContinue">忽略提示</button>
          </form>
        </body>
      </html>
      """
          .trimIndent()

  private fun io.ktor.client.request.HttpRequestData.bodyText(): String =
      when (val content = body) {
        is TextContent -> content.text
        is OutgoingContent.ByteArrayContent -> content.bytes().decodeToString()
        else -> error("Unsupported request body: ${content::class.simpleName}")
      }
}
