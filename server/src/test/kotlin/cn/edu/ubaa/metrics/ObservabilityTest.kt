package cn.edu.ubaa.metrics

import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFailsWith
import kotlinx.coroutines.runBlocking

class ObservabilityTest {

  @Test
  fun businessOperationRecordsAllExpectedResultKinds() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)

    try {
      AppObservability.observeBusinessOperation("auth", "preload") { "ok" }
      AppObservability.observeBusinessOperation("auth", "captcha") {
        markBusinessFailure()
        "handled"
      }
      assertFailsWith<UpstreamTimeoutException> {
        AppObservability.observeBusinessOperation("ygdk", "get_records") {
          throw UpstreamTimeoutException("timeout", "ygdk_timeout")
        }
      }
      assertFailsWith<LoginException> {
        AppObservability.observeBusinessOperation("auth", "login") { throw LoginException("bad") }
      }
      assertFailsWith<IllegalStateException> {
        AppObservability.observeBusinessOperation("user", "user_info") {
          throw IllegalStateException("boom")
        }
      }

      val metrics = registry.scrape()
      assertContains(metrics, "result=\"success\"")
      assertContains(metrics, "result=\"business_failure\"")
      assertContains(metrics, "result=\"timeout\"")
      assertContains(metrics, "result=\"unauthenticated\"")
      assertContains(metrics, "result=\"error\"")
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  @Test
  fun upstreamRequestRecordsAllExpectedResultKinds() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)

    try {
      AppObservability.observeUpstreamRequest("uc", "fetch_uc_user") { "ok" }
      assertFailsWith<UpstreamTimeoutException> {
        AppObservability.observeUpstreamRequest("byxt", "list_terms") {
          throw UpstreamTimeoutException("timeout", "byxt_timeout")
        }
      }
      assertFailsWith<LoginException> {
        AppObservability.observeUpstreamRequest("sso", "submit_credentials") {
          throw LoginException("bad")
        }
      }
      assertFailsWith<IllegalStateException> {
        AppObservability.observeUpstreamRequest("spoc", "get_courses") {
          throw IllegalStateException("boom")
        }
      }

      val metrics = registry.scrape()
      assertContains(metrics, "ubaa_upstream_requests_seconds_count")
      assertContains(metrics, "result=\"success\"")
      assertContains(metrics, "result=\"timeout\"")
      assertContains(metrics, "result=\"unauthenticated\"")
      assertContains(metrics, "result=\"error\"")
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }
}
