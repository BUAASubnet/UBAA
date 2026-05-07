package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.ApiClient
import cn.edu.ubaa.api.feature.CgyyApi
import cn.edu.ubaa.api.storage.AuthTokensStore
import cn.edu.ubaa.api.storage.ClientIdStore
import cn.edu.ubaa.model.dto.CgyyDayInfoResponse
import cn.edu.ubaa.model.dto.CgyyLockCodeResponse
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.CgyyOrdersPageResponse
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.CgyyReservationSelectionDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyReservationSubmitResponse
import cn.edu.ubaa.model.dto.CgyyTimeSlotDto
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import com.russhwolf.settings.MapSettings
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class CgyyApiTest {
  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
  }

  @Test
  fun shouldFetchDayInfo() = runTest {
    val engine = MockEngine { request ->
      assertEquals("/api/v1/cgyy/day-info", request.url.encodedPath)
      assertEquals("4", request.url.parameters["venueSiteId"])
      assertEquals("2026-03-29", request.url.parameters["date"])
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      CgyyDayInfoResponse(
                          venueSiteId = 4,
                          reservationDate = "2026-03-29",
                          availableDates = listOf("2026-03-29"),
                          timeSlots = listOf(CgyyTimeSlotDto(242, "14:00", "15:35", "14:00-15:35")),
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = CgyyApi(ApiClient(engine))
    val result = api.getDayInfo(4, "2026-03-29")

    assertTrue(result.isSuccess)
    assertEquals("2026-03-29", result.getOrNull()?.reservationDate)
  }

  @Test
  fun shouldSubmitReservation() = runTest {
    val engine = MockEngine { request ->
      assertEquals("/api/v1/cgyy/reservations", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      CgyyReservationSubmitResponse(
                          success = true,
                          message = "预约成功",
                          order = CgyyOrderDto(id = 1, tradeNo = "D1"),
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = CgyyApi(ApiClient(engine))
    val result =
        api.submitReservation(
            CgyyReservationSubmitRequest(
                venueSiteId = 4,
                reservationDate = "2026-03-29",
                selections = listOf(CgyyReservationSelectionDto(6, 242)),
                phone = "18800000000",
                theme = "讨论",
                purposeType = 3,
                joinerNum = 3,
                activityContent = "讨论",
                joiners = "张三等3人",
            )
        )

    assertTrue(result.isSuccess)
    assertEquals("预约成功", result.getOrNull()?.message)
  }

  @Test
  fun shouldFetchOrdersAndLockCode() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/cgyy/orders" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            CgyyOrdersPageResponse(
                                content = listOf(CgyyOrderDto(id = 1, theme = "讨论")),
                                totalElements = 1,
                                totalPages = 1,
                                size = 20,
                                number = 0,
                            )
                        )
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        "/api/v1/cgyy/orders/lock-code" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            CgyyLockCodeResponse(buildJsonObject { put("password", "123456") })
                        )
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val api = CgyyApi(ApiClient(engine))

    val orders = api.getMyOrders()
    val lockCode = api.getLockCode()

    assertTrue(orders.isSuccess)
    assertEquals(1, orders.getOrNull()?.content?.size)
    assertTrue(lockCode.isSuccess)
    assertTrue(lockCode.getOrNull()?.rawData?.toString()?.contains("123456") == true)
  }

  @Test
  fun shouldFetchVenueSitesAndPurposeTypes() = runTest {
    val engine = MockEngine { request ->
      when (request.url.encodedPath) {
        "/api/v1/cgyy/sites" ->
            respond(
                content =
                    ByteReadChannel(
                        json.encodeToString(
                            listOf(
                                CgyyVenueSiteDto(
                                    id = 4,
                                    siteName = "二层",
                                    venueName = "老主楼研讨室",
                                    campusName = "学院路校区",
                                )
                            )
                        )
                    ),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        "/api/v1/cgyy/purpose-types" ->
            respond(
                content =
                    ByteReadChannel(json.encodeToString(listOf(CgyyPurposeTypeDto(3, "学术研讨类")))),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        else -> error("Unexpected path: ${request.url.encodedPath}")
      }
    }

    val api = CgyyApi(ApiClient(engine))
    assertEquals(4, api.getVenueSites().getOrNull()?.firstOrNull()?.id)
    assertEquals(3, api.getPurposeTypes().getOrNull()?.firstOrNull()?.key)
  }
}
