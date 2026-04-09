package cn.edu.ubaa.health

import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HealthSupportTest {

  @Test
  fun readinessProbeStartsAsNotReadyUntilFirstCheck() {
    val probe = RedisReadinessProbe { true }
    assertFalse(probe.lastKnownReady())
  }

  @Test
  fun liveEndpointReturnsUpStatus() = testApplication {
    application {
      install(ContentNegotiation) { json() }
      routing { healthRouting(RedisReadinessProbe { true }) }
    }

    val response = client.get("/health/live")

    assertEquals(HttpStatusCode.OK, response.status)
    assertTrue(response.bodyAsText().contains("\"status\":\"up\""))
  }

  @Test
  fun readyEndpointReturnsOkWhenRedisProbeSucceeds() = testApplication {
    application {
      install(ContentNegotiation) { json() }
      routing { healthRouting(RedisReadinessProbe { true }) }
    }

    val response = client.get("/health/ready")

    assertEquals(HttpStatusCode.OK, response.status)
    assertTrue(response.bodyAsText().contains("\"status\":\"ready\""))
    assertTrue(response.bodyAsText().contains("\"redis\":\"up\""))
  }

  @Test
  fun readyEndpointReturnsServiceUnavailableWhenRedisProbeFails() = testApplication {
    application {
      install(ContentNegotiation) { json() }
      routing { healthRouting(RedisReadinessProbe { false }) }
    }

    val response = client.get("/health/ready")

    assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
    assertTrue(response.bodyAsText().contains("\"status\":\"degraded\""))
    assertTrue(response.bodyAsText().contains("\"redis\":\"down\""))
  }
}
