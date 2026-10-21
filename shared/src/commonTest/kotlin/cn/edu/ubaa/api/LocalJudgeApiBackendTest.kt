package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.feature.JudgeApi
import cn.edu.ubaa.api.local.LocalAuthSession
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalJudgeApiBackend
import cn.edu.ubaa.api.local.LocalJudgeApiCache
import cn.edu.ubaa.api.local.LocalJudgeHistoricalCourseStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.api.local.LocalWebVpnSupport
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
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
import kotlinx.datetime.LocalDateTime

class LocalJudgeApiBackendTest {
  @BeforeTest
  fun setup() {
    runTest { localConnectionTestMutex.lock() }
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    LocalJudgeHistoricalCourseStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    ConnectionRuntime.resolveSelectedMode()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalJudgeApiCache.clearAll()
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
  fun `希冀使用官网 HTTPS service 完成回调后读取作业`() = runTest {
    var callbacks = 0
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/login" -> {
          val correctService = request.url.parameters["service"] == "https://judge.buaa.edu.cn/"
          respond(
              "",
              HttpStatusCode.Found,
              headersOf(
                  HttpHeaders.Location,
                  if (correctService) "https://judge.buaa.edu.cn/?ticket=synthetic"
                  else "https://judge.buaa.edu.cn/indexcs/simple.jsp?loginErr=1",
              ),
          )
        }
        "/indexcs/simple.jsp" -> respondHtml("""<html><a id="cgstuloginbtn">校园统一认证登录</a></html>""")
        "/" -> {
          callbacks++
          respond(
              "",
              HttpStatusCode.Found,
              headersOf(
                  HttpHeaders.Location to listOf("/courselist.jsp?courseID=0"),
                  HttpHeaders.SetCookie to listOf("JSESSIONID=synthetic-judge; Path=/; Secure"),
              ),
          )
        }
        "/courselist.jsp" -> {
          if (
              request.headers[HttpHeaders.Cookie].orEmpty().contains("JSESSIONID=synthetic-judge")
          ) {
            respondHtml("""<html><a href="courselist.jsp?courseID=1">合成课程</a></html>""")
          } else respondHtml("")
        }
        "/assignment/index.jsp" -> {
          if (request.url.parameters["assignID"] == null) {
            respondHtml("""<html><a href="index.jsp?assignID=101">合成作业</a></html>""")
          } else
              respondHtml(
                  """<html>作业时间：2026-04-20 09:00:00 至 2026-05-03 23:59:00 作业满分：5，共 1道 题<table><tr><th>1.</th><td>合成题目</td><td>5</td><td>未提交答案</td></tr></table></html>"""
              )
        }
        else -> error("出现非预期请求")
      }
    }
    useMockUpstream(engine)
    val result = fixedClockJudgeApi().getAssignments()
    assertTrue(result.isSuccess)
    assertEquals(listOf("101"), result.getOrNull()?.assignments?.map { it.assignmentId })
    assertTrue(callbacks > 0)
  }

  @Test
  fun `希冀原生登录页不能当成成功的空作业列表`() = runTest {
    var courseRequests = 0
    useMockUpstream(
        MockEngine { request ->
          when (request.url.encodedPath) {
            "/login" ->
                respond(
                    "",
                    HttpStatusCode.Found,
                    headersOf(
                        HttpHeaders.Location,
                        "https://judge.buaa.edu.cn/indexcs/simple.jsp?loginErr=1",
                    ),
                )
            "/indexcs/simple.jsp" ->
                respondHtml("""<html><a id="cgstuloginbtn">校园统一认证登录</a></html>""")
            "/courselist.jsp" -> {
              courseRequests++
              respondHtml("")
            }
            "/api/uc/status" ->
                respond(
                    """{"code":0,"data":{"name":"测试用户","schoolid":"22373333"}}""",
                    HttpStatusCode.OK,
                    headersOf(HttpHeaders.ContentType, "application/json"),
                )
            else -> error("出现非预期请求")
          }
        }
    )
    val result = fixedClockJudgeApi().getAssignments()
    assertTrue(result.isFailure)
    assertEquals(
        "judge_auth_failed",
        (result.exceptionOrNull() as? cn.edu.ubaa.api.auth.ApiCallException)?.code,
    )
    assertEquals(0, courseRequests)
    assertTrue(LocalJudgeHistoricalCourseStore.get(ConnectionMode.DIRECT, "22373333").isEmpty())
  }

  @Test
  fun `WebVPN 网关共享课程会话时不能将其他课程作业混入列表`() = runTest {
    val session = LocalAuthSessionStore.get()!!
    ConnectionRuntime.switchMode(ConnectionMode.WEBVPN)
    LocalAuthSessionStore.save(session)
    var selectedCourse = "0"
    val engine = MockEngine { request ->
      assertEquals("d.buaa.edu.cn", request.url.host)
      val url = io.ktor.http.Url(LocalWebVpnSupport.fromWebVpnUrl(request.url.toString()))
      when (url.encodedPath) {
        "/login" ->
            respond(
                "",
                HttpStatusCode.Found,
                headersOf(
                    HttpHeaders.Location,
                    LocalWebVpnSupport.toWebVpnUrl("https://judge.buaa.edu.cn/"),
                ),
            )
        "/" -> respondHtml("<html>认证完成</html>")
        "/courselist.jsp" -> {
          selectedCourse = url.parameters["courseID"].orEmpty()
          if (selectedCourse == "0") {
            respondHtml(
                """<html><a href="courselist.jsp?courseID=1">课程甲</a><a href="courselist.jsp?courseID=2">课程乙</a></html>"""
            )
          } else {
            // 模拟网关在服务端共享课程选择，其他客户端此时可能切换同一会话。
            kotlinx.coroutines.delay(10)
            respondHtml("<html>课程已选择</html>")
          }
        }
        "/assignment/index.jsp" -> {
          if (url.parameters["assignID"] == null) {
            respondHtml(
                """<html><a href="index.jsp?assignID=${selectedCourse}01">合成作业</a></html>"""
            )
          } else {
            assertEquals("${selectedCourse}01", url.parameters["assignID"], "详情请求使用了其他课程的会话")
            respondHtml(
                """<html>作业时间：2026-04-20 09:00:00 至 2026-05-03 23:59:00 作业满分：5，共 1道 题<table><tr><th>1.</th><td>合成题目</td><td>5</td><td>未提交答案</td></tr></table></html>"""
            )
          }
        }
        else -> error("出现非预期请求")
      }
    }
    useMockUpstream(engine, storageMode = ConnectionMode.WEBVPN)
    val result = fixedClockJudgeApi().getAssignments()
    assertTrue(result.isSuccess)
    assertEquals(
        setOf("1" to "101", "2" to "201"),
        result.getOrThrow().assignments.map { it.courseId to it.assignmentId }.toSet(),
    )
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
                    作业满分： 100.00 ，共 1道 题
                    <table><tbody>
                      <tr><th>1.</th><td>设计说明</td><td>100.00</td><td>未提交答案</td></tr>
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

    val result = fixedClockJudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    val assignment = result.getOrNull()?.assignments?.single()
    assertEquals("1", assignment?.courseId)
    assertEquals("101", assignment?.assignmentId)
    assertEquals("设计作业", assignment?.title)
    assertEquals(JudgeSubmissionStatus.UNSUBMITTED, assignment?.submissionStatus)
    assertTrue(requestedPaths.contains("/courselist.jsp?courseID=0"))
    assertTrue(requestedPaths.contains("/courselist.jsp?courseID=1"))
    assertTrue(requestedPaths.contains("/assignment/index.jsp?assignID=101"))
  }

  @Test
  fun `judge api fetches assignment details until six month cutoff per course`() = runTest {
    val requestedUrls = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
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
                """
                <html><body>
                  <a href="assignment/index.jsp?assignID=101">设计作业</a>
                  <a href="assignment/index.jsp?assignID=103">历史作业</a>
                  <a href="assignment/index.jsp?assignID=104">更早作业</a>
                </body></html>
                """
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
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=103" ->
            respondHtml(
                """
                <html><body>
                  作业时间：2025-10-30 08:00:00 至 2025-11-10 23:00:00
                  作业满分： 10.00 ，共 1道 题 总分：10.00
                  <table><tbody>
                    <tr><th>1.</th><td>历史题</td><td>10.00</td><td>最后一次提交时间：2025-11-01 12:00:00 得分：10.00</td></tr>
                  </tbody></table>
                </body></html>
                """
            )
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=104" ->
            error("Assignment after six month cutoff should not be fetched")
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api =
        JudgeApi(LocalJudgeApiBackend(nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") }))

    val result = api.getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(listOf("101"), result.getOrNull()?.assignments?.map { it.assignmentId })
    assertTrue(
        requestedUrls.contains("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=103")
    )
    assertEquals(emptyList(), result.getOrNull()?.historicalCutoffCourseIds)
  }

  @Test
  fun `judge api parses multiline course links and upstream assignment links`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
            )
        "https://judge.buaa.edu.cn/" -> respondHtml("<html><body>judge ready</body></html>")
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" ->
            respondHtml(
                """
                <html><body>
                  <a
                    class="list-group-item"
                    href="courselist.jsp?courseID=1">
                    软件工程
                  </a>
                </body></html>
                """
            )
        "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" ->
            respondHtml("<html><body>course selected</body></html>")
        "https://judge.buaa.edu.cn/assignment/index.jsp" ->
            respondHtml(
                """
                <html><body>
                  <a href="index.jsp?courseID=1&assignID=101" class="list-group-item">设计作业</a>
                </body></html>
                """
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

    val result = JudgeApi().getAssignments(includeExpired = true)

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(listOf("101"), result.getOrNull()?.assignments?.map { it.assignmentId })
  }

  @Test
  fun `历史作业和旧排除名单不能让当前课程在刷新后消失`() = runTest {
    val requestedUrls = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
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
                """
                    <html><body>
                      <a href="assignment/index.jsp?assignID=101">设计作业</a>
                      <a href="assignment/index.jsp?assignID=103">历史作业</a>
                    </body></html>
                    """
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
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=103" ->
            respondHtml(
                """
                    <html><body>
                      作业时间：2025-10-30 08:00:00 至 2025-11-10 23:00:00
                      作业满分： 10.00 ，共 1道 题 总分：10.00
                      <table><tbody>
                        <tr><th>1.</th><td>历史题</td><td>10.00</td><td>最后一次提交时间：2025-11-01 12:00:00 得分：10.00</td></tr>
                      </tbody></table>
                    </body></html>
                    """
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api =
        JudgeApi(LocalJudgeApiBackend(nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") }))

    LocalJudgeHistoricalCourseStore.add(ConnectionMode.DIRECT, "22373333", listOf("1"))
    val first = api.getAssignments()
    LocalJudgeApiCache.clearAll()
    requestedUrls.clear()
    val second = api.getAssignments()
    val defaultRefreshCourseSelectionRequests =
        requestedUrls.count { it == "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" }
    val includeExpired = api.getAssignments(includeExpired = true)

    assertTrue(first.isSuccess, first.exceptionOrNull()?.message.orEmpty())
    assertTrue(second.isSuccess, second.exceptionOrNull()?.message.orEmpty())
    assertTrue(includeExpired.isSuccess, includeExpired.exceptionOrNull()?.message.orEmpty())
    assertEquals(listOf("101"), first.getOrNull()?.assignments?.map { it.assignmentId })
    assertEquals(listOf("101"), second.getOrNull()?.assignments?.map { it.assignmentId })
    assertTrue(defaultRefreshCourseSelectionRequests > 0)
    assertEquals(
        listOf("103", "101"),
        includeExpired.getOrNull()?.assignments?.map { it.assignmentId },
    )
  }

  @Test
  fun `judge api activates direct judge cas session before fetching assignments`() = runTest {
    var judgeSessionActive = false
    val requestedUrls = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" -> {
          judgeSessionActive = true
          respond(
              content = ByteReadChannel.Empty,
              status = HttpStatusCode.Found,
              headers = headersOf(HttpHeaders.Location, "http://judge.buaa.edu.cn/"),
          )
        }
        "http://judge.buaa.edu.cn/" -> respondHtml("<html><body>judge ready</body></html>")
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
    useMockUpstream(engine, followRedirectsOverride = false)

    val result = fixedClockJudgeApi().getAssignments()

    assertTrue(
        result.isSuccess,
        "${result.exceptionOrNull()?.message.orEmpty()}; urls=$requestedUrls",
    )
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
    assertEquals(
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F",
        requestedUrls.firstOrNull(),
    )
    assertEquals("http://judge.buaa.edu.cn/", requestedUrls.getOrNull(1))
  }

  @Test
  fun `judge api does not cache empty assignment lists`() = runTest {
    var assignmentListRequests = 0
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
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
        "https://judge.buaa.edu.cn/assignment/index.jsp" -> {
          assignmentListRequests++
          if (assignmentListRequests == 1) {
            respondHtml("<html><body>暂无作业</body></html>")
          } else {
            respondHtml(
                """<html><body><a href="assignment/index.jsp?assignID=101">设计作业</a></body></html>"""
            )
          }
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = fixedClockJudgeApi()

    val first = api.getAssignments()
    val second = api.getAssignments()

    assertTrue(first.isSuccess, first.exceptionOrNull()?.message.orEmpty())
    assertTrue(second.isSuccess, second.exceptionOrNull()?.message.orEmpty())
    assertEquals(emptyList(), first.getOrNull()?.assignments)
    assertEquals(listOf("101"), second.getOrNull()?.assignments?.map { it.assignmentId })
    assertEquals(2, assignmentListRequests)
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
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
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

    val result = fixedClockJudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
  }

  @Test
  fun `judge api reactivates session and retries when judge page returns login html`() = runTest {
    var serviceActivations = 0
    var courseListRequests = 0
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" -> {
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

    val result = fixedClockJudgeApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals("设计作业", result.getOrNull()?.assignments?.single()?.title)
    assertEquals(3, serviceActivations)
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

  @Test
  fun `judge api batch details reuses local cache until session reset`() = runTest {
    var detailRequests = 0
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "https://judge.buaa.edu.cn/"),
            )
        "https://judge.buaa.edu.cn",
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
        "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" -> {
          detailRequests++
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
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = JudgeApi()
    val keys = listOf(JudgeAssignmentDetailKeyDto("1", "101"))

    val first = api.getAssignmentDetails(keys)
    val second = api.getAssignmentDetails(keys)
    ConnectionRuntime.resetSession()
    useMockUpstream(engine)
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    val third = api.getAssignmentDetails(keys)

    assertTrue(first.isSuccess, first.exceptionOrNull()?.message.orEmpty())
    assertTrue(second.isSuccess, second.exceptionOrNull()?.message.orEmpty())
    assertTrue(third.isSuccess, third.exceptionOrNull()?.message.orEmpty())
    assertEquals(listOf("101"), first.getOrNull()?.details?.map { it.assignmentId })
    assertEquals(2, detailRequests)
  }

  @Test
  fun `judge api batch details supports webvpn upstream urls`() = runTest {
    ConnectionRuntime.switchMode(ConnectionMode.WEBVPN)
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    val requestedHosts = mutableListOf<String>()
    val engine = MockEngine { request ->
      requestedHosts += request.url.host
      when (LocalWebVpnSupport.fromWebVpnUrl(request.url.toString())) {
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fjudge.buaa.edu.cn%2F" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        LocalWebVpnSupport.toWebVpnUrl("https://judge.buaa.edu.cn/"),
                    ),
            )
        "https://judge.buaa.edu.cn",
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
    useMockUpstream(engine, storageMode = ConnectionMode.WEBVPN)

    val result = JudgeApi().getAssignmentDetails(listOf(JudgeAssignmentDetailKeyDto("1", "101")))

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals("101", result.getOrNull()?.details?.single()?.assignmentId)
    assertTrue(requestedHosts.all { it == "d.buaa.edu.cn" })
  }

  // 四月样例固定在五月读取，避免随着运行日期推进而被历史筛选规则排除。
  private fun fixedClockJudgeApi() =
      JudgeApi(LocalJudgeApiBackend(nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") }))

  private fun useMockUpstream(
      engine: MockEngine,
      followRedirectsOverride: Boolean? = null,
      storageMode: ConnectionMode = ConnectionMode.DIRECT,
  ) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirectsOverride ?: followRedirects
        install(HttpCookies) { storage = LocalCookieStore.storage(storageMode) }
      }
    }
    LocalUpstreamClientProvider.isolatedClientFactory = { followRedirects, cookieStorage ->
      HttpClient(engine) {
        this.followRedirects = followRedirectsOverride ?: followRedirects
        install(HttpCookies) { storage = cookieStorage }
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
