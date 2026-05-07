package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.AnnouncementService
import cn.edu.ubaa.api.auth.AppAnnouncement
import cn.edu.ubaa.api.core.ApiClient
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
import kotlinx.serialization.json.Json

class AnnouncementServiceTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun returnsAnnouncementWhenEndpointRespondsOk() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/app/announcement", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      AppAnnouncement(
                          id = "2026-05-07-main",
                          title = "公告",
                          content = "公告正文",
                          confirmText = "我知道了",
                          linkUrl = "https://example.com/notice",
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val announcement = AnnouncementService(ApiClient(mockEngine)).checkAnnouncement()

    assertEquals(
        AppAnnouncement(
            id = "2026-05-07-main",
            title = "公告",
            content = "公告正文",
            confirmText = "我知道了",
            linkUrl = "https://example.com/notice",
        ),
        announcement,
    )
  }

  @Test
  fun returnsNullWhenEndpointRespondsNoContent() = runTest {
    val mockEngine = MockEngine {
      respond(content = ByteReadChannel(""), status = HttpStatusCode.NoContent)
    }

    assertNull(AnnouncementService(ApiClient(mockEngine)).checkAnnouncement())
  }

  @Test
  fun returnsNullWhenEndpointFails() = runTest {
    val mockEngine = MockEngine {
      respond(content = ByteReadChannel(""), status = HttpStatusCode.InternalServerError)
    }

    assertNull(AnnouncementService(ApiClient(mockEngine)).checkAnnouncement())
  }

  @Test
  fun returnsNullWhenResponseCannotBeParsed() = runTest {
    val mockEngine = MockEngine {
      respond(
          content = ByteReadChannel("{ invalid json"),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    assertNull(AnnouncementService(ApiClient(mockEngine)).checkAnnouncement())
  }
}
