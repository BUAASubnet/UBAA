package cn.edu.ubaa.auth

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.UserData
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking

class SessionManagerMetricsTest {

  @Test
  fun sessionResolveMetricsTrackMemoryHitRedisRestoreAndMiss() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    val store = InMemorySessionStore()

    val primaryManager =
        SessionManager(
            sessionStore = store,
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { createNoopClient() },
        )
    val restoredManager =
        SessionManager(
            sessionStore = store,
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { createNoopClient() },
        )

    try {
      val candidate = primaryManager.prepareSession("2333")
      primaryManager.commitSession(candidate, UserData(name = "Alice", schoolid = "2333"))

      assertNotNull(primaryManager.getSession("2333", SessionManager.SessionAccess.READ_ONLY))
      assertNotNull(restoredManager.getSession("2333", SessionManager.SessionAccess.READ_ONLY))
      assertNull(restoredManager.getSession("missing", SessionManager.SessionAccess.READ_ONLY))

      val metrics = registry.scrape()
      assertContains(metrics, "ubaa_auth_session_resolve_total{result=\"memory_hit\"}")
      assertContains(metrics, "ubaa_auth_session_resolve_total{result=\"redis_restored\"}")
      assertContains(metrics, "ubaa_auth_session_resolve_total{result=\"miss\"}")
    } finally {
      primaryManager.close()
      restoredManager.close()
      AppObservability.reset(registry)
      registry.close()
    }
  }

  private fun createNoopClient(): HttpClient {
    return HttpClient(MockEngine) { engine { addHandler { respond("", HttpStatusCode.OK) } } }
  }
}
