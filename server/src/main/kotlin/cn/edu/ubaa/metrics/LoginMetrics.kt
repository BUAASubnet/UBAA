package cn.edu.ubaa.metrics

import cn.edu.ubaa.auth.AuthConfig
import io.lettuce.core.RedisClient
import io.lettuce.core.Value
import io.lettuce.core.api.StatefulRedisConnection
import io.lettuce.core.api.sync.RedisCommands
import io.micrometer.core.instrument.MeterRegistry
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory

enum class LoginSuccessMode(val tagValue: String) {
  MANUAL("manual"),
  PRELOAD_AUTO("preload_auto"),
}

enum class LoginMetricWindow(val tagValue: String, val hours: Long) {
  ONE_HOUR("1h", 1),
  TWENTY_FOUR_HOURS("24h", 24),
  SEVEN_DAYS("7d", 24 * 7),
  THIRTY_DAYS("30d", 24 * 30),
}

interface LoginMetricsSink {
  suspend fun recordSuccess(username: String, mode: LoginSuccessMode)
}

object NoOpLoginMetricsSink : LoginMetricsSink {
  override suspend fun recordSuccess(username: String, mode: LoginSuccessMode) = Unit
}

interface LoginStatsStore {
  suspend fun recordLogin(username: String, recordedAt: Instant)

  fun countEvents(window: LoginMetricWindow, now: Instant): Long

  fun countUniqueUsers(window: LoginMetricWindow, now: Instant): Long

  fun close()
}

class LoginMetricsRecorder(
    private val store: LoginStatsStore,
    private val registry: MeterRegistry,
    private val clock: Clock = Clock.systemUTC(),
) : LoginMetricsSink {
  private val log = LoggerFactory.getLogger(LoginMetricsRecorder::class.java)

  fun bindMetrics() {
    for (window in LoginMetricWindow.entries) {
      GaugeBindings.bind(
          registry = registry,
          name = "ubaa.auth.login.events.window",
          tags = mapOf("window" to window.tagValue),
      ) {
        store.countEvents(window, clock.instant()).toDouble()
      }

      GaugeBindings.bind(
          registry = registry,
          name = "ubaa.auth.login.unique.users.window",
          tags = mapOf("window" to window.tagValue),
      ) {
        store.countUniqueUsers(window, clock.instant()).toDouble()
      }
    }
  }

  override suspend fun recordSuccess(username: String, mode: LoginSuccessMode) {
    registry.counter("ubaa.auth.login.success", "mode", mode.tagValue).increment()
    try {
      store.recordLogin(username, clock.instant())
    } catch (e: Exception) {
      log.warn("Failed to persist login statistics for user {}", username, e)
    }
  }

  fun close() {
    store.close()
  }
}

