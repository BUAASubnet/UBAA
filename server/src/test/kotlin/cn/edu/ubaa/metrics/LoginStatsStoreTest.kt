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
    val buckets = buildList {
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

    repeat(3) {
      store.recordLogin("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY, now)
    }

    assertEquals(3L, store.countEvents(LoginMetricWindow.ONE_HOUR, now))
    assertEquals(
        3L,
        store.countEvents(LoginMetricWindow.ONE_HOUR, now, LoginConnectionMode.SERVER_RELAY),
    )
    assertEquals(1L, store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now))
    assertEquals(
        1L,
        store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now, LoginConnectionMode.SERVER_RELAY),
    )
    assertEquals(3L, store.countSuccessTotal(LoginSuccessMode.MANUAL))
    assertEquals(
        3L,
        store.countSuccessTotal(LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY),
    )
  }

  @Test
  fun sameUserAcrossHoursIsDeduplicatedWithinWindow() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    store.recordLogin(
        "2333",
        LoginSuccessMode.MANUAL,
        LoginConnectionMode.SERVER_RELAY,
        now.minusSeconds(2 * 3600),
    )
    store.recordLogin("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.DIRECT, now)
    store.recordLogin(
        "2444",
        LoginSuccessMode.PRELOAD_AUTO,
        LoginConnectionMode.WEBVPN,
        now.minusSeconds(3600),
    )

    assertEquals(3L, store.countEvents(LoginMetricWindow.TWENTY_FOUR_HOURS, now))
    assertEquals(
        1L,
        store.countEvents(
            LoginMetricWindow.TWENTY_FOUR_HOURS,
            now,
            LoginConnectionMode.SERVER_RELAY,
        ),
    )
    assertEquals(
        1L,
        store.countEvents(LoginMetricWindow.TWENTY_FOUR_HOURS, now, LoginConnectionMode.DIRECT),
    )
    assertEquals(
        1L,
        store.countEvents(LoginMetricWindow.TWENTY_FOUR_HOURS, now, LoginConnectionMode.WEBVPN),
    )
    assertEquals(2L, store.countUniqueUsers(LoginMetricWindow.TWENTY_FOUR_HOURS, now))
    assertEquals(
        1L,
        store.countUniqueUsers(
            LoginMetricWindow.TWENTY_FOUR_HOURS,
            now,
            LoginConnectionMode.SERVER_RELAY,
        ),
    )
    assertEquals(
        1L,
        store.countUniqueUsers(
            LoginMetricWindow.TWENTY_FOUR_HOURS,
            now,
            LoginConnectionMode.DIRECT,
        ),
    )
    assertEquals(
        1L,
        store.countUniqueUsers(
            LoginMetricWindow.TWENTY_FOUR_HOURS,
            now,
            LoginConnectionMode.WEBVPN,
        ),
    )
    assertEquals(2L, store.countSuccessTotal(LoginSuccessMode.MANUAL))
    assertEquals(1L, store.countSuccessTotal(LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY))
    assertEquals(1L, store.countSuccessTotal(LoginSuccessMode.MANUAL, LoginConnectionMode.DIRECT))
    assertEquals(1L, store.countSuccessTotal(LoginSuccessMode.PRELOAD_AUTO))
    assertEquals(
        1L,
        store.countSuccessTotal(LoginSuccessMode.PRELOAD_AUTO, LoginConnectionMode.WEBVPN),
    )
  }

  @Test
  fun loginsOutsideThirtyDayWindowAreIgnored() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    store.recordLogin(
        "2333",
        LoginSuccessMode.MANUAL,
        LoginConnectionMode.SERVER_RELAY,
        now.minusSeconds(31 * 24 * 3600),
    )
    store.recordLogin("2444", LoginSuccessMode.PRELOAD_AUTO, LoginConnectionMode.DIRECT, now)

    assertEquals(1L, store.countEvents(LoginMetricWindow.THIRTY_DAYS, now))
    assertEquals(1L, store.countUniqueUsers(LoginMetricWindow.THIRTY_DAYS, now))
    assertEquals(1L, store.countSuccessTotal(LoginSuccessMode.MANUAL))
    assertEquals(1L, store.countSuccessTotal(LoginSuccessMode.PRELOAD_AUTO))
    assertEquals(
        0L,
        store.countEvents(LoginMetricWindow.THIRTY_DAYS, now, LoginConnectionMode.SERVER_RELAY),
    )
    assertEquals(
        1L,
        store.countEvents(LoginMetricWindow.THIRTY_DAYS, now, LoginConnectionMode.DIRECT),
    )
    assertEquals(
        0L,
        store.countUniqueUsers(
            LoginMetricWindow.THIRTY_DAYS,
            now,
            LoginConnectionMode.SERVER_RELAY,
        ),
    )
    assertEquals(
        1L,
        store.countUniqueUsers(LoginMetricWindow.THIRTY_DAYS, now, LoginConnectionMode.DIRECT),
    )
  }

  @Test
  fun overallUniqueUsersRemainDeduplicatedAcrossDifferentConnectionModes() = runBlocking {
    val store = InMemoryLoginStatsStore()
    val now = Instant.parse("2026-04-02T08:15:00Z")

    store.recordLogin("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY, now)
    store.recordLogin("2333", LoginSuccessMode.PRELOAD_AUTO, LoginConnectionMode.DIRECT, now)

    assertEquals(2L, store.countEvents(LoginMetricWindow.ONE_HOUR, now))
    assertEquals(1L, store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now))
    assertEquals(
        1L,
        store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now, LoginConnectionMode.SERVER_RELAY),
    )
    assertEquals(
        1L,
        store.countUniqueUsers(LoginMetricWindow.ONE_HOUR, now, LoginConnectionMode.DIRECT),
    )
  }
}
