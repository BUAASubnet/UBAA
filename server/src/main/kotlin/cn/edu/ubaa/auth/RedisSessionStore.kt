package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import io.lettuce.core.RedisClient
import io.lettuce.core.api.StatefulRedisConnection
import io.lettuce.core.api.sync.RedisCommands
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Redis 会话持久化仓库。 负责将会话元数据（用户身份、认证时间、活跃时间）保存到 Redis，以便服务重启后能恢复活跃会话。 */
class RedisSessionStore(
    private val redisUri: String,
    sessionTtl: java.time.Duration = AuthConfig.sessionTtl,
) : SessionPersistence {
  private val mutexes = ConcurrentHashMap<String, Mutex>()
  private val client: RedisClient by lazy { RedisClient.create(redisUri) }
  private val connection: StatefulRedisConnection<String, String> by lazy { client.connect() }
  private val commands: RedisCommands<String, String> by lazy { connection.sync() }
  private val keyPrefix = "session:"
  private val sessionTtl = sessionTtl.seconds.coerceAtLeast(1L)

  data class SessionRecord(
      val userData: UserData,
      val authenticatedAt: Instant,
      val lastActivity: Instant,
  )

  override suspend fun saveSession(
      username: String,
      userData: UserData,
      authenticatedAt: Instant,
      lastActivity: Instant,
      portalType: AcademicPortalType,
  ) {
    withUserLock(username) {
      val key = keyFor(username)
      val sessionData =
          mapOf(
              "name" to userData.name,
              "schoolid" to userData.schoolid,
              "authenticated_at" to authenticatedAt.toEpochMilli().toString(),
              "last_activity" to lastActivity.toEpochMilli().toString(),
              "portal_type" to portalType.name,
          )

      redis {
        commands.hset(key, sessionData)
        commands.expire(key, sessionTtl)
      }
    }
  }

  override suspend fun updateLastActivity(username: String, lastActivity: Instant) {
    withUserLock(username) {
      val key = keyFor(username)
      redis {
        commands.hset(key, "last_activity", lastActivity.toEpochMilli().toString())
        commands.expire(key, sessionTtl)
      }
    }
  }

  override suspend fun updatePortalType(username: String, portalType: AcademicPortalType) {
    withUserLock(username) {
      val key = keyFor(username)
      redis {
        commands.hset(key, "portal_type", portalType.name)
        commands.expire(key, sessionTtl)
      }
    }
  }

  override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? {
    return withUserLock(username) {
      val sessionMap = redis { commands.hgetall(keyFor(username)) }.orEmpty()
      if (sessionMap.isEmpty()) return@withUserLock null

      val name = sessionMap["name"] ?: return@withUserLock null
      val schoolid = sessionMap["schoolid"] ?: return@withUserLock null
      val authenticatedAtMs =
          sessionMap["authenticated_at"]?.toLongOrNull() ?: return@withUserLock null
      val lastActivityMs = sessionMap["last_activity"]?.toLongOrNull() ?: return@withUserLock null
      val portalType =
          sessionMap["portal_type"]
              ?.let { runCatching { AcademicPortalType.valueOf(it) }.getOrNull() }
              ?: AcademicPortalType.UNKNOWN

      SessionPersistence.SessionRecord(
          userData = UserData(name = name, schoolid = schoolid),
          authenticatedAt = Instant.ofEpochMilli(authenticatedAtMs),
          lastActivity = Instant.ofEpochMilli(lastActivityMs),
          portalType = portalType,
      )
    }
  }

  override suspend fun deleteSession(username: String) {
    withUserLock(username) { redis { commands.del(keyFor(username)) } }
    mutexes.remove(username)
  }

  suspend fun deleteAll() {
    redis {
      val keys = commands.keys("$keyPrefix*") ?: return@redis
      if (keys.isNotEmpty()) {
        commands.del(*keys.toTypedArray())
      }
    }
    mutexes.clear()
  }

  override fun close() {
    try {
      runCatching { connection.close() }
      client.shutdown()
    } catch (_: Exception) {}
  }

  private suspend fun <T> withUserLock(username: String, block: suspend () -> T): T {
    val mutex = mutexes.computeIfAbsent(username) { Mutex() }
    return mutex.withLock { block() }
  }

  private suspend fun <T> redis(block: () -> T): T = withContext(Dispatchers.IO) { block() }

  private fun keyFor(username: String): String = "$keyPrefix$username"
}
