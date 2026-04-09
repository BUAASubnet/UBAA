package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import io.lettuce.core.api.async.RedisAsyncCommands
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.future.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Redis 会话持久化仓库。 负责将会话元数据（用户身份、认证时间、活跃时间）保存到 Redis，以便服务重启后能恢复活跃会话。 */
class RedisSessionStore(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
    sessionTtl: java.time.Duration = AuthConfig.sessionTtl,
) : SessionPersistence {
  private val mutexes = ConcurrentHashMap<String, Mutex>()
  private val commands: RedisAsyncCommands<String, String>
    get() = runtime.asyncCommands
  private val keyPrefix = "session:"
  private val sessionTtl = sessionTtl.seconds.coerceAtLeast(1L)

  override suspend fun saveSession(
      username: String,
      userData: UserData,
      authenticatedAt: Instant,
      lastActivity: Instant,
      portalType: AcademicPortalType,
  ): SessionPersistence.SessionVersion {
    return withUserLock(username) {
      val key = keyFor(username)
      val generation =
          (commands.hget(key, "generation").await()?.toLongOrNull() ?: 0L) + 1L
      val version = SessionPersistence.SessionVersion(generation = generation, revision = 1L)
      val sessionData =
          mapOf(
              "name" to userData.name,
              "schoolid" to userData.schoolid,
              "authenticated_at" to authenticatedAt.toEpochMilli().toString(),
              "last_activity" to lastActivity.toEpochMilli().toString(),
              "portal_type" to portalType.name,
              "generation" to version.generation.toString(),
              "revision" to version.revision.toString(),
          )

      commands.hset(key, sessionData).await()
      commands.expire(key, sessionTtl).await()
      version
    }
  }

  override suspend fun updateLastActivity(
      username: String,
      lastActivity: Instant,
  ): SessionPersistence.SessionVersion? {
    return withUserLock(username) {
      val key = keyFor(username)
      if (commands.exists(key).await() == 0L) {
        return@withUserLock null
      }
      commands.hset(key, "last_activity", lastActivity.toEpochMilli().toString()).await()
      val revision = commands.hincrby(key, "revision", 1).await()
      val generation = commands.hget(key, "generation").await()?.toLongOrNull() ?: 1L
      commands.expire(key, sessionTtl).await()
      SessionPersistence.SessionVersion(generation = generation, revision = revision)
    }
  }

  override suspend fun updatePortalType(
      username: String,
      portalType: AcademicPortalType,
  ): SessionPersistence.SessionVersion? {
    return withUserLock(username) {
      val key = keyFor(username)
      if (commands.exists(key).await() == 0L) {
        return@withUserLock null
      }
      commands.hset(key, "portal_type", portalType.name).await()
      val revision = commands.hincrby(key, "revision", 1).await()
      val generation = commands.hget(key, "generation").await()?.toLongOrNull() ?: 1L
      commands.expire(key, sessionTtl).await()
      SessionPersistence.SessionVersion(generation = generation, revision = revision)
    }
  }

  override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? {
    return withUserLock(username) {
      val sessionMap = commands.hgetall(keyFor(username)).await().orEmpty()
      if (sessionMap.isEmpty()) return@withUserLock null

      val name = sessionMap["name"] ?: return@withUserLock null
      val schoolid = sessionMap["schoolid"] ?: return@withUserLock null
      val authenticatedAtMs =
          sessionMap["authenticated_at"]?.toLongOrNull() ?: return@withUserLock null
      val lastActivityMs = sessionMap["last_activity"]?.toLongOrNull() ?: return@withUserLock null
      val portalType =
          sessionMap["portal_type"]?.let {
            runCatching { AcademicPortalType.valueOf(it) }.getOrNull()
          } ?: AcademicPortalType.UNKNOWN
      val revision = sessionMap["revision"]?.toLongOrNull() ?: 1L

      SessionPersistence.SessionRecord(
          userData = UserData(name = name, schoolid = schoolid),
          authenticatedAt = Instant.ofEpochMilli(authenticatedAtMs),
          lastActivity = Instant.ofEpochMilli(lastActivityMs),
          portalType = portalType,
          generation = sessionMap["generation"]?.toLongOrNull() ?: 1L,
          revision = revision,
      )
    }
  }

  override suspend fun currentVersion(username: String): SessionPersistence.SessionVersion? {
    return withUserLock(username) {
      val key = keyFor(username)
      val generation = commands.hget(key, "generation").await()?.toLongOrNull()
      val revision = commands.hget(key, "revision").await()?.toLongOrNull()
      if (generation != null || revision != null) {
        return@withUserLock SessionPersistence.SessionVersion(
            generation = generation ?: 1L,
            revision = revision ?: 1L,
        )
      }

      val exists = commands.exists(key).await()
      if (exists > 0) SessionPersistence.SessionVersion(1L, 1L) else null
    }
  }

  override suspend fun deleteSession(username: String) {
    withUserLock(username) { commands.del(keyFor(username)).await() }
    mutexes.remove(username)
  }

  suspend fun deleteAll() {
    val keys = commands.keys("$keyPrefix*").await() ?: return
    if (keys.isNotEmpty()) {
      commands.del(*keys.toTypedArray()).await()
    }
    mutexes.clear()
  }

  override fun close() {
    // No-op: Redis 连接由 GlobalRedisRuntime 统一管理
  }

  private suspend fun <T> withUserLock(username: String, block: suspend () -> T): T {
    val mutex = mutexes.computeIfAbsent(username) { Mutex() }
    return mutex.withLock { block() }
  }

  private fun keyFor(username: String): String = "$keyPrefix$username"
}
