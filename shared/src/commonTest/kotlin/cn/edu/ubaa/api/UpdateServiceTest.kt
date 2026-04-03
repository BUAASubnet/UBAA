package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class UpdateServiceTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun returnsNullWhenClientAndServerVersionsAreAligned() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/app/version", request.url.encodedPath)
      assertEquals(BuildKonfig.VERSION, request.url.parameters["clientVersion"])

      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      AppVersionCheckResponse(
                          serverVersion = BuildKonfig.VERSION,
                          aligned = true,
                          downloadUrl = "https://github.com/BUAASubnet/UBAA/releases",
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val updateInfo = UpdateService(ApiClient(mockEngine)).checkUpdate()

    assertNull(updateInfo)
  }

  @Test
  fun returnsVersionInfoWhenClientAndServerVersionsAreNotAligned() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/app/version", request.url.encodedPath)
      assertEquals("1.4.0", request.url.parameters["clientVersion"])

      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      AppVersionCheckResponse(
                          serverVersion = "1.5.0",
                          aligned = false,
                          downloadUrl = "https://download.example.com",
                          releaseNotes = "修复登录问题",
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val updateInfo = UpdateService(ApiClient(mockEngine)).checkUpdate("1.4.0")

    assertEquals("1.5.0", updateInfo?.serverVersion)
    assertEquals("https://download.example.com", updateInfo?.downloadUrl)
    assertEquals("修复登录问题", updateInfo?.releaseNotes)
  }
}
