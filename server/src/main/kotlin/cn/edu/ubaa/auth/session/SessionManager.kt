package cn.edu.ubaa.auth

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.JwtUtil
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.engine.cio.endpoint
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.plugins.defaultRequest
import io.ktor.http.HttpHeaders
import io.ktor.serialization.kotlinx.json.json
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

interface SessionPersistence {
  data class SessionVersion(
      val generation: Long,
      val revision: Long,
  )

  data class SessionRecord(
      val userData: UserData,
      val authenticatedAt: Instant,
      val lastActivity: Instant,
      val portalType: AcademicPortalType = AcademicPortalType.UNKNOWN,
      val generation: Long = 1L,
      val revision: Long = 1L,
  ) {
    fun version(): SessionVersion = SessionVersion(generation = generation, revision = revision)
  }

  suspend fun saveSession(
      username: String,
      userData: UserData,
      authenticatedAt: Instant,
      lastActivity: Instant,
      portalType: AcademicPortalType = AcademicPortalType.UNKNOWN,
  ): SessionVersion

  suspend fun updateLastActivity(username: String, lastActivity: Instant): SessionVersion?

  suspend fun updatePortalType(
      username: String,
      portalType: AcademicPortalType,
  ): SessionVersion?

  suspend fun loadSession(username: String): SessionRecord?

  suspend fun currentVersion(username: String): SessionVersion? = loadSession(username)?.version()

  suspend fun deleteSession(username: String)

  fun close()
}

interface ManagedCookieStorage : CookiesStorage {
  suspend fun clear()

  suspend fun migrateTo(newSubject: String)

  suspend fun updatePersistenceTtl(ttl: Duration) {}

  suspend fun touchPersistence(ttl: Duration? = null) {}

  /** 将内存中的待写回数据刷到持久层。实现不需要持久化的可留空。 */
  suspend fun flush() {}

  /** 会话正式提交后切换到写穿模式，确保后续 Cookie 变更可跨重启恢复。 */
  suspend fun setWriteThrough(enabled: Boolean) {}
}

interface ManagedCookieStorageFactory {
  fun create(subject: String, ttl: Duration = AuthConfig.sessionTtl): ManagedCookieStorage

  suspend fun clearSubject(subject: String)

  fun close() {}
}

