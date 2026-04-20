package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class LocalClassroomApiBackendTest {
  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    runTest { localConnectionTestMutex.lock() }
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    ConnectionRuntime.resolveSelectedMode()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    LocalUpstreamClientProvider.reset()
  }

  @AfterTest
  fun tearDown() {
    LocalUpstreamClientProvider.reset()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    localConnectionTestMutex.unlock()
  }

  @Test
  fun `classroom api uses direct upstream backend to query classrooms`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.host == "sso.buaa.edu.cn" && request.url.encodedPath == "/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        request.url.host == "app.buaa.edu.cn" &&
            request.url.encodedPath == "/buaafreeclass/wap/default/search1" -> {
          assertTrue(request.headers[HttpHeaders.UserAgent].orEmpty().contains("Mozilla/5.0"))
          assertEquals("XMLHttpRequest", request.headers["X-Requested-With"])
          assertEquals(
              "https://app.buaa.edu.cn/site/classRoomQuery/index",
              request.headers[HttpHeaders.Referrer],
          )
          assertEquals("1", request.url.parameters["xqid"])
          assertEquals("", request.url.parameters["floorid"])
          assertEquals("2026-04-20", request.url.parameters["date"])
          respond(
              content =
                  ByteReadChannel(
                      json.encodeToString(
                          ClassroomQueryResponse(
                              e = 0,
                              m = "ok",
                              d =
                                  cn.edu.ubaa.model.dto.ClassroomData(
                                      list =
                                          mapOf(
                                              "主楼" to
                                                  listOf(
                                                      cn.edu.ubaa.model.dto.ClassroomInfo(
                                                          id = "1",
                                                          floorid = "101",
                                                          name = "主M101",
                                                          kxsds = "1,2",
                                                      )
                                                  )
                                          )
                                  ),
                          )
                      )
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, "application/json"),
          )
        }
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = ClassroomApi().queryClassrooms(xqid = 1, date = "2026-04-20")

    assertTrue(result.isSuccess)
    assertEquals("主M101", result.getOrNull()?.d?.list?.get("主楼")?.singleOrNull()?.name)
  }

  @Test
  fun `classroom api clears local session when upstream redirects to sso`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.host == "sso.buaa.edu.cn" && request.url.encodedPath == "/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        request.url.host == "app.buaa.edu.cn" &&
            request.url.encodedPath == "/buaafreeclass/wap/default/search1" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn",
                    ),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = ClassroomApi().queryClassrooms(xqid = 1, date = "2026-04-20")

    assertTrue(result.isFailure)
    val exception = assertIs<ApiCallException>(result.exceptionOrNull())
    assertEquals("unauthenticated", exception.code)
    assertNull(LocalAuthSessionStore.get())
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(HttpCookies) { storage = LocalCookieStore.storage(ConnectionMode.DIRECT) }
      }
    }
  }
}
