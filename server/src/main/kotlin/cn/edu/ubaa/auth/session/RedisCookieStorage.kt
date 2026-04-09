package cn.edu.ubaa.auth

import io.ktor.http.Cookie
import io.ktor.http.CookieEncoding
import io.ktor.http.Url
import io.ktor.util.date.GMTDate
import io.lettuce.core.api.async.RedisAsyncCommands
import kotlinx.coroutines.future.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 基于 Redis 实现的持久化 Cookie 存储，带内存写回缓存。
 *
 * 在登录等密集 HTTP 交互期间，Ktor 的 HttpCookies 插件会在 **每个请求前** 调用 [get]、 在 **每个响应 Set-Cookie** 时调用
 * [addCookie]。一次 CAS 登录流程涉及 15-20 个 HTTP 请求，如果每次都直接读写 Redis 会产生 40-80 次同步阻塞调用，成为严重性能瓶颈。
 *
 * 优化策略：
 * - 首次 [get] 时从 Redis 加载全量 Cookie 到内存缓存
 * - 后续 [get] 直接读取内存缓存，不再访问 Redis
 * - [addCookie] 仅更新内存缓存，标记为脏
 * - [flush] 将脏数据批量写回 Redis（由外部在会话提交等关键节点调用）
 * - [clear] / [migrateTo] 会先刷新脏数据再操作
 *
 * @param commands 工厂提供的共享 Redis 异步命令对象。
 * @param initialSubject 关联的用户名或预登录标识（隔离标识）。
 */
