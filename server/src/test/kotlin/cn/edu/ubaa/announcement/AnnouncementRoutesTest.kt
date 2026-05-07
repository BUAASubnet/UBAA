package cn.edu.ubaa.announcement

import cn.edu.ubaa.api.auth.AppAnnouncement
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.serialization.json.Json

class AnnouncementRoutesTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun announcementEndpointReturnsCurrentAnnouncement() = testApplication {
    application {
      install(ContentNegotiation) { json() }
      routing {
        appAnnouncementRouting(
            object : AnnouncementProvider {
              override fun currentAnnouncement(): AppAnnouncement? =
                  AppAnnouncement(
                      id = "2026-05-07-main",
                      title = "公告",
                      content = "公告正文",
                      confirmText = "我知道了",
                  )
            }
        )
      }
    }

    val response = client.get("/api/v1/app/announcement")

    assertEquals(HttpStatusCode.OK, response.status)
    assertEquals(
        AppAnnouncement(
            id = "2026-05-07-main",
            title = "公告",
            content = "公告正文",
            confirmText = "我知道了",
        ),
        json.decodeFromString<AppAnnouncement>(response.bodyAsText()),
    )
  }

  @Test
  fun announcementEndpointReturnsNoContentWhenNoAnnouncementExists() = testApplication {
    application {
      install(ContentNegotiation) { json() }
      routing {
        appAnnouncementRouting(
            object : AnnouncementProvider {
              override fun currentAnnouncement(): AppAnnouncement? = null
            }
        )
      }
    }

    val response = client.get("/api/v1/app/announcement")

    assertEquals(HttpStatusCode.NoContent, response.status)
  }
}
