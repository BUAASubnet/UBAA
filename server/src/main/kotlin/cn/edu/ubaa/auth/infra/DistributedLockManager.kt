package cn.edu.ubaa.auth

import cn.edu.ubaa.ServerRuntimeConfig
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.lettuce.core.ScriptOutputType
import io.lettuce.core.SetArgs
import java.util.UUID
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.future.await

interface DistributedLockManager {
  suspend fun <T> withLock(scope: String, key: String, block: suspend () -> T): T
}

object NoOpDistributedLockManager : DistributedLockManager {
  override suspend fun <T> withLock(scope: String, key: String, block: suspend () -> T): T = block()
}

class RedisDistributedLockManager(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
    private val ttlMillis: Long = AuthConfig.distributedLockTtlMillis,
    private val waitMillis: Long = AuthConfig.distributedLockWaitMillis,
    private val ownerPrefix: String = "${ServerRuntimeConfig.instanceId}:${UUID.randomUUID()}",
) : DistributedLockManager {
  override suspend fun <T> withLock(scope: String, key: String, block: suspend () -> T): T {
    if (key.isBlank()) return block()

    val token = "$ownerPrefix:${UUID.randomUUID()}"
    val redisKey = "lock:$scope:$key"
    val startedAt = System.nanoTime()
    var waited = false

    while (true) {
      val acquired =
          runtime.asyncCommands.set(redisKey, token, SetArgs.Builder.nx().px(ttlMillis)).await() ==
              "OK"
      if (acquired) {
        break
      }
      waited = true
      if ((System.nanoTime() - startedAt) >= waitMillis.milliseconds.inWholeNanoseconds) {
        AppObservability.recordDistributedLockTimeout(scope)
        throw UpstreamTimeoutException("认证请求繁忙，请稍后重试", "auth_lock_timeout")
      }
      delay(25)
    }

    AppObservability.recordDistributedLockAcquire(scope, waited)
    val waitedNanos = System.nanoTime() - startedAt
    if (waitedNanos > 0L) {
      AppObservability.recordDistributedLockWait(scope, waitedNanos)
    }

    try {
      return block()
    } finally {
      release(redisKey, token)
    }
  }

  private suspend fun release(redisKey: String, token: String) {
    runCatching {
      runtime.asyncCommands
          .eval<Long>(
              RELEASE_IF_MATCHES_SCRIPT,
              ScriptOutputType.INTEGER,
              arrayOf(redisKey),
              token,
          )
          .await()
    }
  }

  private companion object {
    private const val RELEASE_IF_MATCHES_SCRIPT =
        "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end"
  }
}

object GlobalDistributedLockManager {
  @Volatile private var current: RedisDistributedLockManager? = null

  val instance: RedisDistributedLockManager
    get() {
      current?.let {
        return it
      }
      return synchronized(this) { current ?: RedisDistributedLockManager().also { current = it } }
    }

  fun close() {
    synchronized(this) { current = null }
  }
}
