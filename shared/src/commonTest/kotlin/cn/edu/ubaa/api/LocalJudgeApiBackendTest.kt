package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class LocalJudgeApiBackendTest {
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
  fun `judge api uses direct upstream backend to fetch assignments`() = runTest {
    val requestedPaths = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedPaths +=
          request.url.encodedPath +
              request.url.encodedQuery.takeIf { it.isNotBlank() }?.let { "?$it" }.orEmpty()
      when (request.url.encodedPath) {
        "/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
            )
        "/" -> respondHtml("<html><body>judge ready</body></html>")
        "/courselist.jsp" ->
            respondHtml(
                """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
            )
        "/assignment/index.jsp" ->
            if (request.url.parameters["assignID"] == "101") {
              respondHtml(
                  """
                  <html><body>
                    作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                    作业满分： 100.00 ，共 2道 题
                    <table><tbody>
                      <tr><th>1.</th><td>设计说明</td><td>60.00</td><td>初次提交时间: 2026-04-17 12:24:26 得分：60.00</td></tr>
                      <tr><th>2.</th><td>用例设计</td><td>40.00</td><td>未提交答案</td></tr>
                    </tbody></table>
                  </body></html>
                  """
              )
            } else {
              respondHtml(
                  """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
              )
            }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = JudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    val assignment = result.getOrNull()?.assignments?.single()
    assertEquals("1", assignment?.courseId)
    assertEquals("101", assignment?.assignmentId)
    assertEquals("设计作业", assignment?.title)
    assertEquals(JudgeSubmissionStatus.PARTIAL, assignment?.submissionStatus)
    assertTrue(requestedPaths.contains("/courselist.jsp?courseID=0"))
    assertTrue(requestedPaths.contains("/courselist.jsp?courseID=1"))
  }

  @Test
  fun `judge api activates direct judge cas session before fetching assignments`() = runTest {
    var judgeSessionActive = false
    val requestedUrls = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F" -> {
          judgeSessionActive = true
          respond(
              content = ByteReadChannel.Empty,
              status = HttpStatusCode.Found,
              headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
          )
        }
        "https://judge.buaa.edu.cn/" -> respondHtml("<html><body>judge ready</body></html>")
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" ->
            if (judgeSessionActive) {
              respondHtml(
                  """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
              )
            } else {
              respondHtml(
                  """
                  <html><body>
                    <form><input name="execution" value="e1s1" /></form>
                    统一身份认证
                  </body></html>
                  """
              )
            }
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" ->
            respondHtml("<html><body>course selected</body></html>")
        "https://judge.buaa.edu.cn/assignment/index.jsp" ->
            respondHtml(
                """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
            )
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" ->
            respondHtml(
                """
                <html><body>
                  作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                  作业满分： 100.00 ，共 1道 题
                  <table><tbody>
                    <tr><th>1.</th><td>设计说明</td><td>100.00</td><td>未提交答案</td></tr>
                  </tbody></table>
                </body></html>
                """
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = JudgeApi().getAssignments()

    assertTrue(
        result.isSuccess,
        "${result.exceptionOrNull()?.message.orEmpty()}; urls=$requestedUrls",
    )
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
    assertEquals(
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F",
        requestedUrls.firstOrNull(),
    )
  }

  @Test
  fun `judge api sends browser headers like python client`() = runTest {
    val engine = MockEngine { request ->
      val userAgent = request.headers[HttpHeaders.UserAgent].orEmpty()
      val accept = request.headers[HttpHeaders.Accept].orEmpty()
      val acceptLanguage = request.headers[HttpHeaders.AcceptLanguage].orEmpty()
      if (
          !userAgent.startsWith("Mozilla/5.0") ||
              !accept.contains("text/html") ||
              !acceptLanguage.contains("zh-CN")
      ) {
        return@MockEngine respond(
            content = ByteReadChannel.Empty,
            status = HttpStatusCode.ServiceUnavailable,
        )
      }

      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
            )
        "https://judge.buaa.edu.cn/" -> respondHtml("<html><body>judge ready</body></html>")
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" ->
            respondHtml(
                """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
            )
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" ->
            respondHtml("<html><body>course selected</body></html>")
        "https://judge.buaa.edu.cn/assignment/index.jsp" ->
            respondHtml(
                """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
            )
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" ->
            respondHtml(
                """
                <html><body>
                  作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                  作业满分： 100.00 ，共 1道 题
                  <table><tbody>
                    <tr><th>1.</th><td>设计说明</td><td>100.00</td><td>未提交答案</td></tr>
                  </tbody></table>
                </body></html>
                """
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = JudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
  }

  @Test
  fun `judge api reactivates session and retries when judge page returns login html`() = runTest {
    var serviceActivations = 0
    var courseListRequests = 0
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F" -> {
          serviceActivations++
          respond(
              content = ByteReadChannel.Empty,
              status = HttpStatusCode.Found,
              headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
          )
        }
        "https://judge.buaa.edu.cn/" -> respondHtml("<html><body>judge ready</body></html>")
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" -> {
          courseListRequests++
          if (courseListRequests == 1) {
            respondHtml(
                """
                <html><body>
                  <form><input name="execution" value="e1s1" /></form>
                  统一身份认证
                </body></html>
                """
            )
          } else {
            respondHtml(
                """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
            )
          }
        }
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" ->
            respondHtml("<html><body>course selected</body></html>")
        "https://judge.buaa.edu.cn/assignment/index.jsp" ->
            respondHtml(
                """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
            )
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" ->
            respondHtml(
                """
                <html><body>
                  作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                  作业满分： 100.00 ，共 1道 题
                  <table><tbody>
                    <tr><th>1.</th><td>设计说明</td><td>100.00</td><td>未提交答案</td></tr>
                  </tbody></table>
                </body></html>
                """
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = JudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
    assertEquals(2, serviceActivations)
    assertEquals(2, courseListRequests)
  }

  @Test
  fun `judge api uses direct upstream backend to fetch assignment detail`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
            )
        "/" -> respondHtml("<html><body>judge ready</body></html>")
        "/courselist.jsp" ->
            respondHtml(
                """<html><body><a href="courselist.jsp?courseID=1">软件工程</a></body></html>"""
            )
        "/assignment/index.jsp" ->
            if (request.url.parameters["assignID"] == "101") {
              respondHtml(
                  """
                  <html><body>
                    作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                    作业满分： 100.00 ，共 2道 题
                    <table><tbody>
                      <tr><th>1.</th><td>设计说明</td><td>60.00</td><td>初次提交时间: 2026-04-17 12:24:26 得分：60.00</td></tr>
                      <tr><th>2.</th><td>用例设计</td><td>40.00</td><td>未提交答案</td></tr>
                    </tbody></table>
                  </body></html>
                  """
              )
            } else {
              respondHtml(
                  """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
              )
            }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = JudgeApi().getAssignmentDetail("1", "101")

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    val detail = result.getOrNull()
    assertEquals("设计作业", detail?.title)
    assertEquals(2, detail?.totalProblems)
    assertEquals(listOf("设计说明", "用例设计"), detail?.problems?.map { it.name })
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

private fun MockRequestHandleScope.respondHtml(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString()),
    )
