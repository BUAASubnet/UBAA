package cn.edu.ubaa.auth

import io.ktor.http.Cookie
import io.ktor.http.Url
import io.ktor.util.date.GMTDate
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

class InMemorySessionStore : SessionPersistence {
  private val sessions = ConcurrentHashMap<String, SessionPersistence.SessionRecord>()

  override suspend fun saveSession(
      username: String,
      userData: cn.edu.ubaa.model.dto.UserData,
      authenticatedAt: java.time.Instant,
      lastActivity: java.time.Instant,
      portalType: AcademicPortalType,
  ): SessionPersistence.SessionVersion {
    val nextGeneration = (sessions[username]?.generation ?: 0L) + 1L
    val record =
        SessionPersistence.SessionRecord(
            userData = userData,
            authenticatedAt = authenticatedAt,
            lastActivity = lastActivity,
            portalType = portalType,
            generation = nextGeneration,
            revision = 1L,
        )
    sessions[username] = record
    return record.version()
  }

  override suspend fun updateLastActivity(
      username: String,
      lastActivity: java.time.Instant,
  ): SessionPersistence.SessionVersion? {
    val current = sessions[username] ?: return null
    val updated = current.copy(lastActivity = lastActivity, revision = current.revision + 1)
    sessions[username] = updated
    return updated.version()
  }

  override suspend fun updatePortalType(
      username: String,
      portalType: AcademicPortalType,
  ): SessionPersistence.SessionVersion? {
    val current = sessions[username] ?: return null
    val updated = current.copy(portalType = portalType, revision = current.revision + 1)
    sessions[username] = updated
    return updated.version()
  }

  override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? =
      sessions[username]

  override suspend fun currentVersion(username: String): SessionPersistence.SessionVersion? =
      sessions[username]?.version()

  override suspend fun deleteSession(username: String) {
    sessions.remove(username)
  }

  override fun close() {
    sessions.clear()
  }
}

open class InMemoryCookieStorageFactory : ManagedCookieStorageFactory {
  private val storages = ConcurrentHashMap<String, InMemoryCookieStorage>()

  override fun create(subject: String, ttl: Duration): ManagedCookieStorage {
    return storages.computeIfAbsent(subject) { createStorage() }
  }

  override suspend fun clearSubject(subject: String) {
    storages.remove(subject)?.clear()
  }

  private fun storage(subject: String): InMemoryCookieStorage {
    return storages.computeIfAbsent(subject) { createStorage() }
  }

  protected open fun createStorage(): InMemoryCookieStorage = InMemoryCookieStorage()

  protected open inner class InMemoryCookieStorage : ManagedCookieStorage {
    private val cookies = ConcurrentHashMap<String, StoredCookie>()

    override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
      val domain = (cookie.domain ?: requestUrl.host).lowercase()
      val path = cookie.path ?: requestUrl.encodedPath.ifBlank { "/" }
      val key = "$domain|$path|${cookie.name}"
      cookies[key] =
          StoredCookie(cookie.copy(domain = domain, path = path), System.currentTimeMillis())
    }

    override suspend fun get(requestUrl: Url): List<Cookie> {
      val now = System.currentTimeMillis()
      return cookies.values.mapNotNull { stored ->
        val cookie = stored.cookie
        val expiresAt = cookie.expires?.timestamp
        val maxAge = cookie.maxAge ?: -1
        val expired =
            (expiresAt != null && expiresAt <= now) ||
                (maxAge >= 0 && now >= (stored.createdAt + maxAge * 1000L))
        if (expired) {
          cookies.remove(key(cookie))
          return@mapNotNull null
        }
        if (!domainMatches(requestUrl.host, cookie.domain ?: requestUrl.host))
            return@mapNotNull null
        if (!pathMatches(requestUrl.encodedPath, cookie.path ?: "/")) return@mapNotNull null
        if (cookie.secure && !requestUrl.protocol.name.equals("https", true)) return@mapNotNull null
        cookie.copy(expires = expiresAt?.let { GMTDate(it) })
      }
    }

    override suspend fun clear() {
      cookies.clear()
    }

    override suspend fun migrateTo(newSubject: String) {
      val target = storage(newSubject)
      target.cookies.putAll(cookies)
      cookies.clear()
    }

    override suspend fun updatePersistenceTtl(ttl: Duration) = Unit

    override suspend fun touchPersistence(ttl: Duration?) = Unit

    override fun close() {}

    private fun key(cookie: Cookie): String {
      return "${cookie.domain}|${cookie.path}|${cookie.name}"
    }
  }

  private data class StoredCookie(val cookie: Cookie, val createdAt: Long)

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
}

class TrackingCookieStorageFactory : InMemoryCookieStorageFactory() {
  val events = mutableListOf<String>()

  override fun createStorage(): InMemoryCookieStorage = TrackingCookieStorage()

  private inner class TrackingCookieStorage : InMemoryCookieStorage() {
    override suspend fun clear() {
      events += "clear"
      super.clear()
    }

    override fun close() {
      events += "close"
      super.close()
    }
  }
}

class InMemoryRefreshTokenStore : RefreshTokenStore {
  private val records = ConcurrentHashMap<String, RefreshTokenRecord>()

  override suspend fun saveToken(
      username: String,
      token: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ) {
    records[username] =
        RefreshTokenRecord(
            username = username,
            tokenHash = token,
            issuedAt = issuedAt,
            expiresAt = expiresAt,
        )
  }

  override suspend fun findToken(token: String): RefreshTokenRecord? {
    val now = Instant.now()
    return records.values.firstOrNull { it.tokenHash == token && it.expiresAt.isAfter(now) }
  }

  override suspend fun rotateToken(
      username: String,
      oldToken: String,
      newToken: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ): Boolean {
    val current = records[username] ?: return false
    if (current.tokenHash != oldToken || !current.expiresAt.isAfter(Instant.now())) {
      records.remove(username)
      return false
    }
    records[username] =
        RefreshTokenRecord(
            username = username,
            tokenHash = newToken,
            issuedAt = issuedAt,
            expiresAt = expiresAt,
        )
    return true
  }

  override suspend fun deleteByUsername(username: String) {
    records.remove(username)
  }

  override fun close() {
    // Keep the in-memory contents available to other SessionManager instances in tests.
  }
}

class InMemoryPreLoginStore : PreLoginPersistence {
  private val records = ConcurrentHashMap<String, PreLoginPersistence.PreLoginRecord>()

  override suspend fun save(clientId: String, lastTouchedAt: Instant) {
    records[clientId] =
        PreLoginPersistence.PreLoginRecord(clientId = clientId, lastTouchedAt = lastTouchedAt)
  }

  override suspend fun load(clientId: String): PreLoginPersistence.PreLoginRecord? =
      records[clientId]

  override suspend fun delete(clientId: String) {
    records.remove(clientId)
  }

  override fun close() {
    records.clear()
  }
}
