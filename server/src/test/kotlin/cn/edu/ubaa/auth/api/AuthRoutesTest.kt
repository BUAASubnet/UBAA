package cn.edu.ubaa.auth

import cn.edu.ubaa.metrics.LoginConnectionMode
import cn.edu.ubaa.metrics.LoginMetricsSink
import cn.edu.ubaa.metrics.LoginSuccessMode
import cn.edu.ubaa.model.dto.LoginPreloadRequest
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginStatsConnectionMode
import cn.edu.ubaa.model.dto.LoginStatsReportRequest
import cn.edu.ubaa.model.dto.LoginStatsSuccessMode
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.JwtUtil
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AuthRoutesTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun loginTimeoutReturnsServiceUnavailable() = testApplication {
    val sessionManager = createSessionManager {
      authMockClient(
          loginPageException = UpstreamTimeoutException("认证服务响应超时，请稍后重试", "auth_upstream_timeout")
      )
    }
    val authService =
        AuthService(
            sessionManager = sessionManager,
            refreshTokenService =
                RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
        )

    application {
      install(ContentNegotiation) { json() }
      routing { authRouting(sessionManager = sessionManager, authService = authService) }
    }

    val response =
        client.post("/api/v1/auth/login") {
          contentType(ContentType.Application.Json)
          setBody(json.encodeToString(LoginRequest(username = "2333", password = "secret")))
        }

    assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
    assertTrue(response.bodyAsText().contains("auth_upstream_timeout"))
  }

  @Test
  fun statusReturnsOkWhenUcValidationSucceeds() = testApplication {
    val sessionManager = createSessionManager { authMockClient() }
    val authService =
        AuthService(
            sessionManager = sessionManager,
            refreshTokenService =
                RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
        )
    val token = prepareSession(sessionManager, "2333")

    application {
      install(ContentNegotiation) { json() }
      routing { authRouting(sessionManager = sessionManager, authService = authService) }
    }

    val response =
        client.get("/api/v1/auth/status") { header(HttpHeaders.Authorization, "Bearer $token") }

    assertEquals(HttpStatusCode.OK, response.status)
    assertTrue(response.bodyAsText().contains("2333"))
  }

  @Test
  fun statusReturnsUnauthorizedAndClearsSessionWhenUcValidationFails() = testApplication {
    val sessionManager = createSessionManager {
      authMockClient(ucStatusContent = """{"code":10600,"data":null}""")
    }
    val authService =
        AuthService(
            sessionManager = sessionManager,
            refreshTokenService =
                RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
        )
    val token = prepareSession(sessionManager, "2444")

    application {
      install(ContentNegotiation) { json() }
      routing { authRouting(sessionManager = sessionManager, authService = authService) }
    }

    val response =
        client.get("/api/v1/auth/status") { header(HttpHeaders.Authorization, "Bearer $token") }

    assertEquals(HttpStatusCode.Unauthorized, response.status)
    assertTrue(response.bodyAsText().contains("invalid_token"))
    assertEquals(null, sessionManager.getSession("2444", SessionManager.SessionAccess.READ_ONLY))
  }

  @Test
  fun statusReturnsServiceUnavailableAndPreservesSessionWhenUcValidationTimesOut() =
      testApplication {
        val sessionManager = createSessionManager {
          authMockClient(
              ucStatusException =
                  UpstreamTimeoutException(
                      "认证服务响应超时，请稍后重试",
                      "auth_upstream_timeout",
                  )
          )
        }
        val authService =
            AuthService(
                sessionManager = sessionManager,
                refreshTokenService =
                    RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
            )
        val token = prepareSession(sessionManager, "2555")

        application {
          install(ContentNegotiation) { json() }
          routing { authRouting(sessionManager = sessionManager, authService = authService) }
        }

        val response =
            client.get("/api/v1/auth/status") { header(HttpHeaders.Authorization, "Bearer $token") }

        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        assertTrue(response.bodyAsText().contains("auth_upstream_timeout"))
        assertTrue(
            sessionManager.getSession("2555", SessionManager.SessionAccess.READ_ONLY) != null
        )
      }

  @Test
  fun preloadLockTimeoutReturnsDegradedResponseInsteadOfServerError() = testApplication {
    val sessionManager = createSessionManager { authMockClient() }
    val authService =
        AuthService(
            sessionManager = sessionManager,
            refreshTokenService =
                RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
            distributedLockManager =
                object : DistributedLockManager {
                  override suspend fun <T> withLock(
                      scope: String,
                      key: String,
                      block: suspend () -> T,
                  ): T {
                    throw UpstreamTimeoutException("认证请求繁忙，请稍后重试", "auth_lock_timeout")
                  }
                },
        )

    application {
      install(ContentNegotiation) { json() }
      routing { authRouting(sessionManager = sessionManager, authService = authService) }
    }

    val response =
        client.post("/api/v1/auth/preload") {
          contentType(ContentType.Application.Json)
          setBody(json.encodeToString(LoginPreloadRequest(clientId = "lock-timeout")))
        }

    assertEquals(HttpStatusCode.OK, response.status)
    assertTrue(response.bodyAsText().contains("\"clientId\":\"lock-timeout\""))
    assertTrue(response.bodyAsText().contains("\"captchaRequired\":false"))
  }

  @Test
  fun anonymousLoginStatsRouteRecordsConnectionMode() = testApplication {
    val sink = RecordingRouteLoginMetricsSink()

    application {
      install(ContentNegotiation) { json() }
      routing {
        authRouting(
            loginMetricsSink = sink,
            sessionManager = createSessionManager { authMockClient() },
        )
      }
    }

    val response =
        client.post("/api/v1/auth/login-stats") {
          contentType(ContentType.Application.Json)
          setBody(
              json.encodeToString(
                  LoginStatsReportRequest(
                      username = "2333",
                      successMode = LoginStatsSuccessMode.PRELOAD_AUTO,
                      connectionMode = LoginStatsConnectionMode.WEBVPN,
                  )
              )
          )
        }

    assertEquals(HttpStatusCode.OK, response.status)
    assertEquals(
        listOf(
            RouteLoginRecord(
                "2333",
                LoginSuccessMode.PRELOAD_AUTO,
                LoginConnectionMode.WEBVPN,
            )
        ),
        sink.records,
    )
  }

  private suspend fun prepareSession(sessionManager: SessionManager, username: String): String {
    val candidate = sessionManager.prepareSession(username)
    sessionManager.commitSession(candidate, UserData(name = "Alice", schoolid = username))
    return JwtUtil.generateToken(username, Duration.ofMinutes(30))
  }

  private fun createSessionManager(clientFactory: () -> HttpClient): SessionManager {
    return SessionManager(
        sessionStore = InMemorySessionStore(),
        preLoginStore = InMemoryPreLoginStore(),
        cookieStorageFactory = InMemoryCookieStorageFactory(),
        clientFactory = { _: CookiesStorage -> clientFactory() },
    )
  }

  private fun authMockClient(
      loginPageException: Throwable? = null,
      ucStatusContent: String = """{"code":0,"data":{"name":"Alice","schoolid":"2333"}}""",
      ucStatusException: Throwable? = null,
  ): HttpClient {
    return HttpClient(MockEngine) {
      engine {
        addHandler { request ->
          when {
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" -> {
              loginPageException?.let { throw it }
              respond(
                  content =
                      """
                      <html>
                        <body>
                          <form id="fm1" action="/login">
                            <input type="hidden" name="execution" value="e1s1" />
                          </form>
                        </body>
                      </html>
                      """
                          .trimIndent(),
                  status = HttpStatusCode.OK,
                  headers = htmlHeaders(),
              )
            }
            request.method == HttpMethod.Post &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" ->
                respond(
                    content = "",
                    status = HttpStatusCode.Found,
                    headers = headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/landing"),
                )
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/landing" ->
                respond(content = "", status = HttpStatusCode.OK, headers = htmlHeaders())
            request.method == HttpMethod.Get &&
                request.url.toString().startsWith("https://uc.buaa.edu.cn/api/login") ->
                respond(content = "", status = HttpStatusCode.OK, headers = jsonHeaders())
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/api/uc/status" -> {
              ucStatusException?.let { throw it }
              respond(
                  content = ucStatusContent,
                  status = HttpStatusCode.OK,
                  headers = jsonHeaders(),
              )
            }
            request.method == HttpMethod.Get &&
                request.url.toString().contains("/jwapp/sys/homeapp/api/home/currentUser.do") ->
                respond(content = "{}", status = HttpStatusCode.OK, headers = jsonHeaders())
            request.method == HttpMethod.Get &&
                request.url
                    .toString()
                    .contains("/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do") ->
                respond(
                    content = """{"code":"0","data":{"userId":"2333"}}""",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            else -> error("Unexpected request ${request.method.value} ${request.url}")
          }
        }
      }
    }
  }

  private fun htmlHeaders() = headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString())

  private fun jsonHeaders() =
      headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString())
}

private data class RouteLoginRecord(
    val username: String,
    val mode: LoginSuccessMode,
    val connectionMode: LoginConnectionMode,
)

private class RecordingRouteLoginMetricsSink : LoginMetricsSink {
  val records = mutableListOf<RouteLoginRecord>()

  override suspend fun recordSuccess(
      username: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
  ) {
    records += RouteLoginRecord(username, mode, connectionMode)
  }
}
