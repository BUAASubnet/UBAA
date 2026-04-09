package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking

class AuthServiceConcurrencyTest {

  @Test
  fun concurrentDuplicateLoginsReuseCommittedSession() = runBlocking {
    val counters = RequestCounters()
    val authService = createAuthService(counters)

    val responses = coroutineScope {
      List(3) { async { authService.login(LoginRequest(username = "2333", password = "secret")) } }
          .awaitAll()
    }

    assertEquals(listOf("2333", "2333", "2333"), responses.map { it.user.schoolid })
    assertEquals(1, counters.loadLoginPage.get())
    assertEquals(1, counters.submitCredentials.get())
    assertEquals(1, counters.activateLogin.get())
    assertEquals(3, counters.fetchUcUser.get())
  }

  @Test
  fun loginWithExecutionSkipsCommittedSessionReuse() = runBlocking {
    val counters = RequestCounters()
    val sessionManager = createSessionManager(counters)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService)

    val candidate = sessionManager.prepareSession("2333")
    sessionManager.commitSession(candidate, UserData(name = "Alice", schoolid = "2333"))

    val response =
        authService.login(
            LoginRequest(
                username = "2333",
                password = "secret",
                execution = "e1s1",
                clientId = "missing-client",
            )
        )

    assertEquals("2333", response.user.schoolid)
    assertEquals(0, counters.loadLoginPage.get())
    assertEquals(1, counters.submitCredentials.get())
    assertEquals(1, counters.activateLogin.get())
    assertEquals(1, counters.fetchUcUser.get())
    assertTrue(
        sessionManager.getSession("2333", SessionManager.SessionAccess.READ_ONLY) != null,
    )
  }

  @Test
  fun reusedSessionValidationTimeoutDoesNotFallbackToFreshLogin() = runBlocking {
    val counters = RequestCounters()
    val sessionManager = createSessionManager {
      authMockClient(
          counters = counters,
          ucStatusException = UpstreamTimeoutException("认证服务响应超时，请稍后重试", "auth_upstream_timeout"),
      )
    }
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService)

    val candidate = sessionManager.prepareSession("2333")
    sessionManager.commitSession(candidate, UserData(name = "Alice", schoolid = "2333"))

    assertFailsWith<UpstreamTimeoutException> {
      authService.login(LoginRequest(username = "2333", password = "secret"))
    }

    assertEquals(0, counters.loadLoginPage.get())
    assertEquals(0, counters.submitCredentials.get())
    assertEquals(0, counters.activateLogin.get())
    assertEquals(1, counters.fetchUcUser.get())
    assertTrue(sessionManager.getSession("2333", SessionManager.SessionAccess.READ_ONLY) != null)
  }

  @Test
  fun freshLoginTimeoutDoesNotLeaveCommittedSessionBehind() = runBlocking {
    val counters = RequestCounters()
    val cookieStorageFactory = TrackingCookieStorageFactory()
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = cookieStorageFactory,
            clientFactory = { _: CookiesStorage ->
              authMockClient(
                  counters = counters,
                  loginSubmitException =
                      UpstreamTimeoutException(
                          "认证服务响应超时，请稍后重试",
                          "auth_upstream_timeout",
                      ),
              )
            },
        )
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService)

    assertFailsWith<UpstreamTimeoutException> {
      authService.login(LoginRequest(username = "2444", password = "secret"))
    }

    assertEquals(1, counters.loadLoginPage.get())
    assertEquals(1, counters.submitCredentials.get())
    assertEquals(0, counters.activateLogin.get())
    assertEquals(0, counters.fetchUcUser.get())
    assertEquals(null, sessionManager.getSession("2444", SessionManager.SessionAccess.READ_ONLY))
    assertTrue(cookieStorageFactory.events.contains("clear"))
    assertTrue(cookieStorageFactory.events.contains("close"))
  }

  @Test
  fun preloadTimeoutDegradesAndCleansPreloginSession() = runBlocking {
    val sessionManager = createSessionManager {
      authMockClient(
          counters = RequestCounters(),
          loginPageException = UpstreamTimeoutException("认证服务响应超时，请稍后重试", "auth_upstream_timeout"),
      )
    }
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService)

    val response = authService.preloadLoginState("client-1")

    assertEquals("client-1", response.clientId)
    assertEquals(false, response.captchaRequired)
    assertEquals(0, sessionManager.preLoginSessionCount())
  }

  @Test
  fun concurrentSessionValidationSharesSingleUcRequest() = runBlocking {
    val counters = RequestCounters()
    val sessionManager = createSessionManager {
      authMockClient(
          counters = counters,
          ucStatusDelayMillis = 50L,
      )
    }
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    val authService = AuthService(sessionManager, refreshTokenService)

    val candidate = sessionManager.prepareSession("2333")
    val session =
        sessionManager.commitSession(candidate, UserData(name = "Alice", schoolid = "2333"))

    val results = coroutineScope {
      List(3) { async { authService.validateSession(session) } }.awaitAll()
    }

    assertTrue(results.all { it is AuthService.SessionValidationResult.Valid })
    assertEquals(1, counters.fetchUcUser.get())
  }

  private fun createAuthService(counters: RequestCounters): AuthService {
    val sessionManager = createSessionManager(counters)
    val refreshTokenService = RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore())
    return AuthService(sessionManager, refreshTokenService)
  }

  private fun createSessionManager(counters: RequestCounters): SessionManager {
    return createSessionManager { authMockClient(counters) }
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
      counters: RequestCounters,
      loginPageStatus: HttpStatusCode = HttpStatusCode.OK,
      loginPageContent: String = loginPageHtml(),
      loginPageException: Throwable? = null,
      loginSubmitStatus: HttpStatusCode = HttpStatusCode.Found,
      loginSubmitException: Throwable? = null,
      ucStatusContent: String = """{"code":0,"data":{"name":"Alice","schoolid":"2333"}}""",
      ucStatusStatus: HttpStatusCode = HttpStatusCode.OK,
      ucStatusException: Throwable? = null,
      ucStatusDelayMillis: Long = 0L,
  ): HttpClient {
    return HttpClient(MockEngine) {
      engine {
        addHandler { request ->
          when {
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" -> {
              counters.loadLoginPage.incrementAndGet()
              loginPageException?.let { throw it }
              respond(
                  content = loginPageContent,
                  status = loginPageStatus,
                  headers = htmlHeaders(),
              )
            }
            request.method == HttpMethod.Post &&
                request.url.toString() == "https://sso.buaa.edu.cn/login" -> {
              counters.submitCredentials.incrementAndGet()
              loginSubmitException?.let { throw it }
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
            }
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/landing" ->
                respond(
                    content = "",
                    status = HttpStatusCode.OK,
                    headers = htmlHeaders(),
                )
            request.method == HttpMethod.Get &&
                request.url.toString().startsWith("https://uc.buaa.edu.cn/api/login") -> {
              counters.activateLogin.incrementAndGet()
              respond(
                  content = "",
                  status = HttpStatusCode.OK,
                  headers = jsonHeaders(),
              )
            }
            request.method == HttpMethod.Get &&
                request.url.toString() == "https://uc.buaa.edu.cn/api/uc/status" -> {
              counters.fetchUcUser.incrementAndGet()
              if (ucStatusDelayMillis > 0) {
                delay(ucStatusDelayMillis)
              }
              ucStatusException?.let { throw it }
              respond(
                  content = ucStatusContent,
                  status = ucStatusStatus,
                  headers = jsonHeaders(),
              )
            }
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

  private fun htmlHeaders() = headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString())

  private fun jsonHeaders() =
      headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString())
}

private class RequestCounters {
  val loadLoginPage = AtomicInteger(0)
  val submitCredentials = AtomicInteger(0)
  val activateLogin = AtomicInteger(0)
  val fetchUcUser = AtomicInteger(0)
}
