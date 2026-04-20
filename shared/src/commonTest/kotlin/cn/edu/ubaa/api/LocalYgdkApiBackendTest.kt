package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkPhotoUpload
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

class LocalYgdkApiBackendTest {
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
  fun `ygdk api uses direct upstream backend to fetch overview`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.host == "app.buaa.edu.cn" && request.url.encodedPath == "/uc/api/oauth/index" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://ygdk.buaa.edu.cn/#/home?code=oauth-code",
                    ),
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/User/campusAppLogin" ->
            respondJson("""{"code":1,"result":{"uid":1001,"token":"token-1"}}""")
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Classify/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"classify_id":3,"name":"阳光体育","term_num":16}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Item/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"item_id":1,"name":"跑步","sort":1},{"item_id":2,"name":"健走","sort":2}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Clockin/getCount" ->
            respondJson(
                """{"code":1,"result":{"term_good_count_show":5,"term_num":16,"week_count":2,"week_num":3}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Term/get" ->
            respondJson("""{"code":1,"result":{"term_id":20261,"name":"2026春"}}""")
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = YgdkApi().getOverview()

    assertTrue(result.isSuccess)
    val overview = result.getOrNull()
    assertEquals("阳光体育", overview?.classifyName)
    assertEquals(1, overview?.defaultItemId)
    assertEquals(5, overview?.summary?.termCount)
    assertEquals(16, overview?.summary?.termTarget)
  }

  @Test
  fun `ygdk api uses direct upstream backend to fetch records`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.host == "app.buaa.edu.cn" && request.url.encodedPath == "/uc/api/oauth/index" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://ygdk.buaa.edu.cn/#/home?code=oauth-code",
                    ),
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/User/campusAppLogin" ->
            respondJson("""{"code":1,"result":{"uid":1001,"token":"token-1"}}""")
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Classify/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"classify_id":3,"name":"阳光体育","term_num":16}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Item/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"item_id":1,"name":"跑步","sort":1},{"item_id":2,"name":"健走","sort":2}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Clockin/getList" -> {
          assertEquals("2", request.url.parameters["page"])
          assertEquals("5", request.url.parameters["limit"])
          respondJson(
              """
              {
                "code": 1,
                "result": {
                  "total": 1,
                  "list": [
                    {
                      "record_id": 10,
                      "item_id": 1,
                      "item_name": "跑步",
                      "start_time": "1743465600",
                      "end_time": "1743469200",
                      "place": "操场",
                      "isopen": 0,
                      "create_time_fmt": "2026-04-01 09:00"
                    }
                  ]
                }
              }
              """
                  .trimIndent()
          )
        }
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result = YgdkApi().getRecords(page = 2, size = 5)

    assertTrue(result.isSuccess)
    val records = result.getOrNull()
    assertEquals(1, records?.content?.size)
    assertEquals("跑步", records?.content?.singleOrNull()?.itemName)
    assertEquals("操场", records?.content?.singleOrNull()?.place)
  }

  @Test
  fun `ygdk api uses direct upstream backend to submit clockin`() = runTest {
    val engine = MockEngine { request ->
      when {
        request.url.host == "app.buaa.edu.cn" && request.url.encodedPath == "/uc/api/oauth/index" ->
            respond(
                content = ByteReadChannel.Empty,
                status = HttpStatusCode.Found,
                headers =
                    headersOf(
                        HttpHeaders.Location,
                        "https://ygdk.buaa.edu.cn/#/home?code=oauth-code",
                    ),
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/User/campusAppLogin" ->
            respondJson("""{"code":1,"result":{"uid":1001,"token":"token-1"}}""")
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Classify/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"classify_id":3,"name":"阳光体育","term_num":16}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Item/getList" ->
            respondJson(
                """{"code":1,"result":{"list":[{"item_id":1,"name":"跑步","sort":1},{"item_id":2,"name":"健走","sort":2}]}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Upload/File/post" ->
            respondJson(
                """{"code":1,"result":{"file_name":"uploaded-proof.png","file_url":"https://ygdk.buaa.edu.cn/file/uploaded-proof.png"}}"""
            )
        request.url.host == "ygdk.buaa.edu.cn" &&
            request.url.encodedPath == "/api/Front/Clockin/Clockin/clockin" ->
            respondJson(
                """{"code":1,"result":{"record_id":77,"term_good_count_show":6,"term_num":16}}"""
            )
        else -> error("Unexpected url: ${request.url}")
      }
    }
    useMockUpstream(engine)

    val result =
        YgdkApi()
            .submitClockin(
                YgdkClockinSubmitRequest(
                    itemId = 2,
                    startTime = "2026-04-01 08:00",
                    endTime = "2026-04-01 09:00",
                    place = "足球场",
                    shareToSquare = true,
                    photo =
                        YgdkPhotoUpload(
                            bytes = byteArrayOf(1, 2, 3),
                            fileName = "proof.png",
                            mimeType = "image/png",
                        ),
                )
            )

    assertTrue(result.isSuccess)
    assertEquals(true, result.getOrNull()?.success)
    assertEquals("打卡成功", result.getOrNull()?.message)
    assertEquals(77, result.getOrNull()?.recordId)
    assertEquals(6, result.getOrNull()?.summary?.termCount)
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

private fun MockRequestHandleScope.respondJson(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
    )
