package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.JwtUtil
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
 * 
 * Now also supports JWT token management, where each JWT token maps to a session.
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

    data class SessionWithToken(
        val session: UserSession,
        val jwtToken: String
    )

    private val sessions = ConcurrentHashMap<String, UserSession>()
    // Map JWT tokens to usernames for quick lookup
    private val tokenToUsername = ConcurrentHashMap<String, String>()

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
     * Stores a successfully authenticated session for the given user and generates a JWT token.
     * Any previous session will be closed and replaced atomically.
     * 
     * @param candidate The session candidate from prepareSession
     * @param userData The user data obtained after successful authentication
     * @return SessionWithToken containing the session and generated JWT token
     */
    fun commitSessionWithToken(candidate: SessionCandidate, userData: UserData): SessionWithToken {
        val newSession = UserSession(
            username = candidate.username,
            client = candidate.client,
            cookieStorage = candidate.cookieStorage,
            userData = userData,
            authenticatedAt = Instant.now()
        )

        // Generate JWT token for this session
        val jwtToken = JwtUtil.generateToken(candidate.username, sessionTtl)

        sessions.compute(candidate.username) { _, previous ->
            previous?.client?.close()
            newSession
        }

        // Clean up old tokens for this user
        cleanupTokensForUser(candidate.username)
        
        // Map the new token to the username
        tokenToUsername[jwtToken] = candidate.username

        return SessionWithToken(newSession, jwtToken)
    }

    /**
     * Stores a successfully authenticated session for the given user.
     * Any previous session will be closed and replaced atomically.
     * This is the legacy method for backward compatibility.
     */
    fun commitSession(candidate: SessionCandidate, userData: UserData): UserSession {
        return commitSessionWithToken(candidate, userData).session
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

    /**
     * Retrieves an active session by JWT token, marking it as recently active.
     * Returns null if the token is invalid, expired, or no corresponding session exists.
     */
    fun getSessionByToken(jwtToken: String): UserSession? {
        // First validate the JWT token
        val username = JwtUtil.validateTokenAndGetUsername(jwtToken) ?: return null
        
        // Check if the token maps to a username in our system
        if (tokenToUsername[jwtToken] != username) {
            return null
        }
        
        // Retrieve and mark active the session
        return getSession(username)
    }

    fun requireSession(username: String): UserSession =
        getSession(username) ?: throw LoginException("Session for $username is not available or has expired.")

    /**
     * Requires a session by JWT token, throwing an exception if not found.
     */
    fun requireSessionByToken(jwtToken: String): UserSession {
        return getSessionByToken(jwtToken)
            ?: throw LoginException("No active session found for JWT token")
    }

    /**
     * Invalidates a session and all associated JWT tokens for the given username.
     */
    fun invalidateSession(username: String) {
        sessions.remove(username)?.client?.close()
        cleanupTokensForUser(username)
    }

    /**
     * Invalidates a session by JWT token.
     */
    fun invalidateSessionByToken(jwtToken: String) {
        val username = tokenToUsername.remove(jwtToken)
        if (username != null) {
            // Only remove session if this was the last token for the user
            if (tokenToUsername.values.none { it == username }) {
                sessions.remove(username)?.client?.close()
            }
        }
    }

    fun cleanupExpiredSessions() {
        sessions.forEach { (username, session) ->
            if (session.isExpired(sessionTtl)) {
                if (sessions.remove(username, session)) {
                    session.client.close()
                    cleanupTokensForUser(username)
                }
            }
        }
        
        // Also clean up expired tokens that might still be in the map
        val expiredTokens = tokenToUsername.keys.filter { token ->
            JwtUtil.isTokenExpired(token)
        }
        expiredTokens.forEach { token ->
            tokenToUsername.remove(token)
        }
    }

    /**
     * Removes all JWT tokens associated with a specific user.
     */
    private fun cleanupTokensForUser(username: String) {
        val tokensToRemove = tokenToUsername.entries
            .filter { it.value == username }
            .map { it.key }
        
        tokensToRemove.forEach { token ->
            tokenToUsername.remove(token)
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
