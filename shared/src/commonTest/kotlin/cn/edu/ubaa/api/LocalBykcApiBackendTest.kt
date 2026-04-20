package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.BykcCourseStatus
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
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDateTime
import kotlinx.serialization.json.Json

class LocalBykcApiBackendTest {
  private val fixedNow = LocalDateTime.parse("2026-04-20T10:00:00")
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
  fun `bykc api fetches profile and filters ended courses in direct mode`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://bykc.buaa.edu.cn/sscv/cas/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://bykc.buaa.edu.cn/cas-login?token=test-token",
                    ),
            )
        "https://bykc.buaa.edu.cn/cas-login?token=test-token" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://bykc.buaa.edu.cn/sscv/getUserProfile" -> {
          assertEquals("test-token", request.headers["auth_token"])
          respondJson(
              """
              {
                "status":"0",
                "errmsg":"",
                "data":{
                  "id":1,
                  "employeeId":"22373333",
                  "realName":"测试学生",
                  "studentNo":"22373333",
                  "studentType":"BENKE",
                  "classCode":"0101",
                  "college":{"id":61,"collegeName":"计算机学院"},
                  "term":{"id":2,"termName":"2025-2026-2"}
                }
              }
              """
                  .trimIndent()
          )
        }
        "https://bykc.buaa.edu.cn/sscv/queryStudentSemesterCourseByPage" -> {
          assertTrue(request.headers["ak"].orEmpty().isNotBlank())
          assertTrue(request.headers["sk"].orEmpty().isNotBlank())
          assertTrue(request.headers["ts"].orEmpty().isNotBlank())
          respondJson(
              """
              {
                "status":"0",
                "errmsg":"",
                "data":{
                  "content":[
                    {
                      "id":101,
                      "courseName":"可选课程",
                      "coursePosition":"学院路校区主M101",
                      "courseTeacher":"张老师",
                      "courseStartDate":"2026-04-21 19:00:00",
                      "courseEndDate":"2026-04-21 21:00:00",
                      "courseSelectStartDate":"2026-04-19 08:00:00",
                      "courseSelectEndDate":"2026-04-21 18:00:00",
                      "courseCancelEndDate":"2026-04-21 18:00:00",
                      "courseMaxCount":30,
                      "courseCurrentCount":10,
                      "courseNewKind1":{"id":1,"kindName":"博雅课程"},
                      "courseNewKind2":{"id":2,"kindName":"德育"},
                      "courseCampusList":["学院路校区"],
                      "selected":false
                    },
                    {
                      "id":102,
                      "courseName":"满员课程",
                      "courseStartDate":"2026-04-22 19:00:00",
                      "courseEndDate":"2026-04-22 21:00:00",
                      "courseSelectStartDate":"2026-04-18 08:00:00",
                      "courseSelectEndDate":"2026-04-22 18:00:00",
                      "courseCancelEndDate":"2026-04-22 18:00:00",
                      "courseMaxCount":30,
                      "courseCurrentCount":30,
                      "selected":false
                    },
                    {
                      "id":103,
                      "courseName":"已结束课程",
                      "courseStartDate":"2026-04-25 19:00:00",
                      "courseEndDate":"2026-04-25 21:00:00",
                      "courseSelectStartDate":"2026-04-10 08:00:00",
                      "courseSelectEndDate":"2026-04-19 18:00:00",
                      "courseCancelEndDate":"2026-04-19 18:00:00",
                      "courseMaxCount":30,
                      "courseCurrentCount":12,
                      "selected":false
                    }
                  ],
                  "totalElements":3,
                  "totalPages":1,
                  "size":20,
                  "number":1
                }
              }
              """
                  .trimIndent()
          )
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = BykcApi(LocalBykcApiBackend(nowProvider = { fixedNow }))

    val profile = api.getProfile()
    val courses = api.getCourses(page = 1, size = 20, all = false)

    assertTrue(profile.isSuccess)
    assertEquals("测试学生", profile.getOrNull()?.realName)
    assertEquals("计算机学院", profile.getOrNull()?.collegeName)
    assertEquals("2025-2026-2", profile.getOrNull()?.termName)

    assertTrue(courses.isSuccess)
    assertEquals(3, courses.getOrNull()?.total)
    assertEquals(2, courses.getOrNull()?.courses?.size)
    assertEquals(BykcCourseStatus.AVAILABLE, courses.getOrNull()?.courses?.get(0)?.status)
    assertEquals(BykcCourseStatus.FULL, courses.getOrNull()?.courses?.get(1)?.status)
  }

  @Test
  fun `bykc api resolves detail chosen courses and statistics in direct mode`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://bykc.buaa.edu.cn/sscv/cas/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://bykc.buaa.edu.cn/cas-login?token=test-token",
                    ),
            )
        "https://bykc.buaa.edu.cn/cas-login?token=test-token" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://bykc.buaa.edu.cn/sscv/queryCourseById" -> respondJson(selectedCourseDetailJson)
        "https://bykc.buaa.edu.cn/sscv/getAllConfig" ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "semester":[
                      {
                        "id":1,
                        "semesterName":"2025-2026-1",
                        "semesterStartDate":"2025-09-01 00:00:00",
                        "semesterEndDate":"2026-01-31 23:59:59"
                      },
                      {
                        "id":2,
                        "semesterName":"2025-2026-2",
                        "semesterStartDate":"2026-02-23 00:00:00",
                        "semesterEndDate":"2026-07-12 23:59:59"
                      }
                    ]
                  }
                }
                """
                    .trimIndent()
            )
        "https://bykc.buaa.edu.cn/sscv/queryChosenCourse" ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "courseList":[
                      {
                        "id":9001,
                        "selectDate":"2026-04-19 10:00:00",
                        "checkin":5,
                        "pass":0,
                        "score":100,
                        "courseInfo":{
                          "id":9527,
                          "courseName":"耕趣农场劳动课",
                          "coursePosition":"沙河校区农场",
                          "courseTeacher":"李老师",
                          "courseStartDate":"2026-04-20 09:00:00",
                          "courseEndDate":"2026-04-20 11:00:00",
                          "courseCancelEndDate":"2026-04-19 18:00:00",
                          "courseMaxCount":100,
                          "courseCurrentCount":60,
                          "courseNewKind1":{"id":1,"kindName":"博雅课程"},
                          "courseNewKind2":{"id":2,"kindName":"劳动教育"},
                          "courseSignType":2,
                          "courseSignConfig":"{\"signStartDate\":\"2026-04-20 08:50:00\",\"signEndDate\":\"2026-04-20 09:20:00\",\"signOutStartDate\":\"2026-04-20 09:50:00\",\"signOutEndDate\":\"2026-04-20 10:20:00\",\"signPointList\":[{\"lat\":40.1001,\"lng\":116.3001,\"radius\":8.0}]}"
                        }
                      }
                    ]
                  }
                }
                """
                    .trimIndent()
            )
        "https://bykc.buaa.edu.cn/sscv/queryStatisticByUserId" ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "validCount":4,
                    "statistical":{
                      "1|博雅课程":{
                        "2|劳动教育":{
                          "assessmentCount":2,
                          "completeAssessmentCount":2
                        }
                      }
                    }
                  }
                }
                """
                    .trimIndent()
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = BykcApi(LocalBykcApiBackend(nowProvider = { fixedNow }))

    val detail = api.getCourseDetail(9527L)
    val chosenCourses = api.getChosenCourses()
    val statistics = api.getStatistics()

    assertTrue(detail.isSuccess, detail.exceptionOrNull()?.message.orEmpty())
    assertEquals("学生中心", detail.getOrNull()?.organizerCollegeName)
    assertEquals(listOf("未指定校区"), detail.getOrNull()?.audienceCampuses)
    assertTrue(detail.getOrNull()?.canSignOut == true)

    assertTrue(chosenCourses.isSuccess)
    assertEquals(1, chosenCourses.getOrNull()?.size)
    assertEquals(5, chosenCourses.getOrNull()?.firstOrNull()?.checkin)
    assertTrue(chosenCourses.getOrNull()?.firstOrNull()?.canSignOut == true)

    assertTrue(statistics.isSuccess)
    assertEquals(4, statistics.getOrNull()?.totalValidCount)
    assertEquals(true, statistics.getOrNull()?.categories?.singleOrNull()?.isQualified)
  }

  @Test
  fun `bykc api supports select deselect and sign in direct mode`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.toString()) {
        "https://bykc.buaa.edu.cn/sscv/cas/login" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://bykc.buaa.edu.cn/cas-login?token=test-token",
                    ),
            )
        "https://bykc.buaa.edu.cn/cas-login?token=test-token" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        "https://bykc.buaa.edu.cn/sscv/choseCourse" ->
            respondJson("""{"status":"0","errmsg":"","data":{"courseCurrentCount":61}}""")
        "https://bykc.buaa.edu.cn/sscv/delChosenCourse" ->
            respondJson("""{"status":"0","errmsg":"","data":{"courseCurrentCount":60}}""")
        "https://bykc.buaa.edu.cn/sscv/getAllConfig" ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "semester":[
                      {
                        "id":2,
                        "semesterName":"2025-2026-2",
                        "semesterStartDate":"2026-02-23 00:00:00",
                        "semesterEndDate":"2026-07-12 23:59:59"
                      }
                    ]
                  }
                }
                """
                    .trimIndent()
            )
        "https://bykc.buaa.edu.cn/sscv/queryChosenCourse" ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "courseList":[
                      {
                        "id":9001,
                        "selectDate":"2026-04-19 10:00:00",
                        "checkin":0,
                        "pass":0,
                        "courseInfo":{
                          "id":9527,
                          "courseName":"耕趣农场劳动课",
                          "courseMaxCount":100,
                          "courseSignConfig":"{\"signStartDate\":\"2026-04-20 08:50:00\",\"signEndDate\":\"2026-04-20 10:20:00\",\"signOutStartDate\":\"2026-04-20 10:30:00\",\"signOutEndDate\":\"2026-04-20 11:00:00\",\"signPointList\":[{\"lat\":40.1001,\"lng\":116.3001,\"radius\":8.0}]}"
                        }
                      }
                    ]
                  }
                }
                """
                    .trimIndent()
            )
        "https://bykc.buaa.edu.cn/sscv/signCourseByUser" -> {
          assertEquals("test-token", request.headers["auth_token"])
          respondJson("""{"status":"0","errmsg":"","data":{}}""")
        }
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = BykcApi(LocalBykcApiBackend(nowProvider = { fixedNow }))

    val select = api.selectCourse(9527L)
    val deselect = api.deselectCourse(9527L)
    val sign = api.signCourse(courseId = 9527L, lat = null, lng = null, signType = 1)

    assertTrue(select.isSuccess)
    assertEquals("选课成功", select.getOrNull()?.message)
    assertTrue(deselect.isSuccess)
    assertEquals("退选成功", deselect.getOrNull()?.message)
    assertTrue(sign.isSuccess)
    assertEquals("签到成功", sign.getOrNull()?.message)
  }

  @Test
  fun `bykc api uses webvpn wrapped urls when current mode is webvpn`() = runTest {
    ConnectionModeStore.save(ConnectionMode.WEBVPN)
    ConnectionRuntime.resolveSelectedMode()
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22374444",
            user = UserData(name = "WebVPN User", schoolid = "22374444"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    val requestedUrls = mutableListOf<String>()
    val wrappedCasLogin =
        LocalWebVpnSupport.toWebVpnUrl("https://bykc.buaa.edu.cn/cas-login?token=test-token")
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when {
        request.url.host == "d.buaa.edu.cn" &&
            request.url.encodedPath.endsWith("/sscv/cas/login") ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers = headersOf(HttpHeaders.Location, wrappedCasLogin),
            )
        request.url.toString() == wrappedCasLogin ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
            )
        request.url.host == "d.buaa.edu.cn" &&
            request.url.encodedPath.endsWith("/sscv/getUserProfile") ->
            respondJson(
                """
                {
                  "status":"0",
                  "errmsg":"",
                  "data":{
                    "id":1,
                    "employeeId":"22374444",
                    "realName":"WebVPN 用户"
                  }
                }
                """
                    .trimIndent()
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = BykcApi(LocalBykcApiBackend(nowProvider = { fixedNow }))

    val profile = api.getProfile()

    assertTrue(profile.isSuccess, profile.exceptionOrNull()?.message.orEmpty())
    assertEquals("WebVPN 用户", profile.getOrNull()?.realName)
    assertTrue(requestedUrls.all { it.startsWith("https://d.buaa.edu.cn/") })
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(ContentNegotiation) { json(this@LocalBykcApiBackendTest.json) }
        install(HttpCookies) {
          storage =
              LocalCookieStore.storage(
                  ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
                      ?: ConnectionMode.DIRECT
              )
        }
      }
    }
  }

  private val selectedCourseDetailJson =
      """
      {
        "status":"0",
        "errmsg":"",
        "data":{
          "id":9527,
          "courseName":"耕趣农场劳动课",
          "coursePosition":"沙河校区农场",
          "courseContact":"曹雅璐",
          "courseContactMobile":"13967341804",
          "courseTeacher":"李老师",
          "courseStartDate":"2026-04-20 09:00:00",
          "courseEndDate":"2026-04-20 11:00:00",
          "courseSelectStartDate":"2026-04-18 08:00:00",
          "courseSelectEndDate":"2026-04-20 08:30:00",
          "courseCancelEndDate":"2026-04-19 18:00:00",
          "courseBelongCollege":{"id":61,"collegeName":"学生中心"},
          "courseMaxCount":100,
          "courseCurrentCount":60,
          "courseCampusList":["全部校区"],
          "courseCollegeList":["全部学院"],
          "courseTermList":["全部年级"],
          "courseGroupList":["全部人群"],
          "courseDesc":"<p>课程描述</p>",
          "courseNewKind1":{"id":1,"kindName":"博雅课程"},
          "courseNewKind2":{"id":2,"kindName":"劳动教育"},
          "courseSignType":2,
          "courseSignConfig":"{\"signStartDate\":\"2026-04-20 08:50:00\",\"signEndDate\":\"2026-04-20 09:20:00\",\"signOutStartDate\":\"2026-04-20 09:50:00\",\"signOutEndDate\":\"2026-04-20 10:20:00\",\"signPointList\":[{\"lat\":40.1001,\"lng\":116.3001,\"radius\":8.0}]}",
          "selected":true
        }
      }
      """
          .trimIndent()
}

private fun MockRequestHandleScope.respondJson(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
    )
