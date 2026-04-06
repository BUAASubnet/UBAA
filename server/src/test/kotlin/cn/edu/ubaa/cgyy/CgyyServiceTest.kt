package cn.edu.ubaa.cgyy

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.CgyyReservationSelectionDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

class CgyyServiceTest {
  @Test
  fun `submitReservation refreshes day info and completes workflow`() = runTest {
    val gateway = FakeGateway()
    val solver =
        object : CgyyCaptchaAutoSolver {
          override fun solve(challenge: CgyyCaptchaChallenge): CgyySolvedCaptcha {
            return CgyySolvedCaptcha(46, """{"x":46,"y":5}""", "point", "verify")
          }
        }

    val service = CgyyService(clientProvider = { gateway }, captchaSolver = solver)
    val result =
        service.submitReservation(
            "2418",
            CgyyReservationSubmitRequest(
                venueSiteId = 4,
                reservationDate = "2026-03-29",
                selections = listOf(CgyyReservationSelectionDto(6, 242)),
                phone = "18800000000",
                theme = "讨论",
                purposeType = 3,
                joinerNum = 3,
                activityContent = "活动内容",
                joiners = "张三等三人",
            ),
        )

    assertTrue(result.success)
    assertEquals(1, gateway.dayInfoCalls)
    assertEquals(1, gateway.createOrderCalls)
    assertEquals(1, gateway.getCaptchaCalls)
    assertEquals(1, gateway.verifyCaptchaCalls)
    assertEquals(1, gateway.submitCalls)
  }

  @Test
  fun `getVenueSites maps array payload from gateway`() = runTest {
    val gateway =
        object : FakeGateway() {
          override suspend fun getVenueSites(): JsonArray {
            return buildJsonArray {
              add(
                  buildJsonObject {
                    put("id", 4)
                    put("siteName", "二层")
                    put("venueName", "老主楼研讨室")
                    put("campusName", "学院路校区")
                  }
              )
            }
          }
        }

    val service = CgyyService(clientProvider = { gateway })
    val sites = service.getVenueSites("2418")

    assertEquals(listOf(CgyyVenueSiteDto(4, "二层", "老主楼研讨室", "学院路校区")), sites)
  }

  @Test
  fun `getOrders maps check content from gateway`() = runTest {
    val gateway =
        object : FakeGateway() {
          override suspend fun getMineOrders(page: Int, size: Int): JsonObject {
            return buildJsonObject {
              put("totalElements", 1)
              put("totalPages", 1)
              put("size", size)
              put("number", page)
              putJsonArray("content") {
                add(
                    buildJsonObject {
                      put("id", 1)
                      put("orderStatus", 1)
                      put("checkStatus", -2)
                      put("checkContent", "材料不完整")
                    }
                )
              }
            }
          }
        }

    val service = CgyyService(clientProvider = { gateway })
    val orders = service.getOrders("2418", page = 0, size = 20)

    assertEquals(1, orders.content.size)
    assertEquals("材料不完整", orders.content.first().checkContent)
    assertEquals(-2, orders.content.first().checkStatus)
    assertNotNull(orders.content.first())
  }