class RedisLoginStatsStore(
    private val redisUri: String = AuthConfig.redisUri,
) : LoginStatsStore {
  private val log = LoggerFactory.getLogger(RedisLoginStatsStore::class.java)

  private enum class WindowMetricType {
    EVENTS,
    UNIQUE_USERS,
  }

  private data class CachedWindowValue(
      val value: Long,
      val expiresAtMillis: Long,
  )

  private data class WindowCacheKey(
      val type: WindowMetricType,
      val window: LoginMetricWindow,
      val currentBucket: Long,
  )

  private val client: RedisClient by lazy { RedisClient.create(redisUri) }
  private val connection: StatefulRedisConnection<String, String> by lazy { client.connect() }
  private val commands: RedisCommands<String, String> by lazy { connection.sync() }
  private val keyTtl = Duration.ofDays(32)
  private val readCacheTtl = Duration.ofSeconds(15)
  private val windowCache = ConcurrentHashMap<WindowCacheKey, CachedWindowValue>()

  override suspend fun recordLogin(username: String, recordedAt: Instant) {
    val bucket = bucketOf(recordedAt)
    val eventKey = eventKey(bucket)
    val uniqueKey = uniqueKey(bucket)
    val usernameHash = hashUsername(username)
    val ttlSeconds = keyTtl.seconds.coerceAtLeast(1L)

    withContext(Dispatchers.IO) {
      commands.incr(eventKey)
      commands.expire(eventKey, ttlSeconds)
      commands.pfadd(uniqueKey, usernameHash)
      commands.expire(uniqueKey, ttlSeconds)
    }
    windowCache.clear()
  }

  override fun countEvents(window: LoginMetricWindow, now: Instant): Long {
    return cachedWindowValue(WindowMetricType.EVENTS, window, now) {
      val keys = bucketsFor(window, now).map(::eventKey)
      if (keys.isEmpty()) {
        0L
      } else {
        sumCounterValues(commands.mget(*keys.toTypedArray()))
      }
    }
  }

  override fun countUniqueUsers(window: LoginMetricWindow, now: Instant): Long {
    return cachedWindowValue(WindowMetricType.UNIQUE_USERS, window, now) {
      val keys = bucketsFor(window, now).map(::uniqueKey)
      if (keys.isEmpty()) {
        0L
      } else {
        commands.pfcount(*keys.toTypedArray())
      }
    }
  }

  override fun close() {
    windowCache.clear()
    runCatching { connection.close() }
    runCatching { client.shutdown() }
  }

  private fun bucketsFor(window: LoginMetricWindow, now: Instant): LongRange {
    val currentBucket = bucketOf(now)
    val firstBucket = currentBucket - window.hours + 1
    return firstBucket..currentBucket
  }

  private fun bucketOf(at: Instant): Long = at.epochSecond / 3600

  private fun eventKey(bucket: Long): String = "metrics:login:events:$bucket"

  private fun uniqueKey(bucket: Long): String = "metrics:login:users:$bucket"

  private fun cachedWindowValue(
      type: WindowMetricType,
      window: LoginMetricWindow,
      now: Instant,
      loader: () -> Long,
  ): Long {
    val currentBucket = bucketOf(now)
    val cacheKey = WindowCacheKey(type, window, currentBucket)
    val nowMillis = System.currentTimeMillis()
    windowCache[cacheKey]
        ?.takeIf { it.expiresAtMillis > nowMillis }
        ?.let {
          return it.value
        }

    val value =
        runCatching(loader)
            .onFailure { error ->
              log.warn(
                  "Failed to load login metric window type={} window={}",
                  type,
                  window.tagValue,
                  error,
              )
            }
            .getOrDefault(0L)
    windowCache[cacheKey] =
        CachedWindowValue(value = value, expiresAtMillis = nowMillis + readCacheTtl.toMillis())
    cleanupExpiredWindowCache(nowMillis)
    return value
  }

  private fun cleanupExpiredWindowCache(nowMillis: Long) {
    for ((key, cached) in windowCache.entries.toList()) {
      if (cached.expiresAtMillis > nowMillis) continue
      windowCache.remove(key, cached)
    }
  }
}

class InMemoryLoginStatsStore : LoginStatsStore {
  private data class LoginBucket(
      val events: AtomicLong = AtomicLong(0),
      val users: MutableSet<String> = ConcurrentHashMap.newKeySet(),
  )

  private val buckets = ConcurrentHashMap<Long, LoginBucket>()

  override suspend fun recordLogin(username: String, recordedAt: Instant) {
    val bucket = buckets.computeIfAbsent(bucketOf(recordedAt)) { LoginBucket() }
    bucket.events.incrementAndGet()
    bucket.users += hashUsername(username)
  }

  override fun countEvents(window: LoginMetricWindow, now: Instant): Long {
    return bucketsFor(window, now).sumOf { bucket -> buckets[bucket]?.events?.get() ?: 0L }
  }

  override fun countUniqueUsers(window: LoginMetricWindow, now: Instant): Long {
    val uniqueUsers = linkedSetOf<String>()
    for (bucket in bucketsFor(window, now)) {
      uniqueUsers += buckets[bucket]?.users.orEmpty()
    }
    return uniqueUsers.size.toLong()
  }

  override fun close() {
    buckets.clear()
  }

  private fun bucketsFor(window: LoginMetricWindow, now: Instant): LongRange {
    val currentBucket = bucketOf(now)
    val firstBucket = currentBucket - window.hours + 1
    return firstBucket..currentBucket
  }

  private fun bucketOf(at: Instant): Long = at.epochSecond / 3600
}

private fun hashUsername(username: String): String {
  val digest = MessageDigest.getInstance("SHA-256")
  val hash = digest.digest(username.toByteArray(StandardCharsets.UTF_8))
  return hash.joinToString("") { "%02x".format(it) }
}

internal fun sumCounterValues(values: Iterable<Value<String>?>): Long {
  return values.sumOf { value -> value?.optional()?.orElse(null)?.toLongOrNull() ?: 0L }
}
