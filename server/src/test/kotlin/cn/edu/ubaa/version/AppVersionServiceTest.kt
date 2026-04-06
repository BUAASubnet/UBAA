package cn.edu.ubaa.version

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotSame
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json

class AppVersionServiceTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun matchingVersionsAreAlignedWithoutFetchingReleaseNotes() = runTest {
    var fetchCalls = 0
    val service =
        AppVersionService(
            config =
                AppVersionRuntimeConfig(
                    serverVersion = "1.5.0",
                    downloadUrl = "https://download.example.com",
                ),
            releaseNotesFetcher =
                object : ReleaseNotesFetcher {
                  override suspend fun fetchReleaseNotes(serverVersion: String): String? {
                    fetchCalls += 1
                    return "ignored"
                  }
                },
        )

    val response = service.checkVersion("v1.5.0")

    assertTrue(response.aligned)
    assertNull(response.releaseNotes)
    assertEquals(0, fetchCalls)
  }

  @Test
  fun lowerClientVersionReturnsUpdateInfo() = runTest {
    val service =
        AppVersionService(
            config =
                AppVersionRuntimeConfig(
                    serverVersion = "1.5.0",
                    downloadUrl = "https://download.example.com",
                ),
            releaseNotesFetcher =
                object : ReleaseNotesFetcher {
                  override suspend fun fetchReleaseNotes(serverVersion: String): String? = "修复了一批问题"
                },
        )

    val response = service.checkVersion("1.4.0")

    assertFalse(response.aligned)
    assertEquals("1.5.0", response.serverVersion)
    assertEquals("https://download.example.com", response.downloadUrl)
    assertEquals("修复了一批问题", response.releaseNotes)
  }

  @Test
  fun higherClientVersionStillReturnsUpdateInfoWhenNotAligned() = runTest {
    val service =
        AppVersionService(
            config =
                AppVersionRuntimeConfig(
                    serverVersion = "1.5.0",
                    downloadUrl = "https://download.example.com",
                ),
            releaseNotesFetcher =
                object : ReleaseNotesFetcher {
                  override suspend fun fetchReleaseNotes(serverVersion: String): String? =
                      "请回退到服务端版本"
                },
        )

    val response = service.checkVersion("1.6.0")

    assertFalse(response.aligned)
    assertEquals("请回退到服务端版本", response.releaseNotes)
  }

  @Test
  fun unknownServerVersionDoesNotTriggerUpdatePrompt() = runTest {
    var fetchCalls = 0
    val service =
        AppVersionService(
            config =
                AppVersionRuntimeConfig(
                    serverVersion = "unknown",
                    downloadUrl = "https://download.example.com",
                ),
            releaseNotesFetcher =
                object : ReleaseNotesFetcher {
                  override suspend fun fetchReleaseNotes(serverVersion: String): String? {
                    fetchCalls += 1
                    return "should not be used"
                  }
                },
        )

    val response = service.checkVersion("1.5.1")

    assertTrue(response.aligned)
    assertEquals("unknown", response.serverVersion)
    assertNull(response.releaseNotes)
    assertEquals(0, fetchCalls)
  }

  @Test
  fun downloadUrlFallsBackToGithubReleasesWhenBlank() {
    assertEquals(
        "https://github.com/BUAASubnet/UBAA/releases",
        AppVersionRuntimeConfig.resolveDownloadUrl("  "),
    )
  }

  @Test
  fun proxyReleaseNotesFetcherFallsBackToRawTagWhenPrefixedTagMissing() = runTest {
    val mockEngine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/github/repos/BUAASubnet/UBAA/releases/tags/v1.5.0" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.NotFound,
            )
        "/github/repos/BUAASubnet/UBAA/releases/tags/1.5.0" ->
            respond(
                content = ByteReadChannel("""{"body":"修复登录和课表同步问题"}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val fetcher =
        ProxyReleaseNotesFetcher(
            client = HttpClient(mockEngine) { install(ContentNegotiation) { json(json) } }
        )

    val releaseNotes = fetcher.fetchReleaseNotes("1.5.0")

    assertEquals("修复登录和课表同步问题", releaseNotes)
  }

  @Test
  fun proxyReleaseNotesFetcherReturnsNullWhenProxyFails() = runTest {
    val mockEngine = MockEngine {
      respond(
          content = ByteReadChannel(""),
          status = HttpStatusCode.InternalServerError,
      )
    }

    val fetcher =
        ProxyReleaseNotesFetcher(
            client = HttpClient(mockEngine) { install(ContentNegotiation) { json(json) } }
        )

    assertNull(fetcher.fetchReleaseNotes("1.5.0"))
  }

  @Test
  fun globalAppVersionServiceRecreatesClosedInstance() {
    GlobalAppVersionService.close()

    val first = GlobalAppVersionService.instance

    GlobalAppVersionService.close()
    val second = GlobalAppVersionService.instance

    assertNotSame(first, second)
    GlobalAppVersionService.close()
  }
}
