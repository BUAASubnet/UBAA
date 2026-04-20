package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class LocalSpocApiBackendTest {
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
  fun `spoc api uses direct upstream backend to fetch assignments`() = runTest {
    val requestBodies = mutableListOf<String>()
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/spocnewht/cas" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token&refreshToken=test-refresh",
                    ),
            )
        "/spocnewht/sys/casLogin" -> {
          assertEquals("Inco-test-token", request.headers["Token"])
          respondJson("""{"code":200,"content":{"jsdm":"01"}}""")
        }
        "/spocnewht/inco/ht/queryOne" -> {
          assertEquals("Inco-test-token", request.headers["Token"])
          assertEquals("01", request.headers["RoleCode"])
          respondJson("""{"code":200,"content":{"dqxq":"2026年春季学期","mrxq":"2025-20262"}}""")
        }
        "/spocnewht/jxkj/queryKclb" -> {
          assertEquals("2025-20262", request.url.parameters["xnxq"])
          respondJson(
              """{"code":200,"content":[{"kcid":"course-1","kcmc":"操作系统","skjs":"牛虹婷,王良"}]}"""
          )
        }
        "/spocnewht/inco/ht/queryListByPage" -> {
          assertEquals(HttpMethod.Post, request.method)
          val bodyText = (request.body as TextContent).text
          requestBodies += bodyText
          val encryptedParam =
              json.parseToJsonElement(bodyText).jsonObject["param"]!!.jsonPrimitive.content
          val plainText = LocalSpocCrypto.decryptParam(encryptedParam)
          respondJson(
              when {
                """"pageNum":1""" in plainText ->
                    """{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":2,"hasNextPage":true,"list":[{"zyid":"a1","tjzt":"未做","zyjzsj":"2026-03-31T15:59:59.000+00:00","zymc":"练习题作业1","zykssj":"2026-03-24T08:00:00.000+00:00","sskcid":"course-1","kcmc":"操作系统","mf":"满分:0"}]}}"""
                """"pageNum":2""" in plainText ->
                    """{"code":200,"content":{"pageNum":2,"pageSize":15,"pages":2,"hasNextPage":false,"list":[{"zyid":"a2","tjzt":"已做","zyjzsj":"2026-03-19T16:00:00.000+00:00","zymc":"lab0实验作业","zykssj":"2026-03-16T08:00:00.000+00:00","sskcid":"course-1","kcmc":"操作系统","mf":"满分:100"}]}}"""
                else -> error("Unexpected page payload: $plainText")
              }
          )
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SpocApi().getAssignments()

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals("2025-20262", response?.termCode)
    assertEquals("2026年春季学期", response?.termName)
    assertEquals(2, response?.assignments?.size)
    assertEquals("lab0实验作业", response?.assignments?.firstOrNull()?.title)
    assertEquals(
        SpocSubmissionStatus.SUBMITTED,
        response?.assignments?.firstOrNull()?.submissionStatus,
    )
    assertEquals("练习题作业1", response?.assignments?.lastOrNull()?.title)
    assertEquals(
        SpocSubmissionStatus.UNSUBMITTED,
        response?.assignments?.lastOrNull()?.submissionStatus,
    )
    assertTrue(requestBodies.all { "\"param\"" in it })
  }

  @Test
  fun `spoc login preserves pathless cookies for subsequent api calls`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/spocnewht/cas" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location to
                            listOf(
                                "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token&refreshToken=test-refresh"
                            ),
                        HttpHeaders.SetCookie to
                            listOf("SPOCSESSION=spoc-session; Domain=spoc.buaa.edu.cn; Secure"),
                    ),
            )
        "/spocnewht/sys/casLogin" -> {
          assertTrue(
              request.headers[HttpHeaders.Cookie].orEmpty().contains("SPOCSESSION=spoc-session")
          )
          respondJson("""{"code":200,"content":{"jsdm":"01"}}""")
        }
        "/spocnewht/inco/ht/queryOne" ->
            respondJson("""{"code":200,"content":{"dqxq":"2026年春季学期","mrxq":"2025-20262"}}""")
        "/spocnewht/jxkj/queryKclb" ->
            respondJson(
                """{"code":200,"content":[{"kcid":"course-1","kcmc":"操作系统","skjs":"牛虹婷"}]}"""
            )
        "/spocnewht/inco/ht/queryListByPage" ->
            respondJson(
                """{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","tjzt":"未做","zyjzsj":"2026-03-31T15:59:59.000+00:00","zymc":"练习题作业1","zykssj":"2026-03-24T08:00:00.000+00:00","sskcid":"course-1","kcmc":"操作系统","mf":"满分:0"}]}}"""
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SpocApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(1, result.getOrNull()?.assignments?.size)
  }

  @Test
  fun `spoc login follows sso redirect chain before extracting token`() = runTest {
    val ssoUrl =
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspoc.buaa.edu.cn%2Fspocnewht%2FcasLogin"
    val serviceUrl = "https://spoc.buaa.edu.cn/spocnewht/casLogin?ticket=test-ticket"
    val tokenUrl = "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token&refreshToken=test-refresh"
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://spoc.buaa.edu.cn/spocnewht/cas" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, ssoUrl),
            )
        ssoUrl ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, serviceUrl),
            )
        serviceUrl ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, tokenUrl),
            )
        "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin" ->
            respondJson("""{"code":200,"content":{"jsdm":"01"}}""")
        "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne" ->
            respondJson("""{"code":200,"content":{"dqxq":"2026年春季学期","mrxq":"2025-20262"}}""")
        "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb?kcmc=&xnxq=2025-20262" ->
            respondJson(
                """{"code":200,"content":[{"kcid":"course-1","kcmc":"操作系统","skjs":"牛虹婷"}]}"""
            )
        "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage" ->
            respondJson(
                """{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","tjzt":"未做","zyjzsj":"2026-03-31T15:59:59.000+00:00","zymc":"练习题作业1","zykssj":"2026-03-24T08:00:00.000+00:00","sskcid":"course-1","kcmc":"操作系统","mf":"满分:0"}]}}"""
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SpocApi().getAssignments()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(1, result.getOrNull()?.assignments?.size)
  }

  @Test
  fun `spoc api uses direct upstream backend to fetch assignment detail`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/spocnewht/cas" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token&refreshToken=test-refresh",
                    ),
            )
        "/spocnewht/sys/casLogin" -> respondJson("""{"code":200,"content":{"jsdm":"01"}}""")
        "/spocnewht/inco/ht/queryOne" ->
            respondJson("""{"code":200,"content":{"dqxq":"2026年春季学期","mrxq":"2025-20262"}}""")
        "/spocnewht/jxkj/queryKclb" ->
            respondJson(
                """{"code":200,"content":[{"kcid":"course-1","kcmc":"操作系统","skjs":"牛虹婷,王良"}]}"""
            )
        "/spocnewht/inco/ht/queryListByPage" ->
            respondJson(
                """{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","tjzt":"未做","zyjzsj":"2026-03-31T15:59:59.000+00:00","zymc":"练习题作业1","zykssj":"2026-03-24T08:00:00.000+00:00","sskcid":"course-1","kcmc":"操作系统","mf":"满分:0"}]}}"""
            )
        "/spocnewht/kczy/queryKczyInfoByid" -> {
          assertEquals("a1", request.url.parameters["id"])
          respondJson(
              """{"code":200,"content":{"id":"a1","zymc":"练习题作业1","zynr":"<p>请尽量给出自己的思考。</p>","zykssj":"2026-03-24T08:00:00.000+00:00","zyjzsj":"2026-03-31T15:59:59.000+00:00","zyfs":"满分:0","sskcid":"course-1"}}"""
          )
        }
        "/spocnewht/kczy/queryXsSubmitKczyInfo" -> {
          assertEquals("a1", request.url.parameters["kczyid"])
          respondJson(
              """{"code":200,"content":{"tjzt":"1","tjsj":"2026-03-31T15:40:00.000+00:00"}}"""
          )
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SpocApi().getAssignmentDetail("a1")

    assertTrue(result.isSuccess)
    val detail = result.getOrNull()
    assertEquals("a1", detail?.assignmentId)
    assertEquals("练习题作业1", detail?.title)
    assertEquals("操作系统", detail?.courseName)
    assertEquals("牛虹婷,王良", detail?.teacherName)
    assertEquals("请尽量给出自己的思考。", detail?.contentPlainText)
    assertEquals("<p>请尽量给出自己的思考。</p>", detail?.contentHtml)
    assertEquals(SpocSubmissionStatus.SUBMITTED, detail?.submissionStatus)
    assertEquals("已提交", detail?.submissionStatusText)
    assertEquals("2026-03-31 23:40:00", detail?.submittedAt)
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        install(HttpCookies) { storage = LocalCookieStore.storage(ConnectionMode.DIRECT) }
      }
    }
  }
}

private fun MockRequestHandleScope.respondJson(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
    )
