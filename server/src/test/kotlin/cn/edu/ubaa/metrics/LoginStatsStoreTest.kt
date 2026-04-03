package cn.edu.ubaa.metrics

import io.lettuce.core.KeyValue
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.runBlocking

class LoginStatsStoreTest {

  @Test
  fun sumCounterValuesIgnoresMissingAndMalformedBuckets() {
    assertEquals(
        9L,
        sumCounterValues(
            listOf(
                KeyValue.just("metrics:login:events:1", "2"),
                KeyValue.empty("metrics:login:events:2"),
                KeyValue.just("metrics:login:events:3", "7"),
                KeyValue.just("metrics:login:events:4", "invalid"),
            ),
        ),
    )
  }

  @Test
  fun sumCounterValuesKeepsLongWindowTotalsWhenMostBucketsAreEmpty() {
    val buckets =
        buildList {
          repeat(24) { index ->
            val key = "metrics:login:events:$index"
            add(KeyValue.empty<String, String>(key))
          }
          set(3, KeyValue.just("metrics:login:events:3", "4"))
          set(18, KeyValue.just("metrics:login:events:18", "6"))
        }

    assertEquals(10L, sumCounterValues(buckets))
  }

  @Test
  fun repeatedLoginsInSameHourIncreaseEventsButNotUniqueUsers() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    repeat(3) { store.recordLogin("2333", now) }

    assertEquals(3L, store.countEvents(LoginMetricWindow.ONE_HOUR, now))
    assertEquals(1L, store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now))
  }

  @Test
  fun sameUserAcrossHoursIsDeduplicatedWithinWindow() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    store.recordLogin("2333", now.minusSeconds(2 * 3600))
    store.recordLogin("2333", now)
    store.recordLogin("2444", now.minusSeconds(3600))

    assertEquals(3L, store.countEvents(LoginMetricWindow.TWENTY_FOUR_HOURS, now))
    assertEquals(2L, store.countUniqueUsers(LoginMetricWindow.TWENTY_FOUR_HOURS, now))
  }

  @Test
  fun loginsOutsideThirtyDayWindowAreIgnored() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    store.recordLogin("2333", now.minusSeconds(31 * 24 * 3600))
    store.recordLogin("2444", now)

    assertEquals(1L, store.countEvents(LoginMetricWindow.THIRTY_DAYS, now))
    assertEquals(1L, store.countUniqueUsers(LoginMetricWindow.THIRTY_DAYS, now))
  }
}