class RedisCookieStorage(
    private val commands: RedisAsyncCommands<String, String>,
    initialSubject: String,
    ttl: java.time.Duration = AuthConfig.sessionTtl,
    private val syncIntervalMillis: Long = AuthConfig.sessionCookieSyncIntervalMillis,
) : ManagedCookieStorage {
  private val mutex = Mutex()
  @Volatile private var key = storageKey(initialSubject)
  @Volatile private var keyTtlSeconds = ttl.seconds.coerceAtLeast(1L)
  private var writeThrough = false
  private var lastRedisSyncAtMillis = 0L

  // 内存缓存：field -> serializedCookie。null 表示尚未从 Redis 加载。
  private var cache: MutableMap<String, String>? = null
  private val dirtyFields = mutableSetOf<String>()
  private val deletedFields = mutableSetOf<String>()

  override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
    val domain = (cookie.domain ?: requestUrl.host).lowercase()
    val path = cookie.path ?: requestUrl.encodedPath.ifBlank { "/" }
    val field = cookieField(cookie.name, domain, path)
    val expiresAt = cookie.expires?.timestamp
    val maxAge = cookie.maxAge ?: -1
    val createdAt = System.currentTimeMillis()
    val expired = isExpired(createdAt, expiresAt, maxAge, createdAt)
    val value =
        serializeCookie(
            name = cookie.name,
            value = cookie.value,
            domain = domain,
            path = path,
            expiresAt = expiresAt,
            secure = cookie.secure,
            httpOnly = cookie.httpOnly,
            maxAge = maxAge,
            createdAt = createdAt,
        )

    mutex.withLock {
      ensureCacheLoaded()
      if (expired) {
        cache!!.remove(field)
        dirtyFields.remove(field)
        deletedFields.add(field)
      } else {
        cache!![field] = value
        dirtyFields.add(field)
        deletedFields.remove(field)
      }
      if (writeThrough) {
        flushInternal()
      }
    }
  }

  override suspend fun get(requestUrl: Url): List<Cookie> {
    val now = System.currentTimeMillis()
    return mutex.withLock {
      ensureCacheLoaded(forceReload = shouldReloadFromRedis(now))
      val cookieMap = cache!!
      if (cookieMap.isEmpty()) return@withLock emptyList()

      val results = mutableListOf<Cookie>()
      val expiredFields = mutableListOf<String>()

      for ((field, encodedCookie) in cookieMap) {
        val record =
            decodeCookie(encodedCookie)
                ?: run {
                  expiredFields.add(field)
                  continue
                }
        if (isExpired(now, record.expiresAt, record.maxAge, record.createdAt)) {
          expiredFields.add(field)
          continue
        }
        if (!domainMatches(requestUrl.host, record.domain)) continue
        if (!pathMatches(requestUrl.encodedPath, record.path)) continue
        if (record.secure && !isHttps(requestUrl)) continue

        results.add(
            Cookie(
                name = record.name,
                value = record.value,
                domain = record.domain,
                path = record.path,
                expires = record.expiresAt?.let { GMTDate(it) },
                secure = record.secure,
                httpOnly = record.httpOnly,
                maxAge = record.maxAge,
                encoding = CookieEncoding.RAW,
            )
        )
      }

      for (f in expiredFields) {
        cookieMap.remove(f)
        dirtyFields.remove(f)
        deletedFields.add(f)
      }
      if (writeThrough && expiredFields.isNotEmpty()) {
        flushInternal()
      }

      results
    }
  }

  /** 将内存中的脏数据批量刷回 Redis。 在会话提交、迁移等关键节点调用。 */
  override suspend fun flush() {
    mutex.withLock { flushInternal() }
  }

  override suspend fun setWriteThrough(enabled: Boolean) {
    mutex.withLock {
      writeThrough = enabled
      if (enabled) {
        flushInternal()
      }
    }
  }

  override fun close() {
    // No-op: Redis 连接生命周期由 RedisCookieStorageFactory 统一管理
  }

  override suspend fun updatePersistenceTtl(ttl: java.time.Duration) {
    mutex.withLock {
      keyTtlSeconds = ttl.seconds.coerceAtLeast(1L)
      if (writeThrough) {
        applyPersistenceTtlInternal()
      }
    }
  }

  override suspend fun touchPersistence(ttl: java.time.Duration?) {
    mutex.withLock {
      ttl?.let { keyTtlSeconds = it.seconds.coerceAtLeast(1L) }
      applyPersistenceTtlInternal()
    }
  }

  override suspend fun clear() {
    mutex.withLock {
      cache = mutableMapOf()
      dirtyFields.clear()
      deletedFields.clear()
      commands.del(key).await()
    }
  }

  override suspend fun migrateTo(newSubject: String) {
    val targetKey = storageKey(newSubject)
    mutex.withLock {
      // 先刷回本地修改
      flushInternal()

      val cookieMap = commands.hgetall(key).await().orEmpty()
      if (cookieMap.isEmpty()) {
        commands.del(key).await()
      } else {
        commands.del(targetKey).await()
        commands.hset(targetKey, cookieMap).await()
        val ttl =
            computeCacheTtlSeconds(cookieMap.values, System.currentTimeMillis()) ?: keyTtlSeconds
        commands.expire(targetKey, ttl).await()
        commands.del(key).await()
      }

      key = targetKey
      cache = null // 下次访问时重新从新 key 加载
      lastRedisSyncAtMillis = 0L
      dirtyFields.clear()
      deletedFields.clear()
    }
  }

  private suspend fun ensureCacheLoaded(forceReload: Boolean = false) {
    if (!forceReload && cache != null) return
    if (forceReload) {
      flushInternal()
    }
    cache = commands.hgetall(key).await()?.toMutableMap() ?: mutableMapOf()
    lastRedisSyncAtMillis = System.currentTimeMillis()
  }

  private suspend fun flushInternal() {
    val map = cache ?: return
    if (dirtyFields.isEmpty() && deletedFields.isEmpty()) return
    val batch = dirtyFields.mapNotNull { f -> map[f]?.let { f to it } }.toMap()
    val ttl = computeCacheTtlSeconds(map.values, System.currentTimeMillis())
    if (deletedFields.isNotEmpty()) {
      commands.hdel(key, *deletedFields.toTypedArray()).await()
    }
    if (batch.isNotEmpty()) commands.hset(key, batch).await()
    when {
      map.isEmpty() -> commands.del(key).await()
      ttl != null -> commands.expire(key, ttl).await()
      else -> commands.expire(key, keyTtlSeconds).await()
    }
    dirtyFields.clear()
    deletedFields.clear()
  }

  private suspend fun applyPersistenceTtlInternal() {
    if ((cache?.isEmpty() == true) && dirtyFields.isEmpty() && deletedFields.isEmpty()) {
      return
    }
    commands.expire(key, keyTtlSeconds).await()
    lastRedisSyncAtMillis = System.currentTimeMillis()
  }

  private fun serializeCookie(
      name: String,
      value: String,
      domain: String,
      path: String,
      expiresAt: Long?,
      secure: Boolean,
      httpOnly: Boolean,
      maxAge: Int,
      createdAt: Long,
  ): String {
    return listOf(
            escape(name),
            escape(value),
            escape(domain),
            escape(path),
            expiresAt?.toString().orEmpty(),
            secure.toString(),
            httpOnly.toString(),
            maxAge.toString(),
            createdAt.toString(),
        )
        .joinToString("\u001F")
  }

  private fun decodeCookie(encoded: String): StoredCookie? {
    val parts = encoded.split("\u001F")
    if (parts.size != 9) return null
    return StoredCookie(
        name = unescape(parts[0]),
        value = unescape(parts[1]),
        domain = unescape(parts[2]),
        path = unescape(parts[3]),
        expiresAt = parts[4].ifBlank { null }?.toLongOrNull(),
        secure = parts[5].toBooleanStrictOrNull() ?: false,
        httpOnly = parts[6].toBooleanStrictOrNull() ?: false,
        maxAge = parts[7].toIntOrNull() ?: -1,
        createdAt = parts[8].toLongOrNull() ?: 0L,
    )
  }

  private fun computeCacheTtlSeconds(values: Collection<String>, now: Long): Long? {
    var hasSessionCookie = false
    var minExpiry: Long? = null
    for (encoded in values) {
      val record = decodeCookie(encoded) ?: continue
      if (isExpired(now, record.expiresAt, record.maxAge, record.createdAt)) continue
      val expiry =
          listOfNotNull(
                  record.expiresAt,
                  record.maxAge.takeIf { it >= 0 }?.let { record.createdAt + it * 1000L },
              )
              .minOrNull()
      if (expiry == null) {
        hasSessionCookie = true
        continue
      }
      minExpiry = minExpiry?.coerceAtMost(expiry) ?: expiry
    }

    if (hasSessionCookie) return keyTtlSeconds
    return minExpiry?.let { ((it - now) / 1000).coerceAtLeast(1L) }
  }

  private fun escape(value: String): String {
    return value.replace("\\", "\\\\").replace("\u001F", "\\u001F").replace("\n", "\\n")
  }

  private fun unescape(value: String): String {
    return value.replace("\\u001F", "\u001F").replace("\\n", "\n").replace("\\\\", "\\")
  }

  private fun isExpired(now: Long, expiresAt: Long?, maxAge: Int, createdAt: Long): Boolean {
    if (expiresAt != null && expiresAt <= now) return true
    if (maxAge >= 0 && now >= (createdAt + maxAge * 1000L)) return true
    return false
  }

  private fun domainMatches(host: String, domain: String): Boolean {
    val cleanDomain = domain.trimStart('.').lowercase()
    val cleanHost = host.lowercase()
    return cleanHost == cleanDomain || cleanHost.endsWith(".$cleanDomain")
  }

  private fun pathMatches(requestPath: String, cookiePath: String): Boolean {
    val req = requestPath.ifBlank { "/" }
    val norm = if (cookiePath.endsWith("/")) cookiePath else "$cookiePath/"
    return req.startsWith(norm.removeSuffix("/"))
  }

  private fun isHttps(url: Url): Boolean = url.protocol.name.equals("https", true)

  private fun shouldReloadFromRedis(now: Long): Boolean {
    if (!writeThrough || syncIntervalMillis <= 0L) return false
    return cache != null && now - lastRedisSyncAtMillis >= syncIntervalMillis
  }

  private data class StoredCookie(
      val name: String,
      val value: String,
      val domain: String,
      val path: String,
      val expiresAt: Long?,
      val secure: Boolean,
      val httpOnly: Boolean,
      val maxAge: Int,
      val createdAt: Long,
  )

  companion object {
    internal fun storageKey(subject: String): String = "cookies:$subject"

    private fun cookieField(name: String, domain: String, path: String): String =
        "$domain|$path|$name"
  }
}
