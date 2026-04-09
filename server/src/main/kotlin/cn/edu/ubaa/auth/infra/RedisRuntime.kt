package cn.edu.ubaa.auth

import cn.edu.ubaa.ServerRuntimeConfig
import io.lettuce.core.RedisClient
import io.lettuce.core.api.StatefulRedisConnection
import io.lettuce.core.api.async.RedisAsyncCommands
import io.lettuce.core.api.sync.RedisCommands
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.future.await
import kotlinx.coroutines.withTimeout

class RedisRuntime(
    private val redisUri: String = AuthConfig.redisUri,
) {
  @Volatile private var closed = false

  private val client: RedisClient by lazy { RedisClient.create(redisUri) }
  private val connection: StatefulRedisConnection<String, String> by lazy { client.connect() }

  val asyncCommands: RedisAsyncCommands<String, String> by lazy { connection.async() }
  val syncCommands: RedisCommands<String, String> by lazy { connection.sync() }

  suspend fun ping(timeoutMillis: Long = ServerRuntimeConfig.redisHealthTimeoutMillis): Boolean {
    if (closed) return false
    return runCatching {
          withTimeout(timeoutMillis.milliseconds) { asyncCommands.ping().await() == "PONG" }
        }
        .getOrDefault(false)
  }

  fun close() {
    if (closed) return
    closed = true
    runCatching { connection.close() }
    runCatching { client.shutdown() }
  }

  fun isClosed(): Boolean = closed
}

object GlobalRedisRuntime {
  @Volatile private var current: RedisRuntime? = null

  val instance: RedisRuntime
    get() {
      current
          ?.takeUnless { it.isClosed() }
          ?.let {
            return it
          }
      return synchronized(this) {
        current?.takeUnless { it.isClosed() } ?: RedisRuntime().also { current = it }
      }
    }

  fun close() {
    synchronized(this) {
      current?.close()
      current = null
    }
  }
}
