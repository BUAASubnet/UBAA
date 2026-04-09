package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.Cookie
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking

class AuthServiceResourceTest {

  @Test
  fun withNoRedirectClientClosesDerivedHandleOnSuccess() = runBlocking {
    val authService = AuthService()
    val baseClient = mockClient()
    val derivedClient = mockClient()
    var closeCount = 0

    authService.derivedClientFactory =
        AuthService.DerivedClientFactory { _ ->
          object : AuthService.DerivedClientHandle {
            override val client: HttpClient = derivedClient

            override fun close() {
              closeCount++
              client.close()
            }
          }
        }

    try {
      val result = authService.withNoRedirectClient(baseClient) { "ok" }
      assertEquals("ok", result)
      assertEquals(1, closeCount)
    } finally {
      baseClient.close()
    }
  }

  @Test
  fun withNoRedirectClientClosesDerivedHandleOnFailure() = runBlocking {
    val authService = AuthService()
    val baseClient = mockClient()
    val derivedClient = mockClient()
    var closeCount = 0

    authService.derivedClientFactory =
        AuthService.DerivedClientFactory { _ ->
          object : AuthService.DerivedClientHandle {
            override val client: HttpClient = derivedClient

            override fun close() {
              closeCount++
              client.close()
            }
          }
        }

    try {
      assertFailsWith<IllegalStateException> {
        authService.withNoRedirectClient(baseClient) { throw IllegalStateException("boom") }
      }
      assertEquals(1, closeCount)
    } finally {
      baseClient.close()
    }
  }

  @Test
  fun disposeSessionCandidateClearsCookieStorageBeforeClosingIt() = runBlocking {
    val trackingCookieStorageFactory = TrackingCookieStorageFactory()
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = trackingCookieStorageFactory,
            clientFactory = { mockClient() },
        )

    val candidate = sessionManager.prepareSession("candidate-user")
    val baselineEventCount = trackingCookieStorageFactory.events.size

