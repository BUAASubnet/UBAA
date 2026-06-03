package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.feature.SigninApi
import cn.edu.ubaa.api.local.LocalAuthSession
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
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
import kotlin.time.Clock
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

class LocalSigninApiBackendTest {
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
  fun `signin api uses direct upstream backend to fetch today classes`() = runTest {
    val expectedDate = currentSigninDate()
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" -> {
          assertEquals(loginName, request.url.parameters["phone"])
          assertEquals("1", request.url.parameters["userLevel"])
          assertEquals("2", request.url.parameters["verificationType"])
          respond(
              content =
                  ByteReadChannel(
                      """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        request.url.toString() ==
            "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id=user-1&dateStr=$expectedDate" -> {
          assertEquals("session-1", request.headers["sessionId"])
          respond(
              content =
                  ByteReadChannel(
                      """
                      {
                        "STATUS": 0,
                        "result": [
                          {
                            "id": "course-1",
                            "courseName": "软件工程",
                            "classBeginTime": "08:00",
                            "classEndTime": "09:40",
                            "signStatus": 0
                          }
                        ]
                      }
                      """
                          .trimIndent()
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().getTodayClasses()

    assertTrue(result.isSuccess)
    assertEquals("course-1", result.getOrNull()?.data?.singleOrNull()?.courseId)
    assertEquals("软件工程", result.getOrNull()?.data?.singleOrNull()?.courseName)
  }

  @Test
  fun `signin api follows iclass my center redirect chain before app login`() = runTest {
    val expectedDate = currentSigninDate()
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val visitedJumpUrls = mutableListOf<String>()
    var appLoginRequests = 0
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" &&
            request.url.parameters["loginName"] == null -> {
          visitedJumpUrls += request.url.toString()
          if (visitedJumpUrls.size > 1) {
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
          } else {
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Ficlass.buaa.edu.cn%3A8346%2F%3Ftype%3DjumpMyCenter",
                    ),
            )
          }
        }
        request.url.host == "sso.buaa.edu.cn" && request.url.encodedPath == "/login" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/cas-login?ticket=ST-test",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.encodedPath == "/cas-login" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, "/?type=jumpMyCenter#/MyCenter"),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" -> {
          assertEquals(loginName, request.url.parameters["phone"])
          appLoginRequests++
          respond(
              content =
                  ByteReadChannel(
                      """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        request.url.toString() ==
            "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id=user-1&dateStr=$expectedDate" ->
            respond(
                content = ByteReadChannel("""{"STATUS":0,"result":[]}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().getTodayClasses()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(2, visitedJumpUrls.size)
    assertEquals(1, appLoginRequests)
  }

  @Test
  fun `signin api uses direct upstream backend to perform signin`() = runTest {
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" -> {
          assertEquals(loginName, request.url.parameters["phone"])
          respond(
              content =
                  ByteReadChannel(
                      """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action" ->
            respond(
                content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action?courseSchedId=course-1&timestamp=1713600000" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":0,"ERRMSG":"签到成功","result":{"stuSignStatus":1}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().performSignin("course-1")

    assertTrue(result.isSuccess)
    assertEquals(true, result.getOrNull()?.success)
    assertEquals("签到成功", result.getOrNull()?.message)
  }

  @Test
  fun `signin api reuses app session across repeated direct calls`() = runTest {
    val expectedDate = currentSigninDate()
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    var loginRequests = 0
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" -> {
          assertEquals(loginName, request.url.parameters["phone"])
          loginRequests++
          respond(
              content =
                  ByteReadChannel(
                      """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                  ),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        request.url.toString() ==
            "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id=user-1&dateStr=$expectedDate" -> {
          assertEquals("session-1", request.headers["sessionId"])
          respond(
              content = ByteReadChannel("""{"STATUS":0,"result":[]}"""),
              status = HttpStatusCode.OK,
              headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
          )
        }
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action" ->
            respond(
                content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action?courseSchedId=course-1&timestamp=1713600000" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":0,"ERRMSG":"签到成功","result":{"stuSignStatus":1}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val api = SigninApi()
    val classes = api.getTodayClasses()
    val signin = api.performSignin("course-1")

    assertTrue(classes.isSuccess, classes.exceptionOrNull()?.message.orEmpty())
    assertTrue(signin.isSuccess, signin.exceptionOrNull()?.message.orEmpty())
    assertEquals(1, loginRequests)
  }

  @Test
  fun `signin api handles string STATUS and signStatus from iclass server`() = runTest {
    val expectedDate = currentSigninDate()
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","result":{"id":"user-1","sessionId":"session-1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id=user-1&dateStr=$expectedDate" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","result":[{"id":"c1","courseName":"软件工程","classBeginTime":"08:00","classEndTime":"09:40","signStatus":"1"}]}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().getTodayClasses()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    val course = result.getOrNull()?.data?.singleOrNull()
    assertEquals("c1", course?.courseId)
    assertEquals(1, course?.signStatus, "signStatus string \"1\" should be parsed as int 1")
  }

  @Test
  fun `perform signin handles string STATUS and stuSignStatus`() = runTest {
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","result":{"id":"user-1","sessionId":"session-1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action" ->
            respond(
                content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action?courseSchedId=course-1&timestamp=1713600000" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","ERRMSG":"签到成功","result":{"stuSignStatus":"1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().performSignin("course-1")

    assertTrue(result.isSuccess)
    assertEquals(
        true,
        result.getOrNull()?.success,
        "string STATUS \"0\" + stuSignStatus \"1\" should be success",
    )
    assertEquals("签到成功", result.getOrNull()?.message)
  }

  @Test
  fun `signin retries on session expired error message`() = runTest {
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    var signinRequests = 0
    val engine = MockEngine { request ->
      when {
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8346 &&
            request.url.parameters["type"] == "jumpMyCenter" ->
            respond(
                content = ByteReadChannel(""),
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                    ),
            )
        request.url.host == "iclass.buaa.edu.cn" &&
            request.url.port == 8347 &&
            request.url.encodedPath == "/app/user/login.action" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","result":{"id":"user-1","sessionId":"session-1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url.toString() ==
            "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action" ->
            respond(
                content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        request.url
            .toString()
            .startsWith("http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action") -> {
          signinRequests++
          if (signinRequests == 1) {
            // First attempt: session expired
            respond(
                content = ByteReadChannel("""{"STATUS":"1","ERRMSG":"请重新登录","result":{}}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
          } else {
            // Retry after session refresh: success
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":"0","ERRMSG":"签到成功","result":{"stuSignStatus":"1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
          }
        }
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = SigninApi().performSignin("course-1")

    assertTrue(result.isSuccess)
    assertEquals(true, result.getOrNull()?.success, "should succeed after retry")
    assertEquals("签到成功", result.getOrNull()?.message)
    assertEquals(2, signinRequests, "should have retried once")
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(HttpCookies) { storage = LocalCookieStore.storage(ConnectionMode.DIRECT) }
      }
    }
  }

  private fun currentSigninDate(): String {
    val date = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
    return buildString {
      append(date.year)
      append(date.month.ordinal.plus(1).toString().padStart(2, '0'))
      append(date.day.toString().padStart(2, '0'))
    }
  }
}
