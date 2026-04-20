package cn.edu.ubaa.auth

import cn.edu.ubaa.metrics.LoginMetricsSink
import cn.edu.ubaa.metrics.LoginConnectionMode
import cn.edu.ubaa.metrics.LoginSuccessMode
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.UserData
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking

class AuthServiceLoginMetricsTest {

  @Test
  fun manualLoginSuccessRecordsManualMetric() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val authService = createAuthService(::successfulManualLoginClient, sink)

    val response = authService.login(LoginRequest(username = "2333", password = "secret"))

    assertEquals("2333", response.user.schoolid)
    assertEquals(
        listOf(LoginRecord("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY)),
        sink.records,
    )
  }

  @Test
  fun preloadAutoLoginSuccessRecordsPreloadMetric() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val authService = createAuthService(::successfulPreloadLoginClient, sink)

    val response = authService.preloadLoginState("device-1")

    assertNotNull(response.accessToken)
    assertEquals("2333", response.userData?.schoolid)
    assertEquals(
        listOf(
            LoginRecord(
                "2333",
                LoginSuccessMode.PRELOAD_AUTO,
                LoginConnectionMode.SERVER_RELAY,
            )
        ),
        sink.records,
    )
  }

  @Test
  fun loginFailureDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val authService = createAuthService(::invalidCredentialsClient, sink)

    assertFailsWith<LoginException> {
      authService.login(LoginRequest(username = "2333", password = "wrong"))
    }

