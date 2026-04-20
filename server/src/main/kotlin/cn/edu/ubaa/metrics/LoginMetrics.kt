package cn.edu.ubaa.metrics

import cn.edu.ubaa.auth.GlobalRedisRuntime
import cn.edu.ubaa.auth.RedisRuntime
import io.lettuce.core.Value
import io.lettuce.core.api.async.RedisAsyncCommands
import io.lettuce.core.api.sync.RedisCommands
import io.micrometer.core.instrument.MeterRegistry
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.future.await
import org.slf4j.LoggerFactory

enum class LoginSuccessMode(val tagValue: String) {
  MANUAL("manual"),
  PRELOAD_AUTO("preload_auto"),
}

enum class LoginConnectionMode(val tagValue: String) {
  DIRECT("direct"),
  WEBVPN("webvpn"),
  SERVER_RELAY("server_relay"),
}

enum class LoginMetricWindow(val tagValue: String, val hours: Long) {
  ONE_HOUR("1h", 1),
  TWENTY_FOUR_HOURS("24h", 24),
  SEVEN_DAYS("7d", 24 * 7),
  THIRTY_DAYS("30d", 24 * 30),
}

interface LoginMetricsSink {
  suspend fun recordSuccess(
      username: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
  )
}

object NoOpLoginMetricsSink : LoginMetricsSink {
  override suspend fun recordSuccess(
      username: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
  ) = Unit
}

interface LoginStatsStore {
  suspend fun recordLogin(
      userId: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
      recordedAt: Instant,
  )

  fun countEvents(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode? = null,
  ): Long

  fun countUniqueUsers(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode? = null,
  ): Long

  fun countSuccessTotal(mode: LoginSuccessMode, connectionMode: LoginConnectionMode? = null): Long

  fun close()
}

class LoginMetricsRecorder(
    private val store: LoginStatsStore,
    private val registry: MeterRegistry,
    private val clock: Clock = Clock.systemUTC(),
) : LoginMetricsSink {
  private val log = LoggerFactory.getLogger(LoginMetricsRecorder::class.java)
  private val boundConnectionModes = listOf<LoginConnectionMode?>(null) + LoginConnectionMode.entries

  fun bindMetrics() {
    for (mode in LoginSuccessMode.entries) {
      for (connectionMode in boundConnectionModes) {
        FunctionCounterBindings.bind(
            registry = registry,
            name = "ubaa.auth.login.success",
            tags =
                mapOf(
                    "mode" to mode.tagValue,
                    "connection_mode" to connectionMode.tagValue(),
                ),
        ) {
          store.countSuccessTotal(mode, connectionMode).toDouble()
        }
      }
    }

    for (window in LoginMetricWindow.entries) {
      for (connectionMode in boundConnectionModes) {
        GaugeBindings.bind(
            registry = registry,
            name = "ubaa.auth.login.events.window",
            tags =
                mapOf(
                    "connection_mode" to connectionMode.tagValue(),
                    "window" to window.tagValue,
                ),
        ) {
          store.countEvents(window, clock.instant(), connectionMode).toDouble()
        }

        GaugeBindings.bind(
            registry = registry,
            name = "ubaa.auth.login.unique.users.window",
            tags =
                mapOf(
                    "connection_mode" to connectionMode.tagValue(),
                    "window" to window.tagValue,
                ),
        ) {
          store.countUniqueUsers(window, clock.instant(), connectionMode).toDouble()
        }
      }
    }
  }

  override suspend fun recordSuccess(
      username: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
  ) {
    try {
      store.recordLogin(username, mode, connectionMode, clock.instant())
    } catch (e: Exception) {
      log.warn("Failed to persist login statistics for user {}", username, e)
    }
  }

  fun close() {
    store.close()
  }
}