  @Test
  fun `getOrders retries with fresh client after transient gateway failure`() = runTest {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    var closedFirstClient = false
    var clientCreations = 0
    val service =
        CgyyService(
            clientProvider = {
              clientCreations++
              if (clientCreations == 1) {
                object : FakeGateway() {
                  override suspend fun getMineOrders(page: Int, size: Int): JsonObject {
                    throw CgyyException("temporary failure", "cgyy_error")
                  }

                  override fun close() {
                    closedFirstClient = true
                  }
                }
              } else {
                object : FakeGateway() {
                  override suspend fun getMineOrders(page: Int, size: Int): JsonObject {
                    return buildJsonObject {
                      put("totalElements", 1)
                      put("totalPages", 1)
                      put("size", size)
                      put("number", page)
                      putJsonArray("content") { add(buildJsonObject { put("id", 9) }) }
                    }
                  }
                }
              }
            }
        )

    try {
      val orders = service.getOrders("2418", page = 0, size = 20)

      assertEquals(2, clientCreations)
      assertTrue(closedFirstClient)
      assertEquals(1, orders.content.size)
      assertEquals(9, orders.content.first().id)
      assertContains(
          registry.scrape(),
          "ubaa_retry_events_total{feature=\"cgyy\",operation=\"list_orders\",reason=\"client_refresh\"}",
      )
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  @Test
  fun `getPurposeTypes falls back to static definitions when gateway payload is empty`() = runTest {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    val service = CgyyService(clientProvider = { FakeGateway() })

    try {
      val types = service.getPurposeTypes("2418")

      assertTrue(types.isNotEmpty())
      assertContains(
          registry.scrape(),
          "ubaa_fallback_events_total{feature=\"cgyy\",operation=\"list_purpose_types\",reason=\"cgyy_static_purpose_types\"}",
      )
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  @Test
  fun `status 2 slot is not treated as reservable`() = runTest {
    val gateway =
        object : FakeGateway() {
          override suspend fun getReservationDayInfo(
              searchDate: String,
              venueSiteId: Int,
          ): JsonObject {
            dayInfoCalls++
            return buildJsonObject {
              put("token", "day-token")
              putJsonArray("reservationDateList") { add(JsonPrimitive("2026-03-29")) }
              putJsonArray("spaceTimeInfo") {
                add(
                    buildJsonObject {
                      put("id", 242)
                      put("beginTime", "14:00")
                      put("endTime", "15:35")
                    }
                )
              }
              putJsonObject("reservationDateSpaceInfo") {
                putJsonArray("2026-03-29") {
                  add(
                      buildJsonObject {
                        put("id", 6)
                        put("spaceName", "主204")
                        put("venueSiteId", venueSiteId)
                        putJsonObject("242") {
                          put("reservationStatus", 2)
                          put("tradeNo", JsonNull)
                          put("orderId", JsonNull)
                          put("takeUp", false)
                        }
                      }
                  )
                }
              }
            }
          }
        }

    val service = CgyyService(clientProvider = { gateway })
    val dayInfo = service.getDayInfo("2418", venueSiteId = 4, date = "2026-03-29")

    assertFalse(dayInfo.spaces.first().slots.first().isReservable)
  }

  private open class FakeGateway : CgyyGateway {
    var dayInfoCalls = 0
    var createOrderCalls = 0
    var getCaptchaCalls = 0
    var verifyCaptchaCalls = 0
    var submitCalls = 0

    override suspend fun getVenueSites(): JsonArray = JsonArray(emptyList())

    override suspend fun getPurposeTypesRaw(): JsonElement? = null

    override suspend fun getReservationDayInfo(searchDate: String, venueSiteId: Int): JsonObject {
      dayInfoCalls++
      return buildJsonObject {
        put("token", "day-token")
        put("reservationTotalNum", 1)
        putJsonArray("reservationDateList") { add(JsonPrimitive("2026-03-29")) }
        putJsonArray("spaceTimeInfo") {
          add(
              buildJsonObject {
                put("id", 242)
                put("beginTime", "14:00")
                put("endTime", "15:35")
              }
          )
        }
        putJsonObject("reservationDateSpaceInfo") {
          putJsonArray("2026-03-29") {
            add(
                buildJsonObject {
                  put("id", 6)
                  put("spaceName", "主204")
                  put("venueSiteId", 4)
                  put("venueSpaceGroupId", JsonNull)
                  putJsonObject("242") {
                    put("reservationStatus", 1)
                    put("startDate", "2026-03-29 14:00")
                    put("endDate", "2026-03-29 15:35")
                    put("tradeNo", JsonNull)
                    put("orderId", JsonNull)
                    put("takeUp", false)
                  }
                }
            )
          }
        }
      }
    }

    override suspend fun createReservationOrder(
        venueSiteId: Int,
        reservationDate: String,
        weekStartDate: String,
        reservationOrderJson: String,
        token: String,
    ): CgyyApiEnvelope {
      createOrderCalls++
      return CgyyApiEnvelope(JsonNull, "OK", buildJsonObject {})
    }

    override suspend fun getCaptcha(): CgyyCaptchaChallenge {
      getCaptchaCalls++
      return CgyyCaptchaChallenge("1234567890abcdef", "captcha-token", "", "")
    }

    override suspend fun verifyCaptcha(pointJson: String, token: String): JsonObject {
      verifyCaptchaCalls++
      return buildJsonObject { put("success", true) }
    }

    override suspend fun submitReservationOrder(
        venueSiteId: Int,
        reservationDate: String,
        reservationOrderJson: String,
        weekStartDate: String,
        phone: String,
        theme: String,
        purposeType: Int,
        joinerNum: Int,
        activityContent: String,
        joiners: String,
        captchaVerification: String,
        token: String,
        isPhilosophySocialSciences: Int,
        isOffSchoolJoiner: Int,
    ): CgyyApiEnvelope {
      submitCalls++
      return CgyyApiEnvelope(
          buildJsonObject {
            putJsonObject("orderInfo") {
              put("id", 1)
              put("tradeNo", "D1")
              put("theme", theme)
            }
          },
          "预约成功",
          buildJsonObject {},
      )
    }

    override suspend fun getMineOrders(page: Int, size: Int): JsonObject = buildJsonObject {}

    override suspend fun getOrderDetail(orderId: Int): JsonObject = buildJsonObject {}

    override suspend fun cancelOrder(orderId: Int): CgyyApiEnvelope =
        CgyyApiEnvelope(JsonNull, "取消成功", buildJsonObject {})

    override suspend fun getLockCode(): JsonElement? = JsonNull

    override fun close() {}
  }
}