    assertTrue(sink.records.isEmpty())
  }

  @Test
  fun captchaInterruptionDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val authService = createAuthService(::captchaRequiredClient, sink)

    assertFailsWith<CaptchaRequiredException> {
      authService.login(LoginRequest(username = "2333", password = "secret"))
    }

    assertTrue(sink.records.isEmpty())
  }

  @Test
  fun cachedSessionTokenIssuanceDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val sessionManager = createSessionManager(::successfulManualLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService, sink)

    val candidate = sessionManager.prepareSession("2333")
    sessionManager.commitSession(
        candidate,
        UserData(name = "Alice", schoolid = "2333"),
        AcademicPortalType.UNDERGRAD,
    )

    val response = authService.login(LoginRequest(username = "2333", password = "secret"))

    assertEquals("2333", response.user.schoolid)
    assertTrue(sink.records.isEmpty())
  }

  @Test
  fun refreshTokensDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val sessionManager = createSessionManager(::successfulManualLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService, sink)

    val candidate = sessionManager.prepareSession("2333")
    sessionManager.commitSession(
        candidate,
        UserData(name = "Alice", schoolid = "2333"),
        AcademicPortalType.UNDERGRAD,
    )
    val issued = refreshTokenService.issueTokens("2333")

    val refreshed = authService.refreshTokens(issued.refreshToken)

    assertNotNull(refreshed)
    assertTrue(sink.records.isEmpty())
  }

  @Test
  fun loginSucceedsWhenPortalWarmupFallsBackToUnavailable() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val sessionManager = createSessionManager(::successfulManualLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val portalWarmupCoordinator =
        AcademicPortalWarmupCoordinator(
            sessionManager = sessionManager,
            portalProbe = { AcademicPortalProbeResult.UNAVAILABLE },
            scope = kotlinx.coroutines.CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    val authService =
        AuthService(sessionManager, refreshTokenService, sink, portalWarmupCoordinator)

    val response = authService.login(LoginRequest(username = "2333", password = "secret"))

    assertEquals("2333", response.user.schoolid)
    assertEquals(
        listOf(LoginRecord("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY)),
        sink.records,
    )
  }

  @Test
  fun validateSessionOnlyDependsOnUcState() = runBlocking {
    val sessionManager = createSessionManager(::successfulManualLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val portalWarmupCoordinator =
        AcademicPortalWarmupCoordinator(
            sessionManager = sessionManager,
            portalProbe = { AcademicPortalProbeResult.UNAVAILABLE },
            scope = kotlinx.coroutines.CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    val authService =
        AuthService(
            sessionManager,
            refreshTokenService,
            portalWarmupCoordinator = portalWarmupCoordinator,
        )

    val candidate = sessionManager.prepareSession("2333")
    val session =
        sessionManager.commitSession(candidate, UserData(name = "Alice", schoolid = "2333"))

    assertTrue(authService.validateSession(session) is AuthService.SessionValidationResult.Valid)
  }

  @Test
  fun manualLoginTokenIssuanceFailureDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val sessionManager = createSessionManager(::successfulManualLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = FailingRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService, sink)

    assertFailsWith<IllegalStateException> {
      authService.login(LoginRequest(username = "2333", password = "secret"))
    }

    assertTrue(sink.records.isEmpty())
  }

  @Test
  fun preloadAutoLoginTokenIssuanceFailureDoesNotRecordMetrics() = runBlocking {
    val sink = RecordingLoginMetricsSink()
    val sessionManager = createSessionManager(::successfulPreloadLoginClient)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = FailingRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService, sink)

    val response = authService.preloadLoginState("device-1")

    assertEquals("device-1", response.clientId)
    assertEquals(null, response.accessToken)
    assertEquals(null, response.refreshToken)
    assertTrue(sink.records.isEmpty())
  }

  private fun createAuthService(
      clientFactory: () -> HttpClient,
      sink: RecordingLoginMetricsSink,
  ): AuthService {
    val sessionManager = createSessionManager(clientFactory)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    return AuthService(sessionManager, refreshTokenService, sink)
  }

  private fun createSessionManager(clientFactory: () -> HttpClient): SessionManager {
    return SessionManager(
        sessionStore = InMemorySessionStore(),
        preLoginStore = InMemoryPreLoginStore(),
        cookieStorageFactory = InMemoryCookieStorageFactory(),
        clientFactory = { _: CookiesStorage -> clientFactory() },
    )
  }

  private fun successfulManualLoginClient(): HttpClient {
    return authMockClient(
        loginPageStatus = HttpStatusCode.OK,
        loginPageContent = loginPageHtml(),
        loginSubmitStatus = HttpStatusCode.Found,
    )
  }

  private fun successfulPreloadLoginClient(): HttpClient {
    return authMockClient(
        loginPageStatus = HttpStatusCode.Found,
        loginPageContent = "",
        loginSubmitStatus = HttpStatusCode.OK,
    )
  }

  private fun invalidCredentialsClient(): HttpClient {
    return authMockClient(
        loginPageStatus = HttpStatusCode.OK,
        loginPageContent = loginPageHtml(),
        loginSubmitStatus = HttpStatusCode.Unauthorized,
    )
  }

  private fun captchaRequiredClient(): HttpClient {
    return authMockClient(
        loginPageStatus = HttpStatusCode.OK,
        loginPageContent = captchaPageHtml(),
        loginSubmitStatus = HttpStatusCode.OK,
    )
  }

  private fun authMockClient(
      loginPageStatus: HttpStatusCode,
      loginPageContent: String,
      loginSubmitStatus: HttpStatusCode,
  ): HttpClient {
    return HttpClient(MockEngine) {
      engine {
        addHandler { request ->
          when {
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" ->
                respond(
                    content = loginPageContent,
                    status = loginPageStatus,
                    headers = htmlHeaders(),
                )
            request.method == HttpMethod.Post &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" ->
                respond(
                    content = "",
                    status = loginSubmitStatus,
                    headers =
                        if (loginSubmitStatus.value in 300..399) {
                          headersOf(HttpHeaders.Location, "https://uc.buaa.edu.cn/landing")
                        } else {
                          htmlHeaders()
                        },
                )
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/landing" ->
                respond(
                    content = "",
                    status = HttpStatusCode.OK,
                    headers = htmlHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url.toString().startsWith("https://uc.buaa.edu.cn/api/login") ->
                respond(
                    content = "",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/api/uc/status" ->
                respond(
                    content = """{"code":0,"data":{"name":"Alice","schoolid":"2333"}}""",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url.toString().endsWith("/jwapp/sys/homeapp/api/home/currentUser.do") ->
                respond(
                    content = """{"code":"0","data":{"name":"Alice"}}""",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url
                    .toString()
                    .endsWith("/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do") ->
                respond(
                    content = """{"code":"1","data":{}}""",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url.toString().startsWith("https://sso.buaa.edu.cn/captcha") ->
                respond(
                    content = ByteReadChannel(byteArrayOf(1, 2, 3)),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, ContentType.Image.JPEG.toString()),
                )
            else -> error("Unexpected request ${request.method.value} ${request.url}")
          }
        }
      }
    }
  }

  private fun loginPageHtml(): String {
    return """
    <html>
      <body>
        <form id="fm1" action="/login">
          <input type="hidden" name="execution" value="e1s1" />
        </form>
      </body>
    </html>
    """
        .trimIndent()
  }

  private fun captchaPageHtml(): String {
    return """
    <html>
      <body>
        <form id="fm1" action="/login">
          <input type="hidden" name="execution" value="e1s1" />
        </form>
        <script>
          config.captcha = { type: 'image', id: 'captcha-1' };
        </script>
      </body>
    </html>
    """
        .trimIndent()
  }

  private fun htmlHeaders() = headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString())

  private fun jsonHeaders() =
      headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString())
}

private data class LoginRecord(
    val username: String,
    val mode: LoginSuccessMode,
    val connectionMode: LoginConnectionMode,
)

private class RecordingLoginMetricsSink : LoginMetricsSink {
  val records = mutableListOf<LoginRecord>()

  override suspend fun recordSuccess(
      username: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
  ) {
    records += LoginRecord(username, mode, connectionMode)
  }
}

private class FailingRefreshTokenStore : RefreshTokenStore {
  override suspend fun saveToken(
      username: String,
      token: String,
      issuedAt: java.time.Instant,
      expiresAt: java.time.Instant,
  ) {
    throw IllegalStateException("token store unavailable")
  }

  override suspend fun findToken(token: String): RefreshTokenRecord? = null

  override suspend fun rotateToken(
      username: String,
      oldToken: String,
      newToken: String,
      issuedAt: java.time.Instant,
      expiresAt: java.time.Instant,
  ): Boolean = false

  override suspend fun deleteByUsername(username: String) = Unit

  override fun close() = Unit
}
