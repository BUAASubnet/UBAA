package cn.edu.ubaa.model.dto

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

class CgyyOrderCancellationTest {
  private val timeZone = TimeZone.of("Asia/Shanghai")

  @Test
  fun `cancel stays available more than four hours before start`() {
    val order =
        CgyyOrderDto(
            id = 1,
            orderStatus = 1,
            checkStatus = 1,
            reservationStartDate = "2026-04-04 18:30:00",
            reservationEndDate = "2026-04-04 20:05:00",
        )

    assertTrue(order.canCancelAt(now = Instant.parse("2026-04-04T06:29:59Z"), timeZone = timeZone))
  }

  @Test
  fun `cancel hides once within four hours before start`() {
    val order =
        CgyyOrderDto(
            id = 1,
            orderStatus = 1,
            checkStatus = 1,
            reservationStartDate = "2026-04-04 18:30:00",
            reservationEndDate = "2026-04-04 20:05:00",
        )

    assertFalse(order.canCancelAt(now = Instant.parse("2026-04-04T06:30:00Z"), timeZone = timeZone))
  }

  @Test
  fun `cancel hides for past reservation`() {
    val order =
        CgyyOrderDto(
            id = 1,
            orderStatus = 1,
            checkStatus = 1,
            reservationStartDate = "2026-04-04 14:00:00",
            reservationEndDate = "2026-04-04 15:35:00",
        )

    assertFalse(order.canCancelAt(now = Instant.parse("2026-04-04T08:00:00Z"), timeZone = timeZone))
  }
}