/** 会话管理器。 负责隔离不同用户的 HttpClient 实例、Cookie 存储，以及管理 JWT 与用户会话之间的映射关系。 支持会话持久化到 Redis，实现重启后的会话恢复。 */
class SessionManager(
    private val sessionTtl: Duration = AuthConfig.sessionTtl,
    private val activityPersistInterval: Duration = Duration.ofSeconds(60),
    private val sessionStore: SessionPersistence = RedisSessionStore(sessionTtl = sessionTtl),
    private val preLoginStore: PreLoginPersistence = RedisPreLoginStore(),
    private val cookieStorageFactory: ManagedCookieStorageFactory = RedisCookieStorageFactory(),
    private val clientFactory: (CookiesStorage) -> HttpClient = ::buildManagedClient,
) {
  private sealed interface RestoreAttempt {
    data class Restored(val session: UserSession) : RestoreAttempt

    data class RaceReused(val session: UserSession) : RestoreAttempt

    data object Miss : RestoreAttempt
  }

  enum class SessionAccess {
    READ_ONLY,
    TOUCH,
  }

  /** 登录过程中的临时会话载体。 */
  data class SessionCandidate(
      val username: String,
      val client: HttpClient,
      val cookieStorage: ManagedCookieStorage,
  )

  /** 活跃的用户会话。 封装了用户的认证信息、专属客户端以及活动时间追踪。 */
  class UserSession(
      val username: String,
      val client: HttpClient,
      val cookieStorage: ManagedCookieStorage,
      val userData: UserData,
      val authenticatedAt: Instant,
      portalType: AcademicPortalType = AcademicPortalType.UNKNOWN,
      initialActivity: Instant = authenticatedAt,
      generation: Long = 1L,
      revision: Long = 1L,
  ) {
    @Volatile private var lastActivity: Instant = initialActivity
    @Volatile private var lastPersistedActivity: Instant = initialActivity
    @Volatile var portalType: AcademicPortalType = portalType
    @Volatile private var generation: Long = generation
    @Volatile private var revision: Long = revision

    fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(lastActivity.plus(ttl))

    fun markActive(now: Instant = Instant.now()) {
      lastActivity = now
    }

    fun shouldPersistActivity(now: Instant, minInterval: Duration): Boolean {
      return !now.isBefore(lastPersistedActivity.plus(minInterval))
    }

    fun markPersistedActivity(at: Instant = lastActivity) {
      lastPersistedActivity = at
    }

    fun updateVersion(version: SessionPersistence.SessionVersion) {
      generation = version.generation
      revision = version.revision
    }

    fun generation(): Long = generation

    fun revision(): Long = revision

    fun refreshFromRecord(record: SessionPersistence.SessionRecord) {
      lastActivity = record.lastActivity
      lastPersistedActivity = record.lastActivity
      portalType = record.portalType
      generation = record.generation
      revision = record.revision
    }

    fun lastActivity(): Instant = lastActivity
  }

  /** 预登录会话：用于 preload 阶段，此时用户尚未输入凭据，通过 clientId 标识。 */
  class PreLoginCandidate(
      val clientId: String,
      val client: HttpClient,
      val cookieStorage: ManagedCookieStorage,
      lastTouchedAt: Instant = Instant.now(),
  ) {
    @Volatile private var lastTouchedAt: Instant = lastTouchedAt

    fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(lastTouchedAt.plus(ttl))

    fun touch(now: Instant = Instant.now()) {
      lastTouchedAt = now
    }

    fun lastTouchedAt(): Instant = lastTouchedAt
  }

  private val sessions = ConcurrentHashMap<String, UserSession>()
  private val preLoginSessions = ConcurrentHashMap<String, PreLoginCandidate>()
  private val restoreMutexes = ConcurrentHashMap<String, Mutex>()
  private val preLoginTtl: Duration = AuthConfig.preLoginTtl

  suspend fun preparePreLoginSession(clientId: String): PreLoginCandidate {
    preLoginSessions[clientId]?.let { existing ->
      if (!existing.isExpired(preLoginTtl)) {
        existing.touch()
        existing.cookieStorage.touchPersistence(preLoginTtl)
        preLoginStore.save(clientId, existing.lastTouchedAt())
        return existing
      }
      if (preLoginSessions.remove(clientId, existing)) {
        disposePreLoginCandidate(existing, clearCookies = true)
      }
    }

    val cookieStorage = cookieStorageFactory.create(preLoginSubject(clientId), preLoginTtl)
    cookieStorage.clear()
    cookieStorage.setWriteThrough(false)

    val client = clientFactory(cookieStorage)
    val candidate = PreLoginCandidate(clientId, client, cookieStorage)
    preLoginSessions[clientId] = candidate
    preLoginStore.save(clientId, candidate.lastTouchedAt())
    return candidate
  }

  suspend fun persistPreLoginSession(clientId: String) {
    val candidate = preLoginSessions[clientId] ?: return
    candidate.touch()
    candidate.cookieStorage.flush()
    candidate.cookieStorage.touchPersistence(preLoginTtl)
    preLoginStore.save(clientId, candidate.lastTouchedAt())
  }

  suspend fun promotePreLoginSession(clientId: String, username: String): SessionCandidate? {
    val resolved =
        preLoginSessions.remove(clientId)?.let { "memory_hit" to it }
            ?: restorePreLoginCandidate(clientId)?.let { "redis_restored" to it }
            ?: run {
              AppObservability.recordPreLoginResolve("miss")
              return null
            }
    val (source, preLogin) = resolved
    if (preLogin.isExpired(preLoginTtl)) {
      disposePreLoginCandidate(preLogin, clearCookies = true)
      AppObservability.recordPreLoginResolve("expired")
      return null
    }

    preLogin.cookieStorage.updatePersistenceTtl(sessionTtl)
    preLogin.cookieStorage.migrateTo(username)
    preLogin.cookieStorage.touchPersistence(sessionTtl)
    preLoginStore.delete(clientId)
    AppObservability.recordPreLoginResolve(source)
    return SessionCandidate(username, preLogin.client, preLogin.cookieStorage)
  }

  suspend fun prepareSession(username: String): SessionCandidate {
    val cookieStorage = cookieStorageFactory.create(username, sessionTtl)
    cookieStorage.clear()
    cookieStorage.setWriteThrough(false)
    val client = clientFactory(cookieStorage)
    return SessionCandidate(username, client, cookieStorage)
  }

  suspend fun commitSession(
      candidate: SessionCandidate,
      userData: UserData,
      portalType: AcademicPortalType = AcademicPortalType.UNKNOWN,
  ): UserSession {
    GlobalAcademicPortalWarmupCoordinator.clear(candidate.username)

    // 登录期间 Cookie 只缓存在内存中，此处批量写回 Redis
    candidate.cookieStorage.flush()
    candidate.cookieStorage.setWriteThrough(true)

    val authenticatedAt = Instant.now()
    val persistedVersion =
        sessionStore.saveSession(
            username = candidate.username,
            userData = userData,
            authenticatedAt = authenticatedAt,
            lastActivity = authenticatedAt,
            portalType = portalType,
        )

    val newSession =
        UserSession(
            username = candidate.username,
            client = candidate.client,
            cookieStorage = candidate.cookieStorage,
            userData = userData,
            authenticatedAt = authenticatedAt,
            portalType = portalType,
            generation = persistedVersion.generation,
            revision = persistedVersion.revision,
        )

    sessions.compute(candidate.username) { _, previous ->
      previous?.client?.close()
      closeCookieStorage(previous?.cookieStorage)
      newSession
    }

    return newSession
  }

  suspend fun getSession(
      username: String,
      access: SessionAccess = SessionAccess.TOUCH,
  ): UserSession? {
    sessions[username]?.let { active ->
      return finalizeResolvedSession(username, active, access, "memory_hit")
    }

    val restoreAttempt =
        try {
          restoreSession(username)
        } catch (e: Exception) {
          AppObservability.recordSessionResolve("failed")
          throw e
        }

    return when (restoreAttempt) {
      RestoreAttempt.Miss -> {
        AppObservability.recordSessionResolve("miss")
        null
      }
      is RestoreAttempt.Restored ->
          finalizeResolvedSession(
              username,
              restoreAttempt.session,
              access,
              "redis_restored",
              skipStoreReconcile = true,
          )
      is RestoreAttempt.RaceReused ->
          finalizeResolvedSession(
              username,
              restoreAttempt.session,
              access,
              "race_reused",
              skipStoreReconcile = true,
          )
    }
  }

  suspend fun getSessionByToken(
      jwtToken: String,
      access: SessionAccess = SessionAccess.TOUCH,
  ): UserSession? {
    val username = JwtUtil.validateTokenAndGetUsername(jwtToken) ?: return null
    return getSession(username, access)
  }

  suspend fun requireSession(username: String): UserSession {
    return getSession(username, SessionAccess.TOUCH)
        ?: throw RuntimeException("Session expired or invalid for user: $username")
  }

  suspend fun updateSessionPortalType(username: String, portalType: AcademicPortalType) {
    val session = sessions[username] ?: return
    if (session.portalType == portalType) return
    session.portalType = portalType
    sessionStore.updatePortalType(username, portalType)?.let { version ->
      session.updateVersion(version)
      session.cookieStorage.touchPersistence(sessionTtl)
    }
  }

  suspend fun invalidateSession(username: String) {
    GlobalAcademicPortalWarmupCoordinator.clear(username)
    val existing = sessions.remove(username)
    if (existing != null) {
      clearCookieStorage(username, existing.cookieStorage)
      existing.client.close()
      closeCookieStorage(existing.cookieStorage)
    } else {
      clearCookieStorage(username, null)
    }
    sessionStore.deleteSession(username)
    restoreMutexes.remove(username)
  }

  suspend fun cleanupExpiredSessions(): Int {
    var removed = 0
    for ((username, session) in sessions.entries.toList()) {
      if (!session.isExpired(sessionTtl)) continue
      if (!sessions.remove(username, session)) continue
      val reconciled = resolveExpiredSession(username, session)
      if (reconciled == null) {
        removed++
      } else {
        sessions[username] = reconciled
      }
    }
    return removed
  }

  suspend fun cleanupExpiredPreLoginSessions(): Int {
    var removed = 0
    for ((clientId, candidate) in preLoginSessions.entries.toList()) {
      if (!candidate.isExpired(preLoginTtl)) continue
      if (!preLoginSessions.remove(clientId, candidate)) continue
      disposePreLoginCandidate(candidate, clearCookies = true)
      removed++
    }
    return removed
  }

  suspend fun cleanupPreLoginSession(clientId: String) {
    val candidate = preLoginSessions.remove(clientId)
    if (candidate != null) {
      disposePreLoginCandidate(candidate, clearCookies = true)
      return
    }
    preLoginStore.delete(clientId)
    cookieStorageFactory.clearSubject(preLoginSubject(clientId))
  }

  fun activeSessionCount(): Int = sessions.size

  fun preLoginSessionCount(): Int = preLoginSessions.size

  fun close() {
    sessions.keys.forEach { GlobalAcademicPortalWarmupCoordinator.clear(it) }
    sessions.values.forEach {
      it.client.close()
      closeCookieStorage(it.cookieStorage)
    }
    sessions.clear()

    preLoginSessions.values.forEach {
      it.client.close()
      closeCookieStorage(it.cookieStorage)
    }
    preLoginSessions.clear()

    restoreMutexes.clear()
    sessionStore.close()
    preLoginStore.close()
    cookieStorageFactory.close()
  }

  internal suspend fun disposeSessionCandidate(
      candidate: SessionCandidate,
      clearCookies: Boolean = true,
  ) {
    if (clearCookies) {
      clearCookieStorage(candidate.username, candidate.cookieStorage)
    }
    candidate.client.close()
    closeCookieStorage(candidate.cookieStorage)
  }

  private suspend fun touchSession(username: String, session: UserSession) {
    val now = Instant.now()
    session.markActive(now)
    if (session.shouldPersistActivity(now, activityPersistInterval)) {
      sessionStore.updateLastActivity(username, now)?.let { version ->
        session.updateVersion(version)
        session.markPersistedActivity(now)
        session.cookieStorage.touchPersistence(sessionTtl)
      }
    }
  }

  private suspend fun finalizeResolvedSession(
      username: String,
      session: UserSession,
      access: SessionAccess,
      result: String,
      skipStoreReconcile: Boolean = false,
  ): UserSession? {
    val reconciled =
        (if (skipStoreReconcile) session else reconcileSessionWithStore(username, session))
            ?: run {
              AppObservability.recordSessionResolve("missing")
              return null
            }
    if (reconciled.isExpired(sessionTtl)) {
      val refreshed =
          resolveExpiredSession(username, reconciled)
              ?: run {
                AppObservability.recordSessionResolve("expired")
                return null
              }
      if (access == SessionAccess.TOUCH) {
        touchSession(username, refreshed)
      }
      sessions[username] = refreshed
      AppObservability.recordSessionResolve("expired_refreshed")
      return refreshed
    }
    if (access == SessionAccess.TOUCH) {
      touchSession(username, reconciled)
    }
    sessions[username] = reconciled
    AppObservability.recordSessionResolve(result)
    return reconciled
  }

  private suspend fun restoreSession(username: String): RestoreAttempt {
    val mutex = restoreMutexes.computeIfAbsent(username) { Mutex() }
    return try {
      mutex.withLock {
        sessions[username]?.let {
          return@withLock RestoreAttempt.RaceReused(it)
        }

        val record = sessionStore.loadSession(username) ?: return@withLock RestoreAttempt.Miss
        val cookieStorage = cookieStorageFactory.create(username, sessionTtl)
        cookieStorage.setWriteThrough(true)
        val client = clientFactory(cookieStorage)
        val restored = createSessionFromRecord(username, client, cookieStorage, record)

        val existing = sessions.putIfAbsent(username, restored)
        if (existing != null) {
          client.close()
          closeCookieStorage(cookieStorage)
          return@withLock RestoreAttempt.RaceReused(existing)
        }

        RestoreAttempt.Restored(restored)
      }
    } finally {
      if (sessions[username] == null) {
        restoreMutexes.remove(username, mutex)
      }
    }
  }

  private suspend fun disposePreLoginCandidate(
      candidate: PreLoginCandidate,
      clearCookies: Boolean,
  ) {
    preLoginStore.delete(candidate.clientId)
    if (clearCookies) {
      clearCookieStorage(preLoginSubject(candidate.clientId), candidate.cookieStorage)
    }
    candidate.client.close()
    closeCookieStorage(candidate.cookieStorage)
  }

  private suspend fun clearCookieStorage(subject: String, storage: ManagedCookieStorage?) {
    if (storage != null) {
      storage.clear()
    } else {
      cookieStorageFactory.clearSubject(subject)
    }
  }

  private fun closeCookieStorage(storage: ManagedCookieStorage?) {
    runCatching { storage?.close() }
  }

  private suspend fun resolveExpiredSession(
      username: String,
      session: UserSession,
  ): UserSession? {
    val persisted = sessionStore.loadSession(username)
    if (
        persisted != null &&
            persisted.generation == session.generation() &&
            !Instant.now().isAfter(persisted.lastActivity.plus(sessionTtl))
    ) {
      session.refreshFromRecord(persisted)
      AppObservability.recordCleanupSkipped("session", "redis_fresh")
      return session
    }

    disposeManagedSession(
        username = username,
        session = session,
        clearPersistedCookies = persisted == null,
        deletePersisted = persisted == null,
    )
    return null
  }

  private suspend fun reconcileSessionWithStore(
      username: String,
      session: UserSession,
  ): UserSession? {
    val persistedVersion =
        sessionStore.currentVersion(username)
            ?: run {
              disposeManagedSession(
                  username = username,
                  session = session,
                  clearPersistedCookies = false,
                  deletePersisted = false,
              )
              return null
            }

    if (
        persistedVersion.generation == session.generation() &&
            persistedVersion.revision == session.revision()
    ) {
      return session
    }

    val persisted =
        sessionStore.loadSession(username)
            ?: run {
              disposeManagedSession(
                  username = username,
                  session = session,
                  clearPersistedCookies = false,
                  deletePersisted = false,
              )
              return null
            }

    if (persisted.generation != session.generation()) {
      val cookieStorage = cookieStorageFactory.create(username, sessionTtl)
      cookieStorage.setWriteThrough(true)
      val client = clientFactory(cookieStorage)
      val rebuilt = createSessionFromRecord(username, client, cookieStorage, persisted)
      if (sessions.replace(username, session, rebuilt)) {
        releaseManagedSession(
            username = username,
            session = session,
            clearPersistedCookies = false,
            deletePersisted = false,
        )
        return rebuilt
      }

      val winner = sessions[username]
      if (
          winner != null &&
              winner.generation() == persisted.generation &&
              winner.revision() == persisted.revision
      ) {
        client.close()
        closeCookieStorage(cookieStorage)
        return winner
      }

      val previous = sessions.put(username, rebuilt)
      previous
          ?.takeIf { it !== rebuilt }
          ?.let {
            releaseManagedSession(
                username = username,
                session = it,
                clearPersistedCookies = false,
                deletePersisted = false,
            )
          }
      return rebuilt
    }

    session.refreshFromRecord(persisted)
    return session
  }

  private suspend fun disposeManagedSession(
      username: String,
      session: UserSession,
      clearPersistedCookies: Boolean,
      deletePersisted: Boolean,
  ) {
    sessions.remove(username, session)
    releaseManagedSession(
        username = username,
        session = session,
        clearPersistedCookies = clearPersistedCookies,
        deletePersisted = deletePersisted,
    )
    restoreMutexes.remove(username)
  }

  private suspend fun releaseManagedSession(
      username: String,
      session: UserSession,
      clearPersistedCookies: Boolean,
      deletePersisted: Boolean,
  ) {
    GlobalAcademicPortalWarmupCoordinator.clear(username)
    if (clearPersistedCookies) {
      clearCookieStorage(username, session.cookieStorage)
    }
    session.client.close()
    closeCookieStorage(session.cookieStorage)
    if (deletePersisted) {
      sessionStore.deleteSession(username)
    }
  }

  private suspend fun restorePreLoginCandidate(clientId: String): PreLoginCandidate? {
    val record = preLoginStore.load(clientId) ?: return null
    val cookieStorage = cookieStorageFactory.create(preLoginSubject(clientId), preLoginTtl)
    cookieStorage.setWriteThrough(false)
    val client = clientFactory(cookieStorage)
    return PreLoginCandidate(
        clientId = clientId,
        client = client,
        cookieStorage = cookieStorage,
        lastTouchedAt = record.lastTouchedAt,
    )
  }

  private fun preLoginSubject(clientId: String): String = "prelogin_$clientId"

  internal fun restoreMutexCountForTesting(): Int = restoreMutexes.size

  private fun createSessionFromRecord(
      username: String,
      client: HttpClient,
      cookieStorage: ManagedCookieStorage,
      record: SessionPersistence.SessionRecord,
  ): UserSession {
    return UserSession(
        username = username,
        client = client,
        cookieStorage = cookieStorage,
        userData = record.userData,
        authenticatedAt = record.authenticatedAt,
        portalType = record.portalType,
        initialActivity = record.lastActivity,
        generation = record.generation,
        revision = record.revision,
    )
  }
}

