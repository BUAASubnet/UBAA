package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.AcceptAllCookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.plugins.defaultRequest
import io.ktor.http.HttpHeaders
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * SessionManager is responsible for maintaining independent authenticated sessions for
 * multiple UBAA users. Each session owns its own [HttpClient] instance and cookie storage,
 * ensuring that cookies won't leak between users.
 */
class SessionManager(
    private val sessionTtl: Duration = Duration.ofMinutes(30)
) {

    data class SessionCandidate(
        val username: String,
        val client: HttpClient,
        val cookieStorage: AcceptAllCookiesStorage
    )

    class UserSession(
        val username: String,
        val client: HttpClient,
        val cookieStorage: AcceptAllCookiesStorage,
        val userData: UserData,
        val authenticatedAt: Instant,
        initialActivity: Instant = authenticatedAt
    ) {
        @Volatile
        private var lastActivity: Instant = initialActivity

        fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(lastActivity.plus(ttl))

        fun markActive() {
            lastActivity = Instant.now()
        }

        fun lastActivity(): Instant = lastActivity
    }

    private val sessions = ConcurrentHashMap<String, UserSession>()

    /**
     * Creates a fresh [SessionCandidate] that can be used for a new login attempt.
     * The caller must close the client manually if authentication fails.
     */
    fun prepareSession(username: String): SessionCandidate {
        val cookieStorage = AcceptAllCookiesStorage()
        val client = buildClient(cookieStorage)
        return SessionCandidate(username, client, cookieStorage)
    }

    /**
     * Stores a successfully authenticated session for the given user.
     * Any previous session will be closed and replaced atomically.
     */
    fun commitSession(candidate: SessionCandidate, userData: UserData): UserSession {
        val newSession = UserSession(
            username = candidate.username,
            client = candidate.client,
            cookieStorage = candidate.cookieStorage,
            userData = userData,
            authenticatedAt = Instant.now()
        )

        sessions.compute(candidate.username) { _, previous ->
            previous?.client?.close()
            newSession
        }

        return newSession
    }

    /**
     * Retrieves an active session for the given user. If the session has expired, it is removed.
     */
    fun getSession(username: String): UserSession? {
        return sessions.compute(username) { _, session ->
            when {
                session == null -> null
                session.isExpired(sessionTtl) -> {
                    session.client.close()
                    null
                }
                else -> {
                    session.markActive()
                    session
                }
            }
        }
    }

    fun requireSession(username: String): UserSession =
        getSession(username) ?: throw LoginException("Session for $username is not available or has expired.")

    fun invalidateSession(username: String) {
        sessions.remove(username)?.client?.close()
    }

    fun cleanupExpiredSessions() {
        sessions.forEach { (username, session) ->
            if (session.isExpired(sessionTtl)) {
                if (sessions.remove(username, session)) {
                    session.client.close()
                }
            }
        }
    }

    private fun buildClient(cookieStorage: AcceptAllCookiesStorage): HttpClient {
        return HttpClient(CIO) {
            install(HttpCookies) { storage = cookieStorage }
            install(HttpTimeout) {
                requestTimeoutMillis = Duration.ofSeconds(30).toMillis()
                connectTimeoutMillis = Duration.ofSeconds(10).toMillis()
                socketTimeoutMillis = Duration.ofSeconds(30).toMillis()
            }
            followRedirects = true
            expectSuccess = false

            defaultRequest {
                headers.append(HttpHeaders.UserAgent, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3")
                headers.append(HttpHeaders.Accept, "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7")
                headers.append(HttpHeaders.AcceptLanguage, "zh-CN,zh;q=0.9")
            }
        }
    }
}

object GlobalSessionManager {
    val instance: SessionManager by lazy { SessionManager() }
}
