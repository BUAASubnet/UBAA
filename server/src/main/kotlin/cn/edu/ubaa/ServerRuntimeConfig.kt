package cn.edu.ubaa

import io.github.cdimascio.dotenv.dotenv
import java.lang.management.ManagementFactory
import java.net.URI

data class AllowedCorsOrigin(
    val raw: String,
    val host: String,
    val schemes: List<String>,
)

object ServerRuntimeConfig {
  private val dotenv = dotenv { ignoreIfMissing = true }

  val instanceId: String =
      env("INSTANCE_ID")
          ?.takeIf(String::isNotBlank)
          ?: env("HOSTNAME")?.takeIf(String::isNotBlank)
          ?: ManagementFactory.getRuntimeMXBean().name

  val enableForwardedHeaders: Boolean =
      env("ENABLE_FORWARDED_HEADERS")?.toBooleanStrictOrNull() ?: true

  val redisHealthTimeoutMillis: Long =
      env("REDIS_HEALTH_TIMEOUT_MS")?.toLongOrNull()?.coerceAtLeast(100L) ?: 1_000L

  private val corsAllowedOriginsRaw: List<String> =
      env("CORS_ALLOWED_ORIGINS")
          ?.split(',')
          ?.map(String::trim)
          ?.filter(String::isNotBlank)
          .orEmpty()

  val allowAnyCorsHost: Boolean = corsAllowedOriginsRaw.any { it == "*" }

  val corsAllowedOrigins: List<AllowedCorsOrigin> =
      corsAllowedOriginsRaw.filterNot { it == "*" }.mapNotNull(::parseOrigin)

  private fun env(name: String): String? = dotenv[name] ?: System.getenv(name)

  private fun parseOrigin(raw: String): AllowedCorsOrigin? {
    return runCatching {
          val uri = URI.create(raw)
          val scheme = uri.scheme?.takeIf(String::isNotBlank) ?: return null
          val host = uri.host?.takeIf(String::isNotBlank) ?: return null
          val hostWithPort = if (uri.port >= 0) "$host:${uri.port}" else host
          AllowedCorsOrigin(raw = raw, host = hostWithPort, schemes = listOf(scheme))
        }
        .getOrNull()
  }
}
