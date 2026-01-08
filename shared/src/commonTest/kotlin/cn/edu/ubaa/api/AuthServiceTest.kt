package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.MapSettings
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import io.ktor.utils.io.*
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AuthServiceTest {

  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    TokenStore.settings = MapSettings()
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
                token = "test-token",
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
    assertEquals("test-token", response?.token)
  }

  @Test
  fun shouldReturnFailureWhenLoginUnauthorized() = runTest {
    val mockEngine = MockEngine { _ ->
      respond(
        content =
          ByteReadChannel(
            json.encodeToString(
              ApiErrorResponse(
                ApiErrorDetails(code = "unauthorized", message = "Invalid credentials")
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
    assertEquals("Invalid credentials", result.exceptionOrNull()?.message)
  }
}
