package cn.edu.ubaa.auth

import io.github.cdimascio.dotenv.dotenv
import java.time.Duration

/** 统一管理认证相关运行时配置。 */
object AuthConfig {
  private val dotenv = dotenv { ignoreIfMissing = true }
  private const val LOCK_TTL_SAFETY_MARGIN_MS = 2_000L

  val redisUri: String = env("REDIS_URI") ?: "redis://localhost:6379"

  val accessTokenTtl: Duration =
      Duration.ofMinutes(env("ACCESS_TOKEN_TTL_MINUTES")?.toLongOrNull() ?: 30L)

  val refreshTokenTtl: Duration =
      Duration.ofDays(env("REFRESH_TOKEN_TTL_DAYS")?.toLongOrNull() ?: 7L)

  val sessionTtl: Duration = Duration.ofDays(env("SESSION_TTL_DAYS")?.toLongOrNull() ?: 7L)

  val preLoginTtl: Duration =
      Duration.ofMinutes(env("PRELOGIN_TTL_MINUTES")?.toLongOrNull()?.coerceAtLeast(1L) ?: 5L)

  val sessionCookieSyncIntervalMillis: Long =
      env("SESSION_COOKIE_SYNC_INTERVAL_MS")?.toLongOrNull()?.coerceAtLeast(1L) ?: 5_000L

  val loginMaxConcurrency: Int = env("LOGIN_MAX_CONCURRENCY")?.toIntOrNull()?.coerceAtLeast(1) ?: 6

  val distributedLockTtlMillis: Long =
      env("AUTH_DISTRIBUTED_LOCK_TTL_MS")?.toLongOrNull()?.coerceAtLeast(100L) ?: 20_000L

  val distributedLockWaitMillis: Long =
      env("AUTH_DISTRIBUTED_LOCK_WAIT_MS")?.toLongOrNull()?.coerceAtLeast(100L) ?: 5_000L

  val validationTimeoutMillis: Long =
      env("AUTH_VALIDATION_TIMEOUT_MS")?.toLongOrNull()?.coerceAtLeast(1L) ?: 3_000L

  val preloadTimeoutMillis: Long =
      env("AUTH_PRELOAD_TIMEOUT_MS")?.toLongOrNull()?.coerceAtLeast(1L) ?: 3_000L

  val loginTimeoutMillis: Long =
      env("AUTH_LOGIN_TIMEOUT_MS")?.toLongOrNull()?.coerceAtLeast(1L) ?: 18_000L

  fun validateDistributedLockBudgets() {
    validateDistributedLockBudgets(
        distributedLockTtlMillis = distributedLockTtlMillis,
        loginTimeoutMillis = loginTimeoutMillis,
        preloadTimeoutMillis = preloadTimeoutMillis,
    )
  }

  internal fun validateDistributedLockBudgets(
      distributedLockTtlMillis: Long,
      loginTimeoutMillis: Long,
      preloadTimeoutMillis: Long,
  ) {
    val requiredMinimum =
        maxOf(loginTimeoutMillis, preloadTimeoutMillis) + LOCK_TTL_SAFETY_MARGIN_MS
    require(distributedLockTtlMillis >= requiredMinimum) {
      "AUTH_DISTRIBUTED_LOCK_TTL_MS must be at least ${requiredMinimum}ms " +
          "to safely cover AUTH_LOGIN_TIMEOUT_MS/AUTH_PRELOAD_TIMEOUT_MS."
    }
  }

  private fun env(name: String): String? = dotenv[name] ?: System.getenv(name)
}
