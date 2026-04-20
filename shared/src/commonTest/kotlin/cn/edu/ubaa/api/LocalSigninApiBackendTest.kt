package cn.edu.ubaa.api

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
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://iclass.buaa.edu.cn:8347/app/user/login.action?password=&phone=22373333&userLevel=1&verificationType=2&verificationUrl=" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
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
  fun `signin api uses direct upstream backend to perform signin`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://iclass.buaa.edu.cn:8347/app/user/login.action?password=&phone=22373333&userLevel=1&verificationType=2&verificationUrl=" ->
            respond(
                content =
                    ByteReadChannel(
                        """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                    ),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action" ->
            respond(
                content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                status = HttpStatusCode.OK,
                headers =
                    headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
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
