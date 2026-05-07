package cn.edu.ubaa

import cn.edu.ubaa.health.RedisReadinessProbe
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.metrics.InMemoryLoginStatsStore
import cn.edu.ubaa.metrics.LoginConnectionMode
import cn.edu.ubaa.metrics.LoginMetricsRecorder
import cn.edu.ubaa.metrics.LoginSuccessMode
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class ApplicationMetricsTest {

  @Test
  fun metricsEndpointIncludesLoginAndHttpMetrics() = testApplication {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    val store = InMemoryLoginStatsStore()
    val clock = Clock.fixed(Instant.parse("2026-04-02T08:15:00Z"), ZoneOffset.UTC)
    val recorder = LoginMetricsRecorder(store, registry, clock)

    application { module(registry, recorder) }

    val rootResponse = client.get("/")
    assertEquals(HttpStatusCode.OK, rootResponse.status)

    runBlocking {
      recorder.recordSuccess("2333", LoginSuccessMode.MANUAL, LoginConnectionMode.SERVER_RELAY)
      recorder.recordSuccess("2444", LoginSuccessMode.PRELOAD_AUTO, LoginConnectionMode.DIRECT)
      AppObservability.observeBusinessOperation("auth", "login") {}
      AppObservability.observeUpstreamRequest("uc", "fetch_uc_user") { "ok" }
      AppObservability.recordSessionResolve("memory_hit")
      AppObservability.recordLoginFlowEvent("login_reuse_hit")
      AppObservability.recordAuthValidationResult("success")
      AppObservability.recordAuthPreloadResult("degraded_timeout")
      AppObservability.recordCleanupRemovals("session", 2)
      AppObservability.recordRetryEvent("cgyy", "submit_reservation", "captcha_retry")
      AppObservability.recordFallbackEvent(
          "spoc",
          "list_assignments",
          "spoc_missing_course_metadata",
      )
    }

    val metricsResponse = client.get("/metrics")
    assertEquals(HttpStatusCode.OK, metricsResponse.status)
    val metrics = metricsResponse.bodyAsText()

    assertContains(metrics, "ubaa_auth_login_success_total")
    assertContains(metrics, "mode=\"manual\"")
    assertContains(metrics, "mode=\"preload_auto\"")
    assertContains(metrics, "connection_mode=\"all\"")
    assertContains(metrics, "connection_mode=\"server_relay\"")
    assertContains(metrics, "connection_mode=\"direct\"")
    assertContains(
        metrics,
        "ubaa_auth_login_events_window{connection_mode=\"all\",window=\"1h\"} 2.0",
    )
    assertContains(
        metrics,
        "ubaa_auth_login_events_window{connection_mode=\"direct\",window=\"1h\"} 1.0",
    )
    assertContains(
        metrics,
        "ubaa_auth_login_events_window{connection_mode=\"server_relay\",window=\"1h\"} 1.0",
    )
    assertContains(
        metrics,
        "ubaa_auth_login_unique_users_window{connection_mode=\"all\",window=\"1h\"} 2.0",
    )
    assertContains(
        metrics,
        "ubaa_auth_login_unique_users_window{connection_mode=\"direct\",window=\"1h\"} 1.0",
    )
    assertContains(
        metrics,
        "ubaa_auth_login_unique_users_window{connection_mode=\"server_relay\",window=\"1h\"} 1.0",
    )
    assertContains(metrics, "ubaa_business_operations_seconds_count")
    assertContains(metrics, "ubaa_upstream_requests_seconds_count")
    assertContains(metrics, "ubaa_auth_session_resolve_total")
    assertContains(metrics, "ubaa_auth_login_flow_total")
    assertContains(metrics, "ubaa_auth_validation_total")
    assertContains(metrics, "ubaa_auth_preload_total")
    assertContains(metrics, "ubaa_cleanup_removals_total")
    assertContains(metrics, "ubaa_retry_events_total")
    assertContains(metrics, "ubaa_fallback_events_total")
    assertContains(metrics, "ktor_http_server_requests_seconds_count")
  }

  @Test
  fun customGaugesRemainSingleRegisteredAcrossRepeatedBindings() {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    val firstRecorder = LoginMetricsRecorder(InMemoryLoginStatsStore(), registry)
    val secondRecorder = LoginMetricsRecorder(InMemoryLoginStatsStore(), registry)

    firstRecorder.bindMetrics()
    secondRecorder.bindMetrics()

    assertEquals(
        16,
        registry.meters.count { it.id.name == "ubaa.auth.login.events.window" },
    )
    assertEquals(
        16,
        registry.meters.count { it.id.name == "ubaa.auth.login.unique.users.window" },
    )
    assertEquals(
        8,
        registry.meters.count { it.id.name == "ubaa.auth.login.success" },
    )

    registerPerformanceGauges(
        registry,
        cn.edu.ubaa.auth.GlobalSessionManager.instance,
        cn.edu.ubaa.bykc.GlobalBykcService.instance,
        cn.edu.ubaa.cgyy.GlobalCgyyService.instance,
        cn.edu.ubaa.spoc.GlobalSpocService.instance,
        cn.edu.ubaa.judge.GlobalJudgeService.instance,
        cn.edu.ubaa.ygdk.GlobalYgdkService.instance,
        RedisReadinessProbe(),
    )
    registerPerformanceGauges(
        registry,
        cn.edu.ubaa.auth.GlobalSessionManager.instance,
        cn.edu.ubaa.bykc.GlobalBykcService.instance,
        cn.edu.ubaa.cgyy.GlobalCgyyService.instance,
        cn.edu.ubaa.spoc.GlobalSpocService.instance,
        cn.edu.ubaa.judge.GlobalJudgeService.instance,
        cn.edu.ubaa.ygdk.GlobalYgdkService.instance,
        RedisReadinessProbe(),
    )

    val customGaugeNames =
        setOf(
            "ubaa.sessions.active",
            "ubaa.sessions.prelogin",
            "ubaa.signin.cache",
            "ubaa.bykc.cache",
            "ubaa.cgyy.cache",
            "ubaa.spoc.cache",
            "ubaa.judge.cache",
            "ubaa.ygdk.cache",
            "ubaa.ygdk.context.cache",
            "ubaa.redis.ready",
        )
    assertTrue(
        registry.meters
            .filter { it.id.name in customGaugeNames }
            .map { it.id.name }
            .groupingBy { it }
            .eachCount()
            .values
            .all { it == 1 }
    )
  }
}
