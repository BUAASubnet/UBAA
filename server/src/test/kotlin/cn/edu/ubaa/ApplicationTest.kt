package cn.edu.ubaa

import cn.edu.ubaa.api.AppVersionCheckResponse
import cn.edu.ubaa.version.AppVersionRuntimeConfig
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlin.test.*
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

class ApplicationTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun testRoot() = testApplication {
    application { module() }
    val response = client.get("/")
    assertEquals(HttpStatusCode.OK, response.status)
    assertEquals("Ktor: ${Greeting().greet()}", response.bodyAsText())
  }

  @Test
  fun requestIdHeaderIsEchoedBack() = testApplication {
    application { module() }

    val response = client.get("/") { header(HttpHeaders.XRequestId, "req-test-123") }

    assertEquals(HttpStatusCode.OK, response.status)
    assertEquals("req-test-123", response.headers[HttpHeaders.XRequestId])
  }

  @Test
  fun userInfoWithoutTokenReturnsUnauthorized() = testApplication {
    application { module() }

    val response = client.get("/api/v1/user/info")

    assertEquals(HttpStatusCode.Unauthorized, response.status)
    assertTrue(response.bodyAsText().contains("invalid_token"))
    assertTrue(response.bodyAsText().contains("登录状态已失效，请重新登录"))
  }

  @Test
  fun versionEndpointReturnsAlignedResponseForMatchingVersion() = testApplication {
    application { module() }

    val serverVersion = AppVersionRuntimeConfig.load().serverVersion
    val response = client.get("/api/v1/app/version") { parameter("clientVersion", serverVersion) }
    val payload = json.decodeFromString<AppVersionCheckResponse>(response.bodyAsText())

    assertEquals(HttpStatusCode.OK, response.status)
    assertTrue(payload.aligned)
    assertEquals(serverVersion, payload.serverVersion)
  }
}
