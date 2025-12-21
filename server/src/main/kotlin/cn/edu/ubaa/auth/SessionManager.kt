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

/** 会话管理器，隔离多用户认证会话，管理 JWT Token 映射 */
class SessionManager(
        private val sessionTtl: Duration = Duration.ofMinutes(30),
        private val dbPath: String = DEFAULT_DB_PATH
) {

    data class SessionCandidate(
            val username: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage
    )

    class UserSession(
            val username: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage,
            val userData: UserData,
            val authenticatedAt: Instant,
            initialActivity: Instant = authenticatedAt
    ) {
        @Volatile private var lastActivity: Instant = initialActivity

        fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(lastActivity.plus(ttl))

        fun markActive() {
            lastActivity = Instant.now()
        }

        fun lastActivity(): Instant = lastActivity
    }

    data class SessionWithToken(val session: UserSession, val jwtToken: String)

    /** 预登录会话候选：用于 preload 阶段，尚未绑定用户名 */
    data class PreLoginCandidate(
            val clientId: String,
            val client: HttpClient,
            val cookieStorage: CookiesStorage,
            val createdAt: Instant = Instant.now()
    ) {
        fun isExpired(ttl: Duration): Boolean = Instant.now().isAfter(createdAt.plus(ttl))
    }

    private val sessions = ConcurrentHashMap<String, UserSession>()
    // 仅为 token 快速查找用户名（重启后懒加载）
    private val tokenToUsername = ConcurrentHashMap<String, String>()
    private val sessionStore = SqliteSessionStore(dbPath)

    // 预登录会话缓存：clientId -> PreLoginCandidate（用于 preload 到 login 之间的会话保持）
    private val preLoginSessions = ConcurrentHashMap<String, PreLoginCandidate>()
    // 预登录会话的 TTL（5 分钟，足够用户填写表单）
    private val preLoginTtl: Duration = Duration.ofMinutes(5)

    /** 为 preload 创建预登录会话（基于 clientId） */
    fun preparePreLoginSession(clientId: String): PreLoginCandidate {
        // 如果已存在未过期的预登录会话，复用它
        preLoginSessions[clientId]?.let { existing ->
            if (!existing.isExpired(preLoginTtl)) {
                return existing
            }
            // 过期则关闭旧会话
            existing.client.close()
            preLoginSessions.remove(clientId)
        }

        // 创建新的预登录会话（使用 clientId 作为 cookie 存储的标识）
        val cookieStorage = SqliteCookieStorage(dbPath, "prelogin_$clientId")
        val client = buildClient(cookieStorage)
        val candidate = PreLoginCandidate(clientId, client, cookieStorage)
        preLoginSessions[clientId] = candidate
        return candidate
    }

    /** 获取预登录会话 */
    fun getPreLoginSession(clientId: String): PreLoginCandidate? {
        val candidate = preLoginSessions[clientId] ?: return null
        if (candidate.isExpired(preLoginTtl)) {
            candidate.client.close()
            preLoginSessions.remove(clientId)
            // 清理预登录 cookies（异步清理，不阻塞）
            kotlinx.coroutines.GlobalScope.launch {
                runCatching { SqliteCookieStorage(dbPath, "prelogin_$clientId").clear() }
            }
            return null
        }
        return candidate
    }

    /** 将预登录会话转换为正式的用户会话候选 */
    fun promotePreLoginSession(clientId: String, username: String): SessionCandidate? {
        val preLogin = preLoginSessions.remove(clientId) ?: return null
        if (preLogin.isExpired(preLoginTtl)) {
            preLogin.client.close()
            return null
        }
        return SessionCandidate(username, preLogin.client, preLogin.cookieStorage)
    }

    /** 清理预登录会话（登录失败或超时时调用） */
    fun cleanupPreLoginSession(clientId: String) {
        preLoginSessions.remove(clientId)?.let { candidate ->
            candidate.client.close()
            // 异步清理 cookies
            kotlinx.coroutines.GlobalScope.launch {
                runCatching { SqliteCookieStorage(dbPath, "prelogin_$clientId").clear() }
            }
        }
    }

    /** 为新登录请求准备会话环境。 若后续认证失败，调用者需手动关闭 client。 */
    fun prepareSession(username: String): SessionCandidate {
        val cookieStorage = SqliteCookieStorage(dbPath, username)
        val client = buildClient(cookieStorage)
        return SessionCandidate(username, client, cookieStorage)
    }

    /** 保存认证成功的会话并生成 JWT。 原子性地替换该用户可能存在的旧会话。 */
    fun commitSessionWithToken(candidate: SessionCandidate, userData: UserData): SessionWithToken {
        val newSession =
                UserSession(
                        username = candidate.username,
                        client = candidate.client,
                        cookieStorage = candidate.cookieStorage,
                        userData = userData,
                        authenticatedAt = Instant.now()
                )

        // 为当前会话生成 JWT
        val jwtToken = JwtUtil.generateToken(candidate.username, sessionTtl)

        sessions.compute(candidate.username) { _, previous ->
            previous?.client?.close()
            newSession
        }

        // 清理该用户的旧 Token
        cleanupTokensForUser(candidate.username)

        // 映射新 Token 至用户名
        tokenToUsername[jwtToken] = candidate.username

        sessionStore.saveSession(
                username = candidate.username,
                userData = userData,
                authenticatedAt = newSession.authenticatedAt,
                lastActivity = newSession.lastActivity()
        )

        return SessionWithToken(newSession, jwtToken)
    }

    /** (兼容旧代码) 保存认证成功的会话。 */
    fun commitSession(candidate: SessionCandidate, userData: UserData): UserSession {
        return commitSessionWithToken(candidate, userData).session
    }

    /** 获取活跃会话。若已过期则自动移除。 */
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

    /** 通过 JWT 获取活跃会话，并标记为活跃。 */
    suspend fun getSessionByToken(jwtToken: String): UserSession? {
        val username = JwtUtil.validateTokenAndGetUsername(jwtToken) ?: return null
        val session = getSession(username) ?: restoreSession(username)
        if (session != null) {
            tokenToUsername[jwtToken] = username
        }
        return session
    }

    suspend fun requireSession(username: String): UserSession =
            getSession(username)
                    ?: throw LoginException(
                            "Session for $username is not available or has expired."
                    )

    /** 通过 JWT 获取会话，若不存在则抛出异常。 */
    suspend fun requireSessionByToken(jwtToken: String): UserSession {
        return getSessionByToken(jwtToken)
                ?: throw LoginException("No active session found for JWT token")
    }

    /** 销毁指定用户的会话及所有关联 Token。 */
    suspend fun invalidateSession(username: String) {
        val session = sessions.remove(username)
        session?.client?.close()

        // 清理 Cookie
        val storage =
                session?.cookieStorage as? SqliteCookieStorage
                        ?: SqliteCookieStorage(dbPath, username)
        storage.clear()

        cleanupTokensForUser(username)
        sessionStore.deleteSession(username)
    }

    /** 通过 Token 销毁会话。 */
    suspend fun invalidateSessionByToken(jwtToken: String) {
        val username = tokenToUsername.remove(jwtToken)
        if (username != null) {
            // 仅在该用户没有其他活跃 Token 时销毁会话
            if (tokenToUsername.values.none { it == username }) {
                invalidateSession(username)
            }
        }
    }

    suspend fun cleanupExpiredSessions() {
        sessions.forEach { (username, session) ->
            if (session.isExpired(sessionTtl)) {
                invalidateSession(username)
            }
        }

        // 清理过期 Token
        val expiredTokens = tokenToUsername.keys.filter { token -> JwtUtil.isTokenExpired(token) }
        expiredTokens.forEach { token -> tokenToUsername.remove(token) }

        // 清理过期的预登录会话
        preLoginSessions.forEach { (clientId, candidate) ->
            if (candidate.isExpired(preLoginTtl)) {
                cleanupPreLoginSession(clientId)
            }
        }
    }

    /** 移除该用户关联的所有 JWT Token。 */
    private fun cleanupTokensForUser(username: String) {
        val tokensToRemove = tokenToUsername.entries.filter { it.value == username }.map { it.key }

        tokensToRemove.forEach { token -> tokenToUsername.remove(token) }
    }

    private fun buildClient(cookieStorage: CookiesStorage): HttpClient {
        return HttpClient(CIO) {
            // 代理配置：通过环境变量 HTTP_PROXY 或 HTTPS_PROXY 设置
            // 例如: HTTP_PROXY=http://127.0.0.1:7890
            // SSL 证书信任：通过环境变量 TRUST_ALL_CERTS=true 禁用证书验证（仅用于开发环境）
            engine {
                val proxyUrl =
                        System.getenv("HTTPS_PROXY")
                                ?: System.getenv("HTTP_PROXY") ?: System.getenv("https_proxy")
                                        ?: System.getenv("http_proxy")
                if (!proxyUrl.isNullOrBlank()) {
                    proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
                }

                // 开发环境下信任所有证书（用于代理 MITM 场景）
                val trustAllCerts = System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true"
                if (trustAllCerts) {
                    https {
                        trustManager =
                                object : javax.net.ssl.X509TrustManager {
                                    override fun checkClientTrusted(
                                            chain: Array<java.security.cert.X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun checkServerTrusted(
                                            chain: Array<java.security.cert.X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun getAcceptedIssuers():
                                            Array<java.security.cert.X509Certificate> = arrayOf()
                                }
                    }
                }
            }

            install(HttpCookies) { storage = cookieStorage }
            install(HttpTimeout) {
                requestTimeoutMillis = Duration.ofSeconds(30).toMillis()
                connectTimeoutMillis = Duration.ofSeconds(10).toMillis()
                socketTimeoutMillis = Duration.ofSeconds(30).toMillis()
            }
            followRedirects = true
            expectSuccess = false

            defaultRequest {
                headers.append(
                        HttpHeaders.UserAgent,
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
                )
                headers.append(
                        HttpHeaders.Accept,
                        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                )
                headers.append(HttpHeaders.AcceptLanguage, "zh-CN,zh;q=0.9")
            }
        }
    }

    private fun restoreSession(username: String): UserSession? {
        val record = sessionStore.loadSession(username) ?: return null
        val cookieStorage = SqliteCookieStorage(dbPath, username)
        val client = buildClient(cookieStorage)
        val restored =
                UserSession(
                        username = username,
                        client = client,
                        cookieStorage = cookieStorage,
                        userData = record.userData,
                        authenticatedAt = record.authenticatedAt,
                        initialActivity = record.lastActivity
                )
        sessions[username] = restored
        return restored
    }

    companion object {
        private val DEFAULT_DB_PATH: String =
                System.getProperty("user.dir") + "/data/session_store.db"
    }
}

object GlobalSessionManager {
    val instance: SessionManager by lazy { SessionManager() }
}
