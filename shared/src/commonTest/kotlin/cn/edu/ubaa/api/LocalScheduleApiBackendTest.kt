package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.feature.GradeApi
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.api.local.LocalAuthSession
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.model.dto.Exam
import cn.edu.ubaa.model.dto.ExamResponse
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.model.dto.TermResponse
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json

class LocalScheduleApiBackendTest {
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
  fun `graduate schedule uses GSMIS when undergraduate portal requires login`() = runTest {
    for (mode in listOf(ConnectionMode.DIRECT, ConnectionMode.WEBVPN)) {
      ConnectionModeStore.save(mode)
      ConnectionRuntime.resolveSelectedMode()
      LocalUpstreamClientProvider.reset()
      val requests = mutableListOf<String>()
      LocalUpstreamClientProvider.clientFactory = {
        HttpClient(
            MockEngine { request ->
              requests.add(request.url.toString())
              val content =
                  when {
                    request.url.encodedPath.endsWith("/currentUser.do") -> "<html>统一身份认证</html>"
                    request.url.encodedPath.endsWith("/getUserInfo.do") ->
                        error("研究生课表不能以 GSMIS 探测为前提")
                    request.url.encodedPath.endsWith("/kfdxnxqcx.do") ->
                        """{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"示例学期"}]}}}"""
                    request.url.encodedPath.endsWith("/bykb/loadXskbData.do") -> {

                      assertEquals(HttpMethod.Post, request.method)
                      """{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"""
                    }
                    else -> ""
                  }
              respond(
                  content,
                  HttpStatusCode.OK,
                  headersOf(HttpHeaders.ContentType, "application/json"),
              )
            }
        )
      }
      // 每种连接模式拥有自己的会话存储。
      LocalAuthSessionStore.save(
          LocalAuthSession(
              username = "test-graduate",
              user = UserData("Test", "test-graduate"),
              authenticatedAt = "2026-09-07T00:00:00Z",
              lastActivity = "2026-09-07T00:00:00Z",
          )
      )
      val imported = ScheduleApi().importSemester().getOrThrow()
      assertEquals("20261", imported.termCode)
      assertEquals(1, requests.count { it.contains("/bykb/loadXskbData.do") })
      assertTrue(requests.any { it.contains("/bykb/loadXskbData.do") })
      if (mode == ConnectionMode.WEBVPN)
          assertTrue(requests.all { it.startsWith("https://d.buaa.edu.cn/") })
    }
  }

  @Test
  fun `undergraduate JSON error falls back to graduate source and remembers it for this login`() =
      runTest {
        val requests = mutableListOf<String>()
        LocalUpstreamClientProvider.clientFactory = {
          HttpClient(
              MockEngine { request ->
                requests.add(request.url.encodedPath)
                val body =
                    when {
                      request.url.encodedPath.endsWith("/currentUser.do") -> """{"code":"1"}"""
                      request.url.encodedPath.endsWith("/schoolCalendars.do") ->
                          """{"datas":[],"code":"1","msg":"unsupported"}"""
                      request.url.encodedPath.endsWith("/kfdxnxqcx.do") ->
                          """{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"示例学期"}]}}}"""
                      request.url.encodedPath.endsWith("/loadXskbData.do") ->
                          """{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"""
                      request.url.encodedPath.endsWith("/*default/index.do") -> "<html>已登录</html>"
                      else -> error("Unexpected request")
                    }
                respond(body)
              }
          )
        }
        val api = ScheduleApi()
        assertEquals("20261", api.getTerms().getOrThrow().single().itemCode)
        requests.clear()
        assertTrue(api.getWeeks("20261").getOrThrow().isEmpty())
        assertEquals(3, requests.size)
        assertTrue(requests.none { it.contains("/homeapp/") })
      }

  @Test
  fun `schedule api uses direct upstream backend to fetch terms`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do" ->
            respond(
                content = ByteReadChannel("""{"user":"ok"}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do" -> {
          assertEquals(
              "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html",
              request.headers[HttpHeaders.Referrer],
          )
          respond(
              content =
                  ByteReadChannel(
                      json.encodeToString(
                          TermResponse(
                              datas =
                                  listOf(
                                      Term(
                                          itemCode = "2025-2026-1",
                                          itemName = "2025-2026学年第一学期",
                                          selected = true,
                                          itemIndex = 1,
                                      )
                                  ),
                              code = "0",
                              msg = null,
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

    val result = ScheduleApi().getTerms()

    assertTrue(result.isSuccess)
    assertEquals("2025-2026-1", result.getOrNull()?.singleOrNull()?.itemCode)
  }

  @Test
  fun `schedule api uses direct upstream backend to fetch exam arrangement`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do" ->
            respond(
                content = ByteReadChannel("""{"user":"ok"}"""),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do?termCode=2025-2026-1" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            ExamResponse(
                                code = "0",
                                datas =
                                    listOf(
                                        Exam(
                                            courseName = "高等数学",
                                            courseNo = "MATH001",
                                            examPlace = "主M101",
                                        )
                                    ),
                            )
                        )
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = ScheduleApi().getExamArrangement("2025-2026-1")

    assertTrue(result.isSuccess)
    assertEquals("高等数学", result.getOrNull()?.arranged?.singleOrNull()?.courseName)
  }

  @Test
  fun `grade api uses direct upstream backend to fetch grades`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.toString() == "https://app.buaa.edu.cn/buaascore/wap/default/index" &&
            request.method == HttpMethod.Get ->
            respond(
                content = ByteReadChannel("<html>score home</html>"),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "text/html"),
            )
        request.url.toString() == "https://app.buaa.edu.cn/buaascore/wap/default/index" &&
            request.method == HttpMethod.Post -> {
          val bodyText = request.bodyText()
          assertTrue("year=2025-2026" in bodyText, "Expected grade request year, got: $bodyText")
          assertTrue("xq=1" in bodyText, "Expected grade request semester, got: $bodyText")
          respond(
              content =
                  ByteReadChannel(
                      """
                      {"e":0,"m":"","d":{"1":{"kcmc":"高等数学","xf":"4.0","kccj":"95","fslx":"百分制","kclx":"必修"}}}
                      """
                          .trimIndent()
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, "application/json"),
          )
        }
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = GradeApi().getGrades("2025-2026-1")

    assertTrue(result.isSuccess)
    assertEquals("高等数学", result.getOrNull()?.grades?.singleOrNull()?.courseName)
    assertEquals("95", result.getOrNull()?.grades?.singleOrNull()?.score)
    assertEquals(null, result.getOrNull()?.grades?.singleOrNull()?.gradePoint)
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(HttpCookies) { storage = LocalCookieStore.storage(ConnectionMode.DIRECT) }
      }
    }
  }

  private fun io.ktor.client.request.HttpRequestData.bodyText(): String =
      when (val content = body) {
        is OutgoingContent.ByteArrayContent -> content.bytes().decodeToString()
        else -> error("Unsupported request body: ${content::class.simpleName}")
      }
}
