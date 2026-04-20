package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.MapSettings
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import io.ktor.utils.io.*
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AuthServiceTest {

  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
  }

  @Test
  fun shouldReturnPreloadResponseWhenPreloadLoginStateSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/auth/preload", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      LoginPreloadResponse(
                          captchaRequired = true,
                          captcha = CaptchaInfo(id = "test-id", imageUrl = "test-url"),
                          execution = "test-execution",
                          clientId = "test-client-id",
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val apiClient = ApiClient(mockEngine)
    val authService = AuthService(apiClient)

    val result = authService.preloadLoginState()

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals(true, response?.captchaRequired)
    assertEquals("test-id", response?.captcha?.id)
    assertEquals("test-execution", response?.execution)
  }

  @Test
  fun shouldReturnLoginResponseWhenLoginSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/auth/login", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      LoginResponse(
                          user = UserData(name = "Test User", schoolid = "12345678"),
                          accessToken = "test-access-token",
                          refreshToken = "test-refresh-token",
                          accessTokenExpiresAt = "2026-03-23T10:00:00Z",
                          refreshTokenExpiresAt = "2026-03-30T10:00:00Z",
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val apiClient = ApiClient(mockEngine)
    val authService = AuthService(apiClient)

    val result = authService.login("username", "password")

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals("Test User", response?.user?.name)
    assertEquals("test-access-token", response?.accessToken)
    assertEquals("test-refresh-token", AuthTokensStore.get()?.refreshToken)
  }

  @Test
  fun shouldReturnFailureWhenLoginUnauthorized() = runTest {
    val mockEngine = MockEngine { _ ->
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      ApiErrorResponse(
                          ApiErrorDetails(
                              code = "invalid_credentials",
                              message = "Invalid credentials",
                          )
                      )
                  )
              ),
          status = HttpStatusCode.Unauthorized,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val apiClient = ApiClient(mockEngine)
    val authService = AuthService(apiClient)

    val result = authService.login("username", "wrong-password")

    assertTrue(result.isFailure)
    assertEquals("账号或密码错误，请重试", result.exceptionOrNull()?.message)
  }

  @Test
  fun shouldRefreshAccessTokenAfterUnauthorizedStatus() = runTest {
    AuthTokensStore.save(
        StoredAuthTokens(
            accessToken = "stale-access-token",
            refreshToken = "stale-refresh-token",
        )
    )

    var statusCalls = 0
    val mockEngine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/auth/status" -> {
          statusCalls++
          val expectedToken =
              if (statusCalls == 1) "Bearer stale-access-token" else "Bearer fresh-access-token"
          assertEquals(expectedToken, request.headers[HttpHeaders.Authorization])

          if (statusCalls == 1) {
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            ApiErrorResponse(
                                ApiErrorDetails(
                                    code = "invalid_token",
                                    message = "Invalid or expired JWT token",
                                )
                            )
                        )
                    ),
                status = HttpStatusCode.Unauthorized,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
          } else {
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            SessionStatusResponse(
                                user = UserData(name = "Test User", schoolid = "12345678"),
                                lastActivity = "2026-03-23T10:00:00Z",
                                authenticatedAt = "2026-03-23T09:00:00Z",
                            )
                        )
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
          }
        }
        "/api/v1/auth/refresh" -> {
          assertNull(request.headers[HttpHeaders.Authorization])
          respond(
              content =
                  ByteReadChannel(
                      json.encodeToString(
                          TokenRefreshResponse(
                              accessToken = "fresh-access-token",
                              refreshToken = "fresh-refresh-token",
                              accessTokenExpiresAt = "2026-03-23T11:00:00Z",
                              refreshTokenExpiresAt = "2026-03-30T10:00:00Z",
                          )
                      )
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, "application/json"),
          )
        }
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val authService = AuthService(ApiClient(mockEngine))
    val result = authService.getAuthStatus()

    assertTrue(result.isSuccess)
    assertEquals("fresh-access-token", AuthTokensStore.get()?.accessToken)
    assertEquals("fresh-refresh-token", AuthTokensStore.get()?.refreshToken)
    assertEquals(2, statusCalls)
  }

  @Test
  fun shouldClearStoredTokensWhenRefreshFails() = runTest {
    AuthTokensStore.save(
        StoredAuthTokens(
            accessToken = "stale-access-token",
            refreshToken = "stale-refresh-token",
        )
    )

    val mockEngine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/auth/status" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            ApiErrorResponse(
                                ApiErrorDetails(
                                    code = "invalid_token",
                                    message = "Invalid or expired JWT token",
                                )
                            )
                        )
                    ),
                status = HttpStatusCode.Unauthorized,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        "/api/v1/auth/refresh" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            ApiErrorResponse(
                                ApiErrorDetails(
                                    code = "invalid_refresh_token",
                                    message = "Invalid or expired refresh token",
                                )
                            )
                        )
                    ),
                status = HttpStatusCode.Unauthorized,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val authService = AuthService(ApiClient(mockEngine))
    val result = authService.getAuthStatus()

    assertTrue(result.isFailure)
    assertNull(AuthTokensStore.get())
  }

  @Test
  fun shouldPreserveStoredTokensWhenStatusTimesOutUpstream() = runTest {
    AuthTokensStore.save(
        StoredAuthTokens(
            accessToken = "stale-access-token",
            refreshToken = "stale-refresh-token",
        )
    )

    val mockEngine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/auth/status" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            ApiErrorResponse(
                                ApiErrorDetails(
                                    code = "auth_upstream_timeout",
                                    message = "认证服务响应超时，请稍后重试",
                                )
                            )
                        )
                    ),
                status = HttpStatusCode.ServiceUnavailable,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val authService = AuthService(ApiClient(mockEngine))
    val result = authService.getAuthStatus()

    assertTrue(result.isFailure)
    val exception = result.exceptionOrNull() as? ApiCallException
    assertTrue(exception != null)
    assertEquals("auth_upstream_timeout", exception.code)
    assertEquals("stale-access-token", AuthTokensStore.get()?.accessToken)
    assertEquals("stale-refresh-token", AuthTokensStore.get()?.refreshToken)
  }
}