/** 全局会话管理器单例。 */
object GlobalSessionManager {
  @Volatile private var current: SessionManager? = null

  val instance: SessionManager
    get() {
      current?.let {
        return it
      }
      return synchronized(this) { current ?: SessionManager().also { current = it } }
    }

  fun close() {
    synchronized(this) {
      current?.close()
      current = null
    }
  }
}

private fun buildManagedClient(cookieStorage: CookiesStorage): HttpClient {
  return HttpClient(CIO) {
    engine {
      maxConnectionsCount = 16
      requestTimeout = 30_000
      endpoint {
        maxConnectionsPerRoute = 8
        keepAliveTime = 30_000
        connectTimeout = 10_000
        pipelineMaxSize = 4
      }
      val proxyUrl = System.getenv("HTTPS_PROXY") ?: System.getenv("HTTP_PROXY")
      if (!proxyUrl.isNullOrBlank()) {
        proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
      }
      if (System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true") {
        https {
          trustManager =
              object : javax.net.ssl.X509TrustManager {
                override fun checkClientTrusted(
                    c: Array<java.security.cert.X509Certificate>?,
                    a: String?,
                ) {}

                override fun checkServerTrusted(
                    c: Array<java.security.cert.X509Certificate>?,
                    a: String?,
                ) {}

                override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> =
                    arrayOf()
              }
        }
      }
    }
    install(HttpCookies) { storage = cookieStorage }
    install(ContentNegotiation) {
      json(
          Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
          }
      )
    }
    install(HttpTimeout) {
      requestTimeoutMillis = 30_000
      connectTimeoutMillis = 10_000
    }
    followRedirects = true
    defaultRequest {
      headers.append(HttpHeaders.UserAgent, "UBAA-Backend/1.0")
      headers.append(HttpHeaders.Accept, "application/json, text/html, */*")
    }
  }
}
