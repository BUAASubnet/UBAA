package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CgyyReservationSelectionDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json

class LocalCgyyApiBackendTest {
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
  fun `cgyy api fetches direct upstream data`() = runTest {
    var manageLoginCalls = 0
    var apiLoginCalls = 0
    val engine = MockEngine { request ->
      when {
        request.url.encodedPath == "/venue-zhjs-server/sso/manageLogin" -> {
          manageLoginCalls++
          respond(
              content = ByteReadChannel.Empty,
              status = HttpStatusCode.OK,
              headers =
                  headersOf(
                      HttpHeaders.SetCookie,
                      "sso_buaa_zhjs_token=sso-token; Path=/; HttpOnly",
                  ),
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/login" -> {
          apiLoginCalls++
          assertEquals("sso-token", request.headers["Sso-Token"])
          respondJson(
              """
              {
                "code":200,
                "message":"OK",
                "data":{
                  "token":{
                    "access_token":"access-1"
                  }
                }
              }
              """
                  .trimIndent()
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/front/website/venues" -> {
          assertEquals("access-1", request.headers["cgAuthorization"])
          assertEquals("3", request.url.parameters["reservationRoleId"])
          assertTrue(request.headers["sign"].orEmpty().isNotBlank())
          respondJson(
              """
              {
                "code":200,
                "message":"OK",
                "data":{
                  "content":[
                    {
                      "id":10,
                      "venueName":"沙河研讨室",
                      "campusName":"沙河校区",
                      "siteList":[
                        {
                          "id":"101",
                          "siteName":"A101"
                        }
                      ]
                    }
                  ]
                }
              }
              """
                  .trimIndent()
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/codes" -> {
          respondJson(
              """
              {
                "code":200,
                "message":"OK",
                "data":[
                  {
                    "children":[
                      {
                        "key":3,
                        "name":"学术研讨类"
                      }
                    ]
                  }
                ]
              }
              """
                  .trimIndent()
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/reservation/day/info" -> {
          assertEquals("2026-04-22", request.url.parameters["searchDate"])
          assertEquals("101", request.url.parameters["venueSiteId"])
          assertTrue(request.url.parameters["nocache"].orEmpty().isNotBlank())
          respondJson(
              """
              {
                "code":200,
                "message":"OK",
                "data":{
                  "token":"day-token",
                  "reservationTotalNum":1,
                  "reservationDateList":["2026-04-22"],
                  "spaceTimeInfo":[
                    {"id":201,"beginTime":"14:00","endTime":"15:35"}
                  ],
                  "reservationDateSpaceInfo":{
                    "2026-04-22":[
                      {
                        "id":301,
                        "spaceName":"A101-1",
                        "venueSiteId":101,
                        "201":{
                          "reservationStatus":1,
                          "startDate":"2026-04-22 14:00",
                          "endDate":"2026-04-22 15:35",
                          "tradeNo":null,
                          "orderId":null,
                          "takeUp":false
                        }
                      }
                    ]
                  }
                }
              }
              """
                  .trimIndent()
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/orders/mine" -> {
          assertEquals("1", request.url.parameters["page"])
          assertEquals("10", request.url.parameters["size"])
          respondJson(
              """
              {
                "code":200,
                "message":"OK",
                "data":{
                  "content":[
                    {
                      "id":1,
                      "theme":"课程讨论",
                      "orderStatus":1,
                      "checkStatus":2
                    }
                  ],
                  "totalElements":1,
                  "totalPages":1,
                  "size":10,
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
    val api = CgyyApi(LocalCgyyApiBackend())

    val sites = api.getVenueSites()
    val purposeTypes = api.getPurposeTypes()
    val dayInfo = api.getDayInfo(101, "2026-04-22")
    val orders = api.getMyOrders(page = 1, size = 10)

    assertTrue(sites.isSuccess, sites.exceptionOrNull()?.message.orEmpty())
    assertEquals(101, sites.getOrNull()?.singleOrNull()?.id)
    assertEquals("沙河研讨室", sites.getOrNull()?.singleOrNull()?.venueName)

    assertTrue(purposeTypes.isSuccess, purposeTypes.exceptionOrNull()?.message.orEmpty())
    assertEquals(3, purposeTypes.getOrNull()?.singleOrNull()?.key)

    assertTrue(dayInfo.isSuccess, dayInfo.exceptionOrNull()?.message.orEmpty())
    assertEquals("day-token", dayInfo.getOrNull()?.reservationToken)
    assertTrue(
        dayInfo.getOrNull()?.spaces?.singleOrNull()?.slots?.singleOrNull()?.isReservable == true
    )

    assertTrue(orders.isSuccess, orders.exceptionOrNull()?.message.orEmpty())
    assertEquals(1, orders.getOrNull()?.content?.size)
    assertEquals("课程讨论", orders.getOrNull()?.content?.singleOrNull()?.theme)

    assertEquals(1, manageLoginCalls)
    assertEquals(1, apiLoginCalls)
  }

  @Test
  fun `cgyy api submits reservation and handles order actions in direct mode`() = runTest {
    var captchaCheckCalls = 0
    val solver =
        object : LocalCgyyCaptchaSolver {
          override fun solve(challenge: LocalCgyyCaptchaChallenge): LocalCgyySolvedCaptcha {
            assertEquals("captcha-token", challenge.token)
            return LocalCgyySolvedCaptcha(
                moveDistance = 46,
                pointJsonData = """{"x":46,"y":5}""",
                pointJson = "encrypted-point",
                captchaVerification = "encrypted-check",
            )
          }
        }
    val engine = MockEngine { request ->
      when {
        request.url.encodedPath == "/venue-zhjs-server/sso/manageLogin" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
                headers =
                    headersOf(
                        HttpHeaders.SetCookie,
                        "sso_buaa_zhjs_token=sso-token; Path=/; HttpOnly",
                    ),
            )
        request.url.encodedPath == "/venue-zhjs-server/api/login" ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "token":{
                      "access_token":"access-2"
                    }
                  }
                }
                """
                    .trimIndent()
            )
        request.url.encodedPath == "/venue-zhjs-server/api/reservation/day/info" ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "token":"day-token",
                    "reservationDateList":["2026-04-22"],
                    "spaceTimeInfo":[
                      {"id":201,"beginTime":"14:00","endTime":"15:35"}
                    ],
                    "reservationDateSpaceInfo":{
                      "2026-04-22":[
                        {
                          "id":301,
                          "spaceName":"A101-1",
                          "venueSiteId":101,
                          "201":{
                            "reservationStatus":1,
                            "startDate":"2026-04-22 14:00",
                            "endDate":"2026-04-22 15:35",
                            "tradeNo":null,
                            "orderId":null,
                            "takeUp":false
                          }
                        }
                      ]
                    }
                  }
                }
                """
                    .trimIndent()
            )
        request.url.encodedPath == "/venue-zhjs-server/api/reservation/order/info" ->
            respondJson("""{"code":200,"message":"OK","data":null}""")
        request.url.encodedPath == "/venue-zhjs-server/api/captcha/get" ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "success":true,
                    "repData":{
                      "secretKey":"1234567890abcdef",
                      "token":"captcha-token",
                      "originalImageBase64":"data:image/png;base64,AA==",
                      "jigsawImageBase64":"data:image/png;base64,AA=="
                    }
                  }
                }
                """
                    .trimIndent()
            )
        request.url.encodedPath == "/venue-zhjs-server/api/captcha/check" -> {
          captchaCheckCalls++
          respondJson("""{"code":200,"message":"OK","data":{"success":true}}""")
        }
        request.url.encodedPath == "/venue-zhjs-server/api/reservation/order/submit" -> {
          assertEquals("access-2", request.headers["cgAuthorization"])
          respondJson(
              """
              {
                "code":200,
                "message":"预约成功",
                "data":{
                  "orderInfo":{
                    "id":1,
                    "tradeNo":"D1",
                    "theme":"课程讨论"
                  }
                }
              }
              """
                  .trimIndent()
          )
        }
        request.url.encodedPath == "/venue-zhjs-server/api/orders/1" ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "id":1,
                    "theme":"课程讨论",
                    "venueName":"沙河研讨室",
                    "siteName":"A101",
                    "reservationDate":"2026-04-22"
                  }
                }
                """
                    .trimIndent()
            )
        request.url.encodedPath == "/venue-zhjs-server/api/orders/new/cancel/1" ->
            respondJson("""{"code":200,"message":"取消成功","data":null}""")
        request.url.encodedPath == "/venue-zhjs-server/api/orders/lock/code" ->
            respondJson("""{"code":200,"message":"OK","data":{"password":"654321"}}""")
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = CgyyApi(LocalCgyyApiBackend(captchaSolver = solver))

    val submit =
        api.submitReservation(
            CgyyReservationSubmitRequest(
                venueSiteId = 101,
                reservationDate = "2026-04-22",
                selections = listOf(CgyyReservationSelectionDto(spaceId = 301, timeId = 201)),
                phone = "18800000000",
                theme = "课程讨论",
                purposeType = 3,
                joinerNum = 4,
                activityContent = "围绕课程项目开展讨论",
                joiners = "张三、李四、王五、赵六",
            )
        )
    val detail = api.getOrderDetail(1)
    val cancel = api.cancelOrder(1)
    val lockCode = api.getLockCode()

    assertTrue(submit.isSuccess, submit.exceptionOrNull()?.message.orEmpty())
    assertEquals("预约成功", submit.getOrNull()?.message)
    assertEquals("D1", submit.getOrNull()?.order?.tradeNo)

    assertTrue(detail.isSuccess, detail.exceptionOrNull()?.message.orEmpty())
    assertEquals("课程讨论", detail.getOrNull()?.theme)
    assertEquals("沙河研讨室", detail.getOrNull()?.venueName)

    assertTrue(cancel.isSuccess, cancel.exceptionOrNull()?.message.orEmpty())
    assertEquals("取消成功", cancel.getOrNull()?.message)

    assertTrue(lockCode.isSuccess, lockCode.exceptionOrNull()?.message.orEmpty())
    assertTrue(lockCode.getOrNull()?.rawData?.toString()?.contains("654321") == true)
    assertEquals(1, captchaCheckCalls)
  }

  @Test
  fun `cgyy api uses webvpn wrapped urls when current mode is webvpn`() = runTest {
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
    val engine = MockEngine { request ->
      requestedUrls += request.url.toString()
      when {
        request.url.host == "d.buaa.edu.cn" &&
            request.url.encodedPath.endsWith("/sso/manageLogin") ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.OK,
                headers =
                    headersOf(
                        HttpHeaders.SetCookie,
                        "sso_buaa_zhjs_token=sso-token; Path=/; HttpOnly",
                    ),
            )
        request.url.host == "d.buaa.edu.cn" && request.url.encodedPath.endsWith("/api/login") ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "token":{
                      "access_token":"access-3"
                    }
                  }
                }
                """
                    .trimIndent()
            )
        request.url.host == "d.buaa.edu.cn" &&
            request.url.encodedPath.endsWith("/api/front/website/venues") ->
            respondJson(
                """
                {
                  "code":200,
                  "message":"OK",
                  "data":{
                    "content":[
                      {
                        "id":20,
                        "venueName":"学院路研讨室",
                        "campusName":"学院路校区",
                        "siteList":[
                          {
                            "id":"202",
                            "siteName":"B202"
                          }
                        ]
                      }
                    ]
                  }
                }
                """
                    .trimIndent()
            )
        else -> error("Unexpected request: ${request.method.value} ${request.url}")
      }
    }
    useMockUpstream(engine)
    val api = CgyyApi(LocalCgyyApiBackend())

    val result = api.getVenueSites()

    assertTrue(result.isSuccess, result.exceptionOrNull()?.message.orEmpty())
    assertEquals(202, result.getOrNull()?.singleOrNull()?.id)
    assertTrue(requestedUrls.all { it.startsWith("https://d.buaa.edu.cn/") })
  }

