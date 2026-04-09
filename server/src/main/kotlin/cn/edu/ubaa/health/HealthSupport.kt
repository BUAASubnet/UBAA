package cn.edu.ubaa.health

import cn.edu.ubaa.ServerRuntimeConfig
import cn.edu.ubaa.auth.GlobalRedisRuntime
import cn.edu.ubaa.metrics.AppObservability
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import kotlinx.serialization.Serializable

@Serializable
data class HealthCheckResponse(
    val status: String,
    val instanceId: String,
    val checks: Map<String, String>,
)

class RedisReadinessProbe(
    private val pingCheck: suspend () -> Boolean = { GlobalRedisRuntime.instance.ping() },
) {
  @Volatile private var lastKnownReady = false

  suspend fun isReady(): Boolean {
    val ready = pingCheck()
    lastKnownReady = ready
    AppObservability.recordReadinessCheck("redis", if (ready) "up" else "down")
    return ready
  }

  fun lastKnownReady(): Boolean = lastKnownReady
}

fun Route.healthRouting(
    readinessProbe: RedisReadinessProbe,
) {
  route("/health") {
    get("/live") {
      call.respond(
          HttpStatusCode.OK,
          HealthCheckResponse(
              status = "up",
              instanceId = ServerRuntimeConfig.instanceId,
              checks = mapOf("application" to "up"),
          ),
      )
    }

    get("/ready") {
      val redisReady = readinessProbe.isReady()
      val status = if (redisReady) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable
      call.respond(
          status,
          HealthCheckResponse(
              status = if (redisReady) "ready" else "degraded",
              instanceId = ServerRuntimeConfig.instanceId,
              checks = mapOf("redis" to if (redisReady) "up" else "down"),
          ),
      )
    }
  }
}
