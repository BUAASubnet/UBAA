package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.ApiClient
import cn.edu.ubaa.api.feature.YgdkApi
import cn.edu.ubaa.api.storage.AuthTokensStore
import cn.edu.ubaa.api.storage.ClientIdStore
import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkClockinSubmitResponse
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkRecordDto
import cn.edu.ubaa.model.dto.YgdkRecordsPageResponse
import cn.edu.ubaa.model.dto.YgdkTermSummaryDto
import com.russhwolf.settings.MapSettings
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.forms.MultiPartFormDataContent
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json

class YgdkApiTest {
  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
  }

  @Test
  fun `should fetch overview and records`() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/ygdk/overview" ->
            respondJson(
                YgdkOverviewResponse(
                    summary = YgdkTermSummaryDto(termCount = 2, termTarget = 16),
                    classifyId = 1,
                    classifyName = "体育打卡",
                    defaultItemId = 17,
                    defaultItemName = "跑步",
                )
            )
        "/api/v1/ygdk/records" -> {
          assertEquals("2", request.url.parameters["page"])
          assertEquals("5", request.url.parameters["size"])
          respondJson(
              YgdkRecordsPageResponse(
                  content = listOf(YgdkRecordDto(recordId = 1, itemName = "跑步")),
                  total = 1,
                  page = 2,
                  size = 5,
                  hasMore = false,
              )
          )
        }
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val api = YgdkApi(ApiClient(engine))
    val overview = api.getOverview()
    val records = api.getRecords(page = 2, size = 5)

    assertTrue(overview.isSuccess)
    assertEquals(16, overview.getOrNull()?.summary?.termTarget)
    assertTrue(records.isSuccess)
    assertEquals(1, records.getOrNull()?.content?.size)
  }

  @Test
  fun `should submit clockin via multipart`() = runTest {
    var capturedRequest: HttpRequestData? = null
    val engine = MockEngine { request ->
      capturedRequest = request
      respondJson(
          YgdkClockinSubmitResponse(
              success = true,
              message = "打卡成功",
              recordId = 1001,
          )
      )
    }

    val api = YgdkApi(ApiClient(engine))
    val result =
        api.submitClockin(
            YgdkClockinSubmitRequest(
                itemId = 17,
                startTime = "2026-04-01 08:00",
                endTime = "2026-04-01 09:00",
                place = "操场",
                shareToSquare = false,
                photo =
                    cn.edu.ubaa.model.dto.YgdkPhotoUpload(
                        bytes = byteArrayOf(1, 2, 3),
                        fileName = "proof.png",
                        mimeType = "image/png",
                    ),
            )
        )

    assertTrue(result.isSuccess)
    assertEquals("打卡成功", result.getOrNull()?.message)
    assertIs<MultiPartFormDataContent>(capturedRequest?.body)
  }

  private inline fun <reified T> MockRequestHandleScope.respondJson(body: T) =
      respond(
          content = ByteReadChannel(json.encodeToString(body)),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
}