class RedisLoginStatsStore(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
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
      val connectionMode: LoginConnectionMode?,
      val currentBucket: Long,
  )

  private val asyncCommands: RedisAsyncCommands<String, String>
    get() = runtime.asyncCommands

  // Gauge 回调是非 suspend 的，需要同步 API 读取
  private val syncCommands: RedisCommands<String, String>
    get() = runtime.syncCommands

  private val keyTtl = Duration.ofDays(32)
  private val readCacheTtl = Duration.ofSeconds(15)
  private val windowCache = ConcurrentHashMap<WindowCacheKey, CachedWindowValue>()

  override suspend fun recordLogin(
      userId: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
      recordedAt: Instant,
  ) {
    val bucket = bucketOf(recordedAt)
    val usernameHash = hashUsername(userId)
    val ttlSeconds = keyTtl.seconds.coerceAtLeast(1L)

    suspend fun incrementEvent(key: String) {
      asyncCommands.incr(key).await()
      asyncCommands.expire(key, ttlSeconds).await()
    }

    suspend fun addUniqueUser(key: String) {
      asyncCommands.pfadd(key, usernameHash).await()
      asyncCommands.expire(key, ttlSeconds).await()
    }

    incrementEvent(eventKey(bucket))
    incrementEvent(eventKey(bucket, connectionMode))
    addUniqueUser(uniqueKey(bucket))
    addUniqueUser(uniqueKey(bucket, connectionMode))
    asyncCommands.incr(successTotalKey(mode)).await()
    asyncCommands.incr(successTotalKey(mode, connectionMode)).await()
    windowCache.clear()
  }

  override fun countEvents(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode?,
  ): Long {
    return cachedWindowValue(WindowMetricType.EVENTS, window, connectionMode, now) {
      val keys = bucketsFor(window, now).map { bucket -> eventKey(bucket, connectionMode) }
      if (keys.isEmpty()) {
        0L
      } else {
        sumCounterValues(syncCommands.mget(*keys.toTypedArray()))
      }
    }
  }

  override fun countUniqueUsers(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode?,
  ): Long {
    return cachedWindowValue(WindowMetricType.UNIQUE_USERS, window, connectionMode, now) {
      val keys = bucketsFor(window, now).map { bucket -> uniqueKey(bucket, connectionMode) }
      if (keys.isEmpty()) {
        0L
      } else {
        syncCommands.pfcount(*keys.toTypedArray())
      }
    }
  }

  override fun countSuccessTotal(
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode?,
  ): Long {
    return runCatching { syncCommands.get(successTotalKey(mode, connectionMode))?.toLongOrNull() ?: 0L }
        .getOrDefault(0L)
  }

  override fun close() {
    windowCache.clear()
  }

  private fun bucketsFor(window: LoginMetricWindow, now: Instant): LongRange {
    val currentBucket = bucketOf(now)
    val firstBucket = currentBucket - window.hours + 1
    return firstBucket..currentBucket
  }

  private fun bucketOf(at: Instant): Long = at.epochSecond / 3600

  private fun eventKey(bucket: Long, connectionMode: LoginConnectionMode? = null): String =
      connectionMode?.let { "metrics:login:events:${it.tagValue}:$bucket" }
          ?: "metrics:login:events:$bucket"

  private fun uniqueKey(bucket: Long, connectionMode: LoginConnectionMode? = null): String =
      connectionMode?.let { "metrics:login:users:${it.tagValue}:$bucket" }
          ?: "metrics:login:users:$bucket"

  private fun successTotalKey(
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode? = null,
  ): String =
      connectionMode?.let { "metrics:login:success:total:${mode.tagValue}:${it.tagValue}" }
          ?: "metrics:login:success:total:${mode.tagValue}"

  private fun cachedWindowValue(
      type: WindowMetricType,
      window: LoginMetricWindow,
      connectionMode: LoginConnectionMode?,
      now: Instant,
      loader: () -> Long,
  ): Long {
    val currentBucket = bucketOf(now)
    val cacheKey = WindowCacheKey(type, window, connectionMode, currentBucket)
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

  private val overallBuckets = ConcurrentHashMap<Long, LoginBucket>()
  private val modeBuckets =
      ConcurrentHashMap<LoginConnectionMode, ConcurrentHashMap<Long, LoginBucket>>().apply {
        LoginConnectionMode.entries.forEach { put(it, ConcurrentHashMap()) }
      }
  private val successTotals =
      ConcurrentHashMap<LoginSuccessMode, AtomicLong>().apply {
        LoginSuccessMode.entries.forEach { put(it, AtomicLong(0)) }
      }
  private val modeSuccessTotals =
      ConcurrentHashMap<
          LoginConnectionMode,
          ConcurrentHashMap<LoginSuccessMode, AtomicLong>,
      >().apply {
        LoginConnectionMode.entries.forEach { connectionMode ->
          put(
              connectionMode,
              ConcurrentHashMap<LoginSuccessMode, AtomicLong>().apply {
                LoginSuccessMode.entries.forEach { put(it, AtomicLong(0)) }
              },
          )
        }
      }

  override suspend fun recordLogin(
      userId: String,
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode,
      recordedAt: Instant,
  ) {
    val bucketKey = bucketOf(recordedAt)
    val userHash = hashUsername(userId)
    val overallBucket = overallBuckets.computeIfAbsent(bucketKey) { LoginBucket() }
    overallBucket.events.incrementAndGet()
    overallBucket.users += userHash
    val scopedBuckets =
        modeBuckets.computeIfAbsent(connectionMode) { ConcurrentHashMap<Long, LoginBucket>() }
    val scopedBucket = scopedBuckets.computeIfAbsent(bucketKey) { LoginBucket() }
    scopedBucket.events.incrementAndGet()
    scopedBucket.users += userHash
    successTotals.computeIfAbsent(mode) { AtomicLong(0) }.incrementAndGet()
    modeSuccessTotals
        .computeIfAbsent(connectionMode) {
          ConcurrentHashMap<LoginSuccessMode, AtomicLong>().apply {
            LoginSuccessMode.entries.forEach { put(it, AtomicLong(0)) }
          }
        }
        .computeIfAbsent(mode) { AtomicLong(0) }
        .incrementAndGet()
  }

  override fun countEvents(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode?,
  ): Long {
    val buckets = bucketStore(connectionMode)
    return bucketsFor(window, now).sumOf { bucket -> buckets[bucket]?.events?.get() ?: 0L }
  }

  override fun countUniqueUsers(
      window: LoginMetricWindow,
      now: Instant,
      connectionMode: LoginConnectionMode?,
  ): Long {
    val buckets = bucketStore(connectionMode)
    val uniqueUsers = linkedSetOf<String>()
    for (bucket in bucketsFor(window, now)) {
      uniqueUsers += buckets[bucket]?.users.orEmpty()
    }
    return uniqueUsers.size.toLong()
  }

  override fun countSuccessTotal(
      mode: LoginSuccessMode,
      connectionMode: LoginConnectionMode?,
  ): Long {
    return if (connectionMode == null) {
      successTotals[mode]?.get() ?: 0L
    } else {
      modeSuccessTotals[connectionMode]?.get(mode)?.get() ?: 0L
    }
  }

  override fun close() {
    overallBuckets.clear()
    modeBuckets.clear()
    successTotals.clear()
    modeSuccessTotals.clear()
  }

  private fun bucketsFor(window: LoginMetricWindow, now: Instant): LongRange {
    val currentBucket = bucketOf(now)
    val firstBucket = currentBucket - window.hours + 1
    return firstBucket..currentBucket
  }

  private fun bucketOf(at: Instant): Long = at.epochSecond / 3600

  private fun bucketStore(
      connectionMode: LoginConnectionMode?
  ): ConcurrentHashMap<Long, LoginBucket> =
      if (connectionMode == null) {
        overallBuckets
      } else {
        modeBuckets.computeIfAbsent(connectionMode) { ConcurrentHashMap() }
      }
}

private fun LoginConnectionMode?.tagValue(): String = this?.tagValue ?: "all"

private fun hashUsername(username: String): String {
  val digest = MessageDigest.getInstance("SHA-256")
  val hash = digest.digest(username.toByteArray(StandardCharsets.UTF_8))
  return hash.joinToString("") { "%02x".format(it) }
}

internal fun sumCounterValues(values: Iterable<Value<String>?>): Long {
  return values.sumOf { value -> value?.optional()?.orElse(null)?.toLongOrNull() ?: 0L }
}
