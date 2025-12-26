package cn.edu.ubaa.utils

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.auth0.jwt.exceptions.JWTVerificationException
import io.github.cdimascio.dotenv.dotenv
import java.time.Duration
import java.time.Instant
import java.util.Date

/**
 * JWT 令牌处理工具。
 * 负责用户身份令牌的签发、验证、解析以及过期检查。
 */
object JwtUtil {

    private val dotenv = dotenv { ignoreIfMissing = true }

    // 优先从环境变量获取密钥
    private val jwtSecret: String =
            dotenv["JWT_SECRET"] ?: System.getenv("JWT_SECRET") ?: "ubaa-dev-secret-unsafe"

    val algorithm: Algorithm = Algorithm.HMAC256(jwtSecret)
    const val ISSUER = "ubaa-server"
    const val AUDIENCE = "ubaa-users"

    /**
     * 为指定用户生成 JWT 令牌。
     *
     * @param username 用户标识（学号）。
     * @param sessionTtl 令牌有效期。
     * @return 签名的 JWT 字符串。
     */
    fun generateToken(username: String, sessionTtl: Duration): String {
        val now = Instant.now()
        return JWT.create()
                .withIssuer(ISSUER)
                .withAudience(AUDIENCE)
                .withSubject(username)
                .withIssuedAt(Date.from(now))
                .withExpiresAt(Date.from(now.plus(sessionTtl)))
                .withClaim("username", username)
                .sign(algorithm)
    }

    /**
     * 验证令牌并提取其中的用户名。
     * @param token 待验证的 JWT 字符串。
     * @return 用户名，若验证失败则返回 null。
     */
    fun validateTokenAndGetUsername(token: String): String? {
        return try {
            JWT.require(algorithm).withIssuer(ISSUER).withAudience(AUDIENCE).build()
                .verify(token).subject
        } catch (_: JWTVerificationException) { null }
    }

    /** 检查令牌是否已过期。 */
    fun isTokenExpired(token: String): Boolean {
        return try { JWT.decode(token).expiresAt.before(Date()) } catch (_: Exception) { true }
    }
}