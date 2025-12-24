package cn.edu.ubaa.auth

import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.Cookie
import io.ktor.http.CookieEncoding
import io.ktor.http.Url
import io.ktor.util.date.GMTDate
import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** SQLite Cookie 存储，按用户隔离，支持持久化 */
class SqliteCookieStorage(private val dbPath: String, private val username: String) :
        CookiesStorage {
    private val mutex = Mutex()

    init {
        ensureDatabase()
    }

    override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
        val domain = (cookie.domain ?: requestUrl.host).lowercase()
        val path = (cookie.path ?: requestUrl.encodedPath.ifBlank { "/" })
        val createdAt = System.currentTimeMillis()
        val expiresAt = cookie.expires?.timestamp

        mutex.withLock {
            getConnection().use { conn ->
                conn.prepareStatement(
                                """
                                INSERT INTO cookies(username, name, value, domain, path, expires_at, secure, http_only, max_age, created_at)
                                VALUES(?,?,?,?,?,?,?,?,?,?)
                                ON CONFLICT(username, name, domain, path) DO UPDATE SET
                                    value=excluded.value,
                                    expires_at=excluded.expires_at,
                                    secure=excluded.secure,
                                    http_only=excluded.http_only,
                                    max_age=excluded.max_age,
                                    created_at=excluded.created_at
                                """
                        )
                        .apply {
                            setString(1, username)
                            setString(2, cookie.name)
                            setString(3, cookie.value)
                            setString(4, domain)
                            setString(5, path)
                            if (expiresAt != null) setLong(6, expiresAt)
                            else setNull(6, java.sql.Types.INTEGER)
                            setInt(7, if (cookie.secure) 1 else 0)
                            setInt(8, if (cookie.httpOnly) 1 else 0)
                            setInt(9, cookie.maxAge ?: -1)
                            setLong(10, createdAt)
                            executeUpdate()
                            close()
                        }
            }
        }
    }

    override suspend fun get(requestUrl: Url): List<Cookie> {
        val now = System.currentTimeMillis()
        return mutex.withLock {
            val results = mutableListOf<Cookie>()
            getConnection().use { conn ->
                conn.prepareStatement(
                                "SELECT name, value, domain, path, expires_at, secure, http_only, max_age, created_at FROM cookies WHERE username=?"
                        )
                        .apply {
                            setString(1, username)
                            val rs = executeQuery()
                            val expiredKeys = mutableListOf<CookieKey>()
                            while (rs.next()) {
                                val name = rs.getString(1)
                                val value = rs.getString(2)
                                val domain = rs.getString(3)
                                val path = rs.getString(4)
                                val expiresAt = rs.getLong(5).takeIf { !rs.wasNull() }
                                val secure = rs.getInt(6) == 1
                                val httpOnly = rs.getInt(7) == 1
                                val maxAge = rs.getInt(8)
                                val createdAt = rs.getLong(9)

                                val isExpired = isExpired(now, expiresAt, maxAge, createdAt)
                                if (isExpired) {
                                    expiredKeys.add(CookieKey(name, domain, path))
                                    continue
                                }

                                if (!domainMatches(requestUrl.host, domain)) continue
                                if (!pathMatches(requestUrl.encodedPath, path)) continue
                                if (secure && !isHttps(requestUrl)) continue

                                val expires = expiresAt?.let { GMTDate(it) }
                                results.add(
                                        Cookie(
                                                name = name,
                                                value = value,
                                                domain = domain,
                                                path = path,
                                                expires = expires,
                                                secure = secure,
                                                httpOnly = httpOnly,
                                                maxAge = maxAge,
                                                encoding = CookieEncoding.RAW
                                        )
                                )
                            }
                            close()

                            if (expiredKeys.isNotEmpty()) {
                                deleteExpired(conn, expiredKeys)
                            }
                        }
            }
            results
        }
    }

    override fun close() {
        // nothing to close; connections are short-lived
    }

    suspend fun clear() {
        mutex.withLock {
            getConnection().use { conn ->
                conn.prepareStatement("DELETE FROM cookies WHERE username=?").apply {
                    setString(1, username)
                    executeUpdate()
                    close()
                }
            }
        }
    }

    suspend fun migrateTo(newUsername: String) {
        mutex.withLock {
            getConnection().use { conn ->
                conn.prepareStatement(
                                """
                    INSERT INTO cookies(username, name, value, domain, path, expires_at, secure, http_only, max_age, created_at)
                    SELECT ?, name, value, domain, path, expires_at, secure, http_only, max_age, created_at
                    FROM cookies WHERE username=?
                    ON CONFLICT(username, name, domain, path) DO UPDATE SET
                        value=excluded.value,
                        expires_at=excluded.expires_at,
                        secure=excluded.secure,
                        http_only=excluded.http_only,
                        max_age=excluded.max_age,
                        created_at=excluded.created_at
                """
                        )
                        .apply {
                            setString(1, newUsername)
                            setString(2, username)
                            executeUpdate()
                            close()
                        }

                conn.prepareStatement("DELETE FROM cookies WHERE username=?").apply {
                    setString(1, username)
                    executeUpdate()
                    close()
                }
            }
        }
    }

    private fun isExpired(
            nowMillis: Long,
            expiresAt: Long?,
            maxAge: Int,
            createdAt: Long
    ): Boolean {
        if (expiresAt != null && expiresAt <= nowMillis) return true
        if (maxAge >= 0) {
            val deadline = createdAt + maxAge * 1000L
            if (nowMillis >= deadline) return true
        }
        return false
    }

    private fun domainMatches(host: String, domain: String): Boolean {
        val cleanDomain = domain.trimStart('.').lowercase()
        val cleanHost = host.lowercase()
        return cleanHost == cleanDomain || cleanHost.endsWith(".$cleanDomain")
    }

    private fun pathMatches(requestPath: String, cookiePath: String): Boolean {
        if (cookiePath.isEmpty()) return true
        val req = if (requestPath.isEmpty()) "/" else requestPath
        val normalized = if (cookiePath.endsWith("/")) cookiePath else "$cookiePath/"
        return req.startsWith(normalized.removeSuffix("/"))
    }

    private fun ensureDatabase() {
        File(dbPath).parentFile?.mkdirs()
        getConnection().use { conn ->
            conn.createStatement().use { stmt ->
                stmt.execute(
                        """
                        CREATE TABLE IF NOT EXISTS cookies (
                            username TEXT NOT NULL,
                            name TEXT NOT NULL,
                            value TEXT NOT NULL,
                            domain TEXT NOT NULL,
                            path TEXT NOT NULL,
                            expires_at INTEGER,
                            secure INTEGER NOT NULL,
                            http_only INTEGER NOT NULL,
                            max_age INTEGER NOT NULL,
                            created_at INTEGER NOT NULL,
                            PRIMARY KEY(username, name, domain, path)
                        )
                        """
                )
            }
        }
    }

    private fun deleteExpired(conn: Connection, keys: List<CookieKey>) {
        conn.prepareStatement(
                        "DELETE FROM cookies WHERE username=? AND name=? AND domain=? AND path=?"
                )
                .use { ps ->
                    keys.forEach { key ->
                        ps.setString(1, username)
                        ps.setString(2, key.name)
                        ps.setString(3, key.domain)
                        ps.setString(4, key.path)
                        ps.addBatch()
                    }
                    ps.executeBatch()
                }
    }

    private fun getConnection(): Connection {
        return DriverManager.getConnection("jdbc:sqlite:$dbPath")
    }

    private fun isHttps(url: Url): Boolean {
        return url.protocol.name.equals("https", ignoreCase = true)
    }

    private data class CookieKey(val name: String, val domain: String, val path: String)
}