    try {
      sessionManager.disposeSessionCandidate(candidate)
      val disposeEvents = trackingCookieStorageFactory.events.drop(baselineEventCount)
      assertEquals(listOf("clear", "close"), disposeEvents)
    } finally {
      sessionManager.close()
    }
  }

  @Test
  fun restoreSessionBuildsSingleClientUnderConcurrentLoad() = runBlocking {
    val record =
        SessionPersistence.SessionRecord(
            userData = UserData("Restored User", "10010"),
            authenticatedAt = Instant.now(),
            lastActivity = Instant.now(),
        )
    val sessionStore = DelayedSessionStore(record)
    val clientBuildCount = AtomicInteger(0)
    val sessionManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage ->
              clientBuildCount.incrementAndGet()
              mockClient()
            },
        )

    try {
      coroutineScope {
        val first = async {
          sessionManager.getSession("restored", SessionManager.SessionAccess.READ_ONLY)
        }
        val second = async {
          sessionManager.getSession("restored", SessionManager.SessionAccess.READ_ONLY)
        }

        val firstSession = first.await()
        val secondSession = second.await()

        assertNotNull(firstSession)
        assertNotNull(secondSession)
        assertSame(firstSession, secondSession)
      }

      assertEquals(1, clientBuildCount.get())
      assertEquals(1, sessionStore.loadCount.get())
    } finally {
      sessionManager.close()
    }
  }

  @Test
  fun committedAndRestoredSessionsPersistSubsequentCookieUpdates() = runBlocking {
    val cookieFactory = PersistentCookieStorageFactory()
    val sessionStore = PersistentSessionStore()
    val requestUrl = Url("https://example.com/app")
    val userData = UserData("Persistent User", "10086")

    val firstManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val candidate = firstManager.prepareSession("persistent-user")
      candidate.cookieStorage.addCookie(requestUrl, Cookie("initial", "v1"))
      firstManager.commitSession(candidate, userData)

      val active =
          firstManager.getSession("persistent-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(active)
      active.cookieStorage.addCookie(requestUrl, Cookie("afterCommit", "v2"))
    } finally {
      firstManager.close()
    }

    val secondManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val restored =
          secondManager.getSession("persistent-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(restored)
      val restoredCookies = restored.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("v1", restoredCookies["initial"]?.value)
      assertEquals("v2", restoredCookies["afterCommit"]?.value)

      restored.cookieStorage.addCookie(requestUrl, Cookie("afterRestore", "v3"))
    } finally {
      secondManager.close()
    }

    val thirdManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val restoredAgain =
          thirdManager.getSession("persistent-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(restoredAgain)
      val cookies = restoredAgain.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("v1", cookies["initial"]?.value)
      assertEquals("v2", cookies["afterCommit"]?.value)
      assertEquals("v3", cookies["afterRestore"]?.value)
    } finally {
      thirdManager.close()
    }
  }

  @Test
  fun preLoginSessionsCanBePromotedAcrossManagers() = runBlocking {
    val preLoginStore = InMemoryPreLoginStore()
    val cookieFactory = PersistentCookieStorageFactory()
    val requestUrl = Url("https://sso.buaa.edu.cn/login")

    val firstManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            preLoginStore = preLoginStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    val candidate = firstManager.preparePreLoginSession("device-1")
    candidate.cookieStorage.addCookie(requestUrl, Cookie("CASTGC", "prelogin-cookie"))
    firstManager.persistPreLoginSession("device-1")

    val secondManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            preLoginStore = preLoginStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val promoted = secondManager.promotePreLoginSession("device-1", "2333")
      assertNotNull(promoted)
      val cookies = promoted.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("prelogin-cookie", cookies["CASTGC"]?.value)
    } finally {
      secondManager.close()
      firstManager.close()
    }
  }

  @Test
  fun preLoginPromotionUsesCommittedSessionTtlForPersistedCookies() = runBlocking {
    val sessionTtl = Duration.ofMinutes(30)
    val cookieFactory = PersistentCookieStorageFactory()
    val sessionManager =
        SessionManager(
            sessionTtl = sessionTtl,
            sessionStore = PersistentSessionStore(),
            preLoginStore = InMemoryPreLoginStore(),
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )
    val requestUrl = Url("https://sso.buaa.edu.cn/login")

    try {
      val candidate = sessionManager.preparePreLoginSession("ttl-device")
      candidate.cookieStorage.addCookie(requestUrl, Cookie("CASTGC", "prelogin-cookie"))
      sessionManager.persistPreLoginSession("ttl-device")

      assertEquals(Duration.ofMinutes(5).toMillis(), cookieFactory.currentTtlMillis("prelogin_ttl-device"))

      val promoted = sessionManager.promotePreLoginSession("ttl-device", "2333")
      assertNotNull(promoted)
      assertEquals(sessionTtl.toMillis(), cookieFactory.currentTtlMillis("2333"))

      val cookies = promoted.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("prelogin-cookie", cookies["CASTGC"]?.value)
    } finally {
      sessionManager.close()
    }
  }

  @Test
  fun touchedSessionRefreshesCookieTtlAndRemainsRestorableAcrossManagers() = runBlocking {
    val sessionTtl = Duration.ofMinutes(30)
    val cookieFactory = PersistentCookieStorageFactory()
    val sessionStore = PersistentSessionStore()
    val requestUrl = Url("https://example.com/app")

    val firstManager =
        SessionManager(
            sessionTtl = sessionTtl,
            activityPersistInterval = Duration.ofMillis(1),
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val candidate = firstManager.prepareSession("touch-user")
      candidate.cookieStorage.addCookie(requestUrl, Cookie("active", "v1"))
      firstManager.commitSession(candidate, UserData("Touch User", "20001"))

      cookieFactory.advanceTimeBy(sessionTtl.toMillis() - 5)
      Thread.sleep(10)

      assertNotNull(firstManager.getSession("touch-user", SessionManager.SessionAccess.TOUCH))
      assertTrue(cookieFactory.touchCount("touch-user") > 0)

      cookieFactory.advanceTimeBy(10)
    } finally {
      firstManager.close()
    }

    val restoredManager =
        SessionManager(
            sessionTtl = sessionTtl,
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val restored =
          restoredManager.getSession("touch-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(restored)
      val cookies = restored.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("v1", cookies["active"]?.value)
    } finally {
      restoredManager.close()
    }
  }

  @Test
  fun remoteSessionOverwriteRebuildsLocalSessionInsteadOfReusingStaleClient() = runBlocking {
    val cookieFactory = PersistentCookieStorageFactory()
    val sessionStore = PersistentSessionStore()
    val requestUrl = Url("https://example.com/app")

    val firstManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )
    val secondManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = cookieFactory,
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val firstCandidate = firstManager.prepareSession("replace-user")
      firstCandidate.cookieStorage.addCookie(requestUrl, Cookie("session", "old"))
      firstManager.commitSession(firstCandidate, UserData("Alice", "30001"))

      val original =
          firstManager.getSession("replace-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(original)

      Thread.sleep(5)

      val secondCandidate = secondManager.prepareSession("replace-user")
      secondCandidate.cookieStorage.addCookie(requestUrl, Cookie("session", "new"))
      secondManager.commitSession(secondCandidate, UserData("Alice", "30001"))

      val rebuilt =
          firstManager.getSession("replace-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(rebuilt)
      assertNotSame(original, rebuilt)

      val cookies = rebuilt.cookieStorage.get(requestUrl).associateBy { it.name }
      assertEquals("new", cookies["session"]?.value)
    } finally {
      secondManager.close()
      firstManager.close()
    }
  }

  @Test
  fun restoredSessionsKeepPortalTypeMetadata() = runBlocking {
    val sessionStore = PersistentSessionStore()
    val sessionManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val candidate = sessionManager.prepareSession("graduate-user")
      sessionManager.commitSession(
          candidate,
          UserData("Graduate User", "SY0001"),
          AcademicPortalType.GRADUATE,
      )
    } finally {
      sessionManager.close()
    }

    val restoredManager =
        SessionManager(
            sessionStore = sessionStore,
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      val restored =
          restoredManager.getSession("graduate-user", SessionManager.SessionAccess.READ_ONLY)
      assertNotNull(restored)
      assertEquals(AcademicPortalType.GRADUATE, restored.portalType)
    } finally {
      restoredManager.close()
    }
  }

  @Test
  fun restoreSessionMissDoesNotLeakMutexes() = runBlocking {
    val sessionManager =
        SessionManager(
            sessionStore = NullSessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage -> mockClient() },
        )

    try {
      assertNull(sessionManager.getSession("missing-user", SessionManager.SessionAccess.READ_ONLY))
      assertEquals(0, sessionManager.restoreMutexCountForTesting())

      coroutineScope {
        val first = async {
          sessionManager.getSession("missing-a", SessionManager.SessionAccess.READ_ONLY)
        }
        val second = async {
          sessionManager.getSession("missing-b", SessionManager.SessionAccess.READ_ONLY)
        }
        assertNull(first.await())
        assertNull(second.await())
      }

      assertEquals(0, sessionManager.restoreMutexCountForTesting())
    } finally {
      sessionManager.close()
    }
  }

  private fun mockClient(): HttpClient {
    return HttpClient(MockEngine) {
      engine { addHandler { respond(content = "", status = HttpStatusCode.OK) } }
    }
  }

  private class DelayedSessionStore(private val record: SessionPersistence.SessionRecord) :
      SessionPersistence {
    val loadCount = AtomicInteger(0)

    override suspend fun saveSession(
        username: String,
        userData: UserData,
        authenticatedAt: Instant,
        lastActivity: Instant,
        portalType: AcademicPortalType,
    ): SessionPersistence.SessionVersion = record.version()

    override suspend fun updateLastActivity(
        username: String,
        lastActivity: Instant,
    ): SessionPersistence.SessionVersion? = null

    override suspend fun updatePortalType(
        username: String,
        portalType: AcademicPortalType,
    ): SessionPersistence.SessionVersion? = null

    override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? {
      loadCount.incrementAndGet()
      delay(50)
      return record
    }

    override suspend fun deleteSession(username: String) {}

    override fun close() {}
  }

  private class NullSessionStore : SessionPersistence {
    override suspend fun saveSession(
        username: String,
        userData: UserData,
        authenticatedAt: Instant,
        lastActivity: Instant,
        portalType: AcademicPortalType,
    ): SessionPersistence.SessionVersion = SessionPersistence.SessionVersion(1L, 1L)

    override suspend fun updateLastActivity(
        username: String,
        lastActivity: Instant,
    ): SessionPersistence.SessionVersion? = null

    override suspend fun updatePortalType(
        username: String,
        portalType: AcademicPortalType,
    ): SessionPersistence.SessionVersion? = null

    override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? = null

    override suspend fun deleteSession(username: String) {}

    override fun close() {}
  }

  private class PersistentSessionStore : SessionPersistence {
    private val sessions = ConcurrentHashMap<String, SessionPersistence.SessionRecord>()

    override suspend fun saveSession(
        username: String,
        userData: UserData,
        authenticatedAt: Instant,
        lastActivity: Instant,
        portalType: AcademicPortalType,
    ): SessionPersistence.SessionVersion {
      val generation = (sessions[username]?.generation ?: 0L) + 1L
      val record =
          SessionPersistence.SessionRecord(
              userData = userData,
              authenticatedAt = authenticatedAt,
              lastActivity = lastActivity,
              portalType = portalType,
              generation = generation,
              revision = 1L,
          )
      sessions[username] = record
      return record.version()
    }

    override suspend fun updateLastActivity(
        username: String,
        lastActivity: Instant,
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

    override fun close() {}
  }

  private class PersistentCookieStorageFactory : ManagedCookieStorageFactory {
    private data class PersistedState(
        val cookies: ConcurrentHashMap<String, Cookie>,
        var ttlMillis: Long,
        var expiresAtMillis: Long,
    )

    private val persistedCookies = ConcurrentHashMap<String, PersistedState>()
    private val touchCounts = ConcurrentHashMap<String, AtomicInteger>()
    private val clockMillis = java.util.concurrent.atomic.AtomicLong(System.currentTimeMillis())

    override fun create(subject: String, ttl: java.time.Duration): ManagedCookieStorage =
        PersistentCookieStorage(subject, ttl.toMillis().coerceAtLeast(1L))

    override suspend fun clearSubject(subject: String) {
      persistedCookies.remove(subject)
    }

    fun advanceTimeBy(deltaMillis: Long) {
      clockMillis.addAndGet(deltaMillis)
    }

    fun currentTtlMillis(subject: String): Long? = loadPersistedState(subject)?.ttlMillis

    fun touchCount(subject: String): Int = touchCounts[subject]?.get() ?: 0

    private inner class PersistentCookieStorage(
        initialSubject: String,
        initialTtlMillis: Long,
    ) : ManagedCookieStorage {
      private var subject = initialSubject
      private var currentTtlMillis = initialTtlMillis
      private var writeThrough = false
      private var loaded = false
      private val cookies = LinkedHashMap<String, Cookie>()
      private var dirty = false

      override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
        ensureLoaded()
        cookies[cookieKey(cookie, requestUrl)] = cookie
        dirty = true
        if (writeThrough) {
          flush()
        }
      }

      override suspend fun get(requestUrl: Url): List<Cookie> {
        ensureLoaded()
        return cookies.values.toList()
      }

      override suspend fun clear() {
        cookies.clear()
        dirty = false
        loaded = true
        persistedCookies.remove(subject)
      }

      override suspend fun migrateTo(newSubject: String) {
        flush()
        val source = loadPersistedState(subject)
        if (source != null) {
          persistedCookies[newSubject] =
              PersistedState(
                  cookies = ConcurrentHashMap(source.cookies),
                  ttlMillis = currentTtlMillis,
                  expiresAtMillis = nowMillis() + currentTtlMillis,
              )
        } else {
          persistedCookies.remove(newSubject)
        }
        persistedCookies.remove(subject)
        subject = newSubject
        loaded = false
        dirty = false
      }

      override suspend fun flush() {
        ensureLoaded()
        if (!dirty) return
        persistedCookies[subject] =
            PersistedState(
                cookies = ConcurrentHashMap(cookies),
                ttlMillis = currentTtlMillis,
                expiresAtMillis = nowMillis() + currentTtlMillis,
            )
        dirty = false
      }

      override suspend fun setWriteThrough(enabled: Boolean) {
        writeThrough = enabled
        if (enabled) {
          flush()
        }
      }

      override suspend fun updatePersistenceTtl(ttl: java.time.Duration) {
        currentTtlMillis = ttl.toMillis().coerceAtLeast(1L)
        loadPersistedState(subject)?.let { state ->
          state.ttlMillis = currentTtlMillis
        }
      }

      override suspend fun touchPersistence(ttl: java.time.Duration?) {
        ttl?.let { currentTtlMillis = it.toMillis().coerceAtLeast(1L) }
        loadPersistedState(subject)?.let { state ->
          state.ttlMillis = currentTtlMillis
          state.expiresAtMillis = nowMillis() + currentTtlMillis
        }
        touchCounts.computeIfAbsent(subject) { AtomicInteger(0) }.incrementAndGet()
      }

      override fun close() {}

      private fun ensureLoaded() {
        if (loaded) return
        cookies.clear()
        val state = loadPersistedState(subject)
        if (state != null) {
          cookies.putAll(state.cookies)
          currentTtlMillis = state.ttlMillis
        }
        loaded = true
      }

      private fun cookieKey(cookie: Cookie, requestUrl: Url): String {
        val domain = cookie.domain ?: requestUrl.host
        val path = cookie.path ?: requestUrl.encodedPath.ifBlank { "/" }
        return "$domain|$path|${cookie.name}"
      }
    }

    private fun loadPersistedState(subject: String): PersistedState? {
      val state = persistedCookies[subject] ?: return null
      if (state.expiresAtMillis <= nowMillis()) {
        persistedCookies.remove(subject, state)
        return null
      }
      return state
    }

    private fun nowMillis(): Long = clockMillis.get()
  }
}
