package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.JwtUtil
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.plugins.defaultRequest
import io.ktor.http.HttpHeaders
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.launch

import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/**
 * 会话管理器。
 * 负责隔离不同用户的 HttpClient 实例、Cookie 存储，以及管理 JWT 与用户会话之间的映射关系。
 * 支持会话持久化到 SQLite 数据库，实现重启后的会话恢复。
 */
class SessionManager(
        private val sessionTtl: Duration = Duration.ofMinutes(30),
        private val dbPath: String = DEFAULT_DB_PATH
) {

    /**
     * 登录过程中的临时会话载体。
     */
    data class SessionCandidate(
            val username: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage
    )

    /**
     * 活跃的用户会话。
     * 封装了用户的认证信息、专属客户端以及活动时间追踪。
     */
    class UserSession(
            val username: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage,
            val userData: UserData,
            val authenticatedAt: Instant,
            initialActivity: Instant = authenticatedAt
    ) {
        @Volatile private var lastActivity: Instant = initialActivity

        /** 判断会话是否因长时间未活动而过期。 */
        fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(lastActivity.plus(ttl))

        /** 标记当前会话为活跃状态，更新最后活动时间。 */
        fun markActive() {
            lastActivity = Instant.now()
        }

        /** 获取最后活动时间。 */
        fun lastActivity(): Instant = lastActivity
    }

    /** 包含会话对象和关联 JWT 的组合。 */
    data class SessionWithToken(val session: UserSession, val jwtToken: String)

    /**
     * 预登录会话：用于 preload 阶段，此时用户尚未输入凭据，通过 clientId 标识。
     */
    data class PreLoginCandidate(
            val clientId: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage,
            val createdAt: Instant = Instant.now()
    ) {
        /** 预登录会话有效期较短。 */
        fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(createdAt.plus(ttl))
    }

    private val sessions = ConcurrentHashMap<String, UserSession>()
    private val tokenToUsername = ConcurrentHashMap<String, String>()
    private val sessionStore = SqliteSessionStore(dbPath)
    private val preLoginSessions = ConcurrentHashMap<String, PreLoginCandidate>()
    private val preLoginTtl: Duration = Duration.ofMinutes(5)

    /**
     * 为 preload 流程准备预登录环境。
     * 如果 clientId 已有活跃会话则复用，否则创建。
     */
    suspend fun preparePreLoginSession(clientId: String): PreLoginCandidate {
        preLoginSessions[clientId]?.let { existing ->
            if (!existing.isExpired(preLoginTtl)) return existing
            existing.client.close()
            preLoginSessions.remove(clientId)
        }

        val cookieStorage = SqliteCookieStorage(dbPath, "prelogin_$clientId")
        cookieStorage.clear()

        val client = buildClient(cookieStorage)
        val candidate = PreLoginCandidate(clientId, client, cookieStorage)
        preLoginSessions[clientId] = candidate
        return candidate
    }

    /** 将预登录会话提升为正式用户会话。 */
    suspend fun promotePreLoginSession(clientId: String, username: String): SessionCandidate? {
        val preLogin = preLoginSessions.remove(clientId) ?: return null
        if (preLogin.isExpired(preLoginTtl)) {
            preLogin.client.close()
            return null
        }

        if (preLogin.cookieStorage is SqliteCookieStorage) {
            preLogin.cookieStorage.migrateTo(username)
        }

        val newCookieStorage = SqliteCookieStorage(dbPath, username)
        val newClient = buildClient(newCookieStorage)
        preLogin.client.close()

        return SessionCandidate(username, newClient, newCookieStorage)
    }

    /** 准备一个全新的登录环境（不基于 preload）。 */
    suspend fun prepareSession(username: String): SessionCandidate {
        val cookieStorage = SqliteCookieStorage(dbPath, username)
        cookieStorage.clear()
        val client = buildClient(cookieStorage)
        return SessionCandidate(username, client, cookieStorage)
    }

    /** 提交并激活会话，生成 JWT 令牌并持久化状态。 */
    fun commitSessionWithToken(candidate: SessionCandidate, userData: UserData): SessionWithToken {
        val newSession = UserSession(
                username = candidate.username,
                client = candidate.client,
                cookieStorage = candidate.cookieStorage,
                userData = userData,
                authenticatedAt = Instant.now()
        )

        val jwtToken = JwtUtil.generateToken(candidate.username, sessionTtl)
        sessions.compute(candidate.username) { _, previous ->
            previous?.client?.close()
            newSession
        }

        cleanupTokensForUser(candidate.username)
        tokenToUsername[jwtToken] = candidate.username

        sessionStore.saveSession(
                username = candidate.username,
                userData = userData,
                authenticatedAt = newSession.authenticatedAt,
                lastActivity = newSession.lastActivity()
        )

        return SessionWithToken(newSession, jwtToken)
    }

    /** 获取活跃会话，支持从数据库恢复已持久化的会话。 */
    suspend fun getSession(username: String): UserSession? {
        val active = sessions[username] ?: restoreSession(username) ?: return null
        if (active.isExpired(sessionTtl)) {
            invalidateSession(username)
            return null
        }
        active.markActive()
        sessionStore.updateLastActivity(username, active.lastActivity())
        sessions[username] = active
        return active
    }

    /** 通过 JWT 令牌反查会话。 */
    suspend fun getSessionByToken(jwtToken: String): UserSession? {
        val username = JwtUtil.validateTokenAndGetUsername(jwtToken) ?: return null
        val session = getSession(username)
        if (session != null) tokenToUsername[jwtToken] = username
        return session
    }

    /**
     * 获取会话，若不存在则抛出异常。
     * 用于需要强制登录状态的业务服务调用。
     */
    suspend fun requireSession(username: String): UserSession {
        return getSession(username) ?: throw RuntimeException("Session expired or invalid for user: $username")
    }

    /** 彻底销毁用户会话及其所有关联令牌。 */
    suspend fun invalidateSession(username: String) {
        sessions.remove(username)?.client?.close()
        SqliteCookieStorage(dbPath, username).clear()
        cleanupTokensForUser(username)
        sessionStore.deleteSession(username)
    }

    /** 构建针对特定用户会话配置的 HttpClient。 */
    private fun buildClient(cookieStorage: CookiesStorage): HttpClient {
        return HttpClient(CIO) {
            engine {
                // 代理支持
                val proxyUrl = System.getenv("HTTPS_PROXY") ?: System.getenv("HTTP_PROXY")
                if (!proxyUrl.isNullOrBlank()) {
                    proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
                }
                // 证书信任（开发环境）
                if (System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true") {
                    https {
                        trustManager = object : javax.net.ssl.X509TrustManager {
                            override fun checkClientTrusted(c: Array<java.security.cert.X509Certificate>?, a: String?) {}
                            override fun checkServerTrusted(c: Array<java.security.cert.X509Certificate>?, a: String?) {}
                            override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = arrayOf()
                        }
                    }
                }
            }
            install(HttpCookies) { storage = cookieStorage }
            install(ContentNegotiation) {
                json(Json { 
                    ignoreUnknownKeys = true 
                    coerceInputValues = true
                })
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

    /** 从数据库记录中恢复会话状态。 */
    private fun restoreSession(username: String): UserSession? {
        val record = sessionStore.loadSession(username) ?: return null
        val cookieStorage = SqliteCookieStorage(dbPath, username)
        val client = buildClient(cookieStorage)
        return UserSession(
                username = username,
                client = client,
                cookieStorage = cookieStorage,
                userData = record.userData,
                authenticatedAt = record.authenticatedAt,
                initialActivity = record.lastActivity
        ).also { sessions[username] = it }
    }

    private fun cleanupTokensForUser(username: String) {
        tokenToUsername.entries.filter { it.value == username }.map { it.key }.forEach { tokenToUsername.remove(it) }
    }

    fun cleanupPreLoginSession(clientId: String) {
        preLoginSessions.remove(clientId)?.client?.close()
    }

    companion object {
        private val DEFAULT_DB_PATH: String = System.getProperty("user.dir") + "/data/session_store.db"
    }
}

/** 全局会话管理器单例。 */
object GlobalSessionManager {
    val instance: SessionManager by lazy { SessionManager() }
}