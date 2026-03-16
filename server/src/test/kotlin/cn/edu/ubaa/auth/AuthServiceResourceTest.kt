package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.Cookie
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
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
        val first = async { sessionManager.getSession("restored", SessionManager.SessionAccess.READ_ONLY) }
        val second = async { sessionManager.getSession("restored", SessionManager.SessionAccess.READ_ONLY) }

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
      firstManager.commitSessionWithToken(candidate, userData)

      val active = firstManager.getSession("persistent-user", SessionManager.SessionAccess.READ_ONLY)
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
        val first = async { sessionManager.getSession("missing-a", SessionManager.SessionAccess.READ_ONLY) }
        val second = async { sessionManager.getSession("missing-b", SessionManager.SessionAccess.READ_ONLY) }
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
      engine {
        addHandler { respond(content = "", status = HttpStatusCode.OK) }
      }
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
    ) {}

    override suspend fun updateLastActivity(username: String, lastActivity: Instant) {}

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
    ) {}

    override suspend fun updateLastActivity(username: String, lastActivity: Instant) {}

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
    ) {
      sessions[username] = SessionPersistence.SessionRecord(userData, authenticatedAt, lastActivity)
    }

    override suspend fun updateLastActivity(username: String, lastActivity: Instant) {
      val current = sessions[username] ?: return
      sessions[username] = current.copy(lastActivity = lastActivity)
    }

    override suspend fun loadSession(username: String): SessionPersistence.SessionRecord? = sessions[username]

    override suspend fun deleteSession(username: String) {
      sessions.remove(username)
    }

    override fun close() {}
  }

  private class PersistentCookieStorageFactory : ManagedCookieStorageFactory {
    private val persistedCookies = ConcurrentHashMap<String, ConcurrentHashMap<String, Cookie>>()

    override fun create(subject: String): ManagedCookieStorage = PersistentCookieStorage(subject)

    override suspend fun clearSubject(subject: String) {
      persistedCookies.remove(subject)
    }

    private inner class PersistentCookieStorage(initialSubject: String) : ManagedCookieStorage {
      private var subject = initialSubject
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
        persistedCookies[newSubject] = ConcurrentHashMap(persistedCookies[subject].orEmpty())
        persistedCookies.remove(subject)
        subject = newSubject
        loaded = false
        dirty = false
      }

      override suspend fun flush() {
        ensureLoaded()
        if (!dirty) return
        persistedCookies[subject] = ConcurrentHashMap(cookies)
        dirty = false
      }

      override suspend fun setWriteThrough(enabled: Boolean) {
        writeThrough = enabled
        if (enabled) {
          flush()
        }
      }

      override fun close() {}

      private fun ensureLoaded() {
        if (loaded) return
        cookies.clear()
        cookies.putAll(persistedCookies[subject].orEmpty())
        loaded = true
      }

      private fun cookieKey(cookie: Cookie, requestUrl: Url): String {
        val domain = cookie.domain ?: requestUrl.host
        val path = cookie.path ?: requestUrl.encodedPath.ifBlank { "/" }
        return "$domain|$path|${cookie.name}"
      }
    }
  }
}
