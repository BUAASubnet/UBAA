package cn.edu.ubaa.auth

import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.future.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface PreLoginPersistence {
  data class PreLoginRecord(
      val clientId: String,
      val lastTouchedAt: Instant,
  )

  suspend fun save(clientId: String, lastTouchedAt: Instant)

  suspend fun load(clientId: String): PreLoginRecord?

  suspend fun delete(clientId: String)

  fun close() {}
}

class RedisPreLoginStore(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
    private val preLoginTtl: java.time.Duration = AuthConfig.preLoginTtl,
) : PreLoginPersistence {
  private val mutexes = ConcurrentHashMap<String, Mutex>()
  private val ttlSeconds = preLoginTtl.seconds.coerceAtLeast(1L)

  override suspend fun save(clientId: String, lastTouchedAt: Instant) {
    withClientLock(clientId) {
      runtime.asyncCommands.set(keyFor(clientId), lastTouchedAt.toEpochMilli().toString()).await()
      runtime.asyncCommands.expire(keyFor(clientId), ttlSeconds).await()
    }
  }

  override suspend fun load(clientId: String): PreLoginPersistence.PreLoginRecord? {
    return withClientLock(clientId) {
      val raw = runtime.asyncCommands.get(keyFor(clientId)).await() ?: return@withClientLock null
      val lastTouchedAt = raw.toLongOrNull()?.let(Instant::ofEpochMilli) ?: return@withClientLock null
      PreLoginPersistence.PreLoginRecord(clientId = clientId, lastTouchedAt = lastTouchedAt)
    }
  }

  override suspend fun delete(clientId: String) {
    withClientLock(clientId) {
      runtime.asyncCommands.del(keyFor(clientId)).await()
    }
    mutexes.remove(clientId)
  }

  private suspend fun <T> withClientLock(clientId: String, block: suspend () -> T): T {
    val mutex = mutexes.computeIfAbsent(clientId) { Mutex() }
    return mutex.withLock { block() }
  }

  private fun keyFor(clientId: String): String = "prelogin:$clientId"
}