  @Test
  fun `cgyy business auth failure keeps global local session when uc session is still valid`() = runTest {
    val engine =
        MockEngine { request ->
          when (request.url.toString()) {
            "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin" ->
                respond(
                    content = ByteReadChannel("{}"),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
                )
            "https://uc.buaa.edu.cn/api/uc/status" ->
                respondJson(
                    """
                    {
                      "code":0,
                      "data":{
                        "name":"Test User",
                        "schoolid":"22373333",
                        "username":"22373333"
                      }
                    }
                    """
                        .trimIndent()
                )
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do" ->
                respondJson("""{"user":"ok"}""")
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do" ->
                respondJson(
                    """
                    {
                      "code":"0",
                      "msg":null,
                      "datas":[
                        {
                          "itemCode":"2025-2026-1",
                          "itemName":"2025-2026学年第一学期",
                          "selected":true,
                          "itemIndex":1
                        }
                      ]
                    }
                    """
                        .trimIndent()
                )
            else -> error("Unexpected request: ${request.method.value} ${request.url}")
          }
        }
    useMockUpstream(engine)

    val cgyyResult = CgyyApi(LocalCgyyApiBackend()).getMyOrders(page = 1, size = 10)

    assertTrue(cgyyResult.isFailure)
    assertEquals("cgyy_error", (cgyyResult.exceptionOrNull() as? ApiCallException)?.code)
    assertNotNull(LocalAuthSessionStore.get())

    val scheduleResult = LocalScheduleApiBackend().getTerms()

    assertTrue(scheduleResult.isSuccess, scheduleResult.exceptionOrNull()?.message.orEmpty())
    assertEquals("2025-2026-1", scheduleResult.getOrNull()?.singleOrNull()?.itemCode)
  }

  @Test
  fun `cgyy business auth failure clears global local session when uc session is invalid`() = runTest {
    val engine =
        MockEngine { request ->
          when (request.url.toString()) {
            "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin" ->
                respond(
                    content = ByteReadChannel("{}"),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
                )
            "https://uc.buaa.edu.cn/api/uc/status" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.Unauthorized,
                )
            else -> error("Unexpected request: ${request.method.value} ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result = CgyyApi(LocalCgyyApiBackend()).getMyOrders(page = 1, size = 10)

    assertTrue(result.isFailure)
    assertEquals("unauthenticated", (result.exceptionOrNull() as? ApiCallException)?.code)
    assertNull(LocalAuthSessionStore.get())
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(ContentNegotiation) { json(this@LocalCgyyApiBackendTest.json) }
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
}

private fun MockRequestHandleScope.respondJson(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
    )
